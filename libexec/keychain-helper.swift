import Foundation
import Security

// Keychain coordinates — must stay in sync with RecoveryKeychain::KEYCHAIN_SERVICE/ACCOUNT
let SERVICE = "idea-foundry-recovery-passphrase"
let ACCOUNT = "idea-foundry"

// Build a SecAccess that grants access ONLY to this binary, so no other process
// (including the `security` CLI) can read the item without a user dialog.
func makeAccess() -> SecAccess? {
    // nil path → trusted application reference for the current running binary.
    // macOS records the binary's code signature (or hash if unsigned); future
    // invocations of the same binary are granted access without a dialog.
    var trustedApp: SecTrustedApplication?
    guard SecTrustedApplicationCreateFromPath(nil, &trustedApp) == errSecSuccess,
          let app = trustedApp else { return nil }

    var access: SecAccess?
    let list = [app] as CFArray
    guard SecAccessCreate("Idea Foundry Recovery Passphrase" as CFString, list, &access) == errSecSuccess else {
        return nil
    }
    return access
}

// Migration path: items previously stored via `security add-generic-password` have
// the security CLI as their trusted application, not this binary.  The security CLI
// can delete those items; we cannot do so silently.
func legacyCLIDelete() {
    guard let url = URL(string: "file:///usr/bin/security") else { return }
    let task = Process()
    task.executableURL = url
    task.arguments = ["delete-generic-password", "-a", ACCOUNT, "-s", SERVICE]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}

func store(payload: Data) -> Bool {
    let delQuery: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: SERVICE,
        kSecAttrAccount: ACCOUNT
    ]
    let delStatus = SecItemDelete(delQuery as CFDictionary)

    // If delete failed for any reason other than "item didn't exist", the old item
    // may have been created by the security CLI.  Try the CLI as a migration step.
    if delStatus != errSecSuccess && delStatus != errSecItemNotFound {
        legacyCLIDelete()
    }

    guard let access = makeAccess() else {
        fputs("keychain-helper: failed to create SecAccess\n", stderr)
        return false
    }

    let addQuery: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: SERVICE,
        kSecAttrAccount: ACCOUNT,
        kSecValueData:   payload,
        kSecAttrAccess:  access     // restrict to this binary only
    ]
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus != errSecSuccess {
        fputs("keychain-helper: SecItemAdd failed (\(addStatus))\n", stderr)
        return false
    }
    return true
}

func retrieve() -> Data? {
    let query: [CFString: Any] = [
        kSecClass:        kSecClassGenericPassword,
        kSecAttrService:  SERVICE,
        kSecAttrAccount:  ACCOUNT,
        kSecReturnData:   true,
        kSecMatchLimit:   kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return data
}

func deleteItem() {
    let query: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: SERVICE,
        kSecAttrAccount: ACCOUNT
    ]
    SecItemDelete(query as CFDictionary)
}

// ── Entry point ──────────────────────────────────────────────────────────────

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: keychain-helper <store|retrieve|delete>\n", stderr)
    exit(1)
}

switch args[1] {
case "store":
    let payload = FileHandle.standardInput.readDataToEndOfFile()
    guard !payload.isEmpty else {
        fputs("keychain-helper: no data on stdin\n", stderr)
        exit(1)
    }
    exit(store(payload: payload) ? 0 : 1)

case "retrieve":
    if let data = retrieve() {
        FileHandle.standardOutput.write(data)
        exit(0)
    } else {
        exit(1) // not found — not an error, caller handles nil
    }

case "delete":
    deleteItem()
    exit(0)

default:
    fputs("keychain-helper: unknown command '\(args[1])'\n", stderr)
    exit(1)
}
