//
//  OnboardingFlow.swift
//  Four consistent feature pages shown immediately after account creation.
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
                       subtitle: "Use points to style your companion and study room"),
        OnboardingPage(image: "onboarding_location", symbol: "location.circle",
                       title: "Enable your location.",
                       subtitle: "See nearby spaces and verify the reports within 150 feet.")
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.sage)
                            .frame(width: 44, height: 44)
                    }
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 12)

            pageView(pages[page])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page)

            bottomArea
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: Page

    private func pageView(_ p: OnboardingPage) -> some View {
        VStack(spacing: 16) {
            AssetImage(name: p.image, symbol: p.symbol)
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: 265)
                .background(Theme.cream, in: RoundedRectangle(cornerRadius: 30))
                .padding(.horizontal, 24)
            Text(p.title)
                .font(Theme.heading(30))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)
                .frame(height: 80)
            Text(p.subtitle)
                .font(Theme.body(18))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .frame(height: 72, alignment: .top)
                .padding(.horizontal, 35)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: Buttons + dots

    private var bottomArea: some View {
        VStack(spacing: 14) {
            Button(page == lastIndex ? "Allow location" : "Continue") {
                if page < lastIndex {
                    withAnimation { page += 1 }
                } else {
                    LocationPermission.shared.request()
                    onFinish()
                }
            }
            .buttonStyle(SagePrimaryButtonStyle())
            if page == lastIndex {
                Button("Not now") { onFinish() }
                    .font(Theme.body(17, .semibold))
                    .foregroundStyle(Theme.sage)
                    .padding(.vertical, 8)
            }

            HStack(spacing: 24) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Theme.sage : Theme.cream)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(height: 40)
        }
    }
}
