package com.dulatheo.documentscanner.ui.paywall

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.R
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.ui.theme.AppColorTokens
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** How the user left the paywall — lets the presenter (`EditScreen`) close
 * it and show an appropriate toast without `PaywallScreen` needing its own
 * reference to the toast host. */
enum class PaywallOutcome { TRIAL_STARTED, SUBSCRIBED, RESTORED, NOT_RESTORED, DISMISSED }

/**
 * Paywall shown whenever a free user hits any premium gate (Sign/Text
 * tools, the free-tier document limit, Office format export, PDF
 * password — DESIGN_SPEC §5) — same screen everywhere, so the full
 * feature list below (§5's "premium features, in order") is always
 * visible regardless of which single gate actually triggered it. Two copy
 * variants driven by `premiumManager.hasUsedTrial()`: a first-time visitor
 * is offered the 3-day trial; someone who already used it sees a plain
 * subscribe screen with no trial mention, since a real trial is
 * one-time-per-account.
 */
@Composable
fun PaywallScreen(
    premiumManager: PremiumManager,
    reason: String? = null,
    onFinished: (PaywallOutcome) -> Unit,
) {
    val tokens = LocalAppColors.current
    val isTrialEligible = !premiumManager.hasUsedTrial()

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
                if (isTrialEligible) stringResource(R.string.paywall_trial_headline) else stringResource(R.string.paywall_unlock_headline),
                color = tokens.ink,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                if (isTrialEligible) {
                    stringResource(R.string.paywall_trial_subtitle)
                } else {
                    stringResource(R.string.paywall_unlock_subtitle)
                },
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
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(tokens.accent)
                    .clickable {
                        if (isTrialEligible) {
                            premiumManager.startTrial()
                            onFinished(PaywallOutcome.TRIAL_STARTED)
                        } else {
                            premiumManager.subscribe()
                            onFinished(PaywallOutcome.SUBSCRIBED)
                        }
                    }
                    .padding(vertical = 15.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (isTrialEligible) stringResource(R.string.edit_start_free_trial) else stringResource(R.string.paywall_subscribe_price),
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                if (isTrialEligible) stringResource(R.string.paywall_trial_fine_print) else stringResource(R.string.paywall_subscribe_fine_print),
                color = tokens.ink3,
                style = MaterialTheme.typography.labelSmall,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            Text(
                stringResource(R.string.paywall_restore_purchases),
                color = tokens.ink2,
                style = MaterialTheme.typography.labelMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onFinished(
                            if (premiumManager.restorePurchases()) PaywallOutcome.RESTORED else PaywallOutcome.NOT_RESTORED
                        )
                    },
            )
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String, tokens: AppColorTokens) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(20.dp).width(26.dp))
        Text(text, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
    }
}
