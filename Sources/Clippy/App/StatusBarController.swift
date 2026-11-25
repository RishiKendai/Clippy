import AppKit
import ClippyCore
import SwiftUI

/// The paperclip menu bar item and its popover, plus the popover's keyboard handling.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: ClipListModel
    private let preview = PreviewController()
    private var keyMonitor: Any?

    /// Called when the popover opens, with the app the user came from.
    var onOpen: (NSRunningApplication?) -> Void = { _ in }

    init(model: ClipListModel) {
        self.model = model
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clippy")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggle)
        }

        let hosting = NSHostingController(rootView: PopoverView(model: model, settings: model.settings))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        model.onPreview = { [weak self] clip, rect in self?.updatePreview(clip, rect) }
        applyAppearance(model.settings.appearance)
        // "System" follows macOS live.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyAppearance(self.model.settings.appearance)
            }
        }
    }

    /// The popover would otherwise take its look from the menu bar, not from Clippy's
    /// Appearance setting. Resolve it explicitly so it always matches the app theme.
    func applyAppearance(_ appearance: Appearance) {
        let dark: Bool
        switch appearance {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        popover.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    private func updatePreview(_ clip: ClipSummary?, _ rect: CGRect) {
        guard let clip, popover.isShown,
              let view = popover.contentViewController?.view, let window = view.window
        else {
            preview.hideSoon()
            return
        }
        // SwiftUI's global space is the hosting view's top-left-origin space.
        let local = view.isFlipped ? rect : NSRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        let rowOnScreen = window.convertToScreen(view.convert(local, to: nil))
        preview.show(clip, rowRect: rowOnScreen, popoverFrame: window.frame, appearance: popover.appearance, above: window.level)
    }

    var isShown: Bool { popover.isShown }

    @objc func toggle() {
        if popover.isShown { close() } else { show() }
    }

    func show() {
        guard let button = statusItem.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        onOpen(front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front)
        model.prepareForOpen()
        // Room below the menu bar on this screen, minus the popover's arrow and a margin.
        if let screen = button.window?.screen ?? NSScreen.main {
            model.maxContentHeight = screen.visibleFrame.height - 40
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            // The search field starts unfocused; typing anywhere moves into it (see handle()).
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
        }
        installKeyMonitor()
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverWillClose(_ notification: Notification) {
        preview.hide()
    }

    func popoverDidClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: Keyboard (DESIGN.md §4 "Interactions")

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let keyEvent = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown else { return false }
                return self.handle(keyEvent)
            }
            return handled ? nil : event
        }
    }

    private var searchFieldFocused: Bool {
        popover.contentViewController?.view.window?.firstResponder is NSTextView
    }

    /// Returns true when the event was handled (and should not reach the search field).
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)

        switch event.keyCode {
        case KeyCode.up where cmd && mods.contains(.option), KeyCode.down where cmd && mods.contains(.option):
            // ⌥⌘↑ / ⌥⌘↓: move the selected pinned clip.
            if let id = model.selectedID { model.movePinned(id, by: event.keyCode == KeyCode.up ? -1 : 1) }
            return true
        case KeyCode.down:
            preview.hide()
            model.moveSelection(1)
            return true
        case KeyCode.up:
            preview.hide()
            model.moveSelection(-1)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if let id = model.selectedID { model.use(id) }
            return true
        case KeyCode.escape:
            model.clearSearchOrClose { close() }
            return true
        case KeyCode.v where cmd && shift:
            if let id = model.selectedID { model.use(id, plain: true) }
            return true
        case KeyCode.p where cmd:
            if let id = model.selectedID { model.togglePin(id) }
            return true
        case KeyCode.delete, KeyCode.forwardDelete:
            // Delete the selected row unless the user is editing a non-empty query.
            guard !searchFieldFocused || model.query.isEmpty, let id = model.selectedID else { return false }
            model.delete(id)
            return true
        case KeyCode.comma where cmd:
            model.onOpenSettings()
            return true
        case KeyCode.q where cmd:
            model.onQuit()
            return true
        default:
            return typeToSearch(event, mods)
        }
    }

    /// Typing a character while the search field isn't focused starts a search with it.
    private func typeToSearch(_ event: NSEvent, _ mods: NSEvent.ModifierFlags) -> Bool {
        guard !searchFieldFocused, mods.isDisjoint(with: [.command, .control]),
              let chars = event.characters, !chars.isEmpty,
              chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
        else { return false }
        model.query += chars
        model.focusSearch()
        // Focusing selects the field's text; put the caret after what was typed instead.
        DispatchQueue.main.async { [weak self] in
            (self?.popover.contentViewController?.view.window?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
        }
        return true
    }
}
