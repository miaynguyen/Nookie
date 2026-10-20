//
//  HomeAndTimerViews.swift
//  Design layer – Home, Study Timer
//

import SwiftUI
import Combine

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var state: DesignState

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning!"
        case 12..<18: return "Good Afternoon!"
        default: return "Good Evening!"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(greeting)
                                .font(Theme.heading(34))
                                .foregroundStyle(Theme.navy)

                            Text(auth.friendlyName)
                                .font(Theme.heading(40))
                                .foregroundStyle(Theme.navy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            Text("\(state.points) pt")
                                .font(Theme.heading(24))
                                .foregroundStyle(Theme.sage)
                        }

                        Spacer(minLength: 8)

                        AssetImage(name: "avatar_portrait", symbol: "person.fill", fill: true)
                            .frame(width: 140, height: 170)
                            .background(Theme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }

                    Text("Your Study room")
                        .font(Theme.heading(26))
                        .foregroundStyle(Theme.navy)

                    AssetImage(name: "decorate_room", symbol: "house")
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.5, contentMode: .fit)
                        .themedCard(Theme.roomBG, radius: 36)

                    NavigationLink {
                        StudyTimerView()
                    } label: {
                        Text("Start Focus")
                    }
                    .buttonStyle(SagePrimaryButtonStyle())

                    Text("Today’s goal \(state.sessionsDone)/\(state.sessionGoal) sessions")
                        .font(Theme.body(24, .bold))
                        .foregroundStyle(Theme.navy)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .themedCard(Theme.butter, radius: 32)
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

// MARK: - Study Timer

struct StudyTimerView: View {
    enum Mode: Hashable { case focus, shortBreak }

    @EnvironmentObject private var state: DesignState

    @State private var mode: Mode = .focus
    @State private var minutes = 25
    @State private var remaining = 25 * 60
    @State private var running = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let durations = [25, 5, 15]

    private var total: Int { minutes * 60 }
    private var fraction: Double { total == 0 ? 0 : Double(remaining) / Double(total) }
    private var timeText: String { String(format: "%02d : %02d", remaining / 60, remaining % 60) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Study Timer")
                    .font(Theme.heading(34))
                    .foregroundStyle(Theme.navy)

                PillSegmented(
                    options: [PillOption(Mode.focus, "Focus"), PillOption(Mode.shortBreak, "Short Break")],
                    selection: $mode,
                    height: 64
                )
                .padding(.horizontal, 20)

                ring
                    .padding(.horizontal, 36)

                durationChips
                    .padding(.horizontal, 20)

                Button(running ? "Pause" : (mode == .focus ? "Start Focus" : "Start Break")) {
                    running.toggle()
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .padding(.horizontal, 20)

                statsCard
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in tick() }
        .onChange(of: mode) { _, newMode in
            setDuration(newMode == .focus ? 25 : 5)
        }
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.mist, lineWidth: 30)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.sage, style: StrokeStyle(lineWidth: 30, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: fraction)

            Circle()
                .fill(Color.white)
                .padding(30)

            VStack(spacing: 8) {
                AssetImage(name: "timer_avatar", symbol: "figure.mind.and.body")
                    .frame(maxWidth: 220, maxHeight: 180)

                Text(timeText)
                    .font(Theme.heading(48))
                    .foregroundStyle(Theme.navy)
            }
            .padding(.horizontal, 44)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Chips

    private var durationChips: some View {
        HStack(spacing: 12) {
            ForEach(durations, id: \.self) { value in
                let isSelected = minutes == value

                Button {
                    setDuration(value)
                } label: {
                    Text("\(value) min")
                        .font(Theme.body(22, .bold))
                        .foregroundStyle(isSelected ? Theme.cream : Theme.navy)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(isSelected ? Theme.sage : Theme.cream, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(running)
            }
        }
    }

    // MARK: Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat(symbol: "calendar", top: "Today", bottom: "\(state.sessionsDone) sessions", tint: Theme.navy)
            statDivider
            stat(symbol: "scope", top: nil, bottom: "\(state.minutesFocused) min focused", tint: Theme.navy)
            statDivider
            stat(symbol: "star.circle.fill", top: nil, bottom: "+\(state.coinsToday) coins", tint: Color(hex: 0xF0A93B))
        }
        .padding(.vertical, 18)
        .themedCard(Theme.mist, radius: 32)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.7))
            .frame(width: 1, height: 70)
    }

    private func stat(symbol: String, top: String?, bottom: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(tint)

            if let top {
                Text(top)
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.sage)
            }

            Text(bottom)
                .font(Theme.body(16, .bold))
                .foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Logic

    private func setDuration(_ newMinutes: Int) {
        running = false
        minutes = newMinutes
        remaining = newMinutes * 60
    }

    private func tick() {
        guard running else { return }

        if remaining > 0 {
            remaining -= 1
        }

        if remaining == 0 {
            running = false
            if mode == .focus {
                state.completeFocusSession(minutes: minutes)
            }
            remaining = total
        }
    }
}
