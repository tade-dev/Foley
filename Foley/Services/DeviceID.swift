import Foundation

/// A stable anonymous id the proxy rate-limits per device. Created once, never leaves the device
/// except as the `X-Device-ID` header.
nonisolated enum DeviceID {
    private static let key = "foley.deviceID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
