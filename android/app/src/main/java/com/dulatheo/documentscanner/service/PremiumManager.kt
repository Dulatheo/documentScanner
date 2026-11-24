package com.dulatheo.documentscanner.service

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

/** Google Play subscription identifiers: one subscription with two base
 * plans, each carrying a 3-day free-trial offer (eligibility "new customer
 * acquisition — never had this subscription", so Play only returns the
 * offer to users who can still use it). */
object PremiumProducts {
    const val SUBSCRIPTION_ID = "premium"
    const val BASE_PLAN_MONTHLY = "monthly"
    const val BASE_PLAN_YEARLY = "yearly"
    const val TRIAL_OFFER_ID = "trial-3d"
}

/** One purchasable plan as shown on the paywall. */
data class PlanOption(
    val basePlanId: String,
    /** Recurring price, already formatted by Play for the user's locale. */
    val formattedPrice: String,
    val priceMicros: Long,
    val currencyCode: String,
    /** ISO 8601 period of the recurring phase, e.g. "P1M" / "P1Y". */
    val billingPeriod: String,
    /** Offer token to buy with: the trial offer when eligible, otherwise the base plan. */
    val offerToken: String,
    val hasFreeTrial: Boolean,
    internal val productDetails: ProductDetails,
) {
    val isYearly: Boolean get() = basePlanId == PremiumProducts.BASE_PLAN_YEARLY

    /** Recurring price per month, for the yearly plan's savings badge. */
    val monthlyEquivalentMicros: Long
        get() = when {
            billingPeriod.endsWith("Y") -> priceMicros / (12 * (billingPeriod.filter { it.isDigit() }.toIntOrNull() ?: 1))
            billingPeriod.endsWith("M") -> priceMicros / (billingPeriod.filter { it.isDigit() }.toIntOrNull() ?: 1)
            else -> priceMicros
        }
}

sealed interface PlansState {
    data object Loading : PlansState
    data object Failed : PlansState
    data class Loaded(val plans: List<PlanOption>) : PlansState
}

sealed interface PurchaseEvent {
    data class Success(val isTrial: Boolean) : PurchaseEvent
    data object Pending : PurchaseEvent
    data object Cancelled : PurchaseEvent
    data class Failed(val message: String?) : PurchaseEvent
}

/**
 * Premium entitlement backed by Google Play Billing, gating premium-only
 * tools (Sign, OCR, Office export, PDF password, unlimited documents —
 * DESIGN_SPEC §5) behind the paywall (`PaywallScreen`).
 *
 * The synchronous getters ([isPremium] etc.) read a cache in
 * [SharedPreferences] that is rewritten from Play's own purchase list on
 * every connection, on [refresh] (called on app resume) and on every
 * purchase update — so call sites can check entitlement at tap time without
 * suspending, and a lapsed subscription is dropped on the next refresh.
 */
class PremiumManager(context: Context) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences("premium_billing", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val _premiumState = MutableStateFlow(prefs.getBoolean(KEY_IS_SUBSCRIBED, false))
    /** Observable mirror of [isPremium], for screens that should recompose on change. */
    val premiumState: StateFlow<Boolean> = _premiumState.asStateFlow()

    private val _plans = MutableStateFlow<PlansState>(PlansState.Loading)
    val plans: StateFlow<PlansState> = _plans.asStateFlow()

    private val _purchaseEvents = MutableSharedFlow<PurchaseEvent>(extraBufferCapacity = 4)
    val purchaseEvents: SharedFlow<PurchaseEvent> = _purchaseEvents.asSharedFlow()

    /** Set while a billing flow is in progress, so the resulting purchase
     * can be attributed to a plan / trial. */
    private var pendingPlan: PlanOption? = null
    private var reconnectDelayMs = 1_000L
    private var isConnecting = false

    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val list = purchases.orEmpty()
                val purchased = list.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                if (purchased != null) {
                    val plan = pendingPlan
                    if (plan != null) {
                        prefs.edit().putString(KEY_PLAN, plan.basePlanId).apply()
                        if (plan.hasFreeTrial) {
                            prefs.edit()
                                .putLong(KEY_TRIAL_END, purchased.purchaseTime + TRIAL_LENGTH_MS)
                                .putBoolean(KEY_HAS_USED_TRIAL, true)
                                .apply()
                        }
                    }
                    applyPurchases(list)
                    _purchaseEvents.tryEmit(PurchaseEvent.Success(isTrial = plan?.hasFreeTrial == true))
                } else if (list.any { it.purchaseState == Purchase.PurchaseState.PENDING }) {
                    _purchaseEvents.tryEmit(PurchaseEvent.Pending)
                }
                pendingPlan = null
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                pendingPlan = null
                _purchaseEvents.tryEmit(PurchaseEvent.Cancelled)
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                pendingPlan = null
                refresh()
                _purchaseEvents.tryEmit(PurchaseEvent.Success(isTrial = false))
            }
            else -> {
                pendingPlan = null
                _purchaseEvents.tryEmit(PurchaseEvent.Failed(result.debugMessage.takeIf { it.isNotBlank() }))
            }
        }
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(appContext)
        .setListener(purchasesListener)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    init {
        connect()
    }

    // MARK: - Synchronous entitlement API (unchanged for existing call sites)

    /** Whether premium features are currently unlocked — an active Play
     * subscription (including one in its free trial). */
    fun isPremium(): Boolean = prefs.getBoolean(KEY_IS_SUBSCRIBED, false)

    /** Whether the user can no longer get the free trial: Play didn't offer
     * a trial for any plan, or one was started on this device. Before plans
     * have loaded this falls back to the local record only. */
    fun hasUsedTrial(): Boolean {
        if (prefs.getBoolean(KEY_HAS_USED_TRIAL, false)) return true
        val state = _plans.value
        return state is PlansState.Loaded && state.plans.none { it.hasFreeTrial }
    }

    fun isTrialActive(): Boolean {
        val end = prefs.getLong(KEY_TRIAL_END, 0L)
        return isPremium() && end > System.currentTimeMillis()
    }

    /** Whole days left in an active trial, for display (e.g. "2 days left"). */
    fun trialDaysRemaining(): Int {
        if (!isTrialActive()) return 0
        val remainingMillis = prefs.getLong(KEY_TRIAL_END, 0L) - System.currentTimeMillis()
        return ((remainingMillis + DAY_MS - 1) / DAY_MS).toInt().coerceAtLeast(1)
    }

    /** The active plan's base plan id ([PremiumProducts.BASE_PLAN_MONTHLY] /
     * [PremiumProducts.BASE_PLAN_YEARLY]) when known on this device. */
    fun activePlanId(): String? = if (isPremium()) prefs.getString(KEY_PLAN, null) else null

    fun isAutoRenewing(): Boolean = prefs.getBoolean(KEY_AUTO_RENEWING, true)

    /** Whether a new document can be created given the library's current
     * size — always true once premium, otherwise gated by
     * [FREE_DOCUMENT_LIMIT]. */
    fun canCreateNewDocument(currentCount: Int): Boolean = isPremium() || currentCount < FREE_DOCUMENT_LIMIT

    // MARK: - Billing

    /** Re-reads purchases and plans from Play (call on app resume). */
    fun refresh() {
        if (billingClient.isReady) {
            queryPurchases(null)
            if (_plans.value !is PlansState.Loaded) queryPlans()
        } else {
            connect()
        }
    }

    fun reloadPlans() {
        _plans.value = PlansState.Loading
        if (billingClient.isReady) queryPlans() else connect()
    }

    /** Starts Play's purchase sheet for [plan]; the outcome arrives on [purchaseEvents]. */
    fun launchPurchase(activity: Activity, plan: PlanOption) {
        pendingPlan = plan
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(plan.productDetails)
                        .setOfferToken(plan.offerToken)
                        .build()
                )
            )
            .build()
        val result = billingClient.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            pendingPlan = null
            _purchaseEvents.tryEmit(PurchaseEvent.Failed(result.debugMessage.takeIf { it.isNotBlank() }))
        }
    }

    /** "Restore Purchases": re-reads the account's subscriptions from Play.
     * [onResult] receives whether Premium is active afterwards. */
    fun restorePurchases(onResult: (Boolean) -> Unit) {
        if (!billingClient.isReady) {
            connect()
            onResult(isPremium())
            return
        }
        queryPurchases(onResult)
    }

    private fun connect() {
        if (isConnecting || billingClient.isReady) return
        isConnecting = true
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                isConnecting = false
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    reconnectDelayMs = 1_000L
                    queryPlans()
                    queryPurchases(null)
                } else {
                    _plans.value = PlansState.Failed
                }
            }

            override fun onBillingServiceDisconnected() {
                isConnecting = false
                mainHandler.postDelayed({ connect() }, reconnectDelayMs)
                reconnectDelayMs = (reconnectDelayMs * 2).coerceAtMost(60_000L)
            }
        })
    }

    private fun queryPlans() {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(PremiumProducts.SUBSCRIPTION_ID)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                )
            )
            .build()
        billingClient.queryProductDetailsAsync(params) { result, detailsResult ->
            val details = detailsResult.productDetailsList.firstOrNull()
            val plans = if (result.responseCode == BillingClient.BillingResponseCode.OK && details != null) {
                buildPlans(details)
            } else {
                emptyList()
            }
            _plans.value = if (plans.isEmpty()) PlansState.Failed else PlansState.Loaded(plans)
        }
    }

    private fun buildPlans(details: ProductDetails): List<PlanOption> {
        val offers = details.subscriptionOfferDetails.orEmpty()
        return listOf(PremiumProducts.BASE_PLAN_YEARLY, PremiumProducts.BASE_PLAN_MONTHLY).mapNotNull { basePlanId ->
            val planOffers = offers.filter { it.basePlanId == basePlanId }
            val base = planOffers.firstOrNull { it.offerId == null } ?: return@mapNotNull null
            val trial = planOffers.firstOrNull { offer ->
                offer.offerId != null && offer.pricingPhases.pricingPhaseList.any { it.priceAmountMicros == 0L }
            }
            val recurring = base.pricingPhases.pricingPhaseList.lastOrNull() ?: return@mapNotNull null
            val trialEligible = trial != null && !prefs.getBoolean(KEY_HAS_USED_TRIAL, false)
            PlanOption(
                basePlanId = basePlanId,
                formattedPrice = recurring.formattedPrice,
                priceMicros = recurring.priceAmountMicros,
                currencyCode = recurring.priceCurrencyCode,
                billingPeriod = recurring.billingPeriod,
                offerToken = if (trialEligible) trial!!.offerToken else base.offerToken,
                hasFreeTrial = trialEligible,
                productDetails = details,
            )
        }
    }

    private fun queryPurchases(onResult: ((Boolean) -> Unit)?) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                applyPurchases(purchases)
            }
            onResult?.let { callback -> mainHandler.post { callback(isPremium()) } }
        }
    }

    /** Rewrites the cached entitlement from Play's purchase list and
     * acknowledges new purchases (Play refunds unacknowledged ones after 3 days). */
    private fun applyPurchases(purchases: List<Purchase>) {
        val active = purchases.filter {
            it.purchaseState == Purchase.PurchaseState.PURCHASED &&
                it.products.contains(PremiumProducts.SUBSCRIPTION_ID)
        }
        active.filterNot { it.isAcknowledged }.forEach { purchase ->
            val ackParams = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            billingClient.acknowledgePurchase(ackParams) { }
        }
        val isSubscribed = active.isNotEmpty()
        prefs.edit()
            .putBoolean(KEY_IS_SUBSCRIBED, isSubscribed)
            .putBoolean(KEY_AUTO_RENEWING, active.firstOrNull()?.isAutoRenewing ?: true)
            .apply()
        if (isSubscribed) {
            // Anyone who has subscribed can't take the new-customer trial again.
            prefs.edit().putBoolean(KEY_HAS_USED_TRIAL, true).apply()
        }
        _premiumState.value = isSubscribed
    }

    companion object {
        /** Free-tier document cap (DESIGN_SPEC §5/§9 "unlimited scanning"):
         * non-premium users can have at most this many documents in their
         * library at once; Premium removes the cap entirely. */
        const val FREE_DOCUMENT_LIMIT = 3

        private const val DAY_MS = 24L * 60 * 60 * 1000
        private const val TRIAL_LENGTH_MS = 3 * DAY_MS

        private const val KEY_HAS_USED_TRIAL = "hasUsedTrial"
        private const val KEY_TRIAL_END = "trialEndMillis"
        private const val KEY_IS_SUBSCRIBED = "isSubscribed"
        private const val KEY_PLAN = "planId"
        private const val KEY_AUTO_RENEWING = "autoRenewing"
    }
}
