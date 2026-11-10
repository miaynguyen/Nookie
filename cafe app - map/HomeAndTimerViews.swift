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
                    Image("nookie_logo").resizable().scaledToFit().frame(width: 125).frame(maxWidth: .infinity)
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

                        ZStack(alignment: .top) {
                            Theme.cream
                            SavedCharacterArtwork(width: 138)
                                .padding(.top, 10)
                        }
                        .frame(width: 140, height: 170, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .accessibilityLabel("Your avatar portrait")
                    }

                    Text("Your Study Room")
                        .font(Theme.heading(26))
                        .foregroundStyle(Theme.navy)

                    StudyRoomScene()
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(900.0 / 950.0, contentMode: .fit)
                        .themedCard(Theme.roomBG, radius: 36)

                    NavigationLink {
                        DecorateView()
                    } label: {
                        Text("Decorate")
                    }
                    .buttonStyle(SagePrimaryButtonStyle())

                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 180)
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
    private var durations: [Int] { mode == .focus ? [50, 25, 10] : [25, 10, 5] }
    @State private var focusMinutes = 25
    @State private var focusRemaining = 1500
    @State private var breakMinutes = 5
    @State private var breakRemaining = 300
    @State private var showingCompletion = false

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


            }
            .padding(.top, 8)
            .padding(.bottom, 180)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in tick() }
        .alert("🎉 Time is up!", isPresented: $showingCompletion) { Button("Done", role: .cancel) {} }
        .onChange(of: mode) { _, newMode in
            if newMode == .focus { minutes = focusMinutes; remaining = focusRemaining }
            else { minutes = breakMinutes; remaining = breakRemaining }
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
            stat(symbol: "scope", top: nil, bottom: "\(state.minutesFocused) min focused", tint: Theme.navy)
            statDivider
            stat(symbol: "star.circle.fill", top: nil, bottom: "\(state.points) pt total", tint: Color(hex: 0xF0A93B))
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
                .font(.system(size: 29))
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
        saveCurrentTimer()
    }

    private func saveCurrentTimer() {
        if mode == .focus { focusMinutes = minutes; focusRemaining = remaining }
        else { breakMinutes = minutes; breakRemaining = remaining }
    }

    private func tick() {
        guard running else { return }
        if remaining > 0 { remaining -= 1 }
        saveCurrentTimer()
        if remaining == 0 {
            running = false
            showingCompletion = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

}
