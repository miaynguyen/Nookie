//
//  OnboardingFlow.swift
//  Four consistent feature pages shown immediately after account creation.
//

import SwiftUI
import CoreLocation
import UIKit
import Combine

private struct OnboardingPage {
    let image: String      // Assets.xcassets 에 넣을 이미지 이름
    let symbol: String     // 이미지가 없을 때 대신 보일 SF Symbol
    let title: String
    let subtitle: String
}

struct OnboardingFlow: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var showWidgetInstructions = false
    @StateObject private var locationPermissions = NookieOnboardingLocationStatus()
    @State private var backgroundRequested = false
    private let widgetPageIndex = 2
    private let backgroundPageIndex = 5

    private let pages: [OnboardingPage] = [
        OnboardingPage(image: "onboarding_find", symbol: "map",
                       title: "Find your focus space",
                       subtitle: "Discover places to study near you"),
        OnboardingPage(image: "onboarding_share", symbol: "iphone.radiowaves.left.and.right",
                       title: "Share live updates",
                       subtitle: "Report crowd, seats, outlets, and noise"),
        OnboardingPage(image: "", symbol: "square.grid.2x2",
                       title: "Add your Nookie widget",
                       subtitle: "Keep your companion on your Home Screen and check in with Nookie."),
        OnboardingPage(image: "onboarding_earn", symbol: "star.circle",
                       title: "Earn & Decorate",
                       subtitle: "Use points to style your companion and study room"),
        OnboardingPage(image: "onboarding_location", symbol: "location.circle",
                       title: "Enable your location.",
                       subtitle: "See nearby spaces and verify the reports within 200 feet."),
        OnboardingPage(image: "", symbol: "location.fill.viewfinder",
                       title: "Stay connected to nearby cafes",
                       subtitle: "Optional background check-ins need Always Allow and Precise Location.")
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

            Group {
                if page == widgetPageIndex {
                    widgetPageView
                } else if page == backgroundPageIndex {
                    backgroundLocationPage
                } else {
                    pageView(pages[page])
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page)

            bottomArea
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
        .sheet(isPresented: $showWidgetInstructions) {
            widgetInstructions
        }
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

    // MARK: Home Screen widget invitation

    // iOS does not permit third-party apps to install a Home Screen widget.
    // This screen offers an optional, accurate manual setup walkthrough.
    private var widgetPageView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                Image("nookie_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 70)

                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Theme.navy)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your Nookie companion")
                            .font(Theme.body(16, .semibold))
                            .foregroundStyle(Theme.navy)
                        Text("A little study buddy on your Home Screen")
                            .font(Theme.body(13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .frame(height: 265)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 30))
            .padding(.horizontal, 24)

            Text("Add your Nookie widget")
                .font(Theme.heading(30))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)
                .frame(height: 80)

            Text("See your character and quick crowd check-ins on your Home Screen. Adding a widget is optional.")
                .font(Theme.body(18))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 35)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var widgetInstructions: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Add Nookie to your Home Screen")
                    .font(Theme.heading(26))
                    .foregroundStyle(Theme.navy)
                ForEach(Array([
                    "Go to your iPhone Home Screen and touch and hold an empty area.",
                    "Tap Edit, then Add Widget (or tap the + button on some iOS versions).",
                    "Search for Nookie, choose a medium or large widget, and tap Add Widget.",
                    "Place the widget where you want it, then tap Done."
                ].enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(Theme.body(17, .bold))
                            .foregroundStyle(Theme.navy)
                            .frame(width: 30, height: 30)
                            .background(Theme.cream, in: Circle())
                        Text(instruction)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.navy)
                    }
                }
                Text("The Nookie Widget Extension must be added to the Xcode project and included in the installed app before it can appear in the gallery. iOS requires you to place widgets manually.")
                    .font(Theme.body(13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Got it") { showWidgetInstructions = false }
                    .buttonStyle(SagePrimaryButtonStyle())
            }
            .padding(24)
            .navigationTitle("Widget setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showWidgetInstructions = false }
                }
            }
        }
    }

    // MARK: Optional background arrival onboarding

    private var backgroundLocationPage: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Cafe arrival check-ins", systemImage: "location.circle.fill")
                    .font(Theme.heading(25))
                    .foregroundStyle(Theme.navy)

                Text("Always Allow lets Nookie detect possible cafe arrivals while the app is in the background. Precise Location helps check whether you're within 200 feet.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.navy)

                Label("Always Allow: " + locationPermissions.authorizationLabel,
                      systemImage: "location.fill")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.sage)

                Label("Precise Location: " + locationPermissions.accuracyLabel,
                      systemImage: "scope")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.sage)

                Text("iOS controls permission prompts. If Always or Precise isn't offered, you can enable them in Settings → Privacy & Security → Location Services → Nookie.")
                    .font(Theme.body(13))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 30))
            .padding(.horizontal, 24)

            Text("Your location, your choice")
                .font(Theme.heading(27))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)

            Text("Background check-ins are optional. Nookie still works if you skip this step.")
                .font(Theme.body(16))
                .foregroundStyle(Theme.sage)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 35)

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .onAppear { locationPermissions.refresh() }
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Buttons + dots

    private var bottomArea: some View {
        VStack(spacing: 14) {
            if page == backgroundPageIndex {
                Button(backgroundRequested ? "Check permissions again" : "Enable background check-ins") {
                    backgroundRequested = true
                    NookieWidgetLocationManager.shared.enableArrivalMonitoring()
                    locationPermissions.refresh()
                }
                .buttonStyle(SagePrimaryButtonStyle())

                Button("Open Location Settings") { openLocationSettings() }
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.navy)

                Button("Finish onboarding") { onFinish() }
                    .font(Theme.body(17, .semibold))
                    .foregroundStyle(Theme.sage)
                    .padding(.vertical, 8)
            } else {
                Button(page == widgetPageIndex ? "How to add widget" : (page == backgroundPageIndex - 1 ? "Allow location" : "Continue")) {
                    if page == widgetPageIndex {
                        showWidgetInstructions = true
                    } else if page == backgroundPageIndex - 1 {
                        LocationPermission.shared.request()
                        withAnimation { page += 1 }
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(SagePrimaryButtonStyle())

                if page == widgetPageIndex {
                    Button("Continue") { withAnimation { page += 1 } }
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.sage)
                        .padding(.vertical, 8)
                } else if page == backgroundPageIndex - 1 {
                    Button("Not now") { onFinish() }
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.sage)
                        .padding(.vertical, 8)
                }
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

/// Read-only status for onboarding; the existing arrival manager owns the actual opt-in.
private final class NookieOnboardingLocationStatus: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published private(set) var authorizationLabel = "Not enabled"
    @Published private(set) var accuracyLabel = "Unknown"

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .authorizedAlways: authorizationLabel = "Enabled"
        case .authorizedWhenInUse: authorizationLabel = "While using app only"
        case .denied, .restricted: authorizationLabel = "Not allowed"
        case .notDetermined: authorizationLabel = "Not requested"
        @unknown default: authorizationLabel = "Unknown"
        }
        accuracyLabel = manager.accuracyAuthorization == .fullAccuracy ? "On" : "Off or unavailable"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }
}
