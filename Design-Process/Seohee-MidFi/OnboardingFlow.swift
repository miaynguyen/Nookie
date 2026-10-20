//
//  OnboardingFlow.swift
//  Design layer – 온보딩 4장 (Find / Share / Earn / Location)
//

import SwiftUI

private struct OnboardingPage {
    let image: String      // Assets.xcassets 에 넣을 이미지 이름
    let symbol: String     // 이미지가 없을 때 대신 보일 SF Symbol
    let title: String
    let subtitle: String
}

struct OnboardingFlow: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(image: "onboarding_find", symbol: "map",
                       title: "Find your focus space",
                       subtitle: "Discover places to study near you"),
        OnboardingPage(image: "onboarding_share", symbol: "iphone.radiowaves.left.and.right",
                       title: "Share live updates",
                       subtitle: "Report crowd, seats, outlets, and noise"),
        OnboardingPage(image: "onboarding_earn", symbol: "star.circle",
                       title: "Earn & Decorate",
                       subtitle: "Use points to build your personal study room"),
        OnboardingPage(image: "onboarding_location", symbol: "location.circle",
                       title: "Enable your location",
                       subtitle: "See nearby spaces and verify reports within 150 ft")
    ]

    private var lastIndex: Int { pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // 뒤로가기
            HStack {
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.sage)
                            .frame(width: 44, height: 44)
                    }
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 12)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomArea
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: Page

    private func pageView(_ p: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            AssetImage(name: p.image, symbol: p.symbol)
                .padding(24)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.06, contentMode: .fit)
                .themedCard(Theme.cream, radius: 36)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer(minLength: 24)

            Text(p.title)
                .font(Theme.heading(34))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)

            Text(p.subtitle)
                .font(Theme.body(20))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 22)

            Spacer(minLength: 24)
        }
    }

    // MARK: Buttons + dots

    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 14) {
            if page < lastIndex {
                Button(page == lastIndex - 1 ? "Get Started" : "Continue") {
                    withAnimation { page += 1 }
                }
                .buttonStyle(SagePrimaryButtonStyle())

                HStack(spacing: 40) {
                    ForEach(0..<lastIndex, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Theme.sage : Theme.cream)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.top, 20)
                .frame(height: 64)
            } else {
                Button("Allow location") {
                    LocationPermission.shared.request()
                    onFinish()
                }
                .buttonStyle(SagePrimaryButtonStyle())

                Button("Not now") {
                    onFinish()
                }
                .buttonStyle(CreamSecondaryButtonStyle())
            }
        }
    }
}
