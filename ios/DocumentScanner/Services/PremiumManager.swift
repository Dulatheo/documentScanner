import Foundation
import StoreKit

/// App Store product identifiers for the Premium subscription group.
/// Both are auto-renewable subscriptions in the same group ("Premium"), each
/// with a 3-day free-trial introductory offer configured in App Store
/// Connect (and in `Products.storekit` for local testing).
enum PremiumProducts {
    static let monthly = "com.documents.scanner.app.premium.monthly"
    static let yearly = "com.documents.scanner.app.premium.yearly"
    static let all = [yearly, monthly]
}

/// Premium entitlement backed by StoreKit 2, gating premium-only tools
/// (Sign, OCR, Office export, PDF password, unlimited documents —
/// DESIGN_SPEC §5) behind the paywall (`PaywallView`).
///
/// The source of truth is `Transaction.currentEntitlements`; nothing is
/// granted locally. A `Transaction.updates` listener picks up renewals,
/// Ask to Buy approvals, refunds and purchases made on other devices.
@MainActor
final class PremiumManager: ObservableObject {
    enum PurchaseResult {
        case success(isTrial: Bool)
        case pending
        case cancelled
        case failed(String)
    }

    enum Plan {
        case monthly, yearly
    }

    /// Whether premium features are currently unlocked — an active,
    /// verified, non-revoked subscription (including one in its free trial).
    @Published private(set) var isPremium = false
    /// Whether the user can still get the 3-day free trial. Starts `true`
    /// until StoreKit answers, so a first-time visitor never sees the
    /// "subscribe" variant flash before the trial one.
    @Published private(set) var isTrialEligible = true
    /// End of the current subscription period (trial end while trialing,
    /// next renewal date otherwise).
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isInTrialPeriod = false
    @Published private(set) var activePlan: Plan?
    @Published private(set) var willAutoRenew = true

    /// Loaded subscription products, yearly first.
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productsLoadFailed = false

    /// Free-tier document cap (DESIGN_SPEC §5/§9 "unlimited scanning"):
    /// non-premium users can have at most this many documents in their
    /// library at once; Premium removes the cap entirely.
    static let freeDocumentLimit = 3

    private var updatesTask: Task<Void, Never>?
    private let cachedPremiumKey = "premium.cachedIsPremium"

    init() {
        // Last known state, so gates don't flicker closed on launch while
        // StoreKit is still answering; corrected by `updateEntitlements()`.
        isPremium = UserDefaults.standard.bool(forKey: cachedPremiumKey)
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.updateEntitlements()
            }
        }
        Task {
            await loadProducts()
            await updateEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Derived state used across the app

    /// Kept for existing call sites: the inverse of trial eligibility.
    var hasUsedTrial: Bool { !isTrialEligible }

    var isTrialActive: Bool {
        isPremium && isInTrialPeriod && (expirationDate.map { $0 > Date() } ?? false)
    }

    /// Whole days left in an active trial, for display (e.g. "2 days left").
    var trialDaysRemaining: Int {
        guard isTrialActive, let end = expirationDate else { return 0 }
        return max(1, Int(ceil(end.timeIntervalSinceNow / (24 * 60 * 60))))
    }

    var monthlyProduct: Product? { products.first { $0.id == PremiumProducts.monthly } }
    var yearlyProduct: Product? { products.first { $0.id == PremiumProducts.yearly } }

    /// Whether a new document can be created given the library's current
    /// size — always true once premium, otherwise gated by
    /// `freeDocumentLimit`.
    func canCreateNewDocument(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeDocumentLimit
    }

    /// Re-checks entitlements (e.g. a period may have lapsed since launch).
    func refresh() {
        if let end = expirationDate, end <= Date() {
            isPremium = false
        }
        Task { await updateEntitlements() }
    }

    // MARK: - StoreKit

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        productsLoadFailed = false
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: PremiumProducts.all)
            products = loaded.sorted { lhs, _ in lhs.id == PremiumProducts.yearly }
            productsLoadFailed = products.isEmpty
            await updateTrialEligibility()
        } catch {
            productsLoadFailed = true
        }
    }

    func purchase(_ product: Product) async -> PurchaseResult {
        let wasEligible = isTrialEligible && product.subscription?.introductoryOffer != nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed(String(localized: "The purchase couldn't be verified."))
                }
                await transaction.finish()
                await updateEntitlements()
                return .success(isTrial: wasEligible)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// "Restore Purchases": syncs with the App Store (may prompt for the
    /// Apple Account password) and re-reads entitlements.
    func restorePurchases() async -> Bool {
        try? await AppStore.sync()
        await updateEntitlements()
        return isPremium
    }

    func updateEntitlements() async {
        var best: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  PremiumProducts.all.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true
            else { continue }
            if best == nil || (transaction.expirationDate ?? .distantFuture) > (best?.expirationDate ?? .distantPast) {
                best = transaction
            }
        }

        if let transaction = best {
            isPremium = true
            expirationDate = transaction.expirationDate
            activePlan = transaction.productID == PremiumProducts.yearly ? .yearly : .monthly
            if #available(iOS 17.2, *) {
                isInTrialPeriod = transaction.offer?.type == .introductory
            } else {
                isInTrialPeriod = transaction.offerType == .introductory
            }
            willAutoRenew = await autoRenewEnabled(for: transaction.productID)
        } else {
            isPremium = false
            expirationDate = nil
            activePlan = nil
            isInTrialPeriod = false
            willAutoRenew = true
        }
        UserDefaults.standard.set(isPremium, forKey: cachedPremiumKey)
        await updateTrialEligibility()
    }

    private func updateTrialEligibility() async {
        // Intro-offer eligibility is per subscription group, so either
        // product answers for both.
        guard let subscription = (yearlyProduct ?? monthlyProduct)?.subscription else { return }
        isTrialEligible = await subscription.isEligibleForIntroOffer
    }

    private func autoRenewEnabled(for productID: String) async -> Bool {
        guard let product = products.first(where: { $0.id == productID }),
              let statuses = try? await product.subscription?.status else { return true }
        for status in statuses where status.state == .subscribed || status.state == .inGracePeriod {
            if case .verified(let info) = status.renewalInfo {
                return info.willAutoRenew
            }
        }
        return true
    }
}

extension Product {
    /// Price per month for a subscription, for the yearly plan's savings badge.
    var monthlyEquivalentPrice: Decimal? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .month: months = Decimal(period.value)
        case .year: months = Decimal(period.value * 12)
        case .week: months = Decimal(period.value) / Decimal(4.345)
        case .day: months = Decimal(period.value) / Decimal(30)
        @unknown default: return nil
        }
        return months > 0 ? price / months : nil
    }

    var hasFreeTrialOffer: Bool {
        subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
}
