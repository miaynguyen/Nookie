import Foundation
import AppIntents
import WidgetKit

/// A deliberately non-successful queued action: the main app must validate
/// location, authentication and cooldown before writing to Firestore.
struct QueueNookieVoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Queue Nookie Crowd Vote"
    static var description = IntentDescription("Queue a crowd report for verification in Nookie.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Cafe ID") var spotID: String
    @Parameter(title: "Crowd Level") var value: Int

    init() {}
    init(spotID: String, value: Int) {
        self.spotID = spotID
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        guard (1...5).contains(value), !spotID.isEmpty,
              let shared = UserDefaults(suiteName: "group.nookie"),
              shared.bool(forKey: "widget.showCrowdPrompt"),
              shared.string(forKey: "widget.lastViewedSpotID") == spotID,
              (shared.string(forKey: "widget.cooldownSpotID") != spotID ||
               ((shared.object(forKey: "widget.cooldownUntil") as? Date) ?? .distantPast) <= Date())
        else { return .result() }

        // This is a request, NOT a successful report or a coin award.
        let payload: [String: Any] = [
            "spotID": spotID, "value": value, "createdAt": Date()
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        shared.set(data, forKey: "widget.pendingVote")
        WidgetCenter.shared.reloadTimelines(ofKind: "NookieWidget")
        return .result()
    }
}
