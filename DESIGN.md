Design spec for **Clippy**, a macOS-only menu bar clipboard manager. This file is the source of truth for how every screen looks and behaves. The visual reference is the Design canvas (artboards: *Popover — Light*, *Popover — Dark*, *Settings window*). If this file and the canvas ever disagree, ask; do not guess.

Target: macOS, menu bar app (no Dock icon), native-feeling. Fast, quiet, low memory.

---

## 1. Product behavior (context for every screen)

- Clippy records everything copied: text, rich text, images, files. Pasting restores the item as-is.
- Plain-content paste is a separate action (product requirement: `⌘⇧V`).
- **Open question:** the design currently shows the "Open Clippy" shortcut default as `⇧⌘V`, which collides with plain paste. Pick a different default (e.g. `⌥⌘V`) or confirm with the owner before building the shortcut recorder.
- Everything is stored locally (SQLite). Nothing leaves the Mac. The Permissions screen states this.
- Each clip is stored with `kind` (`text` | `image` | `file`), content, `source` (app it was copied from), `copiedAt`, `pinned`, `lastUsedAt`.
- **`source` and `copiedAt` are never shown on rows.** They appear only in the hover preview's footer (app name and icon, date as `DD MMM, YYYY`). Search may match `source`.
- **Duplicates:** re-copying content that's already stored doesn't add a row; the existing clip moves to the top of History. Text is a duplicate only when it's **exactly** the same: spaces, newlines and letter case all count (`"\nLinkedIn"` ≠ `"LinkedIn"` ≠ `"linkedin"`). Formatting alone doesn't make a new clip.

---

## 2. Visual foundations

### Typography
- Font: system (`-apple-system` / SF Pro Text). Fallback Inter, `system-ui`. Native: `.systemFont`.
- Base size 13px. Secondary/description 11px. Section headers 11px / 600. Settings window title 13px / 600. About app name 17px / 600.
- Use tabular numerals for counters and stepper values.

### Color tokens

**Popover** (`.clippy` / `.clippy.dark`)

| Token | Light | Dark |
|---|---|---|
| `--desk` (demo wallpaper only) | `#5f7383` | `#1d242b` |
| `--menubar` | `rgba(246,246,248,.9)` | `rgba(36,36,38,.9)` |
| `--pop` (popover surface) | `#f4f4f5` | `#2a2a2c` |
| `--popline` (popover border) | `rgba(0,0,0,.14)` | `rgba(255,255,255,.14)` |
| `--text` | `#1d1d1f` | `#f5f5f7` |
| `--sub` (secondary text) | `#636368` | `#a5a5aa` |
| `--field` (search field bg) | `rgba(0,0,0,.06)` | `rgba(255,255,255,.08)` |
| `--divider` | `rgba(0,0,0,.10)` | `rgba(255,255,255,.10)` |
| `--hover` (row hover/selected bg) | `rgba(0,0,0,.08)` | `rgba(255,255,255,.12)` |
| `--icon` | `#55555a` | `#b8b8bd` |
| `--accent` (focus ring) | `#0a64d8` | `#1a66d6` |

**Settings window** (`.set` / `.set.dark`)

| Token | Light | Dark |
|---|---|---|
| `--win` (window bg) | `#ececee` | `#1c1c1e` |
| `--bar` (toolbar) | `#f6f6f7` | `#2b2b2d` |
| `--card` | `#ffffff` | `#2c2c2e` |
| `--text` / `--sub` | `#1d1d1f` / `#636368` | `#f5f5f7` / `#a5a5aa` |
| `--line` (toolbar divider) | `rgba(0,0,0,.10)` | `rgba(255,255,255,.10)` |
| `--rowline` (row separators) | `rgba(0,0,0,.08)` | `rgba(255,255,255,.08)` |
| `--ring` (card outline) | `rgba(0,0,0,.07)` | `rgba(255,255,255,.08)` |
| `--tabtext` / `--tabontext` | `#55555a` / `#0a5bc4` | `#b8b8bd` / `#7ab8ff` |
| `--tabhover` / `--tabon` | `rgba(0,0,0,.05)` / `rgba(0,0,0,.08)` | `rgba(255,255,255,.07)` / `rgba(255,255,255,.12)` |
| `--accent` (primary button, focus ring) | `#0a64d8` | `#1a66d6` |
| `--link` | `#0a64d8` | `#6cb0ff` |
| `--btn` / `--btnborder` / `--btnactive` | `#fff` / `rgba(0,0,0,.15)` / `#f0f0f0` | `rgba(255,255,255,.10)` / `rgba(255,255,255,.18)` / `rgba(255,255,255,.16)` |
| `--danger` / `--dangerbg` | `#c4271c` / `#fff6f5` | `#ff7d75` / `rgba(255,69,58,.12)` |
| `--ok` / `--okdot` | `#1b7a34` / `#28a745` | `#4cd964` / `#30d158` |
| `--swoff` / `--swon` (switch) | `rgba(120,120,128,.30)` / `#007aff` | `rgba(120,120,128,.40)` / `#0a84ff` |
| `--seg` / `--segon` (segmented control) | `rgba(0,0,0,.07)` / `#fff` | `rgba(255,255,255,.10)` / `#636366` |

In the real app, prefer native materials and semantic system colors (`NSVisualEffectView` popover material, `labelColor`, `secondaryLabelColor`, `separatorColor`). The values above are the intended look; match them closely, but system colors win where they are within a shade.

### Theme / appearance
- Setting lives in **Settings → General → Appearance**: `System` (default) / `Light` / `Dark`.
- `System` follows macOS live (no restart).
- The setting themes **the whole app**: the Settings window, the menu bar popover and the hover preview. The popover must not inherit the menu bar's look. (The canvas shows Light and Dark popover boards side by side only so both can be reviewed.)
- Popover background: **Light** is white-based glass, the native popover material with a white tint at 55%. **Dark** is the native dark glass, untinted.

### Shape, spacing, elevation
- Popover: 380px wide, 12px radius, 8px padding, 1px `--popline` border, shadow `0 18px 50px rgba(0,0,0,.32), 0 2px 8px rgba(0,0,0,.16)`. A 12px rotated-square arrow sits on the top edge under the menu bar icon.
- Rows: 6px radius, 6px horizontal padding.
- Settings cards: 10px radius, 1px `--ring` outline, no shadow.
- Buttons: 6px radius. Segmented control: 8px outer / 6px inner radius.
- Window: 600 × 540, 12px radius, large soft shadow. Traffic lights 12px circles, 8px gap.

### Icons
- Stroke icons, 1.7–2px stroke, round caps/joins, `currentColor`. No emoji. Native: SF Symbols with matching meaning.

---

## 3. Screen: Menu bar item

- Template-image paperclip icon in the menu bar (adapts to light/dark menu bar automatically).
- Click opens the popover anchored beneath the icon. The configured global shortcut opens the same popover.
- The popover closes on: click outside, `Esc`, or after an item is used.

---

## 4. Screen: Popover (main screen)

Layout, top to bottom, inside one 380px-wide card:

1. **Search field** — 30px tall, 7px radius, `--field` background. Leading magnifier (14px, `--sub`), placeholder "Search", live filtering. A clear (✕ filled circle, 18px) button appears only when there is text. Matches against clip content and source app. The field is **not** focused when the popover opens. Typing any character while it's unfocused moves focus into it and starts the search with that character; clicking it also focuses it.
2. **History header** — "History" (11px/600, `--sub`) left, count right ("14 items" / "1 item", 11px regular).
3. **History list** — shows **N rows** (Settings → History → *History items shown*, default 10, range 5–15), then scrolls with a thin 8px scrollbar. Newest first.
4. **Pinned section** — only rendered when at least one pinned item matches. 1px divider, "Pinned" header with plain count, then its own list (same row design), showing *Pinned items shown* rows (default 10, range 5–15) before it scrolls. **Order is the user's:** new pins join the bottom; using or re-copying a pinned clip doesn't move it. Rearrange by dragging a row up or down: it lifts (hover fill, soft shadow) and follows the mouse, and the others slide out of the way once it passes half of a neighbour; the order is saved on release. A click without movement still pastes. Or use the context menu's *Move Up* / *Move Down*, or `⌥⌘↑` / `⌥⌘↓`. Rearranging is off while searching.
   - **Fitting the screen:** the popover never grows past the screen. If both lists at their configured rows don't fit below the menu bar, they shrink: a list that fits in half the space keeps its height and the other gets the rest; otherwise each gets half. Both scroll.
5. **Divider**, then two footer menu items, 26px tall, 5px radius:
   - `Settings…` with `⌘,` right-aligned (`--sub`)
   - `Quit Clippy` with `⌘Q`
   Hover = same neutral `--hover` fill as rows (not blue).
6. **No toasts or notifications.** Pasting, copying, pinning, unpinning and deleting give no toast, HUD or banner. The visible result (pasted text, the row moving or disappearing) is the feedback.
7. **Hover preview (screentip).** Hovering a row for ~450 ms opens a preview card beside the popover. It goes on the left, or on the right if there isn't room, top-aligned with the row. Moving to another row updates it instantly; leaving the rows hides it.
   - Card: 360px wide, 12px padding, 10px radius, 1px `--popline` border, the same glass as the popover (white-based in light).
   - Text: the full text (12px, up to 22 lines / 4,000 characters, then "…"), plus a footer "N characters · N lines" (11px, `--sub`).
   - Image: the image fitted inside 336 × 336, 6px radius.
   - File: each file's icon, name (12px/500) and `~`-abbreviated path (11px, `--sub`), up to 12, then "and N more".
   - Footer, for every kind: 1px `--divider`, then the source app's icon (14px) and name left, the copy date right as `DD MMM, YYYY` (e.g. "25 Nov, 2026"), 11px `--sub`. Re-copied content shows its latest copy. Unknown source → "Unknown app".
   - The card never takes focus and ignores the mouse. Arrow-key navigation hides it.

### Row anatomy

All rows: single line, no secondary line. **No source app, no timestamp** (those are in the hover preview only).

| Kind | Row height | Leading element | Content |
|---|---|---|---|
| Text | 40px | 28 × 28 rounded-square outline (1.5px stroke, 6.5px radius) containing a bold **T** | The text, one line, ellipsis. Newlines collapsed. |
| Image | 56px | *None.* The image itself, small: 44px tall, aspect-preserving (44–220px wide), left-aligned, 6px radius, 1px `rgba(0,0,0,.18)` border | **No file name, no URL, no dimensions.** |
| File | 40px | 28px document glyph (18px icon) | File name, one line, ellipsis. |

- Gap between leading element and text: 10px.
- Trailing actions (visible only when the row is hovered/selected or contains keyboard focus; space is always reserved so the layout never jumps):
  - **Pin / Unpin** (24 × 24, 5px radius). Outline pin when unpinned, filled pin when pinned.
  - **Delete** (24 × 24) trash icon.
  - Button hover bg: `--popline`.

### Row states
- **Hover / keyboard-selected:** background `--hover` (neutral, theme-adaptive). Text and icons keep normal colors. Hover moves the selection (single selection model, shared with keyboard).
- **Focus-visible:** 2px `--accent` outline, 1px offset.
- No blue/accent fill on rows, ever.

### Interactions
- **What counts as an image row:** an image on the clipboard, an image *file* copied in Finder, or an image whose only text is its own name or URL (e.g. a browser's Copy Image). Pasting such a row still pastes exactly what was copied (the file, or the image data). Its name or path remains searchable.
- **Click row / `Return`:** close the popover, return focus to the previously active app and paste the clip (as-is) **at its cursor**: the focused text field or wherever input was active. Then move the clip to the top of History and update `lastUsedAt`. A pinned clip keeps its place in Pinned. No notification. If "Paste automatically on click" is off in Settings, it only copies to the clipboard, also silently. If Accessibility permission is missing, the clip stays on the clipboard and Settings opens on **Permissions**: the one place to fix it. This is not a toast.
- **Pin:** moves the clip to the **bottom** of the Pinned section. **Unpin:** moves it back to the top of History. No toast.
- **Delete:** removes immediately, no toast. (No confirm; single-item delete is cheap.)
- **Keyboard:** `↑/↓` move selection, `Return` paste, `⌘⇧V`-style plain paste on the selected row, `⌘P` pin, `⌥⌘↑/↓` move the selected pinned clip, `⌫` delete selected (unless editing a non-empty search), typing a character starts a search, `⌘,` Settings, `Esc` close/clear search (first `Esc` clears a non-empty query).
- **Search empty states:** no clips at all → "Copy something to get started". Query with no matches → "No matches". Centered, 12px, `--sub`, 18px vertical padding.

---

## 5. Screen: Settings window

Standard macOS preferences window (600 × 540), toolbar-style tabs, one tab visible at a time. Window title shows the active tab name (13px/600, centered in the title bar). Content area scrolls; padding 20px top/bottom, 28px sides; 18px gap between cards.

### Toolbar tabs
`General` · `History` · `Permissions` · `About`. Each is a 72px-min button: 22px icon over an 11px label, 7px radius. States: default (`--tabtext`), hover (`--tabhover`), selected (`--tabon` bg + `--tabontext`). `role="tablist"` / `role="tab"`.

### Shared row pattern
Inside white/dark cards, rows are 44px min, 10px/14px padding, label (13px) + optional description (11px, `--sub`) on the left, control on the right, 16px gap, 1px `--rowline` between rows.

### 5.1 General
Single card, rows in this order:
1. **Appearance** — "System follows your Mac's light or dark setting." Segmented control: `System` (default) · `Light` · `Dark`. Applies instantly to the Settings window (and popover).
2. **Launch Clippy at login** — "Starts quietly in the menu bar when you log in." Switch, default **on**. (Native: `SMAppService`.)
3. **Open Clippy** — "Keyboard shortcut that works in any app." Dropdown/shortcut recorder: `⇧⌘V`, `⌥⌘V`, `⌃⌥V`, `None` (see open question in §1).
4. **Paste automatically on click** — "Off: clicking an item only copies it." Switch, default **on**.
5. **Play sound when copying** — no description. Switch, default **off**.

### 5.2 History
Card 1:
- **Keep items for** — "Unused items older than this are deleted." Stepper: default 30 days, range 1–365, step 1.
- **Text history limit** — "Oldest text items are removed past this." Default 300 items, range 50–1000, step 50.
- **Image history limit** — "Oldest images are removed past this." Default 100 images, range 10–500, step 10.
- **Ignore passwords and secrets** — "Skips content that password managers mark as concealed." Switch, default **on**.

Stepper control: 22 × 22 `−` / `+` buttons, value centered in a 64px tabular-numeral label, 8px gaps.

Card 2:
- **History items shown** — "Rows visible before the History list scrolls." Stepper: default 10 items, range 5–15, step 1.
- **Pinned items shown** — "Rows visible before the Pinned list scrolls." Default 10 items, range 5–15, step 1.

Card 3:
- **Clear history** — "Deletes every unpinned item. Pinned items are kept." Danger-styled button `Clear History…`.
- Clicking it reveals an inline confirmation row inside the same card (tinted `--dangerbg`): "Delete N unpinned items? This can't be undone." with `Cancel` and primary `Clear`. Both collapse the row; `Clear` performs the delete. Leaving the tab also dismisses it.

Footnote (11px, `--sub`, 4px inset): "Pinned items never expire. Using or re-copying an item restarts its retention period."

### 5.3 Permissions
One card, one row: **Accessibility**
- Left column, stacked: title → description "Needed to paste into other apps when you click an item." When not granted, an extra line: "Already listed but still not working? Remove Clippy with − and add it again. Each new build needs this." → status line **below the description**: 8px dot + "Granted" (green, 12px). When not granted: gray/red dot + "Not granted".
- Right: a text link (not a bordered button): **Open System Settings ›** — accent/link color, 13px, trailing right chevron, underline on hover. Opens System Settings → Privacy & Security → Accessibility.

Footnote: "Clippy never sends your clipboard anywhere. Everything stays in a local database on this Mac."

### 5.4 About
- Centered: 64px app icon (15px radius, blue `#0a64d8`, white paperclip), "Clippy" 17px/600, "Version 1.0 (1)" 11px `--sub`.
- Card: **Database** (path in `--sub`, single line with ellipsis: `~/Library/Application Support/Clippy/clippy.sqlite`) + `Show in Finder` button; **Stored items** — "14 in history · 3 pinned" (value right-aligned).

---

## 6. Components

### Switch (iOS 26 style — custom control)
- Track **63 × 28**, fully rounded (14px). Off: `--swoff`. On: **blue** `--swon` (`#007aff` light / `#0a84ff` dark).
- Thumb: **40 × 24** white pill, 2px inset, soft shadow (`0 2px 5px rgba(0,0,0,.18)`), no hairline.
- On position: thumb left = 21px. Track color animates 250 ms.
- While pressed the thumb stretches to 46px wide (on-state left = 15px so the right edge stays put). Thumb travel uses a springy ease (`cubic-bezier(.3,1.3,.5,1)`, ~320 ms).
- **No outline or border** on the track or thumb, and no focus ring around the switch.
- Accessible: `role="switch"`, `aria-checked`, label from the row title (toggled via the accessibility action). This is intentionally **not** the stock `NSSwitch`; build it as a custom SwiftUI/AppKit control to match.

### Segmented control
2px padding, 2px gap, `--seg` track, 8px radius. Selected segment: `--segon` fill, 6px radius, light shadow. Buttons `role="radio"` inside `role="radiogroup"`; one selected at all times.

### Buttons
- Default: `--btn` bg, 1px `--btnborder`, 6px radius, 3px/12px padding, 13px, subtle 1px shadow; pressed = `--btnactive`.
- Primary: `--accent` bg, white text.
- Danger: text `--danger`, otherwise default.
- Link-style (Open System Settings ›): no bg/border, `--link` color, chevron 12px, 3px gap.

### Row hover rule (popover)
Neutral `--hover` fill only. Never use the accent color for hover or selection.

---

## 7. Accessibility
- Every icon-only button has an `aria-label` / accessibility label (Pin/Unpin, Delete, Clear search).
- Row primary action label: "Paste <content>" (use a type description for images: "Paste image").
- Text contrast ≥ 4.5:1 in both themes; do not lower `--sub` below the listed values.
- Everything reachable by keyboard; focus ring visible (`2px --accent`) on buttons and fields (the switch is the exception, see §6).
- Respect Reduce Motion: drop the switch spring and use a plain fade/translate.

---

## 7b. Install & uninstall
- **Install:** opening `Clippy.dmg` shows a 640 × 400 Finder window, no toolbar or status bar: a light backdrop, Clippy's icon (128px) on the left, an arrow, the Applications folder on the right, and the caption "Drag Clippy to Applications to install". The disk uses Clippy's icon.
- **Uninstall:** dragging Clippy from Applications to the Trash removes it completely, with no prompt: clipboard history and database, settings, caches, the login item and its privacy permissions. The paperclip leaves the menu bar right away. Replacing Clippy with a newer copy keeps everything.

## 8. Build notes for Claude Code
- Platform: macOS menu bar app. Suggested structure: `NSStatusItem` + `NSPopover` (or a borderless `NSPanel` for more control) hosting a SwiftUI view; Settings in a `Settings` scene or custom `NSWindow` with toolbar-style tabs.
- Store clips in SQLite (kind, content/blob, source, copiedAt, lastUsedAt, pinned). Keep image data off the main thread; render row thumbnails from small cached downscales, never the full bitmap, to stay low-memory.
- Poll `NSPasteboard.changeCount` on a light timer; ignore items marked concealed (`org.nspasteboard.ConcealedType`) when "Ignore passwords and secrets" is on.
- Paste = write to pasteboard, then synthesize `⌘V` into the previous frontmost app (needs Accessibility permission, which is why the Permissions screen exists).
- Appearance: `System` = no override; `Light`/`Dark` set `NSApp.appearance`.
- Show `source` and `copiedAt` only in the hover preview footer, never on rows.
- When something here is ambiguous, follow the canvas; when the canvas is silent, follow standard macOS conventions and ask before inventing new UI.