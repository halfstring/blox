import Foundation

public enum Storage {
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("blox", isDirectory: true)
            .appendingPathComponent("blocks.json")
    }

    public static func load(from url: URL) -> [Block] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Block].self, from: data)
        } catch {
            NSLog("blox: blocks.json 损坏，已备份并清空 (%@)", "\(error)")
            let name = "blocks-\(Int(Date.now.timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).corrupt.json"
            let backup = url.deletingLastPathComponent().appendingPathComponent(name)
            try? FileManager.default.moveItem(at: url, to: backup)
            return []
        }
    }

    public static func write(_ blocks: [Block], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(blocks).write(to: url, options: [.atomic])
        } catch {
            NSLog("blox: 保存失败 %@", "\(error)")
        }
    }

    public static func windowSizeURL(beside blocksURL: URL) -> URL {
        blocksURL.deletingLastPathComponent().appendingPathComponent("window-size.json")
    }

    public static func loadWindowSize(from url: URL) -> CGSize? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(WindowSizeRecord.self, from: data) else {
            return nil
        }
        return CGSize(width: record.width, height: record.height)
    }

    public static func writeWindowSize(_ size: CGSize, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let record = WindowSizeRecord(width: Double(size.width), height: Double(size.height))
            try encoder.encode(record).write(to: url, options: [.atomic])
        } catch {
            NSLog("blox: 保存窗口大小失败 %@", "\(error)")
        }
    }
}

private struct WindowSizeRecord: Codable {
    var width: Double
    var height: Double
}
