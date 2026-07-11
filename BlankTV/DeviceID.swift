// ============================================================
// BLANK TV — DeviceID.swift
// Stable MAC-formatted device identity for activation
// ============================================================

import Foundation
import CryptoKit
import UIKit

/// iOS cannot read the real hardware MAC, so we derive a stable,
/// MAC-formatted identifier and persist it in the Keychain (survives
/// reinstalls). The reseller/owner panel activates this exact string.
enum DeviceIdentity {

    /// Cached, stable ID in the form `AA:BB:CC:DD:EE:FF` (uppercase).
    static var current: String {
        if let saved = Keychain.shared.deviceID, isValid(saved) { return saved }
        let generated = generate()
        Keychain.shared.deviceID = generated
        return generated
    }

    static func isValid(_ id: String) -> Bool {
        id.range(of: "^([0-9A-F]{2}:){5}[0-9A-F]{2}$", options: .regularExpression) != nil
    }

    private static func generate() -> String {
        // Seed from the vendor identifier + bundle id so it is stable per
        // install yet unique per device/app.
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let bundle = Bundle.main.bundleIdentifier ?? "com.blanktv.player"
        let digest = SHA256.hash(data: Data("\(vendor)|\(bundle)".utf8))
        var bytes = Array(digest.prefix(6))

        // Set the locally-administered bit and clear the multicast bit so the
        // result is a valid unicast, locally-administered MAC.
        bytes[0] = (bytes[0] | 0x02) & 0xFE

        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
