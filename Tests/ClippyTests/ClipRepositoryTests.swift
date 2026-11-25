import AppKit
import Testing
@testable import ClippyCore

private func textClip(_ text: String, rtf: Bool = false) -> AnalyzedClip {
    var reps = [Representation(itemIndex: 0, uti: "public.utf8-plain-text", data: Data(text.utf8))]
    if rtf {
        reps.append(Representation(itemIndex: 0, uti: "public.rtf", data: Data("{\\rtf1 \\b \(text)}".utf8)))
    }
    return PasteboardCodec.analyze(PasteboardSnapshot(reps))!
}

private func imageClip(_ seed: UInt8) -> AnalyzedClip {
    let snap = PasteboardSnapshot([Representation(itemIndex: 0, uti: "public.png", data: Data([seed, 1, 2, 3]))])
    return AnalyzedClip(kind: .image, plainText: "", hash: "img\(seed)", thumbnail: nil, snapshot: snap)
}

private let day: TimeInterval = 86_400

@Suite struct ClipRepositoryTests {
    let repo = try! ClipRepository(path: ":memory:")
    let limits = HistoryLimits()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newestFirst() throws {
        try repo.save(textClip("a"), sourceApp: nil, limits: limits, now: t0)
        try repo.save(textClip("b"), sourceApp: nil, limits: limits, now: t0 + 1)
        #expect(try repo.list().history.map(\.plainText) == ["b", "a"])
    }

    @Test func duplicateMovesToTopAndReplacesFormats() throws {
        let a = try repo.save(textClip("a"), sourceApp: nil, limits: limits, now: t0)
        try repo.save(textClip("b"), sourceApp: nil, limits: limits, now: t0 + 1)
        let again = try repo.save(textClip("a", rtf: true), sourceApp: nil, limits: limits, now: t0 + 2)
        #expect(again == a)
        let list = try repo.list().history
        #expect(list.map(\.plainText) == ["a", "b"])
        #expect(try repo.snapshot(for: a).representations.map(\.uti) == ["public.utf8-plain-text", "public.rtf"])
    }

    @Test func usingAClipMovesItUpAndRestartsRetention() throws {
        let a = try repo.save(textClip("a"), sourceApp: nil, limits: limits, now: t0)
        try repo.save(textClip("b"), sourceApp: nil, limits: limits, now: t0 + 1)
        try repo.markUsed(a, now: t0 + 29 * day)
        #expect(try repo.list().history.first?.id == a)
        // 31 days after copy, but only 2 days after use: kept. "b" expires.
        try repo.purgeExpired(keepDays: 30, now: t0 + 31 * day)
        #expect(try repo.list().history.map(\.plainText) == ["a"])
    }

    @Test func pinnedNeverExpire() throws {
        let p = try repo.save(textClip("keep"), sourceApp: nil, limits: limits, now: t0)
        try repo.setPinned(p, true, limits: limits, now: t0)
        try repo.save(textClip("old"), sourceApp: nil, limits: limits, now: t0)
        try repo.purgeExpired(keepDays: 30, now: t0 + 400 * day)
        let list = try repo.list()
        #expect(list.history.isEmpty)
        #expect(list.pinned.map(\.plainText) == ["keep"])
    }

    @Test func textLimitTrimsOldestUnpinnedOnly() throws {
        let small = HistoryLimits(maxText: 3, maxImages: 2)
        let pinned = try repo.save(textClip("pinned"), sourceApp: nil, limits: small, now: t0)
        try repo.setPinned(pinned, true, limits: small, now: t0)
        for i in 0..<5 {
            try repo.save(textClip("t\(i)"), sourceApp: nil, limits: small, now: t0 + Double(i + 1))
        }
        let list = try repo.list()
        #expect(list.history.map(\.plainText) == ["t4", "t3", "t2"])
        #expect(list.pinned.count == 1)
    }

    @Test func imageLimitIsSeparateFromText() throws {
        let small = HistoryLimits(maxText: 2, maxImages: 2)
        try repo.save(textClip("t"), sourceApp: nil, limits: small, now: t0)
        for i in 0..<4 {
            try repo.save(imageClip(UInt8(i)), sourceApp: nil, limits: small, now: t0 + Double(i + 1))
        }
        let history = try repo.list().history
        #expect(history.filter { $0.kind == .image }.count == 2)
        #expect(history.filter { $0.kind == .text }.count == 1)
    }

    @Test func unpinMovesBackToTopOfHistory() throws {
        let a = try repo.save(textClip("a"), sourceApp: nil, limits: limits, now: t0)
        try repo.save(textClip("b"), sourceApp: nil, limits: limits, now: t0 + 1)
        try repo.setPinned(a, true, limits: limits, now: t0 + 2)
        #expect(try repo.list().history.map(\.plainText) == ["b"])
        try repo.setPinned(a, false, limits: limits, now: t0 + 3)
        #expect(try repo.list().history.map(\.plainText) == ["a", "b"])
    }

    @Test func searchMatchesTextAndHiddenSourceCaseInsensitive() throws {
        try repo.save(textClip("Hello World"), sourceApp: "Notes", limits: limits, now: t0)
        try repo.save(textClip("brew install sqlite"), sourceApp: "Terminal", limits: limits, now: t0 + 1)
        try repo.save(textClip("100% done"), sourceApp: nil, limits: limits, now: t0 + 2)
        #expect(try repo.list(query: "hello").history.map(\.plainText) == ["Hello World"])
        #expect(try repo.list(query: "terminal").history.map(\.plainText) == ["brew install sqlite"])
        #expect(try repo.list(query: "%").history.map(\.plainText) == ["100% done"])
        #expect(try repo.list(query: "zzz").history.isEmpty)
    }

    @Test func deleteAndClearUnpinned() throws {
        let a = try repo.save(textClip("a"), sourceApp: nil, limits: limits, now: t0)
        let b = try repo.save(textClip("b"), sourceApp: nil, limits: limits, now: t0 + 1)
        try repo.save(textClip("c"), sourceApp: nil, limits: limits, now: t0 + 2)
        try repo.setPinned(b, true, limits: limits, now: t0 + 3)
        try repo.delete(a)
        #expect(try repo.snapshot(for: a).isEmpty)
        #expect(try repo.clearUnpinned() == 1)
        let list = try repo.list()
        #expect(list.history.isEmpty)
        #expect(list.pinned.map(\.plainText) == ["b"])
        #expect(try repo.counts() == (0, 1))
    }
}

@Suite struct PinnedOrderTests {
    let repo = try! ClipRepository(path: ":memory:")
    let limits = HistoryLimits()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func pinned() throws -> [String] { try repo.list().pinned.map(\.plainText) }

    @Test func newPinsJoinTheBottom() throws {
        for (i, name) in ["a", "b", "c"].enumerated() {
            let id = try repo.save(textClip(name), sourceApp: nil, limits: limits, now: t0 + Double(i))
            try repo.setPinned(id, true, limits: limits, now: t0 + 10 + Double(i))
        }
        #expect(try pinned() == ["a", "b", "c"])
    }

    @Test func usingOrRecopyingAPinnedClipKeepsItsPlace() throws {
        var ids: [Int64] = []
        for (i, name) in ["a", "b", "c", "d"].enumerated() {
            let id = try repo.save(textClip(name), sourceApp: nil, limits: limits, now: t0 + Double(i))
            try repo.setPinned(id, true, limits: limits, now: t0 + 10 + Double(i))
            ids.append(id)
        }
        try repo.markUsed(ids[3], now: t0 + 100)
        try repo.save(textClip("c"), sourceApp: nil, limits: limits, now: t0 + 200)
        #expect(try pinned() == ["a", "b", "c", "d"])
        #expect(try repo.list().history.isEmpty)
    }

    @Test func reorderPersistsAndRepinGoesToBottom() throws {
        var ids: [Int64] = []
        for (i, name) in ["a", "b", "c"].enumerated() {
            let id = try repo.save(textClip(name), sourceApp: nil, limits: limits, now: t0 + Double(i))
            try repo.setPinned(id, true, limits: limits, now: t0 + 10 + Double(i))
            ids.append(id)
        }
        try repo.reorderPinned([ids[2], ids[0], ids[1]])
        #expect(try pinned() == ["c", "a", "b"])
        try repo.setPinned(ids[2], false, limits: limits, now: t0 + 50)
        try repo.setPinned(ids[2], true, limits: limits, now: t0 + 60)
        #expect(try pinned() == ["a", "b", "c"])
    }

    @Test func clearPinnedKeepsHistory() throws {
        let p = try repo.save(textClip("pinned"), sourceApp: nil, limits: limits, now: t0)
        try repo.setPinned(p, true, limits: limits, now: t0)
        try repo.save(textClip("history"), sourceApp: nil, limits: limits, now: t0 + 1)
        #expect(try repo.clearPinned() == 1)
        #expect(try repo.snapshot(for: p).isEmpty)
        let list = try repo.list()
        #expect(list.pinned.isEmpty)
        #expect(list.history.map(\.plainText) == ["history"])
    }

    @Test func previewMetadataIsReturned() throws {
        try repo.save(textClip("x"), sourceApp: "Safari", limits: limits, now: t0)
        let clip = try #require(try repo.list().history.first)
        #expect(clip.sourceApp == "Safari")
        #expect(clip.copiedAt == t0)
    }
}

@Suite struct DuplicateTests {
    @Test func exactlyTheSameTextIsOneClip() throws {
        let repo = try ClipRepository(path: ":memory:")
        let a = try repo.save(textClip("\nLinkedIn\r"), sourceApp: nil, limits: HistoryLimits())
        let b = try repo.save(textClip("\nLinkedIn\r"), sourceApp: nil, limits: HistoryLimits())
        #expect(a == b)
        #expect(try repo.list().history.count == 1)
    }

    @Test func whitespaceAndCaseMakeDifferentClips() throws {
        let repo = try ClipRepository(path: ":memory:")
        for text in ["LinkedIn", "\nLinkedIn", "LinkedIn\r", "linkedin", "LinkedIn "] {
            try repo.save(textClip(text), sourceApp: nil, limits: HistoryLimits())
        }
        #expect(try repo.list().history.count == 5)
    }

    @Test func reanalyzeRestoresExactHashesAndMergesOnlyExactDuplicates() throws {
        let repo = try ClipRepository(path: ":memory:")
        // Stored under stale hashes (e.g. by a build that trimmed whitespace).
        for (i, text) in ["Dozee", "Dozee\n", "Dozee"].enumerated() {
            var clip = textClip(text)
            clip.hash = "old-\(i)"
            try repo.save(clip, sourceApp: nil, limits: HistoryLimits(), now: Date(timeIntervalSince1970: Double(i)))
        }
        try repo.reanalyzeAll(PasteboardCodec.analyze)
        #expect(try repo.list().history.map(\.plainText) == ["Dozee", "Dozee\n"])
    }
}

@Suite struct ReanalyzeTests {
    @Test func oldFileClipOfAnImageBecomesAnImage() throws {
        let repo = try ClipRepository(path: ":memory:")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-re-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // Stored the way older builds did: as a file clip.
        let snap = PasteboardSnapshot([Representation(itemIndex: 0, uti: "public.file-url", data: url.dataRepresentation)])
        let old = AnalyzedClip(kind: .file, plainText: url.path, hash: "file|\(url.path)", thumbnail: nil, snapshot: snap)
        try repo.save(old, sourceApp: nil, limits: HistoryLimits())
        #expect(try repo.reanalyzeAll(PasteboardCodec.analyze) == 1)
        let clip = try #require(try repo.list().history.first)
        #expect(clip.kind == .image)
        #expect(clip.thumbnail != nil)
    }
}
