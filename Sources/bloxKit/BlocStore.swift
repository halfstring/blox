import Foundation
import SwiftUI

@MainActor
public final class BlocStore: ObservableObject {
    @Published public private(set) var blocks: [Block]
    private let storageURL: URL
    private var timer: Timer?
    private var viewport = BlockLayout.canvasViewport
    var clock: () -> Date = { Date.now }

    public init(storageURL: URL = Storage.defaultURL()) {
        self.storageURL = storageURL
        let loaded = Storage.load(from: storageURL)
        blocks = fireReminders(loaded, now: Date.now)
        if blocks != loaded { save() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickReminders() }
        }
    }

    public var hasAlertingReminder: Bool {
        blocks.contains(where: \.isAlertingReminder)
    }

    public var contentExtent: CGSize {
        let maxX = blocks.map { $0.x + ($0.width ?? BlockLayout.cardWidth) }.max() ?? 0
        let maxY = blocks.map { $0.y + ($0.height ?? BlockLayout.cardSpan.height) }.max() ?? 0
        return CGSize(width: maxX, height: maxY)
    }

    public func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
    }

    public func block(with id: UUID) -> Block? {
        blocks.first { $0.id == id }
    }

    @discardableResult
    public func addSticky() -> Block {
        let point = placement()
        let block = Block(id: UUID(), x: point.x, y: point.y, kind: .sticky(StickyContent(text: "")))
        append(block)
        return block
    }

    @discardableResult
    public func addList() -> Block {
        let point = placement()
        let block = Block(id: UUID(), x: point.x, y: point.y, kind: .list(ListContent(title: "", items: [])))
        append(block)
        return block
    }

    @discardableResult
    public func addReminder(text: String = "", due: Date? = nil) -> Block {
        let dueAt = due ?? clock().addingTimeInterval(600)
        let point = placement()
        let block = Block(id: UUID(), x: point.x, y: point.y, kind: .reminder(ReminderContent(text: clampReminderText(text), due: dueAt, state: .pending)))
        append(block)
        return block
    }

    public func remove(id: UUID) {
        blocks.removeAll { $0.id == id }
        save()
    }

    public func resize(id: UUID, to size: CGSize) {
        mutate(id: id) { block in
            block.width = max(BlockLayout.minCardWidth, size.width)
            block.height = max(BlockLayout.minCardHeight, size.height)
        }
    }

    public func move(id: UUID, to point: CGPoint) {
        mutate(id: id) { block in
            block.x = max(BlockLayout.minBlockX, point.x)
            block.y = max(BlockLayout.minBlockY, point.y)
        }
    }

    public func stickyText(id: UUID) -> String {
        guard case let .sticky(content) = block(with: id)?.kind else { return "" }
        return content.text
    }

    public func setStickyText(id: UUID, _ text: String) {
        mutate(id: id) { block in
            guard case .sticky = block.kind else { return }
            block.kind = .sticky(StickyContent(text: text))
        }
    }

    public func listTitle(id: UUID) -> String {
        guard case let .list(content) = block(with: id)?.kind else { return "" }
        return content.title
    }

    public func setListTitle(id: UUID, _ title: String) {
        mutate(id: id) { block in
            guard case let .list(content) = block.kind else { return }
            block.kind = .list(ListContent(title: title, items: content.items))
        }
    }

    public func listItems(id: UUID) -> [ListItem] {
        guard case let .list(content) = block(with: id)?.kind else { return [] }
        return content.items
    }

    public func addListItem(id: UUID, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id: id) { block in
            guard case let .list(content) = block.kind else { return }
            var items = content.items
            items.append(ListItem(id: UUID(), text: trimmed, done: false))
            block.kind = .list(ListContent(title: content.title, items: items))
        }
    }

    public func toggleListItem(blockID: UUID, itemID: UUID) {
        mutate(id: blockID) { block in
            guard case let .list(content) = block.kind else { return }
            var items = content.items
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].done.toggle()
            }
            block.kind = .list(ListContent(title: content.title, items: items))
        }
    }

    public func removeListItem(blockID: UUID, itemID: UUID) {
        mutate(id: blockID) { block in
            guard case let .list(content) = block.kind else { return }
            let items = content.items.filter { $0.id != itemID }
            block.kind = .list(ListContent(title: content.title, items: items))
        }
    }

    public func reminder(id: UUID) -> ReminderContent? {
        guard case let .reminder(content) = block(with: id)?.kind else { return nil }
        return content
    }

    public func reminderText(id: UUID) -> String {
        reminder(id: id)?.text ?? ""
    }

    public func setReminderText(id: UUID, _ text: String) {
        mutate(id: id) { block in
            guard case let .reminder(content) = block.kind else { return }
            block.kind = .reminder(ReminderContent(text: clampReminderText(text), due: content.due, state: content.state))
        }
    }

    public func reminderDue(id: UUID) -> Date {
        reminder(id: id)?.due ?? Date.now
    }

    public func setReminderDue(id: UUID, _ due: Date) {
        mutate(id: id) { block in
            guard case let .reminder(content) = block.kind else { return }
            let state: ReminderState
            if content.state == .done {
                state = due > clock() ? .pending : .done
            } else {
                state = content.state
            }
            block.kind = .reminder(ReminderContent(text: content.text, due: due, state: state))
        }
    }

    public func completeReminder(id: UUID) {
        mutate(id: id) { block in
            guard case let .reminder(content) = block.kind, content.state != .done else { return }
            block.kind = .reminder(ReminderContent(text: content.text, due: content.due, state: .done))
        }
    }

    public func tickReminders() {
        let fired = fireReminders(blocks, now: clock())
        guard fired != blocks else { return }
        blocks = fired
        save()
    }

    private func placement() -> CGPoint {
        let span = BlockLayout.cardSpan
        let gap: CGFloat = 16
        let stepX = span.width + gap
        let stepY = span.height + gap
        let originX = BlockLayout.minBlockX
        let originY = max(BlockLayout.minBlockY, span.height / 2 + 12)
        let extent = contentExtent
        let canvas = CGSize(
            width: max(viewport.width, extent.width),
            height: max(viewport.height, extent.height)
        )
        let columns = 8
        let rows = 8
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        var best: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(
                    x: originX + CGFloat(column) * stepX,
                    y: originY + CGFloat(row) * stepY
                )
                let candidate = CGRect(
                    x: point.x - span.width / 2,
                    y: point.y - span.height / 2,
                    width: span.width,
                    height: span.height
                ).insetBy(dx: -gap / 2, dy: -gap / 2)
                let blocked = blocks.contains { block in
                    let width = block.width ?? span.width
                    let height = block.height ?? span.height
                    let occupied = CGRect(
                        x: block.x - width / 2,
                        y: block.y - height / 2,
                        width: width,
                        height: height
                    )
                    return candidate.intersects(occupied)
                }
                guard !blocked else { continue }
                let dx = point.x - center.x
                let dy = point.y - center.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    best = point
                }
            }
        }
        if let best { return best }
        let cascade = CGFloat((blocks.count % 9) * 26)
        return CGPoint(
            x: max(BlockLayout.minBlockX, center.x + cascade),
            y: max(BlockLayout.minBlockY, center.y + cascade)
        )
    }

    private func append(_ block: Block) {
        blocks.append(block)
        save()
    }

    private func mutate(id: UUID, _ body: (inout Block) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        var updated = blocks[index]
        body(&updated)
        guard updated != blocks[index] else { return }
        blocks[index] = updated
        save()
    }

    private func save() {
        Storage.write(blocks, to: storageURL)
    }
}
