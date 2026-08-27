package com.dulatheo.documentscanner.service

import android.content.Context
import android.content.SharedPreferences

/**
 * Local premium/trial entitlement, gating premium-only tools (Sign, per
 * DESIGN_SPEC §4.3) behind a paywall (`PaywallScreen`).
 *
 * This is a **local mock entitlement store**, not a real payment
 * integration: [startTrial]/[subscribe] grant entitlement immediately on
 * tap, backed only by [SharedPreferences], so the paywall's full UX (trial
 * countdown, "already used trial" vs. "never tried" variants, restore) can
 * be built and tested without Play Console products existing yet. Wiring
 * this to real Google Play Billing Library calls (`BillingClient`,
 * `ProductDetails`, purchase acknowledgment) is a separate, later step once
 * subscription products are created there — at that point
 * [startTrial]/[subscribe]/[restorePurchases] are the seams to replace with
 * real Billing calls; the rest of the app (the `isPremium()` check gating
 * Sign, the paywall UI) shouldn't need to change.
 */
class PremiumManager(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("premium", Context.MODE_PRIVATE)
    private val trialLengthMillis = 3L * 24 * 60 * 60 * 1000

    /** Whether the 3-day trial has ever been started, on this device — once
     * true, it stays true forever (mirroring how a real trial is
     * one-time-per-account), so the paywall shows the "subscribe" variant
     * instead of "start trial" from then on, even after the trial ends. */
    fun hasUsedTrial(): Boolean = prefs.getBoolean(KEY_HAS_USED_TRIAL, false)

    private fun trialEndMillis(): Long = prefs.getLong(KEY_TRIAL_END, 0L)

    fun isTrialActive(): Boolean {
        val end = trialEndMillis()
        return end > 0 && end > System.currentTimeMillis()
    }

    /** Whole days left in an active trial, for display (e.g. "2 days
     * left"). 0 once the trial has ended or none is active. */
    fun trialDaysRemaining(): Int {
        val end = trialEndMillis()
        val remainingMillis = end - System.currentTimeMillis()
        if (remainingMillis <= 0) return 0
        return ((remainingMillis + (24 * 60 * 60 * 1000) - 1) / (24 * 60 * 60 * 1000)).toInt()
    }

    /** Whether premium features are currently unlocked — either an active
     * mock subscription or an active mock trial. Re-reads SharedPreferences
     * on every call (rather than caching), so callers checking this at
     * button-tap time always see whether a trial has since expired. */
    fun isPremium(): Boolean = prefs.getBoolean(KEY_IS_SUBSCRIBED, false) || isTrialActive()

    fun startTrial() {
        if (hasUsedTrial()) return
        prefs.edit()
            .putBoolean(KEY_HAS_USED_TRIAL, true)
            .putLong(KEY_TRIAL_END, System.currentTimeMillis() + trialLengthMillis)
            .apply()
    }

    fun subscribe() {
        prefs.edit().putBoolean(KEY_IS_SUBSCRIBED, true).apply()
    }

    /** Mock "Restore Purchases" — re-checks local entitlement state. Returns
     * whether anything was restored, so the caller can show an appropriate
     * toast ("Restored" vs. "No previous purchase found"). */
    fun restorePurchases(): Boolean = isPremium()

    /** Whether a new document can be created given the library's current
     * size — always true once premium, otherwise gated by
     * [FREE_DOCUMENT_LIMIT]. */
    fun canCreateNewDocument(currentCount: Int): Boolean = isPremium() || currentCount < FREE_DOCUMENT_LIMIT

    companion object {
        /** Free-tier document cap (DESIGN_SPEC §5/§9 "unlimited scanning"):
         * non-premium users can have at most this many documents in their
         * library at once; Premium removes the cap entirely. */
        const val FREE_DOCUMENT_LIMIT = 3

        private const val KEY_HAS_USED_TRIAL = "hasUsedTrial"
        private const val KEY_TRIAL_END = "trialEndMillis"
        private const val KEY_IS_SUBSCRIBED = "isSubscribed"
    }
}
