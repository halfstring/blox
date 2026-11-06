import Foundation

public struct StickyContent: Codable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ListItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID, text: String, done: Bool) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public struct ListContent: Codable, Equatable {
    public var title: String
    public var items: [ListItem]

    public init(title: String, items: [ListItem]) {
        self.title = title
        self.items = items
    }
}

public enum ReminderState: String, Codable {
    case pending, fired, done
}

public struct ReminderContent: Codable, Equatable {
    public var text: String
    public var due: Date
    public var state: ReminderState

    public init(text: String, due: Date, state: ReminderState) {
        self.text = text
        self.due = due
        self.state = state
    }
}

public enum BlockKind: Codable, Equatable {
    case sticky(StickyContent)
    case list(ListContent)
    case reminder(ReminderContent)
}

public struct Block: Codable, Equatable, Identifiable {
    public let id: UUID
    public var x: CGFloat
    public var y: CGFloat
    public var kind: BlockKind

    public init(id: UUID, x: CGFloat, y: CGFloat, kind: BlockKind) {
        self.id = id
        self.x = x
        self.y = y
        self.kind = kind
    }
}

public extension Block {
    var isAlertingReminder: Bool {
        if case let .reminder(content) = kind, content.state == .fired { return true }
        return false
    }
}

public func fireReminders(_ blocks: [Block], now: Date) -> [Block] {
    blocks.map { block in
        guard case .reminder(var content) = block.kind,
              content.state == .pending,
              content.due <= now else {
            return block
        }
        content.state = .fired
        var updated = block
        updated.kind = .reminder(content)
        return updated
    }
}

public func clampReminderText(_ text: String) -> String {
    String(text.prefix(300))
}

public enum BlockLayout {
    public static let panelWidth: CGFloat = 940
    public static let panelHeight: CGFloat = 640
    public static let paletteHeight: CGFloat = 40
    public static let minWindowWidth: CGFloat = 640
    public static let minWindowHeight: CGFloat = 400
    public static let canvasViewport = CGSize(width: panelWidth, height: panelHeight - paletteHeight)
    public static let cardWidth: CGFloat = 208
    public static let cardSpan = CGSize(width: 220, height: 240)
    public static let minBlockX: CGFloat = 120
    public static let minBlockY: CGFloat = 80
    public static let unrollThreshold: CGFloat = 130
}
