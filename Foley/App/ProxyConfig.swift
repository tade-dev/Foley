import Foundation

/// Where the Worker lives. Read from Info.plist (`FOLEY_PROXY_URL`, fed by Config/Local.xcconfig).
/// Empty means demo-only mode: the bundled scenes play, Build scene explains how to connect a proxy.
nonisolated struct ProxyConfig: Sendable, Equatable {
    let baseURL: URL?

    var isConfigured: Bool { baseURL != nil }

    init(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host() != nil {
            baseURL = url
        } else {
            baseURL = nil
        }
    }

    static func fromBundle(_ bundle: Bundle = .main) -> ProxyConfig {
        ProxyConfig(string: bundle.object(forInfoDictionaryKey: "FOLEY_PROXY_URL") as? String ?? "")
    }
}
