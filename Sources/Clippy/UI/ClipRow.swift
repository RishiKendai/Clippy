import ClippyCore
import SwiftUI

/// One clip (DESIGN.md §4 "Row anatomy"). Single line; source app and time appear only in the hover preview.
struct ClipRow: View {
    let clip: ClipSummary
    let selected: Bool
    let theme: PopoverTheme
    @ObservedObject var model: ClipListModel
    @ViewState private var frame: CGRect = .zero

    static func height(for clip: ClipSummary) -> CGFloat { clip.kind == .image ? 56 : 40 }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.use(clip.id)
            } label: {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.height(for: clip))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(clip.kind == .image ? "Paste image" : "Paste \(clip.label)")

            HStack(spacing: 2) {
                RowIconButton(symbol: clip.pinned ? "pin.fill" : "pin",
                              label: clip.pinned ? "Unpin" : "Pin", theme: theme) {
                    model.togglePin(clip.id)
                }
                RowIconButton(symbol: "trash", label: "Delete", theme: theme) {
                    model.delete(clip.id)
                }
            }
            // Space stays reserved so the layout never jumps.
            .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme.hover : .clear))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
            frame = newFrame
            if model.hoveredID == clip.id { model.hover(clip, inside: true, frame: newFrame) }
        }
        .onHover { inside in model.hover(clip, inside: inside, frame: frame) }
        .contextMenu {
            Button("Paste") { model.use(clip.id) }
            if clip.kind != .image {
                Button("Paste as Plain Text") { model.use(clip.id, plain: true) }
            }
            Button(clip.pinned ? "Unpin" : "Pin") { model.togglePin(clip.id) }
            if clip.pinned, model.canReorderPinned {
                let index = model.pinned.firstIndex { $0.id == clip.id } ?? 0
                Button("Move Up") { model.movePinned(clip.id, by: -1) }
                    .disabled(index == 0)
                Button("Move Down") { model.movePinned(clip.id, by: 1) }
                    .disabled(index == model.pinned.count - 1)
            }
            Divider()
            Button("Delete") { model.delete(clip.id) }
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .text:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6.5)
                    .strokeBorder(theme.icon, lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                    .overlay(Text("T").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.icon))
                    .accessibilityHidden(true)
                label
            }
        case .file:
            HStack(spacing: 10) {
                Image(systemName: "doc")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.icon)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                label
            }
        case .image:
            // The image itself, small: 44pt tall, aspect-fit, left-aligned. No name, no dimensions.
            Group {
                if let image = ThumbnailCache.image(for: clip) {
                    let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: min(max(44 * aspect, 44), 220), height: 44)
                        .clipped()
                } else {
                    theme.field.frame(width: 44, height: 44)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.imageBorder, lineWidth: 1))
        }
    }

    private var label: some View {
        Text(clip.label)
            .font(.system(size: 13))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

private struct RowIconButton: View {
    let symbol: String
    let label: String
    let theme: PopoverTheme
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.icon)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? theme.popline : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}
