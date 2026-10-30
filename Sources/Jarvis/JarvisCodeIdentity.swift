import Foundation
import Security

/// The publisher signs once. Clients only validate; no private keys or
/// re-signing tools are needed on a user's Mac.
enum JarvisCodeIdentity {
    static func validateUpdate(at candidateURL: URL, replacing currentURL: URL) throws {
        let current = try validatedCode(at: currentURL)
        let candidate = try validatedCode(at: candidateURL)
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(current, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(candidate, validationFlags, requirement) == errSecSuccess
        else { throw JarvisUpdateError.incompatibleCodeIdentity }
    }

    private static var validationFlags: SecCSFlags {
        SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
    }

    private static func validatedCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, validationFlags, nil) == errSecSuccess
        else { throw JarvisUpdateError.incompatibleCodeIdentity }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty
        else { throw JarvisUpdateError.incompatibleCodeIdentity }
        return code
    }
}
