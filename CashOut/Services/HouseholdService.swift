import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "HouseholdService")

/// Manages the household pairing state between two devices.
///
/// **Architecture:** replaces the prior CKShare-based pairing (which was abandoned due to
/// iOS universal-link routing fragility). Two devices pair by sharing an 8-character
/// Crockford Base32 code. Each device stores the code locally; records written to the
/// CloudKit public database carry this code as a `householdCode` field, and each device
/// subscribes via `CKQuerySubscription` to records matching its own code.
///
/// **Privacy:** the public CloudKit database is scoped to the app container
/// `iCloud.com.wagneraz.CashOut` — only CashOut binaries signed by this developer can
/// query it. The 8-character code (~1.1 trillion combinations, Crockford Base32
/// eliminates confusable glyphs) is the sole per-household discriminator; brute-forcing
/// is infeasible under CloudKit rate limits.
@MainActor
@Observable
final class HouseholdService: HouseholdServiceProtocol {
    static let shared = HouseholdService()

    /// Current household code, or nil if unpaired. Stored in UserDefaults.
    private(set) var householdCode: String?

    /// Display name shown to the partner on each expense attribution. Defaults to empty
    /// string — the unpaired pairing UI prompts the user to enter their name before
    /// pair/create is allowed. Falling back to `UIDevice.current.name` was unreliable
    /// on iOS 16+ without the user-assigned-device-name entitlement, where the API
    /// returns a generic "iPhone" string that would silently break partner attribution.
    var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: Self.displayNameKey)
            logger.info("displayName set")
        }
    }

    private static let householdCodeKey = "CashOut.householdCode"
    private static let displayNameKey = "CashOut.householdDisplayName"

    /// Crockford Base32 alphabet — removes confusable glyphs (0/O, 1/I/L) and U.
    private static let alphabet: [Character] = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    /// True iff a household code is stored locally. Does NOT validate against CloudKit.
    var isPaired: Bool {
        householdCode != nil && !(householdCode?.isEmpty ?? true)
    }

    init() {
        householdCode = UserDefaults.standard.string(forKey: Self.householdCodeKey)
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey) ?? ""
        logger.debug("HouseholdService.init — isPaired=\(self.isPaired)")
    }

    /// Generates a fresh 8-character code from the Crockford Base32 alphabet, stores it
    /// locally, and returns it. Overwrites any existing code.
    @discardableResult
    func generateCode() -> String {
        let code = String((0..<8).map { _ in Self.alphabet.randomElement()! })
        householdCode = code
        UserDefaults.standard.set(code, forKey: Self.householdCodeKey)
        logger.info("generateCode: new code generated")
        return code
    }

    /// Stores a partner-provided code after validating format (8 chars from alphabet).
    /// Returns false if the code is malformed.
    @discardableResult
    func pair(code: String) -> Bool {
        let normalized = code.uppercased().filter { Self.alphabet.contains($0) }
        guard normalized.count == 8 else {
            logger.warning("pair: rejected malformed code — length=\(normalized.count)")
            return false
        }
        householdCode = normalized
        UserDefaults.standard.set(normalized, forKey: Self.householdCodeKey)
        logger.info("pair: stored code")
        return true
    }

    /// Clears the household code. Records stay on CloudKit until manually purged, but
    /// this device will no longer sync with that household.
    func unpair() {
        householdCode = nil
        UserDefaults.standard.removeObject(forKey: Self.householdCodeKey)
        logger.info("unpair: code cleared")
    }

    /// Formats a code for display with a hyphen in the middle: `KXCW7PQM` → `KXCW-7PQM`.
    static func formatted(_ code: String) -> String {
        guard code.count == 8 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 4)
        return "\(code[..<mid])-\(code[mid...])"
    }
}
