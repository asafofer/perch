import Foundation
import Testing
@testable import PerchCore

@Suite struct FeedbackTests {
    @Test func emailsThatLookLikeOne() {
        for ok in ["you@example.com", "a.b+perch@mail.co.uk", " you@example.io ", "x@y.dev"] { #expect(Feedback.isEmail(ok), "\(ok)") }
        for bad in ["", "you", "you@", "you@example", "you@example.c", "@example.com", "you @example.com", "you@exa mple.com", "you@example."] {
            #expect(!Feedback.isEmail(bad), "\(bad)")
        }
    }

    @Test func filesFitInTheOrderTheyCameUntilTheLimit() {
        let mb = 1024 * 1024
        #expect(Feedback.fits([]) == [])
        #expect(Feedback.fits([1 * mb, 2 * mb]) == [true, true])
        // the recording takes it past 4 MB; the log after it still fits
        #expect(Feedback.fits([1 * mb, 18 * mb, mb / 5]) == [true, false, true])
        #expect(Feedback.fits([4 * mb]) == [true])
        #expect(Feedback.fits([4 * mb, 1]) == [true, false])
    }

    @Test func theSubjectIsTheFirstLine() {
        #expect(Feedback.subject("The card opens on the wrong screen\nafter sleep") == "Perch feedback: The card opens on the wrong screen")
        #expect(Feedback.subject("  \n") == "Perch feedback")
        #expect(Feedback.subject("") == "Perch feedback")
        let long = Feedback.subject("When I hover the top of my external display the card sometimes opens on the laptop instead")
        #expect(long == "Perch feedback: When I hover the top of my external display the card\u{2026}")
    }

    @Test func typesByExtension() {
        #expect(Feedback.type(ofExtension: "PNG") == "image/png")
        #expect(Feedback.type(ofExtension: "log") == "text/plain")
        #expect(Feedback.type(ofExtension: "mov") == "video/quicktime")
        #expect(Feedback.type(ofExtension: "weird") == "application/octet-stream")
    }

    @Test func theFormHasEachFieldAndFile() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let body = Feedback.body(text: "Hello", email: "you@example.com", version: "0.4.3 (210)", macOS: "26.1",
                                 files: [.init(name: "shot \"one\".png", type: "image/png", data: png)], boundary: "B")
        let s = String(decoding: body, as: UTF8.self)
        #expect(s.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"text\"\r\n\r\nHello\r\n"))
        #expect(s.contains("name=\"email\"\r\n\r\nyou@example.com\r\n"))
        #expect(s.contains("name=\"version\"\r\n\r\n0.4.3 (210)\r\n"))
        #expect(s.contains("name=\"macos\"\r\n\r\n26.1\r\n"))
        // a quote in a file name cannot break out of the header
        #expect(s.contains("name=\"file\"; filename=\"shot 'one'.png\"\r\nContent-Type: image/png\r\n\r\n"))
        #expect(body.range(of: png) != nil)
        #expect(s.hasSuffix("--B--\r\n"))
    }

    @Test func whatIsLeftOutIsNotSent() {
        let s = String(decoding: Feedback.body(text: "Hi", email: "", version: nil, macOS: nil, files: [], boundary: "B"), as: UTF8.self)
        #expect(!s.contains("email")); #expect(!s.contains("version")); #expect(!s.contains("macos")); #expect(!s.contains("filename"))
    }

    @Test func longWordsAreCut() {
        let s = String(decoding: Feedback.body(text: String(repeating: "a", count: Feedback.maxCharacters + 50), email: nil, version: nil, macOS: nil, files: [], boundary: "B"), as: UTF8.self)
        #expect(s.contains("\r\n\r\n" + String(repeating: "a", count: Feedback.maxCharacters) + "\r\n"))
        #expect(!s.contains(String(repeating: "a", count: Feedback.maxCharacters + 1)))
    }
}
