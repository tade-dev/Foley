import Testing
import Foundation
@testable import Foley

@Suite struct ProxyConfigTests {
    @Test func emptyURLMeansNotConfigured() { #expect(!ProxyConfig.fromBundle(.main).isConfigured) }
    @Test func parsesURL() {
        #expect(ProxyConfig(string: "https://foley.example.workers.dev").isConfigured)
        #expect(!ProxyConfig(string: "not a url").isConfigured)
    }
}
