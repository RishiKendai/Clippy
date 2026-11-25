import Foundation

public enum ClipKind: String, Sendable {
    case text
    case image
    case file
}

/// One pasteboard type's raw bytes, belonging to pasteboard item `itemIndex`.
public struct Representation: Equatable, Sendable {
    public var itemIndex: Int
    public var uti: String
    public var data: Data

    public init(itemIndex: Int, uti: String, data: Data) {
        self.itemIndex = itemIndex
        self.uti = uti
        self.data = data
    }
}

/// Everything that was on the pasteboard: every item and every type on it.
public struct PasteboardSnapshot: Equatable, Sendable {
    public var representations: [Representation]

    public init(_ representations: [Representation]) {
        self.representations = representations
    }

    /// Representations grouped by pasteboard item, in item order.
    public var items: [[Representation]] {
        let grouped = Dictionary(grouping: representations, by: \.itemIndex)
        return grouped.keys.sorted().map { grouped[$0]! }
    }

    public var byteSize: Int { representations.reduce(0) { $0 + $1.data.count } }

    public var isEmpty: Bool { representations.isEmpty }
}

/// What the codec derives from a snapshot before it's stored.
public struct AnalyzedClip: Sendable {
    public var kind: ClipKind
    /// Text used for the row label, search and plain-text paste. For files: their paths, one per line.
    public var plainText: String
    public var hash: String
    /// Small downscaled PNG for image rows; nil for text and file clips.
    public var thumbnail: Data?
    public var snapshot: PasteboardSnapshot

    public init(kind: ClipKind, plainText: String, hash: String, thumbnail: Data?, snapshot: PasteboardSnapshot) {
        self.kind = kind
        self.plainText = plainText
        self.hash = hash
        self.thumbnail = thumbnail
        self.snapshot = snapshot
    }
}

/// A clip as shown in the list. Raw representations are loaded only when pasting.
public struct ClipSummary: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: ClipKind
    public var plainText: String
    public var thumbnail: Data?
    public var pinned: Bool
    public var lastUsedAt: Date
    /// App the clip was (last) copied from, e.g. "Safari". Shown only in the hover preview.
    public var sourceApp: String?
    /// When the clip was (last) copied. Shown only in the hover preview.
    public var copiedAt: Date

    public init(id: Int64, kind: ClipKind, plainText: String, thumbnail: Data?, pinned: Bool, lastUsedAt: Date,
                sourceApp: String? = nil, copiedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.thumbnail = thumbnail
        self.pinned = pinned
        self.lastUsedAt = lastUsedAt
        self.sourceApp = sourceApp
        self.copiedAt = copiedAt ?? lastUsedAt
    }

    /// Single-line label for the row: newlines collapsed; files show their names.
    public var label: String {
        switch kind {
        case .file:
            return plainText
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)).lastPathComponent }
                .joined(separator: ", ")
        case .text, .image:
            return plainText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}

/// Configurable limits (Settings → History).
public struct HistoryLimits: Sendable {
    public var maxText: Int
    public var maxImages: Int
    public var keepDays: Int

    public init(maxText: Int = 300, maxImages: Int = 100, keepDays: Int = 30) {
        self.maxText = maxText
        self.maxImages = maxImages
        self.keepDays = keepDays
    }
}
