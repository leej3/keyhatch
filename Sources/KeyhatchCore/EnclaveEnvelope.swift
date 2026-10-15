// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum EnvelopeError: Error {
    case secureEnclaveUnavailable, accessControlUnavailable, unsupportedVersion, malformed
}

/// Persist only inside the signed broker's private container, never in the repo.
/// keyReference is Secure Enclave's wrapped representation, NOT an exported key.
public struct EnclaveEnvelope: Codable {
    public let version: Int
    public let keyReference: Data
    public let ephemeralPublicKey: Data
    public let salt: Data
    public let wrappedKey: Data
    public let ciphertext: Data
}

/// Hardware-only wrapping: there is intentionally no software fallback.
/// AES and plaintext necessarily operate in application memory, not the enclave.
public enum EnclaveVault {
    // Preserve the prototype's cryptographic domain across the product rename.
    private static let context = Data("Handrail/envelope/v1".utf8)

    private static func wrappingKey(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                      sharedInfo: context, outputByteCount: 32)
    }

    public static func seal(_ plaintext: Data) throws -> EnclaveEnvelope {
        guard SecureEnclave.isAvailable else { throw EnvelopeError.secureEnclaveUnavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &error
        ) else { throw EnvelopeError.accessControlUnavailable }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: key.publicKey)
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let dataKey = SymmetricKey(size: .bits256)
        let bytes = dataKey.withUnsafeBytes { Data($0) }
        let wrapped = try AES.GCM.seal(bytes, using: wrappingKey(shared, salt: salt),
                                       authenticating: context)
        let sealed = try AES.GCM.seal(plaintext, using: dataKey, authenticating: context)
        guard let wrappedBytes = wrapped.combined, let sealedBytes = sealed.combined else {
            throw EnvelopeError.malformed
        }
        return EnclaveEnvelope(version: 1, keyReference: key.dataRepresentation,
                               ephemeralPublicKey: ephemeral.publicKey.x963Representation,
                               salt: salt, wrappedKey: wrappedBytes, ciphertext: sealedBytes)
    }

    /// Only the broker's user-initiated unlock flow should call this method.
    /// No retry on cancellation. Biometric enrollment changes invalidate access.
    public static func open(_ envelope: EnclaveEnvelope) throws -> Data {
        try decrypt(envelope, using: unlockKey(envelope))
    }

    /// Session key stays in native process memory until lock/expiry. Not enclave RAM.
    public static func unlockKey(_ envelope: EnclaveEnvelope) throws -> SymmetricKey {
        guard envelope.version == 1 else { throw EnvelopeError.unsupportedVersion }
        guard SecureEnclave.isAvailable else { throw EnvelopeError.secureEnclaveUnavailable }
        guard envelope.salt.count == 32, envelope.ephemeralPublicKey.count == 65 else {
            throw EnvelopeError.malformed
        }
        let authentication = LAContext()
        authentication.localizedReason = "Unlock Keyhatch’s credential cache"
        authentication.localizedFallbackTitle = ""
        authentication.touchIDAuthenticationAllowableReuseDuration = 0
        defer { authentication.invalidate() }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: envelope.keyReference, authenticationContext: authentication)
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralPublicKey)
        let shared = try key.sharedSecretFromKeyAgreement(with: peer)
        let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.wrappedKey),
                                     using: wrappingKey(shared, salt: envelope.salt),
                                     authenticating: context)
        guard bytes.count == 32 else { throw EnvelopeError.malformed }
        return SymmetricKey(data: bytes)
    }

    public static func decrypt(_ envelope: EnclaveEnvelope, using key: SymmetricKey) throws -> Data {
        guard envelope.version == 1 else { throw EnvelopeError.unsupportedVersion }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext),
                                using: key, authenticating: context)
    }

    public static func replacingPayload(_ envelope: EnclaveEnvelope, plaintext: Data,
                                        using key: SymmetricKey) throws -> EnclaveEnvelope {
        guard envelope.version == 1 else { throw EnvelopeError.unsupportedVersion }
        guard let ciphertext = try AES.GCM.seal(plaintext, using: key,
                                               authenticating: context).combined else {
            throw EnvelopeError.malformed
        }
        return EnclaveEnvelope(version: envelope.version, keyReference: envelope.keyReference,
            ephemeralPublicKey: envelope.ephemeralPublicKey, salt: envelope.salt,
            wrappedKey: envelope.wrappedKey, ciphertext: ciphertext)
    }
}
