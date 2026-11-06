import SwiftUI
import bloxKit

enum Chrome {
    static let canvas = Color(red: 0.137, green: 0.129, blue: 0.114)
    static let bar = Color(red: 0.169, green: 0.157, blue: 0.137)
    static let hairline = Color.white.opacity(0.07)
    static let ink = Color.white.opacity(0.74)
    static let muted = Color.white.opacity(0.38)
    static let surface = Color.white.opacity(0.05)
    static let surfaceHover = Color.white.opacity(0.09)
    static let accent = Color(red: 0.914, green: 0.722, blue: 0.447)
}

struct CanvasScreen: View {
    @ObservedObject var store: BlocStore
    var onResize: (CGSize) -> Void
    var onResizeEnded: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @State private var activeBlockID: UUID?
    @State private var resizeHover = false
    @State private var resizeStartPoint: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            PaletteBar(store: store)
            canvas
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Chrome.canvas)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let content = contentSize(viewport: proxy.size)
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Rectangle()
                        .fill(Chrome.canvas)
                        .frame(width: content.width, height: content.height)
                    CanvasTexture(size: content)
                    ForEach(store.blocks) { block in
                        BlockCard(
                            store: store,
                            block: block,
                            isActive: activeBlockID == block.id,
                            onActivate: { activeBlockID = block.id }
                        )
                        .position(x: block.x, y: block.y)
                    }
                }
            }
            .defaultScrollAnchor(.center)
            .overlay {
                if store.blocks.isEmpty {
                    Text(settings.strings.emptyCanvas)
                        .font(.system(size: 13))
                        .foregroundStyle(Chrome.muted)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                resizeHandle.padding(10)
            }
            .onAppear { store.setViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in store.setViewport(size) }
        }
    }

    private func contentSize(viewport: CGSize) -> CGSize {
        let extent = store.contentExtent
        return CGSize(
            width: max(viewport.width, extent.width),
            height: max(viewport.height, extent.height)
        )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(resizeHover ? Chrome.ink : Chrome.muted.opacity(0.55))
            .frame(width: 28, height: 28)
            .background(Chrome.canvas.opacity(0.55), in: Circle())
            .contentShape(Rectangle())
            .onHover { inside in
                resizeHover = inside
                if inside {
                    if #available(macOS 15.0, *) {
                        NSCursor.frameResize(position: .bottomRight, directions: .all).set()
                    } else {
                        NSCursor.resizeLeftRight.set()
                    }
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help(settings.strings.resizeHelp)
            .highPriorityGesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let mouse = NSEvent.mouseLocation
                if resizeStartPoint == nil {
                    resizeStartPoint = CGPoint(
                        x: mouse.x - value.translation.width,
                        y: mouse.y + value.translation.height
                    )
                }
                guard let start = resizeStartPoint else { return }
                onResize(CGSize(width: mouse.x - start.x, height: start.y - mouse.y))
            }
            .onEnded { _ in
                resizeStartPoint = nil
                onResizeEnded()
            }
    }
}

struct CanvasTexture: View {
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let step: CGFloat = 26
            var dots = Path()
            var y = step / 2
            while y < canvasSize.height {
                var x = step / 2
                while x < canvasSize.width {
                    dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(.white.opacity(0.045)))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

struct PaletteBar: View {
    @ObservedObject var store: BlocStore
    @EnvironmentObject private var settings: AppSettings
    @State private var hoveredChip: String?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Chrome.accent)
                    .frame(width: 3, height: 10)
                Text("Blox")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Chrome.muted)
            }
            .padding(.trailing, 4)
            chip(settings.strings.stickyChip, icon: "note.text") { store.addSticky() }
            chip(settings.strings.listChip, icon: "checklist") { store.addList() }
            chip(settings.strings.reminderChip, icon: "bell.badge") { store.addReminder() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: BlockLayout.paletteHeight)
        .background(Chrome.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Chrome.hairline)
                .frame(height: 1)
        }
    }

    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Chrome.ink)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                hoveredChip == title ? Chrome.surfaceHover : Chrome.surface,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredChip = title
            } else if hoveredChip == title {
                hoveredChip = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredChip == title)
    }
}
