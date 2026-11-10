import SwiftUI
import Combine
import FirebaseAuth
import WidgetKit

/// Local per-account balance and inventory. Firebase sync can be added once the team agrees on a schema.
final class DesignState: ObservableObject {
    @Published private(set) var points = 30
    @Published private(set) var minutesFocused = 0
    @Published private(set) var unlockedItems: Set<String> = []
    private var rewardedSpots: Set<String> = []
    private var userID = ""

    func configure(userID: String) {
        guard !userID.isEmpty, self.userID != userID else { return }
        self.userID = userID
        let defaults = UserDefaults.standard
        points = defaults.object(forKey: key("points")) as? Int ?? 30
        minutesFocused = defaults.integer(forKey: key("minutes"))
        unlockedItems = Set(defaults.stringArray(forKey: key("items")) ?? [])
        rewardedSpots = Set(defaults.stringArray(forKey: key("rewardedSpots")) ?? [])
        publishWidgetBalance()
    }

    private func key(_ name: String) -> String { "study.\(userID).\(name)" }

    func owns(_ id: String) -> Bool { unlockedItems.contains(id) }

    @discardableResult
    func unlock(_ id: String, cost: Int) -> Bool {
        guard !userID.isEmpty, cost >= 0, points >= cost else { return false }
        if unlockedItems.contains(id) { return true }
        points -= cost
        unlockedItems.insert(id)
        UserDefaults.standard.set(points, forKey: key("points"))
        publishWidgetBalance()
        UserDefaults.standard.set(Array(unlockedItems), forKey: key("items"))
        return true
    }

    func completeFocusSession(minutes: Int) {
        minutesFocused += minutes
        awardPoints(20)
        UserDefaults.standard.set(minutesFocused, forKey: key("minutes"))
    }

    func awardPoints(_ amount: Int) {
        guard !userID.isEmpty, amount > 0 else { return }
        points += amount
        UserDefaults.standard.set(points, forKey: key("points"))
        publishWidgetBalance()
    }

    private func publishWidgetBalance() {
        guard !userID.isEmpty else { return }
        let shared = UserDefaults(suiteName: "group.nookie")
        shared?.set(points, forKey: "widget.coinBalance")
        WidgetCenter.shared.reloadTimelines(ofKind: "NookieWidget")
    }

    /// One reward per spot per account, so editing a report does not mint points repeatedly.
    func awardContribution(spotID: String) {
        guard !rewardedSpots.contains(spotID) else { return }
        rewardedSpots.insert(spotID)
        UserDefaults.standard.set(Array(rewardedSpots), forKey: key("rewardedSpots"))
        awardPoints(10)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var state = DesignState()
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack {
            tabContent(.home) { HomeView() }
            tabContent(.map) { StudyMapScreen() }
            tabContent(.decorate) { StudyTimerView() }
            tabContent(.profile) { ProfileView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $tab)
        }
        .background(Color.white.ignoresSafeArea())
        .environmentObject(state)
        .onAppear {
            state.configure(userID: auth.user?.uid ?? "")
            NookieWidgetLocationManager.shared.handleAccountLogin(uid: auth.user?.uid)
        }
        .onChange(of: auth.user?.uid) { _, uid in
            state.configure(userID: uid ?? "")
            NookieWidgetLocationManager.shared.handleAccountLogin(uid: uid)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            NookieWidgetLocationManager.shared.recoverArrivalOnForeground()
        }
    }

    private func tabContent<Content: View>(_ target: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == target ? 1 : 0)
            .allowsHitTesting(tab == target)
            .accessibilityHidden(tab != target)
    }
}


/// Keep the single shared widget bound to the current Firebase account.
/// Personal preferences live in an account-specific UserDefaults suite.
enum NookieAccountWidgetSync {
    static func activate(uid: String?) {
        guard let shared = UserDefaults(suiteName: "group.nookie") else { return }
        let previous = shared.string(forKey: "widget.activeUserID")
        if previous != uid {
            for key in ["widget.pendingVote", "widget.lastVoteAt", "widget.rewardAt",
                        "widget.nearby", "widget.cafe", "widget.hourlyLevels",
                        "widget.coinBalance", "widget.voteSpotID", "widget.showCrowdPrompt",
                        "widget.lastViewedSpotID", "widget.lastViewedCafe",
                        "widget.lastProximityVerifiedAt", "widget.proximityExpiresAt",
                        "widget.cooldownSpotID", "widget.cooldownUntil"] {
                shared.removeObject(forKey: key)
            }
        }
        shared.set(uid, forKey: "widget.activeUserID")
        if let uid, !uid.isEmpty {
            let account = UserDefaults(suiteName: "nookie.account.\(uid)")
            if let spot = account?.string(forKey: "widget.cooldownSpotID"),
               let until = account?.object(forKey: "widget.cooldownUntil") as? Date,
               until > Date() {
                shared.set(spot, forKey: "widget.cooldownSpotID")
                shared.set(until, forKey: "widget.cooldownUntil")
            } else {
                shared.removeObject(forKey: "widget.cooldownSpotID")
                shared.removeObject(forKey: "widget.cooldownUntil")
            }
        }
        guard let uid, !uid.isEmpty else {
            for key in ["model", "hair", "top", "bottom", "shoes"] {
                shared.removeObject(forKey: "character.v2.\(key)")
            }
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let account = UserDefaults(suiteName: "nookie.account.\(uid)")
        let defaults = ["model": 0, "hair": 7, "top": 1, "bottom": 1, "shoes": 1]
        for (key, fallback) in defaults {
            shared.set(account?.object(forKey: "character.v2.\(key)") as? Int ?? fallback,
                       forKey: "character.v2.\(key)")
        }
        shared.set(UserDefaults.standard.integer(forKey: "study.\(uid).points") == 0 &&
                   UserDefaults.standard.object(forKey: "study.\(uid).points") == nil
                   ? 30 : UserDefaults.standard.integer(forKey: "study.\(uid).points"),
                   forKey: "widget.coinBalance")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
