//
//  DecorateAndProfileViews.swift
//  Design layer – Decorate, My account, Personal Information
//

import SwiftUI

// MARK: - Decorate

struct DecorateView: View {
    enum DecorTab: Hashable { case furniture, clothes, walls }

    @EnvironmentObject private var state: DesignState

    @State private var tab: DecorTab = .furniture
    @State private var selectedItem: String?

    // 피그마엔 8개가 한 화면에 있었는데, 탭별로 4개씩 나눴어요. (탭 이름과 맞추려고)
    private let items: [DecorTab: [String]] = [
        .furniture: ["Desk", "Chair", "Lamp", "Plant"],
        .clothes: ["Shirt", "Hat", "Glass", "Bag"],
        .walls: ["Paint", "Window", "Poster", "Shelf"]
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Decorate")
                        .font(Theme.heading(34))
                        .foregroundStyle(Theme.navy)

                    Text("\(state.points) pt")
                        .font(Theme.heading(28))
                        .foregroundStyle(Theme.sage)
                }
                .padding(.horizontal, 4)

                AssetImage(name: "decorate_room", symbol: "chair.lounge")
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.5, contentMode: .fit)
                    .themedCard(Theme.roomBG, radius: 36)

                PillSegmented(
                    options: [
                        PillOption(DecorTab.furniture, "Furniture"),
                        PillOption(DecorTab.clothes, "Clothes"),
                        PillOption(DecorTab.walls, "Walls")
                    ],
                    selection: $tab,
                    height: 72
                )

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items[tab] ?? [], id: \.self) { name in
                        let isSelected = selectedItem == name

                        Button {
                            // TODO: 포인트로 구매 → 방/아바타에 적용 (로직은 팀원과 연결 필요)
                            selectedItem = isSelected ? nil : name
                        } label: {
                            Text(name)
                                .font(Theme.body(20))
                                .foregroundStyle(Theme.navy)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 96)
                                .background(Theme.mist, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                                            .stroke(Theme.navy, lineWidth: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Save Room") {
                    // TODO: 저장 로직 연결
                }
                .buttonStyle(SagePrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color.white)
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
                .padding(.bottom, 16)
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
                    InfoField(text: auth.friendlyName)
                    InfoField(text: auth.emailText)
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
        AssetImage(name: "profile_avatar", symbol: "person.fill", fill: true)
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
                .font(.system(size: 20, weight: .regular))
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
