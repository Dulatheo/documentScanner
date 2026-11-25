import StoreKit
import SwiftUI

/// How the user left the paywall — lets the presenter (`EditFlowView`)
/// dismiss and show an appropriate toast without `PaywallView` needing its
/// own reference to `ToastCenter`. Purchase failures and pending (Ask to
/// Buy) purchases are reported inside the paywall itself, which stays open.
enum PaywallOutcome {
    case trialStarted
    case subscribed
    case restored
    case notRestored
    case dismissed
}

/// Legal links shown on the paywall (required by App Review for
/// auto-renewable subscriptions).
enum LegalLinks {
    static let termsOfUse = URL(string: "https://dulatheo.github.io/documentscanner/terms")!
    static let privacyPolicy: URL? = URL(string: "https://dulatheo.github.io/documentscanner/privacy")
    static let support = URL(string: "https://dulatheo.github.io/documentscanner/support")!
}

/// Paywall shown whenever a free user hits any premium gate (Sign/Text
/// tools, the free-tier document limit, Office format export, PDF
/// password — DESIGN_SPEC §5). Offers two plans (yearly preselected,
/// monthly), both with a 3-day free trial for eligible users; prices come
/// from StoreKit so they're localized to the user's storefront.
struct PaywallView: View {
    @ObservedObject var premiumManager: PremiumManager
    /// Optional context shown as a small banner above the headline — e.g.
    /// explaining *why* the paywall appeared when it wasn't a direct tap on
    /// a premium tool (the free document limit, per DESIGN_SPEC §5).
    var reason: String? = nil
    var onFinished: (PaywallOutcome) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var selectedProductID = PremiumProducts.yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alertMessage: String?

    private var isTrialEligible: Bool {
        premiumManager.isTrialEligible && (selectedProduct?.hasFreeTrialOffer ?? true)
    }

    private var selectedProduct: Product? {
        premiumManager.products.first { $0.id == selectedProductID }
    }

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
                            // Plain "Unlock Premium" in both cases: App Review
                            // (3.1.2) wants the billed amount, not the free
                            // trial, to be the most prominent pricing element.
                            Text("Unlock Premium")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(theme.ink)
                                .multilineTextAlignment(.center)
                            Text(
                                premiumManager.isTrialEligible
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

                bottomPanel
            }
        }
        .task {
            if premiumManager.products.isEmpty {
                await premiumManager.loadProducts()
            }
        }
        .alert(
            "Purchase",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .interactiveDismissDisabled(isPurchasing)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if premiumManager.products.isEmpty {
                productsPlaceholder
            } else {
                VStack(spacing: 10) {
                    if let yearly = premiumManager.yearlyProduct {
                        planCard(yearly, title: "Yearly", periodLabel: String(localized: "per year"), badge: savingsBadge)
                    }
                    if let monthly = premiumManager.monthlyProduct {
                        planCard(monthly, title: "Monthly", periodLabel: String(localized: "per month"), badge: nil)
                    }
                }

                Button(action: purchase) {
                    ZStack {
                        Text(isTrialEligible ? "Start Free Trial" : "Subscribe")
                            .opacity(isPurchasing ? 0 : 1)
                        if isPurchasing {
                            ProgressView().tint(.white)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                }
                .disabled(isPurchasing || isRestoring || selectedProduct == nil)

                VStack(spacing: 4) {
                    Text(finePrint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.ink2)
                    Text("Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel it in your account settings.")
                        .font(.system(size: 11))
                        .foregroundColor(theme.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Button(action: restore) {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(isPurchasing || isRestoring)
                Button("Terms of Use") { openURL(LegalLinks.termsOfUse) }
                if let privacy = LegalLinks.privacyPolicy {
                    Button("Privacy Policy") { openURL(privacy) }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(theme.ink2)
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .background(theme.surface)
        .overlay(Divider().overlay(theme.line), alignment: .top)
    }

    @ViewBuilder
    private var productsPlaceholder: some View {
        if premiumManager.isLoadingProducts {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            VStack(spacing: 10) {
                Text("Couldn't load subscription options.")
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
                Button("Try Again") {
                    Task { await premiumManager.loadProducts() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func planCard(_ product: Product, title: LocalizedStringKey, periodLabel: String, badge: String?) -> some View {
        let isSelected = product.id == selectedProductID
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? theme.accent : theme.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.ink)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(theme.accent))
                        }
                    }
                    if premiumManager.isTrialEligible && product.hasFreeTrialOffer {
                        Text("3 days free")
                            .font(.system(size: 12))
                            .foregroundColor(theme.ink2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(theme.ink)
                    Text(periodLabel)
                        .font(.system(size: 11))
                        .foregroundColor(theme.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? theme.accentSoft : theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? theme.accent : theme.line, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    /// "Save 58%" — yearly vs. 12× monthly, from the storefront's prices.
    private var savingsBadge: String? {
        guard let monthly = premiumManager.monthlyProduct?.monthlyEquivalentPrice,
              let yearly = premiumManager.yearlyProduct?.monthlyEquivalentPrice,
              monthly > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: 1 - yearly / monthly).doubleValue
        let percent = Int((ratio * 100).rounded(.down))
        guard percent > 0 else { return nil }
        let format = String(localized: "Save %lld%%")
        return String(format: format, percent)
    }

    private var finePrint: String {
        guard let product = selectedProduct else { return "" }
        let isYearly = product.id == PremiumProducts.yearly
        if isTrialEligible {
            let format = isYearly
                ? String(localized: "3 days free, then %@/year. Cancel anytime.")
                : String(localized: "3 days free, then %@/month. Cancel anytime.")
            return String(format: format, product.displayPrice)
        }
        let format = isYearly
            ? String(localized: "%@/year. Renews automatically. Cancel anytime.")
            : String(localized: "%@/month. Renews automatically. Cancel anytime.")
        return String(format: format, product.displayPrice)
    }

    // `text: LocalizedStringKey`, not `String` — see `EditTool.label`'s doc
    // comment for why: it's what lets `Text(text)` below auto-resolve
    // through the String Catalog for the five literal call sites, with no
    // need to wrap them individually. (`icon` stays `String` — it's an SF
    // Symbol name, not language content.)
    private func featureRow(icon: String, text: LocalizedStringKey) -> some View {
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

    private func purchase() {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        Task {
            let result = await premiumManager.purchase(product)
            isPurchasing = false
            switch result {
            case .success(let isTrial):
                onFinished(isTrial ? .trialStarted : .subscribed)
            case .pending:
                alertMessage = String(localized: "Your purchase is pending approval. Premium will unlock once it's approved.")
            case .cancelled:
                break
            case .failed(let message):
                alertMessage = message
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            let restored = await premiumManager.restorePurchases()
            isRestoring = false
            onFinished(restored ? .restored : .notRestored)
        }
    }
}
