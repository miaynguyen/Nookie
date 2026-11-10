// Add this file to a NEW Widget Extension target in Xcode (iOS 17+).
// The app must publish a sanitized snapshot to the shared App Group.
import SwiftUI
import WidgetKit
import AppIntents

private let group = "group.usc.nookie.shared"
private let navy = Color(red: 19/255, green: 47/255, blue: 67/255)
private let cream = Color(red: 245/255, green: 243/255, blue: 232/255)

struct CrowdEntry: TimelineEntry {
    let date: Date
    let cafe: String
    let levels: [Int]
    let isNearby: Bool
    let lastVoteAt: Date?
    let rewardAt: Date?
    let avatar: [Int]
    var canVote: Bool {
        isNearby && (lastVoteAt.map { date.timeIntervalSince($0) >= 3600 } ?? true)
    }
    var thanks: Bool { false } // No post-vote reward screen
}

struct CrowdProvider: TimelineProvider {
    func placeholder(in context: Context) -> CrowdEntry { load() }
    func getSnapshot(in context: Context, completion: @escaping (CrowdEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CrowdEntry>) -> Void) {
        let entry = load()
        // A request, not a guaranteed refresh. iOS controls actual delivery.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
    private func load() -> CrowdEntry {
        let d = UserDefaults(suiteName: group) ?? .standard
        return CrowdEntry(date: .now,
            cafe: d.string(forKey: "widget.cafe") ?? "Study spot",
            levels: d.array(forKey: "widget.hourlyLevels") as? [Int] ?? Array(repeating: 0, count: 15),
            isNearby: d.bool(forKey: "widget.nearby"),
            lastVoteAt: d.object(forKey: "widget.lastVoteAt") as? Date,
            rewardAt: d.object(forKey: "widget.rewardAt") as? Date,
            avatar: ["model", "hair", "top", "bottom", "shoes"].enumerated().map { index, key in
                let name = "character.v2.\(key)"
                return d.object(forKey: name) == nil ? [0, 7, 1, 1, 1][index] : d.integer(forKey: name)
            })
    }
}

struct CrowdVoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Submit crowd vote"
    static var openAppWhenRun = true // Open app for authenticated Firebase submission and location recheck.
    @Parameter(title: "Crowd level") var level: Int
    init() {}
    init(level: Int) { self.level = level }
    func perform() async throws -> some IntentResult {
        let d = UserDefaults(suiteName: group) ?? .standard
        let cooldownPassed = (d.object(forKey: "widget.lastVoteAt") as? Date)
            .map { Date().timeIntervalSince($0) >= 3600 } ?? true
        guard d.bool(forKey: "widget.nearby"), cooldownPassed,
              (1...5).contains(level) else { return .result() }
        // Queue only. The main app must validate GPS and save to Firestore before rewarding.
        d.set(level, forKey: "widget.pendingVote")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CrowdWidgetView: View {
    let entry: CrowdEntry
    private let labels = ["Empty", "Few", "Half", "Busy", "Full"]
    private let greens: [Color] = [
        Color(red: 0.91, green: 0.94, blue: 0.86),
        Color(red: 0.81, green: 0.87, blue: 0.73),
        Color(red: 0.65, green: 0.77, blue: 0.58),
        Color(red: 0.44, green: 0.60, blue: 0.42),
        Color(red: 0.21, green: 0.36, blue: 0.26)]
    var body: some View {
        VStack(spacing: 8) {
            if entry.thanks {
                Spacer()
                Text("Thanks for sharing!").font(.custom("LobsterTwo-BoldItalic", size: 24))
                Text("+5 coins").font(.custom("Open Sans", size: 23)).bold()
                Spacer()
            } else if entry.canVote {
                Text(entry.cafe).font(.custom("LobsterTwo-BoldItalic", size: 22)).lineLimit(1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<15, id: \.self) { i in
                        let hour = Calendar.current.component(.hour, from: entry.date)
                        let barHour = 8 + i
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barHour == hour ? Color(red: 0.08, green: 0.40, blue: 0.84) : abs(barHour-hour) <= 3 ? Color(red: 0.64, green: 0.79, blue: 0.96) : Color(red: 1, green: 0.88, blue: 0.62))
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(max(4, min(5, entry.levels[i]))) * 8)
                    }
                }.frame(height: 44, alignment: .bottom)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { level in
                        Button(intent: CrowdVoteIntent(level: level)) {
                            Text(labels[level-1])
                                .font(.custom("Open Sans", size: 10)).bold()
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(level > 3 ? .white : navy)
                                .background(greens[level-1], in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Submit").font(.custom("LobsterTwo-BoldItalic", size: 18))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .foregroundStyle(.white).background(navy, in: RoundedRectangle(cornerRadius: 9))
                // Tapping a crowd choice opens the app to validate and submit.
            } else {
                Spacer(minLength: 0)
                Image("nookie_logo").resizable().scaledToFit().frame(height: 55)
                WidgetCharacterHead(style: entry.avatar).frame(height: 115).clipped()
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .containerBackground(cream, for: .widget)
    }
}

// Reuse the original layer image names. The same PNG assets must be included in the widget target.
private struct WidgetCharacterHead: View {
    let style: [Int]
    var body: some View {
        GeometryReader { geo in
            let hair = style.count > 1 ? style[1] : 7
            let boy = hair > 5 || (style.first == 1 && hair <= 5)
            let index = hair > 5 ? hair - 5 : hair
            ZStack(alignment: .topLeading) {
                Image("character_model").resizable().frame(width: 126, height: 250).offset(y: 20)
                if style.count > 2 && style[2] > 0 {
                    Image(String(format: "character_top_%02d", style[2]))
                        .resizable().frame(width: 95, height: 80).offset(x: 15, y: 80)
                }
                if hair > 0 {
                    Image(String(format: "character_hair_%@_%02d", boy ? "boy" : "girl", index))
                        .resizable().frame(width: 120, height: !boy && index <= 2 ? 127 : 124)
                        .offset(x: boy ? -1 : 3, y: boy ? 0 : 2)
                }
            }
            .frame(width: 126, height: 275, alignment: .topLeading)
            .scaleEffect(min(geo.size.width/126, 1.1), anchor: .top)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct NookieCrowdWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NookieCrowdWidget", provider: CrowdProvider()) { entry in
            CrowdWidgetView(entry: entry)
        }
        .configurationDisplayName("Nookie Crowd Check-In")
        .description("Your character and nearby study spot crowd check-ins.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

