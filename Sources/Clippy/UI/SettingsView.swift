import AppKit
import Combine
import ClippyCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", history = "History", permissions = "Permissions", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .history: "clock"
        case .permissions: "lock"
        case .about: "info.circle"
        }
    }
}

/// Which Settings tab is showing (lets the app open Settings on a specific tab).
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Settings window content (DESIGN.md §5): toolbar-style tabs, one tab at a time.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: ClipListModel
    let onTabChange: (SettingsTab) -> Void

    @ObservedObject var nav: SettingsNavigation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = SettingsTheme(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { t in
                    TabButton(tab: t, selected: nav.tab == t, theme: theme) { nav.tab = t }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 8)
            .background(theme.bar)
            .overlay(alignment: .bottom) { theme.line.frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch nav.tab {
                    case .general: GeneralTab(settings: settings, theme: theme)
                    case .history: HistoryTab(settings: settings, model: model, theme: theme)
                    case .permissions: PermissionsTab(theme: theme)
                    case .about: AboutTab(model: model, theme: theme)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.win)
        .foregroundStyle(theme.text)
        .font(.system(size: 13))
        .frame(width: 600, height: 540)
        .ignoresSafeArea()
        .onChange(of: nav.tab) { _, t in onTabChange(t) }
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let selected: Bool
    let theme: SettingsTheme
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 18)).frame(height: 22)
                Text(tab.rawValue).font(.system(size: 11))
            }
            .foregroundStyle(selected ? theme.tabOnText : theme.tabText)
            .frame(minWidth: 72)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? theme.tabOn : (hovering ? theme.tabHover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: Shared layout

struct SettingsCard<Content: View>: View {
    let theme: SettingsTheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.ring, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var description: String? = nil
    let theme: SettingsTheme
    var showSeparator = true
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            if showSeparator { theme.rowline.frame(height: 1) }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let description {
                        Text(description).font(.system(size: 11)).foregroundStyle(theme.sub)
                    }
                }
                Spacer(minLength: 0)
                control
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
    }
}

private struct Footnote: View {
    let text: String
    let theme: SettingsTheme
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(theme.sub).padding(.horizontal, 4)
    }
}

// MARK: Tabs

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let theme: SettingsTheme

    var body: some View {
        SettingsCard(theme: theme) {
            SettingsRow(title: "Appearance", description: "System follows your Mac's light or dark setting.", theme: theme, showSeparator: false) {
                SegmentedControl(options: Appearance.allCases, selection: $settings.appearance, title: \.label, accessibilityLabel: "Appearance")
            }
            SettingsRow(title: "Launch Clippy at login", description: "Starts quietly in the menu bar when you log in.", theme: theme) {
                ClippySwitch(isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { on in
                        settings.launchAtLogin = on
                        LoginItemManager.set(on)
                    }
                ), label: "Launch Clippy at login")
            }
            SettingsRow(title: "Open Clippy", description: "Keyboard shortcut that works in any app.", theme: theme) {
                Picker("Open Clippy", selection: $settings.openShortcut) {
                    ForEach(OpenShortcut.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            SettingsRow(title: "Paste automatically on click", description: "Off: clicking an item only copies it.", theme: theme) {
                ClippySwitch(isOn: $settings.autoPaste, label: "Paste automatically on click")
            }
            SettingsRow(title: "Play sound when copying", theme: theme) {
                ClippySwitch(isOn: $settings.playSound, label: "Play sound when copying")
            }
        }
    }
}

private struct HistoryTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: ClipListModel
    let theme: SettingsTheme
    /// Which clear action is waiting for confirmation, and how many items it would delete.
    @ViewState private var confirming: ClearTarget?
    @ViewState private var pendingCount = 0

    private enum ClearTarget { case history, pinned }

    var body: some View {
        SettingsCard(theme: theme) {
            SettingsRow(title: "Keep items for", description: "Unused items older than this are deleted.", theme: theme, showSeparator: false) {
                StepperControl(value: $settings.keepDays, range: 1...365, step: 1, unit: "days", label: "Keep items for")
            }
            SettingsRow(title: "Text history limit", description: "Oldest text items are removed past this.", theme: theme) {
                StepperControl(value: $settings.maxText, range: 50...1000, step: 50, unit: "items", label: "Text history limit")
            }
            SettingsRow(title: "Image history limit", description: "Oldest images are removed past this.", theme: theme) {
                StepperControl(value: $settings.maxImages, range: 10...500, step: 10, unit: "images", label: "Image history limit")
            }
            SettingsRow(title: "Ignore passwords and secrets", description: "Skips content that password managers mark as concealed.", theme: theme) {
                ClippySwitch(isOn: $settings.ignoreSecrets, label: "Ignore passwords and secrets")
            }
        }

        SettingsCard(theme: theme) {
            SettingsRow(title: "History items shown", description: "Rows visible before the History list scrolls.", theme: theme, showSeparator: false) {
                StepperControl(value: $settings.historyRows, range: AppSettings.visibleRowsRange, step: 1, unit: "items", label: "History items shown")
            }
            SettingsRow(title: "Pinned items shown", description: "Rows visible before the Pinned list scrolls.", theme: theme) {
                StepperControl(value: $settings.pinnedRows, range: AppSettings.visibleRowsRange, step: 1, unit: "items", label: "Pinned items shown")
            }
        }

        SettingsCard(theme: theme) {
            SettingsRow(title: "Clear history", description: "Deletes every unpinned item. Pinned items are kept.", theme: theme, showSeparator: false) {
                Button("Clear History…") { ask(.history) }
                    .buttonStyle(ClippyButtonStyle(kind: .danger))
            }
            if confirming == .history {
                confirmRow("Delete \(pendingCount) unpinned \(pendingCount == 1 ? "item" : "items")? This can’t be undone.") {
                    _ = try? model.repo.clearUnpinned()
                }
            }
            SettingsRow(title: "Clear pinned items", description: "Deletes every pinned item. History is kept.", theme: theme) {
                Button("Clear Pinned…") { ask(.pinned) }
                    .buttonStyle(ClippyButtonStyle(kind: .danger))
            }
            if confirming == .pinned {
                confirmRow("Delete \(pendingCount) pinned \(pendingCount == 1 ? "item" : "items")? This can’t be undone.") {
                    _ = try? model.repo.clearPinned()
                }
            }
        }
        .onDisappear { confirming = nil }

        Footnote(text: "Pinned items never expire. Using or re-copying an item restarts its retention period.", theme: theme)
    }

    private func ask(_ target: ClearTarget) {
        let counts = try? model.repo.counts()
        pendingCount = (target == .history ? counts?.history : counts?.pinned) ?? 0
        confirming = target
    }

    /// Inline danger confirmation (DESIGN.md §5.2): Cancel collapses it, Clear deletes.
    private func confirmRow(_ message: String, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Text(message).font(.system(size: 12))
            Spacer(minLength: 0)
            Button("Cancel") { confirming = nil }
                .buttonStyle(ClippyButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Clear") {
                clear()
                confirming = nil
                model.reload()
            }
            .buttonStyle(ClippyButtonStyle(kind: .primary))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(theme.dangerBg)
    }
}

private struct PermissionsTab: View {
    let theme: SettingsTheme
    @ViewState private var granted = Permissions.accessibilityGranted
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsCard(theme: theme) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                    Text("Needed to paste into other apps when you click an item.")
                        .font(.system(size: 11)).foregroundStyle(theme.sub)
                    if !granted {
                        Text("Already listed but still not working? Remove Clippy with − and add it again. Each new build needs this.")
                            .font(.system(size: 11)).foregroundStyle(theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(granted ? theme.okDot : theme.danger).frame(width: 8, height: 8)
                        Text(granted ? "Granted" : "Not granted")
                            .font(.system(size: 12))
                            .foregroundStyle(granted ? theme.ok : theme.danger)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                LinkButton(title: "Open System Settings") {
                    if !granted { Permissions.requestAccessibility() }
                    Permissions.openAccessibilitySettings()
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .onReceive(refresh) { _ in granted = Permissions.accessibilityGranted }

        Footnote(text: "Clippy never sends your clipboard anywhere. Everything stays in a local database on this Mac.", theme: theme)
    }
}

private struct AboutTab: View {
    @ObservedObject var model: ClipListModel
    let theme: SettingsTheme
    @ViewState private var counts: (history: Int, pinned: Int) = (0, 0)

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var dbURL: URL? { try? ClipRepository.defaultURL() }

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(hex: 0x0A64D8))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "paperclip").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Color(hex: 0x0A64D8, alpha: 0.35), radius: 6, y: 4)
                .accessibilityHidden(true)
            Text("Clippy").font(.system(size: 17, weight: .semibold))
            Text(version).font(.system(size: 11)).foregroundStyle(theme.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)

        SettingsCard(theme: theme) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Database")
                    Text(dbURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "—")
                        .font(.system(size: 11)).foregroundStyle(theme.sub)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button("Show in Finder") {
                    if let dbURL { NSWorkspace.shared.activateFileViewerSelecting([dbURL]) }
                }
                .buttonStyle(ClippyButtonStyle())
            }
            .padding(.vertical, 10).padding(.horizontal, 14).frame(minHeight: 44)

            SettingsRow(title: "Stored items", theme: theme) {
                Text("\(counts.history) in history · \(counts.pinned) pinned")
                    .foregroundStyle(theme.sub)
                    .monospacedDigit()
            }
        }
        .onAppear { counts = (try? model.repo.counts()) ?? (0, 0) }
    }
}
