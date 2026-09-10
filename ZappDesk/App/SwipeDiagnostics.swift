import Foundation

/// Opt-in diagnostics contain gesture fields and switching outcomes, never key events.
enum SwipeDiagnostics {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--trace-swipes")
    private static let queue = DispatchQueue(label: "ZappDesk.swipeDiagnostics")
    private static let file: FileHandle? = {
        guard enabled else { return nil }
        let url = URL(fileURLWithPath: "/tmp/ZappDesk-swipe-trace.log")
        try? Data().write(to: url, options: .atomic)
        return try? FileHandle(forWritingTo: url)
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let data = Data("\(Date().timeIntervalSince1970) \(message())\n".utf8)
        queue.async { try? file?.write(contentsOf: data) }
    }
}
