import XCTest
@testable import MNGCore

final class VaultKeyTests: XCTestCase {
    private func unlocked(_ fixture: VaultFixture, password: String? = nil) throws -> VaultKey {
        try VaultKey.unlock(
            uid: fixture.uid,
            password: password ?? fixture.password,
            saltBase64: fixture.saltBase64,
            iterations: fixture.iterations
        )
    }

    private func decodeBase64(_ value: String) throws -> [UInt8] {
        let data = try XCTUnwrap(Data(base64Encoded: value))
        return [UInt8](data)
    }

    func testBrowserVectorDecrypts() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture)

        XCTAssertNoThrow(try key.verify(uid: fixture.uid, verifierBase64: fixture.verifierBase64))

        let manifest = try key.decryptManifest(
            uid: fixture.uid,
            data: try decodeBase64(fixture.manifestBase64)
        )
        let manifestJSON = try XCTUnwrap(fixture.manifestJSON.data(using: .utf8))
        let expected = try JSONDecoder().decode(VaultManifest.self, from: manifestJSON)

        XCTAssertEqual(manifest, expected)
        XCTAssertEqual(manifest.uid, fixture.uid)
        XCTAssertEqual(manifest.name, "Kho thử nghiệm")
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.folders.count, 1)
        XCTAssertEqual(manifest.folders[0].name, "Album")
        XCTAssertNil(manifest.folders[0].parent)
        XCTAssertEqual(manifest.files.count, 1)
        XCTAssertEqual(manifest.files[0].name, "ghi chú.txt")
        XCTAssertEqual(manifest.files[0].mime, "text/plain")
        XCTAssertEqual(manifest.files[0].remote, "")
        XCTAssertEqual(manifest.files[0].fileID, "")
        XCTAssertEqual(
            manifest.files[0].chunks[0].id,
            "11111111111111111111111111111111"
        )

        let chunk = try key.decrypt(
            aad: fixture.chunkAAD,
            data: try decodeBase64(fixture.chunkBase64)
        )
        XCTAssertEqual(
            String(decoding: chunk.copyBytes(), as: UTF8.self),
            fixture.chunkPlain
        )

        let thumb = try key.decrypt(
            aad: fixture.thumbAAD,
            data: try decodeBase64(fixture.thumbBase64)
        )
        XCTAssertEqual(
            String(decoding: thumb.copyBytes(), as: UTF8.self),
            fixture.thumbPlain
        )
    }

    func testManifestEncryptRoundTrips() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture)
        let manifest = try key.decryptManifest(
            uid: fixture.uid,
            data: try decodeBase64(fixture.manifestBase64)
        )

        let nonce = [UInt8](repeating: 9, count: VaultKey.nonceBytes)
        let blob = try key.encryptManifest(
            uid: fixture.uid,
            nonce: nonce,
            manifest: manifest
        )

        XCTAssertEqual(Array(blob.prefix(VaultKey.nonceBytes)), nonce)
        XCTAssertEqual(
            try key.decryptManifest(uid: fixture.uid, data: blob),
            manifest
        )
    }

    func testDecomposedPasswordIsNormalized() throws {
        let fixture = try TestFixtures.vault()
        let decomposed = fixture.password.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(decomposed, fixture.password)

        let key = try unlocked(fixture, password: decomposed)
        XCTAssertNoThrow(try key.verify(uid: fixture.uid, verifierBase64: fixture.verifierBase64))
    }

    func testWrongPasswordIsRejected() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture, password: "not the fixture password")

        XCTAssertThrowsError(
            try key.verify(uid: fixture.uid, verifierBase64: fixture.verifierBase64)
        ) { error in
            XCTAssertEqual(error as? MNGError, .wrongPassword)
        }
    }

    func testTamperedAndMisboundCiphertextIsRejected() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture)

        var manifest = try decodeBase64(fixture.manifestBase64)
        manifest[manifest.count - 1] ^= 0xFF
        XCTAssertThrowsError(try key.decryptManifest(uid: fixture.uid, data: manifest))

        let otherUID = "fedcba9876543210fedcba9876543210"
        XCTAssertThrowsError(
            try key.decryptManifest(uid: otherUID, data: try decodeBase64(fixture.manifestBase64))
        )

        var chunk = try decodeBase64(fixture.chunkBase64)
        chunk[0] ^= 0xFF
        XCTAssertThrowsError(try key.decrypt(aad: fixture.chunkAAD, data: chunk))
    }

    func testInvalidMetadataIsRejected() throws {
        let fixture = try TestFixtures.vault()
        let shortSalt = Data(repeating: 0, count: 15).base64EncodedString()
        let longSalt = Data(repeating: 0, count: 65).base64EncodedString()

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: "", password: fixture.password, saltBase64: fixture.saltBase64, iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("uid")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", password: fixture.password, saltBase64: fixture.saltBase64, iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("uid")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: "", saltBase64: fixture.saltBase64, iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("password")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: fixture.password, saltBase64: "not base64!", iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("salt")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: fixture.password, saltBase64: shortSalt, iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("salt")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: fixture.password, saltBase64: longSalt, iterations: fixture.iterations)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("salt")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: fixture.password, saltBase64: fixture.saltBase64, iterations: 0)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("iterations")) }

        XCTAssertThrowsError(
            try VaultKey.unlock(uid: fixture.uid, password: fixture.password, saltBase64: fixture.saltBase64, iterations: 2_000_001)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("iterations")) }
    }

    func testBlobLayoutAndLimits() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture)
        let nonce = [UInt8](repeating: 7, count: VaultKey.nonceBytes)
        let plaintext = Array("plaintext chunk".utf8)

        let blob = try key.encrypt(aad: fixture.chunkAAD, nonce: nonce, plaintext: plaintext)
        XCTAssertEqual(Array(blob.prefix(VaultKey.nonceBytes)), nonce)
        XCTAssertEqual(blob.count, VaultKey.nonceBytes + plaintext.count + 16)
        XCTAssertEqual(
            try key.decrypt(aad: fixture.chunkAAD, data: blob).copyBytes(),
            plaintext
        )

        let otherAAD = VaultKey.chunkAAD(uid: fixture.uid, fileID: "other-file", index: 0, total: 1)
        XCTAssertThrowsError(try key.decrypt(aad: otherAAD, data: blob))

        XCTAssertThrowsError(
            try key.encrypt(aad: fixture.chunkAAD, nonce: [0], plaintext: plaintext)
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("nonce")) }

        // Rust rejects blobs shorter than nonce + tag + one plaintext byte.
        XCTAssertThrowsError(
            try key.decrypt(aad: fixture.chunkAAD, data: [UInt8](repeating: 0, count: 28))
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("ciphertext")) }

        // Empty plaintext produces a 28-byte blob, which the reader rejects by
        // design (mirrors the Rust minimum-length check).
        let emptyBlob = try key.encrypt(aad: fixture.chunkAAD, nonce: nonce, plaintext: [])
        XCTAssertEqual(emptyBlob.count, 28)
        XCTAssertThrowsError(try key.decrypt(aad: fixture.chunkAAD, data: emptyBlob))
    }

    func testManifestUIDMustMatch() throws {
        let fixture = try TestFixtures.vault()
        let key = try unlocked(fixture)
        let manifest = VaultManifest(uid: fixture.uid, name: "x")

        XCTAssertThrowsError(
            try key.encryptManifest(
                uid: "fedcba9876543210fedcba9876543210",
                nonce: VaultKey.randomNonce(),
                manifest: manifest
            )
        ) { XCTAssertEqual($0 as? MNGError, .invalidVault("manifest uid")) }
    }

    func testAADStringsMatchRust() throws {
        let fixture = try TestFixtures.vault()

        XCTAssertEqual(
            VaultKey.manifestAAD(uid: fixture.uid),
            "mng-vault/v1/\(fixture.uid)/manifest"
        )
        XCTAssertEqual(
            VaultKey.verifierAAD(uid: fixture.uid),
            "mng-vault/v1/\(fixture.uid)/verifier"
        )
        XCTAssertEqual(
            VaultKey.chunkAAD(
                uid: fixture.uid,
                fileID: "aabbccddeeff00112233445566778899",
                index: 0,
                total: 1
            ),
            fixture.chunkAAD
        )
        XCTAssertEqual(
            VaultKey.thumbAAD(
                uid: fixture.uid,
                fileID: "aabbccddeeff00112233445566778899"
            ),
            fixture.thumbAAD
        )
        XCTAssertEqual(
            VaultKey.verifierText(uid: fixture.uid),
            "mng-vault-verifier/v1/\(fixture.uid)"
        )
        XCTAssertEqual(VaultKey.randomNonce().count, VaultKey.nonceBytes)
    }

    func testSanitizeManifestDropsUnnamedEntries() {
        var manifest = VaultManifest(
            version: 1,
            uid: "0123456789abcdef0123456789abcdef",
            folders: [
                VaultFolder(id: "", name: "missing id"),
                VaultFolder(id: "f1", name: ""),
                VaultFolder(id: "f2", name: "Album")
            ],
            files: [
                VaultFile(id: "", name: "missing id"),
                VaultFile(id: "a", name: ""),
                VaultFile(id: "b", name: "ok.txt")
            ]
        )

        sanitizeManifest(&manifest)

        XCTAssertEqual(manifest.folders.map(\.id), ["f2"])
        XCTAssertEqual(manifest.files.map(\.id), ["b"])
    }
}
