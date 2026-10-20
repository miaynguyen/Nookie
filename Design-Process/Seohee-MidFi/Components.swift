//
//  Components.swift
//  Design layer – 공통 컴포넌트
//

import SwiftUI
import UIKit
import CoreLocation
import FirebaseAuth

// MARK: - Asset image (피그마 일러스트가 아직 없으면 SF Symbol로 대체)

struct AssetImage: View {
    let name: String
    var symbol: String = "photo"
    var fill: Bool = false

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: fill ? .fill : .fit)
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .padding(32)
                .foregroundStyle(Theme.sage.opacity(0.6))
        }
    }
}

// MARK: - Button styles

struct SagePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(22, .bold))
            .foregroundStyle(Theme.cream)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.sage, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CreamSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(22, .bold))
            .foregroundStyle(Theme.sage)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Pill segmented control (Community / My saved, Furniture / Clothes / Walls ...)

struct PillOption<T: Hashable> {
    let value: T
    let title: String

    init(_ value: T, _ title: String) {
        self.value = value
        self.title = title
    }
}

struct PillSegmented<T: Hashable>: View {
    let options: [PillOption<T>]
    @Binding var selection: T
    var height: CGFloat = 64

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = selection == option.value

                Button {
                    withAnimation(.snappy) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(Theme.body(20, .bold))
                        .foregroundStyle(isSelected ? Theme.navy : Theme.sage)
                        .frame(maxWidth: .infinity, minHeight: height - 12)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Theme.butter)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

// MARK: - Bottom tab bar

enum AppTab: CaseIterable, Hashable {
    case home, map, decorate, profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .map: return "Map"
        case .decorate: return "Decorate"
        case .profile: return "Profile"
        }
    }

    // 피그마의 커스텀 아이콘을 에셋으로 넣으면 Image(systemName:) 대신 Image("이름")으로 교체하세요.
    var symbol: String {
        switch self {
        case .home: return "house"
        case .map: return "map"
        case .decorate: return "chair.lounge"
        case .profile: return "person.crop.circle"
        }
    }
}

struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab

                Button {
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 24))
                        Text(tab.title)
                            .font(Theme.body(12, .bold))
                    }
                    .foregroundStyle(isSelected ? Theme.navy : Theme.sage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Theme.butter)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.white, in: Capsule())
        .padding(12)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Location permission (온보딩 "Allow location" 버튼용)

final class LocationPermission: NSObject {
    static let shared = LocationPermission()
    private let manager = CLLocationManager()

    func request() {
        manager.requestWhenInUseAuthorization()
    }
}

// MARK: - Auth helpers (팀원 AuthStore는 수정하지 않고 확장만)

extension AuthStore {
    var friendlyName: String {
        if let name = user?.displayName, !name.isEmpty { return name }
        if let email = user?.email, let prefix = email.split(separator: "@").first {
            return String(prefix).capitalized
        }
        return "Friend"
    }

    var emailText: String {
        user?.email ?? "—"
    }
}

// MARK: - Keyboard

func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
