import Testing
import Foundation
@testable import PerchCore

/// A home folder with Grok Bot's saved state and the ChatGPT app's, in the shapes those apps write.
private final class PersonalHome {
    let url: URL
    let now = Date()
    let account = "google-oauth2|user_01TEST"
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-personal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    var scanner: SessionScanner { SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("none"))) }
    func ms(_ offset: TimeInterval) -> Double { (now.timeIntervalSince1970 + offset) * 1000 }

    private var grok: URL { url.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence") }
    func slice(_ key: String, _ value: Any) {
        try? FileManager.default.createDirectory(at: grok, withIntermediateDirectories: true)
        let data = try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "value": value])
        try? data.write(to: grok.appendingPathComponent(GrokBotStore.fileName(key)))
    }
    func accountSlice(_ name: String, _ value: Any) {
        slice("sand.client.slice.account.\(account.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~")))!).\(name)", value)
    }
    func bots(_ rows: [[String: Any]]) {
        slice("sand.client.slice.client-meta.account-slot", account)
        accountSlice("roster.last-roster", ["rows": rows])
    }
    func bot(_ id: String, _ name: String, ago: TimeInterval, unread: Bool = false, waiting: String? = nil, last: String, extra: [String: Any] = [:]) -> [String: Any] {
        var r: [String: Any] = ["id": id, "name": name, "createdAt": ms(-86_400), "lastActivityAt": ms(-ago), "hasUnread": unread,
                                "lastEntry": ["kind": "text", "text": last], "isGroup": false, "isHiddenFromSidebar": false, "isRemovedFromSidebar": false]
        if let waiting { r["awaitingUserResponse"] = ["reason": "question", "reasonCopy": waiting, "since": ms(-ago)] }
        return r.merging(extra) { _, b in b }
    }

    func dots(sidebar: [[String: Any]], primary: [String: Any]? = nil) {
        var state: [String: Any] = ["cloud-aeon-sidebar-cache-v1": ["hostId": "durable", "profilesByThreadId": Dictionary(uniqueKeysWithValues: sidebar.enumerated().map { ("thread\($0.offset)", $0.element) })]]
        if let primary { state["primary-aeon-selection-v1"] = ["response": ["selection": [:], "profile": primary]] }
        let f = url.appendingPathComponent(".codex/.codex-global-state.json")
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: ["electron-persisted-atom-state": state]).write(to: f)
    }
    func iso(_ offset: TimeInterval) -> String {
        // Six fractional digits, as the ChatGPT app writes them.
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: now.addingTimeInterval(offset)).replacingOccurrences(of: "Z", with: "123Z")
    }
}

@Suite struct PersonalAgentsScanTests {
    @Test func grokBotsAreListedOnePerBotWithTheirChat() {
        let h = PersonalHome()
        h.bots([h.bot("b1", "Scout", ago: 60, unread: true, last: "Your flight moved to 9:40."),
                h.bot("b2", "Ledger", ago: 600, last: "Paid the rent."),
                h.bot("b3", "Old", ago: 60, last: "x", extra: ["isRemovedFromSidebar": true])])
        h.accountSlice("transcript.replicas.b1", ["entries": [
            ["kind": "message", "role": "user", "content": "Watch my flight to Lisbon for changes", "timestampMs": h.ms(-300)],
            ["kind": "send-message", "message": ["type": "text", "content": "Your flight moved to 9:40, gate B12."], "timestampMs": h.ms(-60)],
        ]])
        let found = h.scanner.grokBots(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.topic) == ["Scout", "Ledger"])
        #expect(found[0].app == "grokbot"); #expect(found[0].terminal == false); #expect(found[0].sessionId == "b1")
        #expect(found[0].status.text == "Grok Bot replied"); #expect(found[0].focusedAt == nil)   // unread: news
        #expect(found[0].said == "Your flight moved to 9:40, gate B12.")
        #expect(found[0].asked == "Watch my flight to Lisbon for changes")
        #expect(found[1].said == "Paid the rent."); #expect(found[1].focusedAt != nil)   // read, and no chat copy: the list's last message
    }

    @Test func aGrokBotWaitingOnYouSaysSoAndShowsItsQuestion() {
        let h = PersonalHome()
        h.bots([h.bot("q", "Scout", ago: 30, waiting: "Needs your answer", last: "Which seat?")])
        h.accountSlice("transcript.replicas.q", ["entries": [
            ["kind": "send-message", "message": ["type": "widget", "widget": ["prompt": "Which seat?", "options": [["label": "Window"], ["label": "Aisle"]]]], "timestampMs": h.ms(-30)],
            // answered earlier: not open
            ["kind": "send-message", "message": ["type": "widget", "widget": ["prompt": "Old", "options": [["label": "A"]]]], "respondedValue": "A", "timestampMs": h.ms(-20)],
        ]])
        var p = h.scanner.grokBots(limit: 15, now: h.now).first?.project
        #expect(p?.needsAttention == true); #expect(p?.ask == nil)   // the last card was answered
        h.accountSlice("transcript.replicas.q", ["entries": [
            ["kind": "send-message", "message": ["type": "widget", "widget": ["prompt": "Which seat?", "options": [["label": "Window"], ["label": "Aisle"]]]], "timestampMs": h.ms(-30)],
        ]])
        p = h.scanner.grokBots(limit: 15, now: h.now).first?.project
        #expect(p?.ask?.kind == .question); #expect(p?.ask?.questions.first?.options == ["Window", "Aisle"]); #expect(p?.ask?.answerable == true)
        #expect(p?.status.text == "Grok Bot is waiting for you")
    }

    @Test func aGrokBotCardThatGoesAwayOnMoveOnIsNoLongerAsked() {
        let h = PersonalHome()
        h.bots([h.bot("m", "Scout", ago: 30, last: "Never mind, I booked the window.")])
        h.accountSlice("transcript.replicas.m", ["entries": [
            ["kind": "send-message", "message": ["type": "widget", "widget": ["prompt": "Which seat?", "dismissOnMoveOn": true, "options": [["label": "Window"], ["label": "Aisle"]]]], "timestampMs": h.ms(-60)],
            ["kind": "send-message", "message": ["type": "text", "content": "Never mind, I booked the window."], "timestampMs": h.ms(-30)],
        ]])
        let p = h.scanner.grokBots(limit: 15, now: h.now).first?.project
        #expect(p?.ask == nil); #expect(p?.status.text == "Grok Bot replied")
    }

    @Test func aDotIsOneRowFromTheNewestCopyWithItsLastMessage() {
        let h = PersonalHome()
        let room: [String: Any] = ["message_preview": ["latest_item_timestamp": h.iso(-3600), "preview": "Here is your weekly metrics brief."], "last_read_at": h.iso(-7200)]
        let older: [String: Any] = ["id": "aeon1", "display_name": "Pip", "status": "active", "is_paused": true, "created_at": h.iso(-86_400 * 9),
                                    "updated_at": h.iso(-5000), "last_check_in_at": h.iso(-5000), "messaging_room_preview": room]
        let newer: [String: Any] = ["id": "aeon1", "display_name": "Pip", "status": "active", "is_paused": false, "created_at": h.iso(-86_400 * 9),
                                    "updated_at": h.iso(-1800), "last_check_in_at": h.iso(-1800)]
        h.dots(sidebar: [older, older], primary: newer)
        let found = h.scanner.dots(limit: 15, now: h.now).map(\.project)
        #expect(found.count == 1)
        #expect(found.first?.topic == "Pip"); #expect(found.first?.app == "dots")
        #expect(found.first?.status.text == "Dots replied")   // the newer copy is not paused
        #expect(found.first?.said == "Here is your weekly metrics brief.")
        #expect(found.first?.focusedAt == nil)   // its newest message came after you last read it
    }

    @Test func aPausedDotWaitsOnYouAndAnOldOneIsLeftOut() {
        let h = PersonalHome()
        h.dots(sidebar: [["id": "a", "display_name": "Pip", "status": "active", "is_paused": true, "updated_at": h.iso(-600)],
                         ["id": "b", "display_name": "Gone", "status": "active", "is_paused": false, "updated_at": h.iso(-86_400 * 30)],
                         ["id": "c", "display_name": "Bye", "status": "deleting", "is_paused": false, "updated_at": h.iso(-60)]])
        let found = h.scanner.dots(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.topic) == ["Pip"]); #expect(found.first?.needsAttention == true)
    }

    @Test func dotsTimesWithSixFractionalDigitsAreRead() {
        #expect(DotsStore.date("2026-10-14T10:02:49.867829Z") != nil)
        #expect(DotsStore.date("2026-10-14T10:02:49Z") != nil)
    }

    /// Checked against Grok Bot 0.78.1's sidebar: these bots showed as an orange tablet, a violet tablet, a pink teardrop and
    /// (chosen in the app) a black blob.
    @Test func aGrokBotWearsTheShapeAndColourGrokBotGivesIt() {
        #expect(GrokBotStore.look(id: "f616e30e-74cb-4c4c-86af-b06512f66e87", shape: "", color: "") == "tablet:yellow")
        #expect(GrokBotStore.look(id: "06a1e421-e8a5-4420-a9b2-0bb79a23db6e", shape: nil, color: nil) == "tablet:violet")
        #expect(GrokBotStore.look(id: "6a2cf2f0-68b5-4912-b292-c908ea0bb5a3", shape: "", color: "") == "teardrop:magenta")
        #expect(GrokBotStore.look(id: "0cad71b6-17dd-4432-8e5f-d83857037a99", shape: "blob", color: "black") == "blob:black")
        #expect(GrokBotStore.look(id: "x", shape: "pumpkin", color: "nope").hasPrefix("pumpkin:"))
    }

    @Test func grokBotFileNamesAreTheirKeysInBase32() {
        #expect(GrokBotStore.fileName("sand.client.slice.ui-layout") == "onqw4zbomnwgszlooqxhg3djmnss45ljfvwgc6lpov2a.blob")
    }
}
