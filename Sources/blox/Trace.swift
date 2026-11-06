import Foundation

@MainActor
enum Trace {
    static func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["BLOX_TRACE"] != nil else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        let path = "/tmp/blox-trace.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
