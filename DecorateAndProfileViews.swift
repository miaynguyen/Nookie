//
//  DecorateAndProfileViews.swift
//  Design layer – Decorate, My account, Personal Information
//

import SwiftUI

// MARK: - Decorate

struct DecorateView: View {
    @EnvironmentObject private var state: DesignState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Button { dismiss() } label: {
                        Label("Back to Home", systemImage: "chevron.left")
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.navy)
                    }
                    .accessibilityLabel("Back to Home")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Decorate")
                            .font(Theme.heading(34))
                            .foregroundStyle(Theme.navy)

                        Text("\(state.points) pt")
                            .font(Theme.heading(28))
                            .foregroundStyle(Theme.sage)
                    }
                    .padding(.horizontal, 4)

                    CharacterStudioView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 220)
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Profile

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var state: DesignState

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("My account")
                        .font(Theme.heading(34))
                        .foregroundStyle(Theme.navy)

                    ProfileAvatar()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(auth.friendlyName)
                            .font(Theme.heading(32))
                            .foregroundStyle(Theme.navy)

                        Text("\(state.points) pt")
                            .font(Theme.heading(28))
                            .foregroundStyle(Theme.sage)
                    }

                    VStack(spacing: 14) {
                        NavigationLink {
                            PersonalInformationView()
                        } label: {
                            ProfileMenuRow(title: "Personal Information")
                        }

                        // TODO: 아래 3개는 아직 이동할 화면이 없어요 (디자인/기능 추가 시 NavigationLink로 교체)
                        Button {} label: { ProfileMenuRow(title: "My Reports") }
                        Button {} label: { ProfileMenuRow(title: "Refer Friends") }
                        Button {} label: { ProfileMenuRow(title: "Privacy & Location") }
                    }
                    .buttonStyle(.plain)

                    // 팀원 코드의 로그아웃(auth.signOut)을 그대로 호출해요. 피그마엔 없던 버튼이에요.
                    Button("Log out") {
                        auth.signOut()
                    }
                    .buttonStyle(CreamSecondaryButtonStyle())
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 160)
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.sage)
    }
}

struct PersonalInformationView: View {
    @EnvironmentObject private var auth: AuthStore

    // 학교는 아직 저장되는 곳이 없어서 샘플 텍스트예요.
    private let school = "University of Southern California"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                Text("Personal Information")
                    .font(Theme.heading(34))
                    .foregroundStyle(Theme.navy)

                ProfileAvatar()

                VStack(spacing: 14) {
                    InfoField(text: "Username: \(auth.friendlyName)")
                    InfoField(text: school)
                    InfoField(text: "••••••••••")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Small pieces

private struct ProfileAvatar: View {
    var body: some View {
        SavedCharacterArtwork(width: 123)
            .padding(.top, 8)
            .frame(width: 260, height: 290)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }
}

private struct ProfileMenuRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.body(24, .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 19, weight: .regular))
            Spacer()
        }
        // 피그마 그대로 cream 글씨예요. 대비가 약해서 읽기 어려우면 Theme.navy 로 바꿔보세요.
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 72)
        .themedCard(Theme.mist, radius: 36)
    }
}

private struct InfoField: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(Theme.body(22, .semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 72)
        .themedCard(Theme.mist, radius: 36)
    }
}
