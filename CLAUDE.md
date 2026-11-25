# Clippy: notes for Claude Code

Clippy is a macOS menu bar clipboard manager (Swift, SwiftUI + AppKit, SQLite). No Dock icon.

## Read first
- **`DESIGN.md` is the source of truth for UI and behaviour.** It covers tokens, row anatomy, settings tabs, components and accessibility. Read it before changing any screen.
- **This file** holds the engineering rules, the architecture and the decision log.
- If the Design canvas, `DESIGN.md` and the code disagree, `DESIGN.md` wins. If `DESIGN.md` says nothing, follow standard macOS conventions and **ask before inventing new UI**.
- A change that alters behaviour or look updates `DESIGN.md` in the same change. A new engineering or design decision gets a line in the decision log below.

## Product rules (do not break)
- **Copy keeps everything.** Every `NSPasteboardItem` and every type on it is stored as raw data: plain, RTF, RTFD, HTML, images, file URLs and app-private types.
- **Paste as-is.** Clicking a clip, pressing Return in the popover, or ⌘V restores all stored types, so formatting survives.
- **⌘⇧V pastes plain text** system-wide, and on the selected row in the popover. The system-wide version swaps a plain copy onto the clipboard, pastes, then restores the original contents.
- **⌥⌘V is the default shortcut to open Clippy.** ⇧⌘V is reserved for plain paste and is never offered as the open shortcut.
- **Limits** apply to unpinned clips only: 300 text/file clips, 100 images (configurable in Settings).
- **Retention:** unpinned clips are deleted 30 days after `last_used_at` (configurable). Using or re-copying a clip resets it. Pinned clips never expire.
- **Duplicates:** re-copying existing content moves that clip to the top and doesn't create a second one. Text must match exactly: whitespace, line endings and case all count.
- `source_app` and `copied_at` are **never shown on rows**, only in the hover preview footer (date as `DD MMM, YYYY`). Search may match `source_app`.
- **Pinned order is the user's:** new pins go to the bottom, use/re-copy doesn't reorder (`pin_order` column), and the user can drag or ⌥⌘↑/↓ to rearrange.
- **Visible rows:** History and Pinned each show 10 rows by default (5–15 in Settings), then scroll; both shrink to fit the screen.
- When "Ignore passwords and secrets" is on, skip concealed, transient and auto-generated content (nspasteboard.org markers).
- Nothing leaves the Mac.
- **Trash = uninstall.** When the installed app (in /Applications or ~/Applications) is moved to the Trash, its database, preferences, caches and privacy permissions are deleted (`Uninstaller`, `InstallLocation`). Finder refuses to trash a running app, so this is done by a cleanup LaunchAgent (`~/Library/LaunchAgents/com.clippy.app.cleanup.plist`) that the installed app writes at launch. Dev builds in `build/` never install it. Replacing the app with an update doesn't count.

## Architecture
```
Sources/ClippyCore/        library, no UI, fully unit-tested
  SQLiteDatabase.swift     thin sqlite3 wrapper (query/transaction/user_version)
  Models.swift             ClipKind, Representation, PasteboardSnapshot, AnalyzedClip, ClipSummary (+ row label), HistoryLimits
  ClipRepository.swift     all queries + history rules (dedup, limits, retention, pin, search) and Migrations
  PasteboardCodec.swift    pasteboard ⇄ snapshot, secret markers, kind/plain text/thumbnail/hash
  InstallLocation.swift    uninstall rules: installed vs dev copy, trash detection, data locations
Sources/Clippy/            the menu bar app
  App/       main.swift, AppDelegate (wires everything, hotkeys, retention timer), StatusBarController (status item, popover, appearance, popover keyboard),
             PreviewPanel.swift (hover preview card beside the popover), Windows.swift (SettingsWindowController)
  Services/  AppSettings (UserDefaults), ClipboardMonitor (polls changeCount), PasteService (as-is / plain / ⌘V synth / restore),
             SystemServices.swift (LoginItemManager, Permissions, HotKeyManager, KeyCode),
             Uninstaller (installs the cleanup LaunchAgent; also watches its own bundle while running)
  UI/        Theme (DESIGN.md tokens + ViewState alias), ClipListModel (popover state, ThumbnailCache), PopoverView, ClipRow,
             SettingsView (tabs), Components/Controls.swift (ClippySwitch, SegmentedControl, StepperControl, ClippyButtonStyle, LinkButton)
Tests/ClippyTests/         swift-testing: ClipRepositoryTests, PasteboardCodecTests
Resources/                 Info.plist template (__VERSION__/__BUILD__), AppIcon.icns (regenerate: make icon)
scripts/                   build-app.sh (debug|release → build/<config>/Clippy.app), make-dmg.sh (+ make-dmg-background.swift), make-icon.swift
Makefile                   entry point for everything below
```
- **Database:** `~/Library/Application Support/Clippy/clippy.sqlite`, WAL mode.
  - `clips`: list data (`kind`, `plain_text`, `thumb`, `hash`, `pinned`, timestamps).
  - `representations`: raw pasteboard data per `(clip_id, item_index, uti)`. Loaded only when pasting.
- **Migrations:** `PRAGMA user_version`. Never edit an existing migration; append a new one.

## Build, run, test
- Only the Command Line Tools are installed (no Xcode), so use SwiftPM through the Makefile.
- `make dev` builds `build/debug/Clippy.app`, launches it with `open` (LaunchServices) and tails its log (`build/dev.log`); Ctrl-C quits. It stops any running Clippy first. **Never run the binary directly from a terminal:** macOS would then treat the terminal app (e.g. VS Code) as responsible for Clippy and check *its* Accessibility permission, so pasting silently fails.
- `make build` builds a universal (arm64 + x86_64) `build/release/Clippy.app` and packages `dist/Clippy.dmg` to share (the version lives in the app's Info.plist, not the file name). The DMG opens as a styled drag-to-install window (background with an arrow, app left, Applications right). Finder sets that layout through AppleScript, so the first `make build` asks to let the terminal control Finder. `VERSION=1.1 BUILD_NUMBER=2 make build` sets the version.
- `make install` builds the release app, copies it to `/Applications` and opens it. `make test` runs the tests, `make clean` deletes build output, and `make icon` regenerates the icon.
- Run tests through `make test`. With the Command Line Tools, plain `swift test` can fail with "plugin for module 'TestingMacros' not found"; the Makefile passes `-plugin-path …/host/plugins/testing`.
- **Sharing the DMG:** an ad-hoc signed app gets a Gatekeeper warning on other Macs. Recipients right-click the app and choose Open, or run `xattr -dr com.apple.quarantine /Applications/Clippy.app`. To ship it properly, sign with a Developer ID and notarize: `SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<notarytool profile> make build`.
- Paste injection needs Accessibility permission (and event-posting access), which macOS ties to the app's signature. Builds are signed with the local self-signed identity "Clippy Dev", so the permission survives rebuilds. `make signing-cert` creates it once per Mac, in a dedicated keychain `~/Library/Keychains/clippy-dev.keychain-db` that the build scripts unlock themselves, so codesign never prompts. Without it the build falls back to ad-hoc signing, and macOS drops the permission after every rebuild.
- Clippy logs `accessibility=… postEvent=…` at startup and one line per paste (target app, frontmost app, permission state). Check `build/dev.log` first when a paste doesn't land.
- Inspect the DB: `sqlite3 ~/Library/Application\ Support/Clippy/clippy.sqlite 'select id,kind,pinned,datetime(last_used_at,"unixepoch"),substr(plain_text,1,40) from clips order by last_used_at desc'`

## Conventions
- **Never write `@State`.** In this SDK `@State` is a macro whose plugin ships only with Xcode, so it fails to compile with the Command Line Tools. Use `@ViewState`, an alias for `SwiftUI.State` defined in `UI/Theme.swift`.
- Swift 6 language mode.
  - UI types are `@MainActor`.
  - Database access is serialized on the store's own queue.
  - Heavy pasteboard reads and thumbnails run off the main thread.
- Colours come from `Theme` (the DESIGN.md tokens). Don't hard-code colours in views.
- Every icon-only control gets an accessibility label. Respect Reduce Motion.
- Any change to ClipStore rules or to PasteboardCodec gets a swift-testing test.

## Decision log
- 2026-11-25: Settled DESIGN.md §1's open question. ⇧⌘V is plain paste, so "Open Clippy" defaults to ⌥⌘V. Its options are ⌥⌘V, ⌃⌥V, ⌃⌘V and None.
- 2026-11-25 (superseded the same day): ~~"Pasted into" HUD and in-popover toasts~~. **No toasts or notifications at all**, per the owner. Don't add any.
- 2026-11-25: Clips store the raw data of every pasteboard type instead of a single format, so pasting preserves formatting exactly.
- 2026-11-25: Duplicates are matched by what the row shows: text by its plain text, images by the primary image bytes, files by their paths. The same text with different formatting counts as one clip, and the newest copy's formats replace the stored ones.
- 2026-11-25: Launch at login is registered automatically on first launch only for the copy in `/Applications`, so dev builds never become login items. Accessibility is requested on the first paste, not at launch.
- 2026-11-25: Release builds are universal (arm64 + x86_64) so the shared DMG runs on Intel Macs too.
- 2026-11-25: The switch is a custom control (DESIGN.md §6), not `NSSwitch`.
- 2026-11-25: In the popover, ⌫ deletes the selected row only while the search field is empty; otherwise it edits the query.
- 2026-11-25: Built with SwiftPM, packaged into a `.app` by a script, because Xcode isn't installed.
- 2026-11-25: The popover's appearance is set explicitly from the Appearance setting; otherwise NSPopover inherits the menu bar's look. Light mode adds a 55% white tint over the native glass.
- 2026-11-25: The hover preview is a separate non-activating, click-through `NSPanel` rather than a SwiftUI popover or `.help` tooltip. It can show full text, images and file lists without stealing focus from the search field or the paste target.
- 2026-11-25: Paste flow: write the clip, `NSApp.hide` plus activate the previous app, wait until it's frontmost, then synthesize ⌘V. Without Accessibility permission Clippy requests it and leaves the clip on the clipboard, with no message.
- 2026-11-25: The switch has no border, hairline or focus ring (owner request).
- 2026-11-25: The search field is not focused when the popover opens (owner request). Typing a character focuses it and starts the search.
- 2026-11-25: Image files copied in Finder, and images whose only text is their name or URL, are `kind = image` and show a small thumbnail (56pt row, 44pt image). Clips stored by older builds are re-checked once at launch (`classificationVersion` in UserDefaults; bump it when the classification or duplicate rules change).
- 2026-11-25: If a paste can't be typed because Accessibility is missing, Settings opens on Permissions instead of failing silently.
- 2026-11-25: `make dev` launches through LaunchServices because of the terminal-responsibility problem described above. That was the cause of "clicking a clip doesn't paste into VS Code".
- 2026-11-25: The "Clippy Dev" key lives in its own keychain, not the login keychain, because the login keychain made codesign block on a keychain-access dialog.
- 2026-11-25: Pinned has its own order (`pin_order`, migration v2), not last use. New pins join the bottom; use and re-copy don't move a pinned clip. Reorder by drag, context menu or ⌥⌘↑/↓; disabled while searching. Drag is a `DragGesture` (high priority, 4pt minimum) with live swapping, not system drag-and-drop: `onDrag` never started because each row is a Button that takes the mouse-down.
- 2026-11-25: Owner asked for source app and copy date in the hover preview (footer, `DD MMM, YYYY`). Rows still never show them.
- 2026-11-25 (superseded the same day): ~~Duplicate text matched ignoring surrounding whitespace~~. **Owner: duplicates must be exactly the same text**; whitespace, newlines and case make a different clip. `classificationVersion` 4 restores exact hashes (merging only exact duplicates: pinned wins, else most recent).
- 2026-11-25: History/Pinned visible rows are settings (default 10, 5–15). When both don't fit on screen the lists shrink (shorter one keeps its height if it fits in half). `maxContentHeight` is set from the screen each time the popover opens.
- 2026-11-25: The DMG is `dist/Clippy.dmg` (no version in the name) with a styled drag-to-install window. The layout is written by Finder via AppleScript (built-in tools only; downloading `dmgbuild` was not an option).
- 2026-11-25: Owner asked that trashing the app removes everything. macOS has no uninstall hook, so the running installed app watches its bundle (`O_EVTONLY` + `F_GETPATH`). After 2 s, if the bundle is in the Trash or gone and nothing replaced it, it wipes data, login item and TCC entries, removes its status item and exits. If Clippy isn't running when it's trashed, nothing can clean up.
- 2026-11-25: Trash-to-uninstall now runs from a LaunchAgent, because Finder won't move a running app to the Trash, so the in-app watcher never fired in practice. The agent is a `/bin/sh -c` script (system tools only), `WatchPaths` = the app bundle itself (watching `/Applications` never fires because it's a firmlink), `AssociatedBundleIdentifiers` = Clippy. It waits 3 s, exits if the app is back (update / `make install`), otherwise deletes data, prefs and TCC entries and boots itself out. Verified live: quit + trash → wiped in under 8 s; `make install` → kept.
