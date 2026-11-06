import Foundation
import bloxKit

@main
struct SelfTestMain {
    @MainActor
    static func main() {
        run()
    }
}

@MainActor
private var failures = 0

@MainActor
private func check(_ condition: Bool, _ name: String) {
    if condition {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name)")
    }
}

@MainActor
private func reminderBlock(_ due: Date, _ state: ReminderState = .pending) -> Block {
    Block(id: UUID(), x: 200, y: 200, kind: .reminder(ReminderContent(text: "hello", due: due, state: state)))
}

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("blox-selftest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@MainActor
private func run() {
    let cases: [(String, () throws -> Void)] = [
        ("fireLogic", fireLogic),
        ("codableRoundTrip", codableRoundTrip),
        ("clampText", clampText),
        ("persistAndReload", persistAndReload),
        ("firePersists", firePersists),
        ("cappedReminder", cappedReminder),
        ("corruptBackup", corruptBackup),
        ("completeAndMove", completeAndMove),
        ("placementEmptySpace", placementEmptySpace),
        ("windowSizePersists", windowSizePersists),
        ("cardResize", cardResize),
        ("newStickySize", newStickySize)
    ]
    for (name, test) in cases {
        do {
            try test()
        } catch {
            failures += 1
            print("✗ \(name) 异常: \(error)")
        }
    }
    print(failures == 0 ? "--- SELFTEST OK ---" : "--- SELFTEST FAILED \(failures) ---")
    exit(failures == 0 ? 0 : 1)
}

@MainActor
private func fireLogic() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let overdue = reminderBlock(now.addingTimeInterval(-60))
    let future = reminderBlock(now.addingTimeInterval(600))
    let done = reminderBlock(now.addingTimeInterval(-600), .done)
    let sticky = Block(id: UUID(), x: 10, y: 10, kind: .sticky(StickyContent(text: "note")))

    let result = fireReminders([overdue, future, done, sticky], now: now)

    if case let .reminder(fired) = result[0].kind {
        check(fired.state == .fired, "到期 pending → fired")
    } else {
        check(false, "fireLogic 解构1")
    }
    if case let .reminder(kept) = result[1].kind {
        check(kept.state == .pending, "未到期保持 pending")
    } else {
        check(false, "fireLogic 解构2")
    }
    if case let .reminder(doneCase) = result[2].kind {
        check(doneCase.state == .done, "done 不回退")
    } else {
        check(false, "fireLogic 解构3")
    }
    check(result[3] == sticky, "sticky 不受影响")
}

@MainActor
private func codableRoundTrip() throws {
    let due = Date(timeIntervalSince1970: 1_700_000_123)
    let blocks = [
        Block(id: UUID(), x: 12.5, y: 88, kind: .sticky(StickyContent(text: "发文章"))),
        Block(id: UUID(), x: 300, y: 400, kind: .list(ListContent(title: "购物", items: [
            ListItem(id: UUID(), text: "牛奶", done: true),
            ListItem(id: UUID(), text: "鸡蛋", done: false)
        ]))),
        reminderBlock(due)
    ]

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(blocks)
    let decoded = try decoder.decode([Block].self, from: data)

    check(decoded == blocks, "JSON 往返一致")
}

@MainActor
private func clampText() throws {
    check(clampReminderText(String(repeating: "字", count: 400)).count == 300, "提醒文本限额300")
    check(clampReminderText("短") == "短", "短文本不变")
}

@MainActor
private func persistAndReload() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("blocks.json")

    let store = BlocStore(storageURL: url)
    store.addSticky()
    store.addReminder(text: "尽快改名", due: Date(timeIntervalSinceNow: 3600))
    check(store.blocks.count == 2, "新增两条卡片")

    let reloaded = BlocStore(storageURL: url).blocks
    check(reloaded.count == 2, "重启重载一致")
}

@MainActor
private func firePersists() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("blocks.json")

    let store = BlocStore(storageURL: url)
    let block = store.addReminder(text: "交房租", due: Date(timeIntervalSince1970: 1))
    store.tickReminders()
    check(store.reminder(id: block.id)?.state == .fired, "tick 后置 fired")

    let reloaded = BlocStore(storageURL: url).blocks
    check(reloaded.first.map(\.isAlertingReminder) == true, "fired 落盘且重载")
}

@MainActor
private func cappedReminder() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = BlocStore(storageURL: dir.appendingPathComponent("blocks.json"))
    store.addReminder()
    let id = store.blocks[0].id
    store.setReminderText(id: id, String(repeating: "词", count: 400))
    check(store.reminderText(id: id).count == 300, "编辑时限300")
}

@MainActor
private func corruptBackup() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("blocks.json")
    try Data("___corruption___".utf8).write(to: url)

    let store = BlocStore(storageURL: url)
    check(store.blocks.isEmpty, "损坏文件清空加载")
    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    check(contents.contains { $0.contains("corrupt") }, "损坏文件已备份")
    check(!contents.contains { $0 == "blocks.json" }, "原损坏文件已移出")
}

@MainActor
private func completeAndMove() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = BlocStore(storageURL: dir.appendingPathComponent("blocks.json"))
    let block = store.addReminder(text: "带伞", due: Date(timeIntervalSince1970: 1))
    store.tickReminders()
    check(store.hasAlertingReminder, "过期提醒进入警觉状态")
    store.completeReminder(id: block.id)
    check(store.reminder(id: block.id)?.state == .done, "标记完成")
    check(!store.hasAlertingReminder, "完成后撤销警觉")
    store.move(id: block.id, to: CGPoint(x: -500, y: -500))
    check(store.block(with: block.id)?.x == BlockLayout.minBlockX, "拖拽横坐标钳制")
    check(store.block(with: block.id)?.y == BlockLayout.minBlockY, "拖拽纵坐标钳制")
}

@MainActor
private func placementEmptySpace() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = BlocStore(storageURL: dir.appendingPathComponent("blocks.json"))
    for _ in 0..<6 { store.addSticky() }
    let span = BlockLayout.newCardSize
    let rects = store.blocks.map { block in
        CGRect(x: block.x - span.width / 2, y: block.y - span.height / 2, width: span.width, height: span.height)
    }
    var overlapped = false
    for i in rects.indices {
        for j in rects.indices where j > i {
            if rects[i].intersects(rects[j]) { overlapped = true }
        }
    }
    check(!overlapped, "新建卡片落在空白处")
    check(Set(store.blocks.map { "\(Int($0.x))-\(Int($0.y))" }).count == 6, "新建卡片位置互不相同")
    check(rects.allSatisfy { $0.minX >= 0 && $0.minY >= 0 }, "新建卡片在画布内")
}

@MainActor
private func windowSizePersists() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = Storage.windowSizeURL(beside: dir.appendingPathComponent("blocks.json"))
    let size = CGSize(width: 1180, height: 820)
    Storage.writeWindowSize(size, to: url)
    check(Storage.loadWindowSize(from: url) == size, "窗口大小持久化")
}


@MainActor
private func cardResize() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("blocks.json")
    let store = BlocStore(storageURL: url)
    let block = store.addSticky()
    store.resize(id: block.id, to: CGSize(width: 280, height: 240))
    check(store.block(with: block.id)?.width == 280 && store.block(with: block.id)?.height == 240, "卡片可缩放")
    let reloaded = BlocStore(storageURL: url)
    check(reloaded.block(with: block.id)?.width == 280, "卡片尺寸持久化")
    reloaded.resize(id: block.id, to: CGSize(width: 10, height: 10))
    check(reloaded.block(with: block.id)?.width == BlockLayout.minCardWidth, "卡片尺寸不小于下限")
}

@MainActor
private func newStickySize() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = BlocStore(storageURL: dir.appendingPathComponent("blocks.json"))
    let block = store.addSticky()
    check(block.width == BlockLayout.newCardSize.width && block.height == BlockLayout.newCardSize.height, "新建标签默认尺寸")
    check(store.block(with: block.id)?.height == BlockLayout.newCardSize.height, "新建标签尺寸已保存")
}
