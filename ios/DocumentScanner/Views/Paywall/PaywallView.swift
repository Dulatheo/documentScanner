import SwiftUI

/// How the user left the paywall — lets the presenter (`EditFlowView`)
/// dismiss and show an appropriate toast without `PaywallView` needing its
/// own reference to `ToastCenter` (matching how other sheets in this app,
/// e.g. the OCR sheet, hand results back via callback rather than showing
/// toasts themselves).
enum PaywallOutcome {
    case trialStarted
    case subscribed
    case restored
    case notRestored
    case dismissed
}

/// Paywall shown whenever a free user hits any premium gate (Sign/Text
/// tools, the free-tier document limit, Office format export, PDF
/// password — DESIGN_SPEC §5) — same screen everywhere, so the full
/// feature list below (§5's "premium features, in order") is always
/// visible regardless of which single gate actually triggered it. Two copy
/// variants driven by `premiumManager.hasUsedTrial`: a first-time visitor
/// is offered the 3-day trial; someone who already used it sees a plain
/// subscribe screen with no trial mention, since a real trial is
/// one-time-per-account.
struct PaywallView: View {
    @ObservedObject var premiumManager: PremiumManager
    /// Optional context shown as a small banner above the headline — e.g.
    /// explaining *why* the paywall appeared when it wasn't a direct tap on
    /// a premium tool (the free document limit, per DESIGN_SPEC §5).
    var reason: String? = nil
    var onFinished: (PaywallOutcome) -> Void

    @Environment(\.theme) private var theme

    private var isTrialEligible: Bool { !premiumManager.hasUsedTrial }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { onFinished(.dismissed) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.ink2)
                            .padding(10)
                            .background(Circle().fill(theme.surface))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(theme.accent))
                            .padding(.top, 4)

                        if let reason {
                            Text(reason)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(theme.accentSoft))
                        }

                        VStack(spacing: 8) {
                            Text(isTrialEligible ? "Try Premium free for 3 days" : "Unlock Premium")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(theme.ink)
                                .multilineTextAlignment(.center)
                            Text(
                                isTrialEligible
                                    ? "Cancel anytime during your trial \u{2014} you won't be charged early."
                                    : "Subscribe to unlock everything Premium brings."
                            )
                            .font(.system(size: 14))
                            .foregroundColor(theme.ink2)
                            .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 30)

                        // Every premium feature, always shown here regardless
                        // of which single gate opened this screen — in the
                        // order DESIGN_SPEC §5 lists them.
                        VStack(alignment: .leading, spacing: 14) {
                            featureRow(icon: "doc.richtext", text: "Export to Word, Excel & PowerPoint")
                            featureRow(icon: "text.viewfinder", text: "Recognize and copy text from any scan")
                            featureRow(icon: "signature", text: "Sign documents with your finger")
                            featureRow(icon: "infinity", text: "Unlimited saved documents (3 free)")
                            featureRow(icon: "lock.fill", text: "Password-protect your PDF exports")
                        }
                        .padding(.horizontal, 30)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 16)
                }

                VStack(spacing: 14) {
                    Button(action: primaryAction) {
                        Text(isTrialEligible ? "Start Free Trial" : "Subscribe \u{2014} $4.99/mo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                    }

                    Text(isTrialEligible ? "3 days free, then $4.99/month. Cancel anytime." : "$4.99/month. Cancel anytime.")
                        .font(.system(size: 11))
                        .foregroundColor(theme.ink3)
                        .multilineTextAlignment(.center)

                    Button(action: { onFinished(premiumManager.restorePurchases() ? .restored : .notRestored) }) {
                        Text("Restore Purchases")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.ink2)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .padding(.top, 12)
                .background(theme.surface)
                .overlay(Divider().overlay(theme.line), alignment: .top)
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.accent)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(theme.ink)
        }
    }

    private func primaryAction() {
        if isTrialEligible {
            premiumManager.startTrial()
            onFinished(.trialStarted)
        } else {
            premiumManager.subscribe()
            onFinished(.subscribed)
        }
    }
}
