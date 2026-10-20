import SwiftUI
import Combine
import FirebaseAuth

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
        .onAppear { state.configure(userID: auth.user?.uid ?? "") }
        .onChange(of: auth.user?.uid) { _, uid in state.configure(userID: uid ?? "") }
    }

    private func tabContent<Content: View>(_ target: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == target ? 1 : 0)
            .allowsHitTesting(tab == target)
            .accessibilityHidden(tab != target)
    }
}
