import Foundation

/// Local premium/trial entitlement, gating premium-only tools (Sign, per
/// DESIGN_SPEC §4.3) behind a paywall (`PaywallView`).
///
/// This is a **local mock entitlement store**, not a real payment
/// integration: `startTrial()`/`subscribe()` grant entitlement immediately
/// on tap, backed only by `UserDefaults`, so the paywall's full UX (trial
/// countdown, "already used trial" vs. "never tried" variants, restore) can
/// be built and tested without App Store Connect products existing yet.
/// Wiring this to real StoreKit 2 transactions (`Product.purchase()`,
/// `Transaction.currentEntitlements`, a `Transaction.updates` listener) is a
/// separate, later step once subscription products are created there —
/// at that point `startTrial`/`subscribe`/`restorePurchases` are the seams
/// to replace with real StoreKit calls; the rest of the app (the `isPremium`
/// check gating Sign, the paywall UI) shouldn't need to change.
@MainActor
final class PremiumManager: ObservableObject {
    /// Whether premium features are currently unlocked — either an active
    /// mock subscription or an active mock trial.
    @Published private(set) var isPremium: Bool
    /// Whether the 3-day trial has ever been started, on this device —
    /// once true, it stays true forever (mirroring how a real trial is
    /// one-time-per-account), so the paywall shows the "subscribe" variant
    /// instead of "start trial" from then on, even after the trial ends.
    @Published private(set) var hasUsedTrial: Bool
    @Published private(set) var trialEndDate: Date?

    private let defaults: UserDefaults
    private let trialLength: TimeInterval = 3 * 24 * 60 * 60

    private enum Keys {
        static let hasUsedTrial = "premium.hasUsedTrial"
        static let trialEndDate = "premium.trialEndDate"
        static let isSubscribed = "premium.isSubscribed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasUsedTrial = defaults.bool(forKey: Keys.hasUsedTrial)
        trialEndDate = defaults.object(forKey: Keys.trialEndDate) as? Date
        let isSubscribed = defaults.bool(forKey: Keys.isSubscribed)
        let trialActive = trialEndDate.map { $0 > Date() } ?? false
        isPremium = isSubscribed || trialActive
    }

    var isTrialActive: Bool {
        trialEndDate.map { $0 > Date() } ?? false
    }

    /// Whole days left in an active trial, for display (e.g. "2 days left").
    /// 0 once the trial has ended or none is active.
    var trialDaysRemaining: Int {
        guard let end = trialEndDate, end > Date() else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSinceNow / (24 * 60 * 60))))
    }

    /// Re-reads entitlement state (e.g. in case the trial has expired since
    /// this instance was created) — call on relevant screen appearances
    /// rather than relying solely on the `@Published` values staying fresh,
    /// since nothing here observes wall-clock time passing on its own.
    func refresh() {
        isPremium = defaults.bool(forKey: Keys.isSubscribed) || isTrialActive
    }

    func startTrial() {
        guard !hasUsedTrial else { return }
        let end = Date().addingTimeInterval(trialLength)
        trialEndDate = end
        hasUsedTrial = true
        isPremium = true
        defaults.set(true, forKey: Keys.hasUsedTrial)
        defaults.set(end, forKey: Keys.trialEndDate)
    }

    func subscribe() {
        isPremium = true
        defaults.set(true, forKey: Keys.isSubscribed)
    }

    /// Mock "Restore Purchases" — re-checks local entitlement state.
    /// Returns whether anything was restored, so the caller can show an
    /// appropriate toast ("Restored" vs. "No previous purchase found").
    @discardableResult
    func restorePurchases() -> Bool {
        let wasPremium = isPremium
        refresh()
        return isPremium || wasPremium
    }
}
