package com.dulatheo.documentscanner.ui.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.R
import com.dulatheo.documentscanner.service.PlanOption
import com.dulatheo.documentscanner.service.PlansState
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.service.PremiumProducts
import com.dulatheo.documentscanner.service.PurchaseEvent
import com.dulatheo.documentscanner.ui.theme.AppColorTokens
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** How the user left the paywall — lets the presenter (`EditScreen`) close
 * it and show an appropriate toast without `PaywallScreen` needing its own
 * reference to the toast host. Failed / pending purchases are reported
 * inside the paywall, which stays open. */
enum class PaywallOutcome { TRIAL_STARTED, SUBSCRIBED, RESTORED, NOT_RESTORED, DISMISSED }

/** Legal links shown on the paywall (hosted on GitHub Pages). */
object LegalLinks {
    const val TERMS_OF_USE: String = "https://dulatheo.github.io/documentscanner/terms"
    const val PRIVACY_POLICY: String = "https://dulatheo.github.io/documentscanner/privacy"
    const val SUPPORT: String = "https://dulatheo.github.io/documentscanner/support"
}

/**
 * Paywall shown whenever a free user hits any premium gate (Sign/Text
 * tools, the free-tier document limit, Office format export, PDF
 * password — DESIGN_SPEC §5). Offers two Play base plans (yearly
 * preselected, monthly), each with a 3-day free trial when Play reports the
 * user as eligible; prices come from Play, localized.
 */
@Composable
fun PaywallScreen(
    premiumManager: PremiumManager,
    reason: String? = null,
    onFinished: (PaywallOutcome) -> Unit,
) {
    val tokens = LocalAppColors.current
    val context = LocalContext.current
    val plansState by premiumManager.plans.collectAsState()
    val plans = (plansState as? PlansState.Loaded)?.plans.orEmpty()
    var selectedPlanId by remember { mutableStateOf(PremiumProducts.BASE_PLAN_YEARLY) }
    val selectedPlan = plans.firstOrNull { it.basePlanId == selectedPlanId } ?: plans.firstOrNull()
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var alertMessage by remember { mutableStateOf<String?>(null) }
    val anyTrial = plans.any { it.hasFreeTrial } || (plans.isEmpty() && !premiumManager.hasUsedTrial())
    val isTrialEligible = selectedPlan?.hasFreeTrial ?: anyTrial

    val pendingMessage = stringResource(R.string.paywall_purchase_pending)
    val failedMessage = stringResource(R.string.paywall_purchase_failed)

    LaunchedEffect(Unit) {
        if (plansState is PlansState.Failed) premiumManager.reloadPlans()
    }
    LaunchedEffect(premiumManager) {
        premiumManager.purchaseEvents.collect { event ->
            isPurchasing = false
            when (event) {
                is PurchaseEvent.Success ->
                    onFinished(if (event.isTrial) PaywallOutcome.TRIAL_STARTED else PaywallOutcome.SUBSCRIBED)
                PurchaseEvent.Pending -> alertMessage = pendingMessage
                PurchaseEvent.Cancelled -> {}
                is PurchaseEvent.Failed -> alertMessage = event.message ?: failedMessage
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(tokens.bg)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 18.dp, end = 18.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(tokens.surface)
                    .clickable { onFinished(PaywallOutcome.DISMISSED) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = stringResource(R.string.paywall_close),
                    tint = tokens.ink2,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier.size(72.dp).clip(CircleShape).background(tokens.accent),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.WorkspacePremium, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
            }
            Spacer(Modifier.height(20.dp))
            if (reason != null) {
                Text(
                    reason,
                    color = tokens.accent,
                    style = MaterialTheme.typography.labelMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(tokens.accentSoft)
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                )
                Spacer(Modifier.height(16.dp))
            }
            Text(
                // Plain "Unlock Premium" in both cases: the billed amount,
                // not the free trial, should be the most prominent pricing
                // element on the screen.
                stringResource(R.string.paywall_unlock_headline),
                color = tokens.ink,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                if (anyTrial) stringResource(R.string.paywall_trial_subtitle) else stringResource(R.string.paywall_unlock_subtitle),
                color = tokens.ink2,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(24.dp))
            // Every premium feature, always shown here regardless of which
            // single gate opened this screen — in the order DESIGN_SPEC §5
            // lists them.
            Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                FeatureRow(icon = Icons.Filled.Description, text = stringResource(R.string.paywall_feature_export), tokens = tokens)
                FeatureRow(icon = Icons.Filled.TextSnippet, text = stringResource(R.string.paywall_feature_ocr), tokens = tokens)
                FeatureRow(icon = Icons.Filled.Create, text = stringResource(R.string.paywall_feature_sign), tokens = tokens)
                FeatureRow(icon = Icons.Filled.AllInclusive, text = stringResource(R.string.paywall_feature_unlimited), tokens = tokens)
                FeatureRow(icon = Icons.Filled.Lock, text = stringResource(R.string.paywall_feature_password), tokens = tokens)
            }
            Spacer(Modifier.height(16.dp))
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(tokens.surface)
                .padding(horizontal = 22.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (plansState) {
                PlansState.Loading -> Box(Modifier.fillMaxWidth().padding(vertical = 36.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = tokens.accent, modifier = Modifier.size(28.dp))
                }
                PlansState.Failed -> Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(stringResource(R.string.paywall_load_failed), color = tokens.ink2, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                    TextButton(onClick = { premiumManager.reloadPlans() }) {
                        Text(stringResource(R.string.paywall_try_again), color = tokens.accent, fontWeight = FontWeight.SemiBold)
                    }
                }
                is PlansState.Loaded -> {
                    val savings = savingsPercent(plans)
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        plans.forEach { plan ->
                            PlanCard(
                                plan = plan,
                                isSelected = plan.basePlanId == selectedPlan?.basePlanId,
                                badge = if (plan.isYearly && savings != null) stringResource(R.string.paywall_save_percent, savings) else null,
                                enabled = !isPurchasing,
                                tokens = tokens,
                                onClick = { selectedPlanId = plan.basePlanId },
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(tokens.accent)
                            .clickable(enabled = !isPurchasing && !isRestoring && selectedPlan != null) {
                                val activity = context.findActivity() ?: return@clickable
                                val plan = selectedPlan ?: return@clickable
                                isPurchasing = true
                                premiumManager.launchPurchase(activity, plan)
                            }
                            .padding(vertical = 15.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isPurchasing) {
                            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                        } else {
                            Text(
                                if (isTrialEligible) stringResource(R.string.edit_start_free_trial) else stringResource(R.string.paywall_subscribe),
                                color = Color.White,
                                style = MaterialTheme.typography.titleMedium,
                            )
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    selectedPlan?.let { plan ->
                        Text(
                            finePrint(plan),
                            color = tokens.ink2,
                            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            stringResource(R.string.paywall_auto_renew_disclosure),
                            color = tokens.ink2,
                            style = MaterialTheme.typography.labelSmall,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                if (isRestoring) {
                    CircularProgressIndicator(color = tokens.ink2, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                } else {
                    FooterLink(stringResource(R.string.paywall_restore_purchases), tokens) {
                        if (isPurchasing) return@FooterLink
                        isRestoring = true
                        premiumManager.restorePurchases { restored ->
                            isRestoring = false
                            onFinished(if (restored) PaywallOutcome.RESTORED else PaywallOutcome.NOT_RESTORED)
                        }
                    }
                }
                if (LegalLinks.TERMS_OF_USE.isNotEmpty()) {
                    FooterLink(stringResource(R.string.paywall_terms), tokens) { context.openUrl(LegalLinks.TERMS_OF_USE) }
                }
                if (LegalLinks.PRIVACY_POLICY.isNotEmpty()) {
                    FooterLink(stringResource(R.string.paywall_privacy), tokens) { context.openUrl(LegalLinks.PRIVACY_POLICY) }
                }
            }
        }
    }

    alertMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { alertMessage = null },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { alertMessage = null }) { Text(stringResource(R.string.action_done)) }
            },
        )
    }
}

@Composable
private fun PlanCard(
    plan: PlanOption,
    isSelected: Boolean,
    badge: String?,
    enabled: Boolean,
    tokens: AppColorTokens,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (isSelected) tokens.accentSoft else tokens.bg)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) tokens.accent else tokens.line, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (isSelected) tokens.accent else tokens.ink3,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(if (plan.isYearly) R.string.paywall_plan_yearly else R.string.paywall_plan_monthly),
                    color = tokens.ink,
                    style = MaterialTheme.typography.titleSmall,
                )
                if (badge != null) {
                    Text(
                        badge,
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(tokens.accent)
                            .padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            }
            if (plan.hasFreeTrial) {
                Text(stringResource(R.string.paywall_three_days_free), color = tokens.ink2, style = MaterialTheme.typography.bodySmall)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(plan.formattedPrice, color = tokens.ink, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
            Text(
                stringResource(if (plan.isYearly) R.string.paywall_per_year else R.string.paywall_per_month),
                color = tokens.ink3,
                style = MaterialTheme.typography.labelSmall,
            )
        }
    }
}

@Composable
private fun finePrint(plan: PlanOption): String = when {
    plan.hasFreeTrial && plan.isYearly -> stringResource(R.string.paywall_trial_fine_print_year, plan.formattedPrice)
    plan.hasFreeTrial -> stringResource(R.string.paywall_trial_fine_print_month, plan.formattedPrice)
    plan.isYearly -> stringResource(R.string.paywall_fine_print_year, plan.formattedPrice)
    else -> stringResource(R.string.paywall_fine_print_month, plan.formattedPrice)
}

/** "Save N%" — yearly vs. 12× monthly, from Play's prices (same currency only). */
private fun savingsPercent(plans: List<PlanOption>): Int? {
    val yearly = plans.firstOrNull { it.isYearly } ?: return null
    val monthly = plans.firstOrNull { !it.isYearly } ?: return null
    if (yearly.currencyCode != monthly.currencyCode || monthly.monthlyEquivalentMicros <= 0) return null
    val percent = ((1.0 - yearly.monthlyEquivalentMicros.toDouble() / monthly.monthlyEquivalentMicros) * 100).toInt()
    return percent.takeIf { it > 0 }
}

@Composable
private fun FooterLink(text: String, tokens: AppColorTokens, onClick: () -> Unit) {
    Text(
        text,
        color = tokens.ink2,
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier.clickable(onClick = onClick).padding(vertical = 4.dp),
    )
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String, tokens: AppColorTokens) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(20.dp).width(26.dp))
        Text(text, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun Context.findActivity(): Activity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

private fun Context.openUrl(url: String) {
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
}
