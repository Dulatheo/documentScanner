import SwiftUI

/// Shown when a Premium user taps the PRO badge on Home (DESIGN_SPEC §5) —
/// a free user gets `PaywallView` instead, but there's nothing left to sell
/// someone already subscribed, so this just confirms their status and hands
/// off to the platform's own subscription management (`PremiumManager` is a
/// local mock with no billing details of its own to show).
struct SubscriptionInfoView: View {
    @ObservedObject var premiumManager: PremiumManager
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(theme.accent))
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("You're a PRO user")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(theme.ink)
                    .multilineTextAlignment(.center)
                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                } label: {
                    Text("Manage Subscription")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                }

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.ink2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    // `String`, not `LocalizedStringKey` — `%lld` needs formatting via
    // `String(format:)`, which only works on plain `String`; the fixed
    // "active subscription" branch is wrapped in `String(localized:)` at
    // the point of production for the same reason `dismissLabel` is in
    // `ExportSheetView` (this property's own type is `String`, so a literal
    // assigned to it wouldn't auto-resolve through the String Catalog).
    private var statusText: String {
        if premiumManager.isTrialActive {
            let format = String(localized: "Free trial \u{00b7} %lld days left")
            return String(format: format, premiumManager.trialDaysRemaining)
        }
        return String(localized: "Your Premium subscription is active.")
    }
}
