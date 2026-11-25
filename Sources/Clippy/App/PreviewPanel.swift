import AppKit
import ClippyCore
import SwiftUI

/// Hover preview ("screentip") beside the popover showing a clip's whole content:
/// full text, a large image, or every file with its path, plus the source app and copy date. Non-activating and click-through,
/// so it never steals focus from the search field or the app being pasted into.
@MainActor
final class PreviewController {
    private let panel: NSPanel
    private var pending: Task<Void, Never>?
    private var shownID: Int64?

    /// Delay before the first preview appears; moving between rows afterwards is instant.
    private let openDelay: Duration = .milliseconds(450)
    static let width: CGFloat = 360

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    /// Shows the preview for `clip`, next to `rowRect` (screen coordinates) and beside `popoverFrame`.
    func show(_ clip: ClipSummary, rowRect: NSRect, popoverFrame: NSRect, appearance: NSAppearance?, above level: NSWindow.Level) {
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        pending?.cancel()
        let delay: Duration = panel.isVisible ? .zero : openDelay
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            self?.present(clip, rowRect: rowRect, popoverFrame: popoverFrame, appearance: appearance)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        shownID = nil
        panel.orderOut(nil)
    }

    /// Hides after a short grace period, so moving to the next row doesn't flicker.
    func hideSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func present(_ clip: ClipSummary, rowRect: NSRect, popoverFrame: NSRect, appearance: NSAppearance?) {
        panel.appearance = appearance
        let host = NSHostingView(rootView: PreviewCard(clip: clip))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        let screen = (NSScreen.screens.first { $0.frame.intersects(popoverFrame) } ?? NSScreen.main)?.visibleFrame ?? popoverFrame
        let gap: CGFloat = 8
        // Prefer the left of the popover; flip to the right if there isn't room.
        var x = popoverFrame.minX - gap - size.width
        if x < screen.minX { x = popoverFrame.maxX + gap }
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        // Top-align with the hovered row, kept on screen.
        var y = rowRect.maxY - size.height
        y = min(max(y, screen.minY + 4), screen.maxY - size.height - 4)

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if shownID != clip.id || !panel.isVisible {
            panel.orderFrontRegardless()
        }
        shownID = clip.id
    }
}

/// The preview's content: same tokens as the popover, on the same glass material.
private struct PreviewCard: View {
    let clip: ClipSummary
    @Environment(\.colorScheme) private var scheme

    /// Long text is cut so the card stays fast and fits on screen.
    private static let maxCharacters = 4000
    private static let maxLines = 22

    var body: some View {
        let theme = PopoverTheme(scheme)
        VStack(alignment: .leading, spacing: 8) {
            switch clip.kind {
            case .text: textBody(theme)
            case .image: imageBody(theme)
            case .file: fileBody(theme)
            }
            metadata(theme)
        }
        .padding(12)
        .frame(width: PreviewController.width, alignment: .leading)
        .background(
            ZStack {
                GlassBackground()
                scheme == .light ? Color.white.opacity(0.55) : Color.clear
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.popline, lineWidth: 1))
    }

    @ViewBuilder private func textBody(_ theme: PopoverTheme) -> some View {
        let full = clip.plainText
        let shown = full.count > Self.maxCharacters ? String(full.prefix(Self.maxCharacters)) + "…" : full
        Text(shown)
            .font(.system(size: 12))
            .foregroundStyle(theme.text)
            .lineLimit(Self.maxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        let lines = full.split(whereSeparator: \.isNewline).count
        Text("\(full.count.formatted()) characters · \(max(1, lines).formatted()) \(lines == 1 ? "line" : "lines")")
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(theme.sub)
    }

    /// Where and when the clip was copied (the latest copy, for re-copied content).
    @ViewBuilder private func metadata(_ theme: PopoverTheme) -> some View {
        theme.divider.frame(height: 1)
        HStack(spacing: 6) {
            if let app = clip.sourceApp {
                if let icon = Self.icon(forApp: app) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14).accessibilityHidden(true)
                }
                Text(app).lineLimit(1).truncationMode(.tail)
            } else {
                Text("Unknown app")
            }
            Spacer(minLength: 8)
            Text(Self.dateFormatter.string(from: clip.copiedAt)).monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.sub)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Copied from \(clip.sourceApp ?? "an unknown app") on \(Self.dateFormatter.string(from: clip.copiedAt))")
    }

    /// "25 Nov, 2026"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM, yyyy"
        return f
    }()

    /// The source app's icon, if it's running or installed in /Applications under that name.
    private static func icon(forApp name: String) -> NSImage? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }), let icon = running.icon {
            return icon
        }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let path = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        }
        return nil
    }

    @ViewBuilder private func imageBody(_ theme: PopoverTheme) -> some View {
        if let image = ThumbnailCache.image(for: clip) {
            let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
            let maxSide = PreviewController.width - 24
            let w = aspect >= 1 ? maxSide : maxSide * aspect
            let h = aspect >= 1 ? maxSide / aspect : maxSide
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.imageBorder, lineWidth: 1))
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func fileBody(_ theme: PopoverTheme) -> some View {
        let paths = clip.plainText.split(separator: "\n").map(String.init)
        ForEach(Array(paths.prefix(12).enumerated()), id: \.offset) { _, path in
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        if paths.count > 12 {
            Text("and \(paths.count - 12) more")
                .font(.system(size: 11))
                .foregroundStyle(theme.sub)
        }
    }
}

/// Behind-window blur matching the popover's glass.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
