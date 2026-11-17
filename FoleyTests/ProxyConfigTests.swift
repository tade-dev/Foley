import Testing
import Foundation
@testable import Foley

private final class BundleToken {}

@Suite struct ProxyConfigTests {
    /// Tests the value, not the machine: whether this developer has a proxy configured
    /// locally must not decide whether the suite passes.
    @Test func emptyURLMeansNotConfigured() {
        #expect(!ProxyConfig(string: "").isConfigured)
        #expect(!ProxyConfig(string: "   ").isConfigured)
    }

    @Test func readsTheValueFromTheBundleKey() {
        let bundle = Bundle(for: BundleToken.self)
        _ = ProxyConfig.fromBundle(bundle)   // must not crash when the key is absent
        #expect(!ProxyConfig.fromBundle(bundle).isConfigured)
    }
    @Test func parsesURL() {
        #expect(ProxyConfig(string: "https://foley.example.workers.dev").isConfigured)
        #expect(!ProxyConfig(string: "not a url").isConfigured)
    }

    /// An xcconfig treats "//" as a comment, so a pasted https:// URL arrives truncated and a
    /// bare host is the only form that survives. Both must work.
    @Test func acceptsABareHostBecauseXcconfigEatsDoubleSlashes() {
        let config = ProxyConfig(string: "foley-proxy.example.workers.dev")
        #expect(config.isConfigured)
        #expect(config.baseURL?.scheme == "https")
        #expect(config.baseURL?.host() == "foley-proxy.example.workers.dev")
    }

    @Test func rejectsATruncatedSchemeRatherThanPretendingItWorks() {
        #expect(!ProxyConfig(string: "https:").isConfigured)
        #expect(!ProxyConfig(string: "https://").isConfigured)
    }

    @Test func trailingSlashesDoNotDoubleUpOnPaths() {
        let config = ProxyConfig(string: "https://foley.example.workers.dev/")
        #expect(config.baseURL?.appending(path: "/scene").absoluteString == "https://foley.example.workers.dev/scene")
    }
}
