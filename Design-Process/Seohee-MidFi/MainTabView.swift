//
//  MainTabView.swift
//  Design layer – 로그인 후 메인 화면 (하단 탭바 + 4개 탭)
//

import SwiftUI
import Combine

/// 홈/타이머/꾸미기에서 같이 쓰는 값들.
/// ⚠️ 지금은 앱을 껐다 켜면 초기화되는 "로컬 값"이에요.
/// 포인트를 진짜로 저장하려면 팀원과 Firestore(users/{uid}) 연결이 필요해요.
final class DesignState: ObservableObject {
    @Published var points = 320
    @Published var sessionsDone = 2
    @Published var sessionGoal = 4
    @Published var minutesFocused = 50
    @Published var coinsToday = 20

    func completeFocusSession(minutes: Int) {
        sessionsDone += 1
        minutesFocused += minutes
        coinsToday += 20
        points += 20
    }

    func awardPoints(_ amount: Int) {
        points += amount
    }
}

struct MainTabView: View {
    @StateObject private var state = DesignState()
    @State private var tab: AppTab = .home

    var body: some View {
        // 탭을 전환해도 지도 화면 상태(검색, 카메라 위치, Firestore 리스너)가 유지되도록
        // 모든 탭을 살려두고 투명도로만 전환해요.
        ZStack {
            tabContent(.home) { HomeView() }
            tabContent(.map) { StudyMapScreen() }
            tabContent(.decorate) { DecorateView() }
            tabContent(.profile) { ProfileView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $tab)
        }
        .background(Color.white.ignoresSafeArea())
        .environmentObject(state)
    }

    private func tabContent<Content: View>(_ target: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == target ? 1 : 0)
            .allowsHitTesting(tab == target)
            .accessibilityHidden(tab != target)
    }
}
