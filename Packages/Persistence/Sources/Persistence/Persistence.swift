/// Persistence — SwiftData models and the Keychain wrapper.
///
/// Hard rule (spec §6.3.1): secrets (passwords, private keys, passphrases, AI API
/// keys) live ONLY in the Keychain with `ThisDeviceOnly`. They must never appear
/// in SwiftData, logs, or UserDefaults.
public enum PersistenceInfo {
    public static let moduleName = "Persistence"
}
