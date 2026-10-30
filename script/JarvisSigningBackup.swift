// Build-machine utility: encrypted backup of both code identities and the
// existing Ed25519 update key. No secret is printed or passed on a command line.
import CommonCrypto
import CryptoKit
import Darwin
import Foundation
import Security

private struct BackupPayload: Codable {
    let releasePKCS12: Data
    let developmentPKCS12: Data
    let updateKey: Data
}

private struct EncryptedBackup: Codable {
    let format: Int
    let salt: Data
    let sealed: Data
}

private enum SigningBackup {
    static let service = "com.jarvis.mac.update-signing.v1"
    static let account = "release-ed25519"
    static let root = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()

    static func fail(_ message: String) -> NSError {
        NSError(domain: "JarvisSigningBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Security error \(status)"])
        }
    }

    static func password() throws -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        defer { _ = buffer.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard readpassphrase("Backup password: ", &buffer, buffer.count, RPP_REQUIRE_TTY) != nil else {
            throw fail("Run this command in an interactive terminal.")
        }
        return String(cString: buffer)
    }

    static func encryptionKey(password: String, salt: Data) throws -> SymmetricKey {
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes,
                        password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        600_000,
                        out.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw fail("Password derivation failed.") }
        return SymmetricKey(data: output)
    }

    static func identity(named name: String) throws -> SecIdentity {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        let matches = (result as? [SecIdentity] ?? []).filter { identity in
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return false }
            return SecCertificateCopySubjectSummary(certificate) as String? == name
        }
        guard matches.count == 1, let identity = matches.first else { throw fail("Missing or ambiguous identity: \(name)") }
        return identity
    }

    static func exportIdentity(_ name: String, password: String) throws -> Data {
        let identity = try identity(named: name)
        let passphrase = password as CFString
        var parameters = SecItemImportExportKeyParameters()
        parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        parameters.passphrase = Unmanaged.passUnretained(passphrase)
        var data: CFData?
        try check(SecItemExport(identity, .formatPKCS12, [], &parameters, &data))
        guard let data else { throw fail("Could not export \(name)") }
        return data as Data
    }

    static func updateKey() throws -> Data {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let key = result as? Data else { throw fail("Update key is missing.") }
        return key
    }

    static func importedIdentity(_ data: Data, password: String) throws -> SecIdentity {
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password, kSecImportToMemoryOnly as String: true]
        try check(SecPKCS12Import(data as CFData, options as CFDictionary, &items))
        guard let dictionaries = items as? [[String: Any]], dictionaries.count == 1,
              let value = dictionaries.first?[kSecImportItemIdentity as String]
        else { throw fail("Invalid identity backup.") }
        return value as! SecIdentity
    }

    static func validate(_ payload: BackupPayload, password: String) throws {
        let publicPEM = try String(contentsOf: root.appendingPathComponent("Resources/JarvisReleaseSigning.pem"), encoding: .utf8)
        let base64 = publicPEM.split(separator: "\n").filter { !$0.hasPrefix("---") }.joined()
        guard let pinned = Data(base64Encoded: base64) else { throw fail("Missing pinned release certificate.") }
        let release = try importedIdentity(payload.releasePKCS12, password: password)
        var certificate: SecCertificate?
        try check(SecIdentityCopyCertificate(release, &certificate))
        guard let certificate, SecCertificateCopyData(certificate) as Data == pinned else {
            throw fail("Backup release identity differs from the pinned certificate.")
        }
        let dev = try importedIdentity(payload.developmentPKCS12, password: password)
        var devCertificate: SecCertificate?
        try check(SecIdentityCopyCertificate(dev, &devCertificate))
        guard let devCertificate, SecCertificateCopySubjectSummary(devCertificate) as String? == "Jarvis Dev Signing" else {
            throw fail("Invalid development identity.")
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: payload.updateKey)
        let info = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
        guard let expected = plist?["JarvisUpdatePublicKey"] as? String,
              expected == key.publicKey.rawRepresentation.base64EncodedString()
        else { throw fail("Backup update key differs from the embedded public key.") }
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2, ["export", "verify", "restore"].contains(args[0]) else {
            throw fail("Usage: swift script/JarvisSigningBackup.swift export|verify|restore <encrypted-file>")
        }
        let url = URL(fileURLWithPath: args[1])
        let password = try password()
        if args[0] == "export" {
            guard try Self.password() == password else { throw fail("Passwords do not match.") }
            guard password.count >= 12 else { throw fail("Use a password of at least 12 characters.") }
            guard !FileManager.default.fileExists(atPath: url.path) else { throw fail("Backup already exists; refusing to overwrite.") }
            let payload = try BackupPayload(
                releasePKCS12: exportIdentity("Jarvis Release Signing", password: password),
                developmentPKCS12: exportIdentity("Jarvis Dev Signing", password: password),
                updateKey: updateKey()
            )
            try validate(payload, password: password)
            var salt = Data(count: 32)
            let randomStatus = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            try check(randomStatus)
            let key = try encryptionKey(password: password, salt: salt)
            let sealed = try AES.GCM.seal(JSONEncoder().encode(payload), using: key)
            guard let combined = sealed.combined else { throw fail("Encryption failed.") }
            let data = try JSONEncoder().encode(EncryptedBackup(format: 1, salt: salt, sealed: combined))
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw fail("Cannot create backup.")
            }
            try data.write(to: url)
            print("Encrypted backup created and key identities verified. Store it offline; keep its password separately.")
            return
        }
        let archive = try JSONDecoder().decode(EncryptedBackup.self, from: Data(contentsOf: url))
        guard archive.format == 1, archive.salt.count == 32 else { throw fail("Unsupported backup format.") }
        let key = try encryptionKey(password: password, salt: archive.salt)
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: archive.sealed), using: key)
        let payload = try JSONDecoder().decode(BackupPayload.self, from: plain)
        try validate(payload, password: password)
        if args[0] == "verify" {
            print("Backup verified: release identity, development identity, and update key."); return
        }
        // Check any existing update key before changing the keychain.
        do {
            let existing = try updateKey()
            guard existing == payload.updateKey else { throw fail("Existing update key differs; refusing to replace it.") }
        } catch let error as NSError {
            guard error.domain == NSOSStatusErrorDomain, error.code == Int(errSecItemNotFound) else { throw error }
        }
        var keychain: SecKeychain?
        try check(SecKeychainOpen(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db").path, &keychain))
        guard let keychain else { throw fail("Cannot open login keychain.") }
        for data in [payload.releasePKCS12, payload.developmentPKCS12] {
            let options: [String: Any] = [kSecImportExportPassphrase as String: password, kSecImportExportKeychain as String: keychain]
            var items: CFArray?
            let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
            guard status == errSecSuccess || status == errSecDuplicateItem else { try check(status); return }
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload.updateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { try check(status); return }
        print("Keys restored. Run setup_signing.sh checks and sign two test builds before publishing.")
    }
}

do { try SigningBackup.main() }
catch { fputs("Signing backup: \(error.localizedDescription)\n", stderr); exit(1) }
