import SwiftUI
import bloxKit

enum Paper {
    static let ink = Color(red: 0.129, green: 0.118, blue: 0.098)
    static let secondary = Color(red: 0.310, green: 0.290, blue: 0.259)
    static let muted = Color(red: 0.420, green: 0.396, blue: 0.349)
    static let hairline = Color.black.opacity(0.08)
    static let success = Color(red: 0.322, green: 0.502, blue: 0.373)
    static let alert = Color(red: 0.627, green: 0.180, blue: 0.141)
}

struct BlockCard: View {
    @ObservedObject var store: BlocStore
    @EnvironmentObject private var settings: AppSettings
    let block: Block
    @State private var translation = CGSize.zero
    @State private var hovered = false
    @State private var resizePreview: CGSize?
    @State private var resizeOrigin: CGSize?
    @State private var resizeHover = false
    @State private var measuredSize = CGSize.zero

    private var displayWidth: CGFloat { resizePreview?.width ?? block.width ?? BlockLayout.cardWidth }
    private var fixedHeight: CGFloat? { resizePreview?.height ?? block.height }

    var body: some View {
        VStack(spacing: 0) {
            grip
            content
                .frame(maxWidth: .infinity, maxHeight: fixedHeight == nil ? nil : .infinity)
        }
        .frame(width: displayWidth)
        .frame(height: fixedHeight)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Paper.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in measuredSize = size }
            }
        }
        .offset(translation)
        .zIndex(translation == .zero ? (resizePreview == nil ? 0 : 9) : 8)
        .environment(\.colorScheme, .light)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(role: .destructive) {
                store.remove(id: block.id)
            } label: {
                Label(settings.strings.delete, systemImage: "trash")
            }
        }
    }

    private var grip: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Paper.secondary.opacity(0.55))
            Spacer()
            if hovered {
                Button {
                    store.remove(id: block.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Paper.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(settings.strings.delete)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { translation = $0.translation }
            .onEnded { value in
                let x = max(BlockLayout.minBlockX, block.x + value.translation.width)
                let y = max(BlockLayout.minBlockY, block.y + value.translation.height)
                translation = .zero
                store.move(id: block.id, to: CGPoint(x: x, y: y))
            }
    }

    private var bg: Color {
        switch block.kind {
        case .sticky:
            Color(red: 0.957, green: 0.894, blue: 0.651)
        case .list:
            Color(red: 0.863, green: 0.910, blue: 0.949)
        case .reminder(let content):
            switch content.state {
            case .pending:
                Color(red: 0.918, green: 0.902, blue: 0.875)
            case .fired:
                Color(red: 0.945, green: 0.788, blue: 0.761)
            case .done:
                Color(red: 0.874, green: 0.855, blue: 0.827)
            }
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Paper.secondary.opacity(resizeHover ? 0.85 : 0.4))
            .frame(width: 18, height: 18)
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
            .highPriorityGesture(resizeGesture)
            .padding(2)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeOrigin == nil {
                    let baseHeight = fixedHeight ?? (measuredSize.height > 1 ? measuredSize.height : 200)
                    resizeOrigin = CGSize(width: displayWidth, height: baseHeight)
                }
                guard let base = resizeOrigin else { return }
                resizePreview = CGSize(
                    width: max(BlockLayout.minCardWidth, base.width + value.translation.width),
                    height: max(BlockLayout.minCardHeight, base.height + value.translation.height)
                )
            }
            .onEnded { _ in
                if let preview = resizePreview {
                    store.resize(id: block.id, to: preview)
                }
                resizeOrigin = nil
                resizePreview = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .sticky:
            StickyBody(store: store, blockID: block.id, flexible: fixedHeight != nil)
        case .list:
            if fixedHeight == nil {
                ListBody(store: store, blockID: block.id)
            } else {
                ScrollView { ListBody(store: store, blockID: block.id) }
                    .scrollIndicators(.hidden)
            }
        case .reminder:
            if fixedHeight == nil {
                ReminderBody(store: store, blockID: block.id)
            } else {
                ScrollView { ReminderBody(store: store, blockID: block.id) }
                    .scrollIndicators(.hidden)
            }
        }
    }
}

struct StickyBody: View {
    @ObservedObject var store: BlocStore
    let blockID: UUID
    let flexible: Bool

    var body: some View {
        Group {
            if flexible {
                ScrollView {
                    field
                }
                .scrollIndicators(.hidden)
            } else {
                field
            }
        }
        .frame(minHeight: flexible ? 0 : 132)
        .padding(.bottom, 20)
    }

    private var field: some View {
        TextField("", text: Binding(
            get: { store.stickyText(id: blockID) },
            set: { store.setStickyText(id: blockID, $0) }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Paper.ink)
        .tint(Paper.ink)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }
}

struct ListBody: View {
    @ObservedObject var store: BlocStore
    @EnvironmentObject private var settings: AppSettings
    let blockID: UUID
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(settings.strings.listTitle, text: Binding(
                get: { store.listTitle(id: blockID) },
                set: { store.setListTitle(id: blockID, $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Paper.ink)
            ForEach(store.listItems(id: blockID)) { item in
                ListItemRow(store: store, blockID: blockID, item: item)
            }
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Paper.muted)
                    .frame(width: 16, height: 16)
                TextField(settings.strings.newItem, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.ink)
                    .onSubmit {
                        store.addListItem(id: blockID, draft)
                        draft = ""
                    }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }
}

struct ListItemRow: View {
    @ObservedObject var store: BlocStore
    @EnvironmentObject private var settings: AppSettings
    let blockID: UUID
    let item: ListItem
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.toggleListItem(blockID: blockID, itemID: item.id)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.done ? Paper.success : Paper.muted)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            Text(item.text.isEmpty ? settings.strings.emptyItem : item.text)
                .font(.system(size: 12))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Paper.muted : Paper.ink)
                .lineLimit(2)
            Spacer(minLength: 2)
            if hovered {
                Button {
                    store.removeListItem(blockID: blockID, itemID: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Paper.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovered = $0 }
    }
}

struct ReminderBody: View {
    @ObservedObject var store: BlocStore
    @EnvironmentObject private var settings: AppSettings
    let blockID: UUID

    var body: some View {
        if let content = store.reminder(id: blockID) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    statusIcon(content.state)
                    Text(statusTitle(content))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor(content.state))
                    Spacer()
                }
                if content.state == .done {
                    Text(content.text)
                        .font(.system(size: 12))
                        .strikethrough()
                        .foregroundStyle(Paper.muted)
                        .frame(minHeight: 44, alignment: .topLeading)
                } else {
                    TextEditor(text: Binding(
                        get: { store.reminderText(id: blockID) },
                        set: { store.setReminderText(id: blockID, $0) }
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.ink)
                    .tint(Paper.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                }
                HStack {
                    Spacer()
                    Text("\(content.text.count)/300")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(content.text.count >= 300 ? Paper.alert : Paper.secondary)
                }
                DatePicker(
                    "",
                    selection: Binding(
                        get: { store.reminderDue(id: blockID) },
                        set: { store.setReminderDue(id: blockID, $0) }
                    ),
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .environment(\.locale, settings.language.locale)
                .disabled(content.state == .done)
                if content.state == .fired {
                    Button {
                        store.completeReminder(id: blockID)
                    } label: {
                        Text(settings.strings.markDone)
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Paper.alert)
                }
            }
            .environment(\.locale, settings.language.locale)
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    private func statusIcon(_ state: ReminderState) -> some View {
        Group {
            switch state {
            case .pending:
                Image(systemName: "bell").foregroundStyle(Paper.secondary)
            case .fired:
                Image(systemName: "bell.ring.fill").foregroundStyle(Paper.alert)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Paper.muted)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 16, height: 16)
    }

    private func statusTitle(_ content: ReminderContent) -> String {
        switch content.state {
        case .pending:
            settings.strings.reminderPrefix + " " + content.due.formatted(date: .abbreviated, time: .shortened)
        case .fired:
            settings.strings.due
        case .done:
            settings.strings.done
        }
    }

    private func statusColor(_ state: ReminderState) -> Color {
        switch state {
        case .pending: Paper.secondary
        case .fired: Paper.alert
        case .done: Paper.muted
        }
    }
}
