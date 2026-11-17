import Foundation

/// Where the Worker lives. Read from Info.plist (`FOLEY_PROXY_URL`, fed by Config/Local.xcconfig).
/// Empty means demo-only mode: the bundled scenes play, Build scene explains how to connect a proxy.
nonisolated struct ProxyConfig: Sendable, Equatable {
    let baseURL: URL?

    var isConfigured: Bool { baseURL != nil }

    /// Accepts either a full `https://host` URL or a bare `host`.
    ///
    /// A bare host is the form that actually survives: `Config/Local.xcconfig` feeds this value,
    /// and an xcconfig treats `//` as a comment, so a pasted `https://host` arrives as `https:`.
    init(string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { baseURL = nil; return }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".") else {
            baseURL = nil
            return
        }
        baseURL = url
    }

    static func fromBundle(_ bundle: Bundle = .main) -> ProxyConfig {
        ProxyConfig(string: bundle.object(forInfoDictionaryKey: "FOLEY_PROXY_URL") as? String ?? "")
    }
}
