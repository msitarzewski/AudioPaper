import Foundation
import Security

/// API credentials the providers need. Stored in the Keychain; never written to defaults or disk.
public enum SecretKey: String, CaseIterable, Sendable {
    case braveAPIKey = "BRAVE_API_KEY"
    case deviantArtClientID = "DEVIANTART_CLIENT_ID"
    case deviantArtClientSecret = "DEVIANTART_CLIENT_SECRET"
    case theAudioDBAPIKey = "THEAUDIODB_API_KEY"
    case fanartTVProjectKey = "FAN_ART_API_KEY"
    case fanartTVClientKey = "FAN_ART_CLIENT_KEY"
}

public protocol SecretStore: Sendable {
    func value(for key: SecretKey) -> String?
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    /// Values already read, shared by every store instance so a save in Settings is seen by the providers.
    /// Avoids hitting the Keychain (slow, main-thread-unfriendly) each time a provider checks `isConfigured`.
    private static let memo = Memo()

    private final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String?] = [:]
        func get(_ key: String) -> String?? { lock.withLock { values[key] } }
        func set(_ key: String, _ value: String?) { lock.withLock { values[key] = .some(value) } }
    }

    public init(service: String = "com.audiopaper.credentials") {
        self.service = service
    }

    public func value(for key: SecretKey) -> String? {
        let memoKey = service + "/" + key.rawValue
        if let known = Self.memo.get(memoKey) { return known }
        let value = readKeychain(key)
        Self.memo.set(memoKey, value)
        return value
    }

    private func readKeychain(_ key: SecretKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    /// Saves `value` (or removes the key when nil or empty). Returns whether the Keychain accepted it, so
    /// Settings never says "Saved" for a key that wasn't.
    @discardableResult
    public func set(_ value: String?, for key: SecretKey) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let deleted = SecItemDelete(base as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
            log.error("Keychain delete failed for \(key.rawValue, privacy: .public): \(deleted)")
            return false
        }
        let value = value.flatMap { $0.isEmpty ? nil : $0 }
        guard let value else {
            Self.memo.set(service + "/" + key.rawValue, nil)
            return true
        }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Keychain save failed for \(key.rawValue, privacy: .public): \(status)")
            Self.memo.set(service + "/" + key.rawValue, nil)
            return false
        }
        Self.memo.set(service + "/" + key.rawValue, value)
        return true
    }
}

/// Reads credentials from process environment, then a `.env` file. Used by the `apctl` developer tool.
public struct EnvironmentSecretStore: SecretStore {
    private let values: [String: String]

    public init(dotEnv: URL? = nil) {
        var values = ProcessInfo.processInfo.environment
        if let dotEnv, let text = try? String(contentsOf: dotEnv, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if value.count >= 2, value.first == value.last, value.first == "\"" || value.first == "'" {
                    value = String(value.dropFirst().dropLast())
                }
                if values[key] == nil { values[key] = value }
            }
        }
        self.values = values
    }

    public func value(for key: SecretKey) -> String? {
        values[key.rawValue].flatMap { $0.isEmpty ? nil : $0 }
    }
}
