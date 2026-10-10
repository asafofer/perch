import Testing
import Foundation
@testable import PerchCore

/// The card's body from the agent's own words: the gist of a long reply, and what it did when the reply says nothing.
@Suite struct RecapOutcomeTests {
    @Test func aLeadInThatSaysSomethingEndsWithAFullStop() {
        let reply = "Done. The hero now fits at phone width:\n\n- Padding drops from 96px to 48px under 640px\n- The headline wraps at 18ch instead of overflowing\n\nI left the poster image in its place.\n\nWant me to bring the video back for desktop only?"
        #expect(Recap.outcome(reply) == "The hero now fits at phone width.")
    }
    @Test func aSummarySectionIsReadFirst() {
        let reply = "I'll walk you through what changed.\n\n## Summary\n\nThe parser now skips code blocks, so the card never shows raw fences. Tests cover three shapes.\n\n## Details\n\n1. `Recap.outcome` drops fenced blocks first.\n2. Inline code stays."
        #expect(Recap.outcome(reply) == "The parser now skips code blocks, so the card never shows raw fences. Tests cover three shapes.")
        #expect(Recap.outcome("I looked into it.\n\nTL;DR: the cache was never cleared, so old cards stayed.") == "The cache was never cleared, so old cards stayed.")
        #expect(Recap.outcome("**Summary:** the build passes again.\n\nI also tidied the imports.") == "The build passes again.")
    }
    @Test func openersThatOnlyAnnounceAreSkipped() {
        let reply = "Let me look at the three files you mentioned first.\n\nI read `Transcript.swift`, `Project.swift` and `SessionScan.swift`. The scan was dropping sessions whose first line was a summary record, because it expected a user message there."
        #expect(Recap.outcome(reply) == "I read `Transcript.swift`, `Project.swift` and `SessionScan.swift`.")
        #expect(Recap.outcome("Here\u{2019}s what I found:\n\n| File | Lines |\n|---|---|\n| a.swift | 120 |\n\nThe biggest file is a.swift at 120 lines.") == "The biggest file is a.swift at 120 lines.")
    }
    @Test func codeBlocksAreNeverTheOutcome() {
        #expect(Recap.outcome("```\nLiveStatus.swift\nNotchGeometry.swift\n```\n\nNone of them read pi sessions.") == "None of them read pi sessions.")
        #expect(Recap.outcome("``` LiveStatus.swift NotchGeometry.swift ``` None of them read pi sessions.") == "None of them read pi sessions.")
        #expect(Recap.outcome("```swift\nlet x = 1") == nil)
    }
    @Test func listItemsJoinAsSentencesNeverRunTogether() {
        #expect(Recap.outcome("Done.\n1. Fixed the hero spacing\n2. Cut the video") == "Fixed the hero spacing. Cut the video.")
        // A paragraph and the list after it are two things: the second sentence comes only from the same one.
        #expect(Recap.outcome("The build passes again.\n\n- Fixed the import order") == "The build passes again.")
    }
    @Test func aDashInProseIsNotAList() {
        #expect(Recap.outcome("The build passes - all 120 tests.\nNothing else changed.") == "The build passes - all 120 tests. Nothing else changed.")
    }
}

@Suite struct RecapWhatItDidTests {
    func line(_ type: String, _ content: String, stop: String? = nil) -> String {
        let s = stop.map { #","stop_reason":"\#($0)""# } ?? ""
        return #"{"type":"\#(type)","sessionId":"s1","cwd":"/Users/a/site","timestamp":"2026-10-07T09:0\#(Int.random(in: 0...9)):00.000Z","message":{"content":\#(content)\#(s)}}"#
    }
    func tool(_ name: String, _ input: String) -> String { line("assistant", #"[{"type":"tool_use","id":"t\#(Int.random(in: 0...99999))","name":"\#(name)","input":\#(input)}]"#, stop: "tool_use") }
    func reply(_ text: String) -> String { line("assistant", #"[{"type":"text","text":"\#(text)"}]"#, stop: "end_turn") }
    func ask(_ text: String) -> String { line("user", #""\#(text)""#) }
    let result = #"{"type":"user","timestamp":"2026-10-07T09:01:00.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#
    func card(_ lines: [String]) -> Project { Recap.project(digest: TranscriptParser.digest(lines: lines), git: nil, now: Date())! }

    @Test func aCommitSaysWhatWasCommitted() {
        let commit = #"{"command":"git add -A && git commit -m \"$(cat <<'EOF'\nAdd texture presets\n\nMore words.\nEOF\n)\"","description":"Commit the changes"}"#
        #expect(card([ask("commit this"), tool("Bash", commit), result, reply("Done.")]).context == "Committed: Add texture presets")
        #expect(card([ask("commit"), tool("Bash", #"{"command":"git commit -am 'Fix the sign'"}"#), result, reply("Done.")]).context == "Committed: Fix the sign")
    }
    @Test func editsNameTheFiles() {
        let edit = { (f: String) in tool("Edit", #"{"file_path":"/Users/a/site/\#(f)","old_string":"a","new_string":"b"}"#) }
        #expect(card([ask("fix it"), edit("a.swift"), result, reply("Done.")]).context == "Edited a.swift")
        #expect(card([ask("fix it"), edit("a.swift"), result, edit("b.swift"), result, edit("a.swift"), result, reply("Fixed.")]).context == "Edited a.swift and b.swift")
        #expect(card([ask("fix it"), edit("a.swift"), result, edit("b.swift"), result, edit("c.swift"), result, reply("Done!")]).context == "Edited 3 files")
    }
    @Test func aCommandSaysWhatRan() {
        #expect(card([ask("test it"), tool("Bash", #"{"command":"swift test","description":"Run the test suite"}"#), result, reply("Done.")]).context == "Ran the test suite")
        #expect(card([ask("restart"), tool("Bash", #"{"command":"./scripts/run.sh"}"#), result, reply("Done.")]).context == "Ran `./scripts/run.sh`")
    }
    @Test func aShortAnswerIsTheAnswer() {
        // Only read and answered: the answer itself, as written.
        #expect(card([ask("which macOS?"), tool("Read", #"{"file_path":"/Users/a/site/Package.swift"}"#), result, reply("macOS 26.")]).context == "macOS 26.")
        #expect(card([ask("and in one word?"), reply("Notch.")]).context == "Notch.")
    }
    @Test func onlyTheLastTurnCounts() {
        let edit = tool("Edit", #"{"file_path":"/Users/a/site/a.swift","old_string":"a","new_string":"b"}"#)
        #expect(card([ask("fix it"), edit, result, reply("Done."), ask("thanks, anything else?"), reply("Sure!")]).context == "You asked: \u{201C}thanks, anything else?\u{201D}")
    }
    @Test func codexPatchesNameTheFiles() {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"c1","cwd":"/Users/a/site","originator":"codex-tui"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-07T09:00:00.000Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"fix the sign"}]}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Update File: /Users/a/site/sign.css\n@@\n-a\n+b\n*** End Patch"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-07T09:01:00.000Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}"#,
        ]
        let d = CodexTranscript.digest(lines: lines)
        #expect(d.work.edited == ["sign.css"])
        #expect(Recap.project(digest: d, git: nil, now: Date(), agent: .codex)?.context == "Edited sign.css")
    }
    @Test func pastTenseOfACommandsDescription() {
        #expect(Activity.past("Run the test suite") == "Ran the test suite")
        #expect(Activity.past("Check git status") == "Checked git status")
        #expect(Activity.past("Stop the server") == "Stopped the server")
        #expect(Activity.past("Build the app") == "Built the app")
        #expect(Activity.past("Format the code") == "Formatted the code")
        #expect(Activity.past("Verify the signature") == "Verified the signature")
        #expect(Activity.past("Rebuild and relaunch") == "Rebuilt and relaunched")
        #expect(Activity.past("Git status") == "Ran git status")
        #expect(Activity.past("npm test") == "Ran npm test")
    }
}
