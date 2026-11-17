#if DEBUG
import Foundation

/// Scripted interaction sequences for recording demo clips, selected with `-demo <name>`.
/// Debug only: it drives the real UI, it does not replace it.
enum DemoDirector {
    static var name: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "-demo"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func isRunning(_ which: String) -> Bool { name == which }

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
