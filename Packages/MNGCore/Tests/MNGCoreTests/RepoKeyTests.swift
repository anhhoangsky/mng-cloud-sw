import XCTest
@testable import MNGCore

final class RepoKeyTests: XCTestCase {
    private func unlockV2(_ fixture: E2EEFixture) throws -> RepoKey {
        try RepoKey.unlock(
            encVersion: 2,
            repoID: fixture.repoID,
            password: fixture.password,
            magicHex: fixture.magicHex,
            randomKeyHex: fixture.randomKeyHex,
            saltHex: ""
        )
    }

    func testBrowserVectorV2Matches() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)

        XCTAssertEqual(
            repo.contentKeyBytesForTesting,
            try Hex.decode(fixture.contentKeyHex)
        )
        XCTAssertEqual(
            repo.contentIVBytesForTesting,
            try Hex.decode(fixture.contentIVHex)
        )

        let plaintext = try Hex.decode(fixture.plainHex)
        let expectedCiphertext = try Hex.decode(fixture.cipherHex)
        let ciphertext = try repo.encryptBlock(plaintext)

        XCTAssertEqual(ciphertext, expectedCiphertext)
        XCTAssertEqual(RepoKey.blockID(ciphertext: ciphertext), fixture.blockID)
        XCTAssertEqual(try repo.decryptBlock(expectedCiphertext), plaintext)
    }

    func testEmptyBlockMatchesBrowser() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)

        let ciphertext = try repo.encryptBlock([])
        XCTAssertEqual(Hex.encode(ciphertext), fixture.emptyCipherHex)
        XCTAssertEqual(RepoKey.blockID(ciphertext: ciphertext), fixture.emptyBlockID)
        XCTAssertEqual(try repo.decryptBlock(ciphertext), [])
    }

    func testBrowserVectorV3Matches() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try RepoKey.unlock(
            encVersion: 3,
            repoID: fixture.repoID,
            password: fixture.password,
            magicHex: fixture.v3.magicHex,
            randomKeyHex: fixture.v3.randomKeyHex,
            saltHex: fixture.saltV3Hex
        )

        XCTAssertEqual(
            repo.contentKeyBytesForTesting,
            try Hex.decode(fixture.v3.contentKeyHex)
        )
        XCTAssertEqual(
            repo.contentIVBytesForTesting,
            try Hex.decode(fixture.v3.contentIVHex)
        )

        let plaintext = try Hex.decode(fixture.plainHex)
        let expectedCiphertext = try Hex.decode(fixture.v3.cipherHex)
        let ciphertext = try repo.encryptBlock(plaintext)

        XCTAssertEqual(ciphertext, expectedCiphertext)
        XCTAssertEqual(RepoKey.blockID(ciphertext: ciphertext), fixture.v3.blockID)
        XCTAssertEqual(try repo.decryptBlock(expectedCiphertext), plaintext)
    }

    func testWrongPasswordIsRejected() throws {
        let fixture = try TestFixtures.e2ee()
        let tamperedMagic = "00" + String(fixture.magicHex.dropFirst(2))

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 2,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: tamperedMagic,
                randomKeyHex: fixture.randomKeyHex,
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .wrongPassword)
        }
    }

    func testInvalidPaddingIsRejected() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)

        // A full 16-byte block has no room for PKCS#7 padding. Encrypting it
        // produces two blocks; decrypting only the first one yields the raw
        // 16 bytes, whose final 'F' is not a valid padding byte. This makes
        // the rejection deterministic instead of relying on a lucky bit flip.
        let block = Array("0123456789ABCDEF".utf8)
        let ciphertext = try repo.encryptBlock(block)
        let firstBlock = Array(ciphertext.prefix(16))

        XCTAssertThrowsError(try repo.decryptBlock(firstBlock)) { error in
            XCTAssertEqual(error as? MNGError, .invalidCiphertext)
        }
    }

    func testTamperingChangesBlockID() throws {
        let fixture = try TestFixtures.e2ee()
        var ciphertext = try Hex.decode(fixture.cipherHex)
        let before = RepoKey.blockID(ciphertext: ciphertext)

        ciphertext[0] ^= 0xFF

        XCTAssertNotEqual(RepoKey.blockID(ciphertext: ciphertext), before)
    }

    func testInvalidParametersAreRejected() throws {
        let fixture = try TestFixtures.e2ee()

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 4,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: fixture.magicHex,
                randomKeyHex: fixture.randomKeyHex,
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .unsupportedVersion(4))
        }

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 3,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: fixture.magicHex,
                randomKeyHex: fixture.randomKeyHex,
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidSalt)
        }

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 2,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: "zz",
                randomKeyHex: fixture.randomKeyHex,
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidHex("magic"))
        }

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 2,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: fixture.magicHex,
                randomKeyHex: "zz",
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidHex("random_key"))
        }

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 2,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: fixture.magicHex,
                randomKeyHex: "",
                saltHex: ""
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidLibraryKey)
        }
    }

    func testRoundTripsManyLengths() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)

        for length in [0, 1, 15, 16, 17, 255, 4_096, 65_537] {
            let plaintext = (0..<length).map { index in
                UInt8(truncatingIfNeeded: index * 31 + 7)
            }
            let ciphertext = try repo.encryptBlock(plaintext)

            XCTAssertEqual(ciphertext.count, RepoKey.ciphertextLen(length))
            XCTAssertEqual(try repo.decryptBlock(ciphertext), plaintext)
        }
    }

    func testCiphertextLengthMatchesRust() {
        XCTAssertEqual(RepoKey.ciphertextLen(0), 16)
        XCTAssertEqual(RepoKey.ciphertextLen(1), 16)
        XCTAssertEqual(RepoKey.ciphertextLen(15), 16)
        XCTAssertEqual(RepoKey.ciphertextLen(16), 32)
        XCTAssertEqual(RepoKey.ciphertextLen(17), 32)
        XCTAssertEqual(RepoKey.ciphertextLen(RepoKey.blockBytes), RepoKey.blockBytes + 16)
    }

    func testOversizedBlockIsRejected() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)
        let oversized = [UInt8](repeating: 0, count: RepoKey.blockBytes + 1)

        XCTAssertThrowsError(try repo.encryptBlock(oversized)) { error in
            XCTAssertEqual(
                error as? MNGError,
                .blockTooLarge(RepoKey.blockBytes + 1)
            )
        }
    }

    func testMalformedCiphertextIsRejected() throws {
        let fixture = try TestFixtures.e2ee()
        let repo = try unlockV2(fixture)

        XCTAssertThrowsError(try repo.decryptBlock([])) { error in
            XCTAssertEqual(error as? MNGError, .invalidCiphertext)
        }

        XCTAssertThrowsError(
            try repo.decryptBlock([UInt8](repeating: 0, count: 15))
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidCiphertext)
        }

        XCTAssertThrowsError(
            try repo.decryptBlock(
                [UInt8](repeating: 0, count: RepoKey.blockBytes + 32)
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidCiphertext)
        }
    }

    func testWrongV3SaltLengthIsRejected() throws {
        let fixture = try TestFixtures.e2ee()
        let shortSalt = String(fixture.saltV3Hex.dropLast(2))

        XCTAssertThrowsError(
            try RepoKey.unlock(
                encVersion: 3,
                repoID: fixture.repoID,
                password: fixture.password,
                magicHex: fixture.v3.magicHex,
                randomKeyHex: fixture.v3.randomKeyHex,
                saltHex: shortSalt
            )
        ) { error in
            XCTAssertEqual(error as? MNGError, .invalidSalt)
        }
    }
}
