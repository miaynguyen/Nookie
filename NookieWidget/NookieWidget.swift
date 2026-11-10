
import SwiftUI
import WidgetKit
import AppIntents

private let nookieAppGroup = "group.nookie"

struct NookieEntry: TimelineEntry {
    let date: Date
    let hair: Int
    let top: Int
    let bottom: Int
    let shoes: Int

    // Shared cafe information
    let cafeName: String
    let spotID: String
    let hourlyLevels: [Int]
    let showCrowdPrompt: Bool
    let queuedVote: Bool
    let confirmationUntil: Date
    let chartConfirmationUntil: Date
    let cooldownUntil: Date
    // A frozen phase per timeline entry avoids reinterpreting a short transition.
    let confirmationPhase: Int // 0 normal, 1 updated chart, 2 reward
    let confirmedHour: Int
    let confirmedLevel: Int
}

struct NookieProvider: TimelineProvider {

    private func makeEntry(at date: Date = Date()) -> NookieEntry {
        let shared = UserDefaults(
            suiteName: "group.nookie"
        )

        let chartUntil = (shared?.object(forKey: "widget.chartConfirmationUntil") as? Date) ?? .distantPast
        let rewardUntil = (shared?.object(forKey: "widget.confirmationUntil") as? Date) ?? .distantPast
        let phase = 0 // Voting returns directly to the default character after submission.
        return NookieEntry(
            date: date,

            hair: shared?.object(
                forKey: "character.v2.hair"
            ) as? Int ?? 7,

            top: shared?.object(
                forKey: "character.v2.top"
            ) as? Int ?? 1,

            bottom: shared?.object(
                forKey: "character.v2.bottom"
            ) as? Int ?? 1,

            shoes: shared?.object(
                forKey: "character.v2.shoes"
            ) as? Int ?? 1,

            cafeName: shared?.string(
                forKey: "widget.lastViewedCafe"
            ) ?? "",

            spotID: shared?.string(
                forKey: "widget.lastViewedSpotID"
            ) ?? "",

            hourlyLevels: shared?.array(
                forKey: "widget.hourlyLevels"
            ) as? [Int] ?? [],

            showCrowdPrompt: (shared?.bool(forKey: "widget.showCrowdPrompt") ?? false)
                && (shared?.string(forKey: "widget.cooldownSpotID") != shared?.string(forKey: "widget.lastViewedSpotID")
                    || ((shared?.object(forKey: "widget.cooldownUntil") as? Date) ?? .distantPast) <= date),
            queuedVote: shared?.data(forKey: "widget.pendingVote") != nil,
            confirmationUntil: rewardUntil,
            chartConfirmationUntil: chartUntil,
            cooldownUntil: shared?.string(forKey: "widget.cooldownSpotID") == shared?.string(forKey: "widget.lastViewedSpotID")
                ? ((shared?.object(forKey: "widget.cooldownUntil") as? Date) ?? .distantPast)
                : .distantPast,
            confirmationPhase: phase,
            confirmedHour: shared?.object(forKey: "widget.confirmedVoteHour") as? Int ?? -1,
            confirmedLevel: shared?.object(forKey: "widget.confirmedVoteLevel") as? Int ?? 0
        )
    }

    func placeholder(in context: Context) -> NookieEntry {
        makeEntry()
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (NookieEntry) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NookieEntry>) -> Void
    ) {
        let now = Date()
        let current = makeEntry(at: now)
        var entries = [current]
        // Also re-evaluate when a cooldown ends; proximity must still be verified.
        if current.cooldownUntil > now {
            entries.append(makeEntry(at: current.cooldownUntil))
        }
        // No fabricated eligibility: only the app can verify proximity again.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
    }
}

private struct NookieCharacterView: View {
    let entry: NookieEntry

    private func layer(
        _ name: String,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            layer("character_model",
                  width: 126, height: 250, x: 0, y: 20)

            if entry.shoes > 0 {
                layer(
                    String(format: "character_shoes_%02d", entry.shoes),
                    width: 98,
                    height: 100 * 82 / 165,
                    x: 13,
                    y: 219
                )
            }

            if entry.bottom > 0 {
                layer(
                    String(format: "character_bottom_%02d", entry.bottom),
                    width: 120,
                    height: entry.bottom == 1 ? 132 : 129,
                    x: 5,
                    y: 120
                )
            }

            if entry.top > 0 {
                layer(
                    String(format: "character_top_%02d", entry.top),
                    width: 95,
                    height: 80,
                    x: 15,
                    y: 80
                )
            }

            if entry.hair > 0 {
                let boyStyle = entry.hair > 5
                let number = boyStyle
                    ? entry.hair - 5
                    : entry.hair

                layer(
                    String(
                        format: "character_hair_%@_%02d",
                        boyStyle ? "boy" : "girl",
                        number
                    ),
                    width: 120,
                    height: !boyStyle && number <= 2 ? 127 : 124,
                    x: boyStyle ? -1 : 3,
                    y: boyStyle ? 0 : 2
                )
            }
        }
        .frame(width: 126, height: 275, alignment: .topLeading)
    }
}

private struct NookieCrowdGraph: View {
    let hourlyLevels: [Int]

    private let yellow = Color(red: 0.96, green: 0.82, blue: 0.49)
    private let lightBlue = Color(red: 0.70, green: 0.84, blue: 0.94)
    private let deepBlue = Color(red: 0.14, green: 0.42, blue: 0.72)

    private var hour: Int { Calendar.current.component(.hour, from: Date()) }
    private var startHour: Int { max(0, min(12, hour - 6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Seat availability")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.25))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(startHour..<(startHour + 12), id: \.self) { slot in
                    let level = slot < hourlyLevels.count ? max(0, min(5, hourlyLevels[slot])) : 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level == 0 ? Color.gray.opacity(0.12) :
                              slot == hour ? deepBlue : abs(slot - hour) <= 3 ? lightBlue : yellow)
                        .frame(maxWidth: .infinity)
                        .frame(height: level == 0 ? 3 : CGFloat(level) * 8)
                }
            }
            .frame(height: 43, alignment: .bottom)
            HStack {
                Text("\(startHour)h")
                Spacer()
                Text("\(hour)h now")
                Spacer()
                Text("\(startHour + 11)h")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Crowd Graph", as: .systemMedium) {
    NookieWidget()
} timeline: {
    NookieEntry(
        date: Date(),
        hair: 7,
        top: 1,
        bottom: 1,
        shoes: 1,
        cafeName: "Juniper Coffee",
        spotID: "demo-cafe",
        hourlyLevels: [
            0, 0, 0, 0, 0, 0,
            1, 2, 2, 3, 4, 4,
            5, 4, 3, 3, 2, 2,
            1, 1, 0, 0, 0, 0
        ],
        showCrowdPrompt: true,
        queuedVote: false,
        confirmationUntil: .distantPast,
        chartConfirmationUntil: .distantPast,
        cooldownUntil: .distantPast,
        confirmationPhase: 1,
        confirmedHour: 12,
        confirmedLevel: 3
    )
    
}

struct NookieWidgetView: View {
    let entry: NookieEntry

    private let cream = Color(
        red: 1.0,
        green: 0.97,
        blue: 0.91
    )

    var body: some View {
        Group {
            if entry.showCrowdPrompt && entry.cooldownUntil <= entry.date {
                crowdLayout
            } else {
                characterLayout
            }
        }
        .containerBackground(cream, for: .widget)
    }

    // Preserve the just-confirmed hour through the first confirmation stage,
    // even if a Firestore listener refreshes shared hourly data meanwhile.
    private var confirmationLevels: [Int] {
        var levels = entry.hourlyLevels.count == 24
            ? entry.hourlyLevels : Array(repeating: 0, count: 24)
        if (0..<24).contains(entry.confirmedHour), (1...5).contains(entry.confirmedLevel) {
            levels[entry.confirmedHour] = entry.confirmedLevel
        }
        return levels
    }

    // First confirmation stage: show the freshly updated report on the graph.
    private var chartConfirmationLayout: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.cafeName.isEmpty ? "Nearby Cafe" : entry.cafeName)
                .font(.custom("LobsterTwo-BoldItalic", size: 22))
                .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.25))
                .lineLimit(1)
            NookieCrowdGraph(hourlyLevels: confirmationLevels)
            Text("Your update was added to the chart!")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.28, green: 0.42, blue: 0.24))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    // Confirmed only after Firestore reports success and the app awards coins.
    private var confirmationLayout: some View {
        VStack(spacing: 9) {
            Text("Thanks for sharing!")
                .font(.custom("LobsterTwo-BoldItalic", size: 27))
                .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.25))
            Text("+5 coins")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(red: 0.28, green: 0.42, blue: 0.24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // SCREEN 1: Default character and Nookie logo
    private var characterLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {

                Image("nookie_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 0.48)
                    .accessibilityLabel("Nookie")

                GeometryReader { portrait in
                    let scale = min(
                        portrait.size.width / 126,
                        portrait.size.height / 155
                    )

                    NookieCharacterView(entry: entry)
                        .scaleEffect(
                            scale,
                            anchor: .topLeading
                        )
                        .frame(
                            width: 126 * scale,
                            height: 155 * scale,
                            alignment: .topLeading
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottom
                        )
                        .clipped()
                }
                .frame(width: geometry.size.width * 0.49)
            }
            .padding(.horizontal, 12)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
    }

    // SCREEN 2: Keep the original Nookie palette and font styling.
    // Voting remains queued for verification in the main app.
    private var crowdLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.cafeName.isEmpty ? "Nearby Cafe" : entry.cafeName)
                .font(.custom("LobsterTwo-BoldItalic", size: 22))
                .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.25))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 7)

            NookieCrowdGraph(hourlyLevels: entry.hourlyLevels)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 9)

            if entry.queuedVote {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Vote saved for verification in Nookie")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.25))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color(red: 0.90, green: 0.94, blue: 0.84),
                            in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 5) {
                    ForEach(1...5, id: \.self) { value in
                        Button(intent: QueueNookieVoteIntent(spotID: entry.spotID, value: value)) {
                            Text(["Empty", "Few", "Half", "Busy", "Full"][value - 1])
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(value >= 4 ? Color.white : Color(red: 0.13, green: 0.22, blue: 0.13))
                                .frame(maxWidth: .infinity, minHeight: 31)
                                .background(nookieVoteColor(value), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func nookieVoteColor(_ value: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.90, green: 0.94, blue: 0.84),
            Color(red: 0.80, green: 0.88, blue: 0.71),
            Color(red: 0.64, green: 0.76, blue: 0.54),
            Color(red: 0.42, green: 0.58, blue: 0.36),
            Color(red: 0.21, green: 0.34, blue: 0.20)
        ]
        return colors[max(0, min(4, value - 1))]
    }

}

struct NookieWidget: Widget {
    let kind = "NookieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: NookieProvider()
        ) { entry in
            NookieWidgetView(entry: entry)
        }
        .configurationDisplayName("Nookie")
        .description("Your customized study companion.")
        .supportedFamilies([.systemMedium])
    }
}
