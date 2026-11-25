import AppKit
import Testing
@testable import ClippyCore

@Suite(.serialized) struct PasteboardCodecTests {
    /// A private pasteboard so tests never touch the user's clipboard.
    let pb = NSPasteboard(name: NSPasteboard.Name("com.clippy.tests.\(UUID().uuidString)"))

    private func rtfData(_ text: String) -> Data {
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.systemRed,
            .link: URL(string: "https://example.com")!,
        ])
        return try! attr.data(from: NSRange(location: 0, length: attr.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func richTextRoundTripsEveryFormatByteForByte() throws {
        let item = NSPasteboardItem()
        item.setString("Bold red link", forType: .string)
        item.setData(rtfData("Bold red link"), forType: .rtf)
        item.setString("<b style=\"color:red\"><a href=\"https://example.com\">Bold red link</a></b>", forType: .html)
        item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.private"))
        pb.clearContents()
        pb.writeObjects([item])

        let snap = try #require(PasteboardCodec.read(pb))
        PasteboardCodec.write(snap, to: pb)
        let again = try #require(PasteboardCodec.read(pb))

        for uti in ["public.utf8-plain-text", "public.rtf", "public.html", "com.example.private"] {
            let a = snap.representations.first { $0.uti == uti }
            let b = again.representations.first { $0.uti == uti }
            #expect(a != nil && a == b, "format \(uti) should survive a round trip")
        }
        let analyzed = try #require(PasteboardCodec.analyze(snap))
        #expect(analyzed.kind == .text)
        #expect(analyzed.plainText == "Bold red link")
    }

    @Test func plainTextIsDerivedFromRTFWhenNoStringType() throws {
        let snap = PasteboardSnapshot([Representation(itemIndex: 0, uti: "public.rtf", data: rtfData("Only RTF"))])
        #expect(PasteboardCodec.plainText(from: snap) == "Only RTF")
    }

    @Test func plainTextIsDerivedFromHTML() {
        let snap = PasteboardSnapshot([Representation(itemIndex: 0, uti: "public.html",
                                                       data: Data("<p>Tom &amp; <b>Jerry</b></p>".utf8))])
        #expect(PasteboardCodec.plainText(from: snap) == "Tom & Jerry")
    }

    @Test func multipleFilesStayMultipleItems() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.pdf")]
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        let snap = try #require(PasteboardCodec.read(pb))
        #expect(snap.items.count == 2)
        let analyzed = try #require(PasteboardCodec.analyze(snap))
        #expect(analyzed.kind == .file)
        #expect(analyzed.plainText == "/tmp/a.txt\n/tmp/b.pdf")

        PasteboardCodec.write(snap, to: pb)
        let back = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(back == urls)
    }

    @Test func imageGetsThumbnailAndNoText() throws {
        pb.clearContents()
        pb.setData(pngData(), forType: .png)
        let snap = try #require(PasteboardCodec.read(pb))
        let analyzed = try #require(PasteboardCodec.analyze(snap))
        #expect(analyzed.kind == .image)
        #expect(analyzed.plainText.isEmpty)
        #expect(analyzed.thumbnail != nil)
    }

    @Test func sameTextDifferentFormattingIsTheSameClip() throws {
        let plain = PasteboardSnapshot([Representation(itemIndex: 0, uti: "public.utf8-plain-text", data: Data("hi".utf8))])
        var rich = plain
        rich.representations.append(Representation(itemIndex: 0, uti: "public.rtf", data: rtfData("hi")))
        #expect(PasteboardCodec.analyze(plain)?.hash == PasteboardCodec.analyze(rich)?.hash)
    }

    @Test func secretMarkersAreDetected() {
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("hunter2", forType: .string)
        #expect(PasteboardCodec.hasSecretMarker(pb))
    }

    @Test func unshowableContentIsSkipped() {
        let snap = PasteboardSnapshot([Representation(itemIndex: 0, uti: "com.example.private", data: Data([9]))])
        #expect(PasteboardCodec.analyze(snap) == nil)
    }

    @Test func oversizedClipsAreSkipped() {
        pb.clearContents()
        pb.setString(String(repeating: "x", count: 2_000), forType: .string)
        #expect(PasteboardCodec.read(pb, maxBytes: 1_000) == nil)
    }

    @Test func rowLabelCollapsesNewlinesAndShowsFileNames() {
        let text = ClipSummary(id: 1, kind: .text, plainText: "line one\n\n  line two  ", thumbnail: nil, pinned: false, lastUsedAt: Date())
        #expect(text.label == "line one line two")
        let files = ClipSummary(id: 2, kind: .file, plainText: "/a/b/report.pdf\n/c/logo.svg", thumbnail: nil, pinned: false, lastUsedAt: Date())
        #expect(files.label == "report.pdf, logo.svg")
    }
}

@Suite struct ImageClassificationTests {
    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 30, pixelsHigh: 20, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func copiedImageFileShowsAsImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-test-\(UUID().uuidString).png")
        try png().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let snap = PasteboardSnapshot([
            Representation(itemIndex: 0, uti: "public.file-url", data: url.dataRepresentation),
            Representation(itemIndex: 0, uti: "public.utf8-plain-text", data: Data(url.lastPathComponent.utf8)),
        ])
        let clip = try #require(PasteboardCodec.analyze(snap))
        #expect(clip.kind == .image)
        #expect(clip.thumbnail != nil)
        #expect(clip.plainText == url.path)
    }

    @Test func nonImageFileStaysAFile() throws {
        let snap = PasteboardSnapshot([
            Representation(itemIndex: 0, uti: "public.file-url", data: URL(fileURLWithPath: "/tmp/report.pdf").dataRepresentation),
        ])
        #expect(PasteboardCodec.analyze(snap)?.kind == .file)
    }

    @Test func browserImageWithURLTextIsAnImage() throws {
        let snap = PasteboardSnapshot([
            Representation(itemIndex: 0, uti: "public.tiff", data: png()),
            Representation(itemIndex: 0, uti: "public.utf8-plain-text", data: Data("https://example.com/cat.jpg".utf8)),
        ])
        #expect(PasteboardCodec.analyze(snap)?.kind == .image)
    }

    @Test func realTextWithAnImageStaysText() throws {
        let snap = PasteboardSnapshot([
            Representation(itemIndex: 0, uti: "public.png", data: png()),
            Representation(itemIndex: 0, uti: "public.utf8-plain-text", data: Data("Quarterly totals\t120\t340".utf8)),
        ])
        #expect(PasteboardCodec.analyze(snap)?.kind == .text)
    }
}
