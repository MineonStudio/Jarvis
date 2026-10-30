import Foundation
@testable import Jarvis
import XCTest

final class JarvisCodeIdentityTests: XCTestCase {
    private var directory: URL!
    private var keychain: URL!
    private let password = UUID().uuidString

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        keychain = directory.appendingPathComponent("test.keychain-db")
        try run("/usr/bin/security", ["create-keychain", "-p", password, keychain.path])
        try run("/usr/bin/security", ["unlock-keychain", "-p", password, keychain.path])
        for name in ["Publisher A", "Publisher B"] {
            let key = directory.appendingPathComponent("\(name).key")
            let cert = directory.appendingPathComponent("\(name).pem")
            try run("/usr/bin/openssl", [
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
                "-keyout", key.path, "-out", cert.path, "-subj", "/CN=\(name)",
                "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=critical,codeSigning"
            ])
            try run("/usr/bin/security", ["import", cert.path, "-k", keychain.path, "-T", "/usr/bin/codesign"])
            try run("/usr/bin/security", ["import", key.path, "-k", keychain.path, "-T", "/usr/bin/codesign"])
        }
        // Only this disposable keychain is modified. Explicitly authorize
        // Apple signing tools so CI never leaves an interactive test prompt.
        try run("/usr/bin/security", [
            "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain.path
        ])
    }

    override func tearDownWithError() throws {
        if let keychain {
            try run("/usr/bin/security", ["delete-keychain", keychain.path])
        }
        if let directory {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testDifferentBinariesFromSamePublisherKeepCodeIdentity() throws {
        let current = try app(named: "Current", executable: "/usr/bin/true")
        let update = try app(named: "Update", executable: "/usr/bin/false")
        XCTAssertNoThrow(try JarvisCodeIdentity.validateUpdate(at: update, replacing: current))
    }

    func testDifferentSelfSignedPublisherIsRejectedDespiteBothHavingNoTeamID() throws {
        let current = try app(named: "Current")
        let update = try app(named: "Update", signer: "Publisher B")
        XCTAssertThrowsError(try JarvisCodeIdentity.validateUpdate(at: update, replacing: current))
    }

    func testAdHocSignatureCannotReplaceOrEstablishPublisherIdentity() throws {
        let signed = try app(named: "Signed")
        let adHoc = try app(named: "AdHoc", signer: "-")
        XCTAssertThrowsError(try JarvisCodeIdentity.validateUpdate(at: adHoc, replacing: signed))
        XCTAssertThrowsError(try JarvisCodeIdentity.validateUpdate(at: signed, replacing: adHoc))
    }

    func testTamperedSignedResourcesAreRejected() throws {
        let current = try app(named: "Current")
        let update = try app(named: "Update")
        try Data("tampered".utf8).write(to: update.appendingPathComponent("Contents/Resources/sealed.txt"))
        XCTAssertThrowsError(try JarvisCodeIdentity.validateUpdate(at: update, replacing: current))
    }

    func testDifferentBundleIdentifierIsRejected() throws {
        let current = try app(named: "Current")
        let update = try app(named: "Update", identifier: "com.jarvis.mac.dev")
        XCTAssertThrowsError(try JarvisCodeIdentity.validateUpdate(at: update, replacing: current))
    }

    private func app(
        named name: String,
        signer: String = "Publisher A",
        identifier: String = "com.jarvis.mac",
        executable: String = "/usr/bin/true"
    ) throws -> URL {
        let app = directory.appendingPathComponent("\(name).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: executable, toPath: app.appendingPathComponent("Contents/MacOS/Jarvis").path)
        let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Jarvis", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("original".utf8).write(to: app.appendingPathComponent("Contents/Resources/sealed.txt"))
        try run("/usr/bin/codesign", ["--force", "--timestamp=none", "--keychain", keychain.path, "--sign", signer, app.path])
        return app
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(data: output, encoding: .utf8) ?? "Invalid tool output")
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}
