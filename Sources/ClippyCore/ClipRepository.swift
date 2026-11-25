import Foundation

/// All database reads and writes plus the history rules (dedup, limits, retention, pinning).
/// Thread-safe: every call is serialized with a lock, so it can be used from any queue.
public final class ClipRepository: @unchecked Sendable {
    private let db: SQLiteDatabase
    private let lock = NSLock()

    /// Default location: ~/Library/Application Support/Clippy/clippy.sqlite
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Clippy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clippy.sqlite")
    }

    /// Opens the database at `path` (":memory:" for tests) and runs migrations.
    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try Migrations.run(on: db)
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Writing

    /// Stores a copied clip. If identical content already exists, that clip moves to the top
    /// (its `last_used_at` is bumped, which also restarts retention) and its formats are
    /// replaced by the newest copy. Then the unpinned limits are enforced.
    @discardableResult
    public func save(_ clip: AnalyzedClip, sourceApp: String?, limits: HistoryLimits, now: Date = Date()) throws -> Int64 {
        try locked {
            try db.transaction {
                let t = now.timeIntervalSince1970
                let rows = try db.query(
                    """
                    INSERT INTO clips(kind, plain_text, thumb, hash, source_app, byte_size, copied_at, last_used_at, pinned)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(hash) DO UPDATE SET
                        kind = excluded.kind,
                        plain_text = excluded.plain_text,
                        thumb = excluded.thumb,
                        source_app = excluded.source_app,
                        byte_size = excluded.byte_size,
                        copied_at = excluded.copied_at,
                        last_used_at = excluded.last_used_at
                    RETURNING id
                    """,
                    [
                        .text(clip.kind.rawValue),
                        .text(clip.plainText),
                        clip.thumbnail.map { .blob($0) } ?? .null,
                        .text(clip.hash),
                        sourceApp.map { .text($0) } ?? .null,
                        .int(Int64(clip.snapshot.byteSize)),
                        .double(t),
                        .double(t),
                    ]
                )
                guard let id = rows.first?.int(0) else {
                    throw SQLiteError(code: -1, message: "insert returned no id")
                }
                try db.query("DELETE FROM representations WHERE clip_id = ?", [.int(id)])
                for rep in clip.snapshot.representations {
                    try db.query(
                        "INSERT OR REPLACE INTO representations(clip_id, item_index, uti, data) VALUES(?, ?, ?, ?)",
                        [.int(id), .int(Int64(rep.itemIndex)), .text(rep.uti), .blob(rep.data)]
                    )
                }
                try enforceLimitsLocked(limits)
                return id
            }
        }
    }

    /// Marks a clip as used: an unpinned clip moves to the top of History and its retention
    /// restarts. Pinned clips keep their place (Pinned has its own order).
    public func markUsed(_ id: Int64, now: Date = Date()) throws {
        try locked {
            _ = try db.query("UPDATE clips SET last_used_at = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .int(id)])
        }
    }

    /// Pins a clip (it joins the **bottom** of Pinned) or unpins it (it moves to the top of History).
    public func setPinned(_ id: Int64, _ pinned: Bool, limits: HistoryLimits, now: Date = Date()) throws {
        try locked {
            let t = now.timeIntervalSince1970
            if pinned {
                _ = try db.query(
                    """
                    UPDATE clips SET pinned = 1, pinned_at = ?,
                        pin_order = (SELECT COALESCE(MAX(pin_order), -1) + 1 FROM clips WHERE pinned = 1)
                    WHERE id = ? AND pinned = 0
                    """,
                    [.double(t), .int(id)]
                )
            } else {
                _ = try db.query(
                    "UPDATE clips SET pinned = 0, pinned_at = NULL, pin_order = NULL, last_used_at = ? WHERE id = ?",
                    [.double(t), .int(id)]
                )
                try enforceLimitsLocked(limits)
            }
        }
    }

    /// Sets the order of the Pinned section: `ids` top to bottom. Pinned clips not listed keep
    /// their relative order after the listed ones.
    public func reorderPinned(_ ids: [Int64]) throws {
        try locked {
            try db.transaction {
                let current = try db.query("SELECT id FROM clips WHERE pinned = 1 ORDER BY pin_order, id").map { $0.int(0) }
                let listed = ids.filter(current.contains)
                let order = listed + current.filter { !listed.contains($0) }
                for (index, id) in order.enumerated() {
                    _ = try db.query("UPDATE clips SET pin_order = ? WHERE id = ?", [.int(Int64(index)), .int(id)])
                }
            }
        }
    }

    public func delete(_ id: Int64) throws {
        try locked {
            _ = try db.query("DELETE FROM clips WHERE id = ?", [.int(id)])
        }
    }

    /// Deletes every unpinned clip. Returns how many were deleted.
    @discardableResult
    public func clearUnpinned() throws -> Int {
        try locked {
            try db.query("DELETE FROM clips WHERE pinned = 0")
            return db.changes
        }
    }

    /// Deletes every pinned clip. Returns how many were deleted.
    @discardableResult
    public func clearPinned() throws -> Int {
        try locked {
            try db.query("DELETE FROM clips WHERE pinned = 1")
            return db.changes
        }
    }

    /// Deletes unpinned clips not used within `keepDays`. Returns how many were deleted.
    @discardableResult
    public func purgeExpired(keepDays: Int, now: Date = Date()) throws -> Int {
        try locked {
            let cutoff = now.timeIntervalSince1970 - Double(keepDays) * 86_400
            try db.query("DELETE FROM clips WHERE pinned = 0 AND last_used_at < ?", [.double(cutoff)])
            return db.changes
        }
    }

    public func enforceLimits(_ limits: HistoryLimits) throws {
        try locked { try enforceLimitsLocked(limits) }
    }

    /// Keeps the newest `maxText` unpinned text/file clips and `maxImages` unpinned images.
    private func enforceLimitsLocked(_ limits: HistoryLimits) throws {
        try db.query(
            """
            DELETE FROM clips WHERE id IN (
                SELECT id FROM clips WHERE pinned = 0 AND kind IN ('text', 'file')
                ORDER BY last_used_at DESC LIMIT -1 OFFSET ?)
            """,
            [.int(Int64(max(0, limits.maxText)))]
        )
        try db.query(
            """
            DELETE FROM clips WHERE id IN (
                SELECT id FROM clips WHERE pinned = 0 AND kind = 'image'
                ORDER BY last_used_at DESC LIMIT -1 OFFSET ?)
            """,
            [.int(Int64(max(0, limits.maxImages)))]
        )
    }

    // MARK: Reading

    /// History (newest use first) and Pinned (in the user's order), filtered by `query`
    /// (case-insensitive, matches clip text and the source app).
    public func list(query: String = "") throws -> (history: [ClipSummary], pinned: [ClipSummary]) {
        try locked {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var sql = "SELECT \(Self.summaryColumns) FROM clips"
            var params: [SQLValue] = []
            if !q.isEmpty {
                let escaped = q
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                sql += " WHERE plain_text LIKE ? ESCAPE '\\' OR source_app LIKE ? ESCAPE '\\'"
                params = [.text("%\(escaped)%"), .text("%\(escaped)%")]
            }
            sql += " ORDER BY pinned, CASE WHEN pinned = 1 THEN pin_order END, last_used_at DESC, id DESC"
            let all = try db.query(sql, params).map(Self.summary(from:))
            return (all.filter { !$0.pinned }, all.filter(\.pinned))
        }
    }

    private static let summaryColumns = "id, kind, plain_text, thumb, pinned, last_used_at, source_app, copied_at"

    private static func summary(from row: SQLRow) -> ClipSummary {
        ClipSummary(
            id: row.int(0),
            kind: ClipKind(rawValue: row.text(1) ?? "text") ?? .text,
            plainText: row.text(2) ?? "",
            thumbnail: row.blob(3),
            pinned: row.int(4) != 0,
            lastUsedAt: Date(timeIntervalSince1970: row.double(5)),
            sourceApp: row.text(6),
            copiedAt: Date(timeIntervalSince1970: row.double(7))
        )
    }

    /// Every stored format of a clip, for pasting it back exactly as copied.
    public func snapshot(for id: Int64) throws -> PasteboardSnapshot {
        try locked {
            let rows = try db.query(
                "SELECT item_index, uti, data FROM representations WHERE clip_id = ? ORDER BY item_index, rowid",
                [.int(id)]
            )
            return PasteboardSnapshot(rows.map {
                Representation(itemIndex: Int($0.int(0)), uti: $0.text(1) ?? "", data: $0.blob(2) ?? Data())
            })
        }
    }

    public func summary(for id: Int64) throws -> ClipSummary? {
        try locked {
            try db.query("SELECT \(Self.summaryColumns) FROM clips WHERE id = ?", [.int(id)]).first.map(Self.summary(from:))
        }
    }

    /// Re-derives kind, label text, thumbnail and duplicate hash for every stored clip (after the
    /// classification or duplicate rules change). Clips that turn out to be duplicates are merged:
    /// a pinned one wins, otherwise the most recently used. Returns how many clips changed.
    @discardableResult
    public func reanalyzeAll(_ analyze: (PasteboardSnapshot) -> AnalyzedClip?) throws -> Int {
        let rows = try locked { try db.query("SELECT id, kind, hash FROM clips").map { ($0.int(0), $0.text(1) ?? "", $0.text(2) ?? "") } }
        var changed = 0
        for (id, kind, hash) in rows {
            guard let clip = analyze(try snapshot(for: id)), clip.kind.rawValue != kind || clip.hash != hash else { continue }
            try locked {
                try db.transaction {
                    if let other = try db.query("SELECT id, pinned, last_used_at FROM clips WHERE hash = ? AND id != ?",
                                                [.text(clip.hash), .int(id)]).first {
                        let me = try db.query("SELECT pinned, last_used_at FROM clips WHERE id = ?", [.int(id)]).first
                        let mine = (me?.int(0) ?? 0, me?.double(1) ?? 0)
                        let theirs = (other.int(1), other.double(2))
                        let keepMine = mine.0 != theirs.0 ? mine.0 > theirs.0 : mine.1 >= theirs.1
                        try db.query("DELETE FROM clips WHERE id = ?", [.int(keepMine ? other.int(0) : id)])
                        if !keepMine { return }
                    }
                    try db.query(
                        "UPDATE clips SET kind = ?, plain_text = ?, thumb = ?, hash = ? WHERE id = ?",
                        [.text(clip.kind.rawValue), .text(clip.plainText), clip.thumbnail.map { .blob($0) } ?? .null, .text(clip.hash), .int(id)]
                    )
                }
            }
            changed += 1
        }
        return changed
    }

    public func counts() throws -> (history: Int, pinned: Int) {
        try locked {
            let row = try db.query("SELECT SUM(pinned = 0), SUM(pinned = 1) FROM clips").first
            return (Int(row?.int(0) ?? 0), Int(row?.int(1) ?? 0))
        }
    }
}

/// Schema versions, applied in order via `PRAGMA user_version`.
/// Never edit an existing step; append a new one.
enum Migrations {
    static let steps: [String] = [
        // v1
        """
        CREATE TABLE clips(
            id INTEGER PRIMARY KEY,
            kind TEXT NOT NULL,
            plain_text TEXT,
            thumb BLOB,
            hash TEXT NOT NULL UNIQUE,
            source_app TEXT,
            byte_size INTEGER,
            copied_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            pinned_at REAL
        );
        CREATE TABLE representations(
            clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            item_index INTEGER NOT NULL,
            uti TEXT NOT NULL,
            data BLOB NOT NULL,
            PRIMARY KEY(clip_id, item_index, uti)
        );
        CREATE INDEX idx_clips_order ON clips(pinned, last_used_at DESC);
        """,
        // v2: Pinned has its own, user-defined order (no longer by last use). Existing pins keep
        // the order they were shown in.
        """
        ALTER TABLE clips ADD COLUMN pin_order INTEGER;
        UPDATE clips SET pin_order = (
            SELECT COUNT(*) FROM clips c2 WHERE c2.pinned = 1 AND
                (c2.last_used_at > clips.last_used_at OR (c2.last_used_at = clips.last_used_at AND c2.id > clips.id))
        ) WHERE pinned = 1;
        """,
    ]

    static func run(on db: SQLiteDatabase) throws {
        let current = db.userVersion
        guard current < steps.count else { return }
        for version in current..<steps.count {
            try db.transaction {
                try db.execute(steps[version])
                try db.setUserVersion(version + 1)
            }
        }
    }
}
