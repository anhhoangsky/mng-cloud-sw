# Crypto parity

The iOS client must read and write exactly the same formats as the Rust client.
Two JSON vector files copied verbatim from
`mng-cloud-rs/crates/mng-core/tests/fixtures` are the gate:

- `Packages/MNGCore/Tests/MNGCoreTests/Fixtures/e2ee_kat.json`
- `Packages/MNGCore/Tests/MNGCoreTests/Fixtures/vault_kat.json`

Never edit the expected values to make a test pass.

## Seafile encrypted libraries (v2/v3)

Source: `crates/mng-core/src/crypto/e2ee.rs`.

| Parameter | Value |
| --- | --- |
| v2 salt | fixed `da9045c306c7cc26` |
| v3 salt | 32 random bytes stored with the library |
| Key | `PBKDF2-SHA256(password, salt, 1000, 32)` |
| Magic | `PBKDF2-SHA256(repo_id ‖ password, salt, 1000, 32)` |
| Key IV | `PBKDF2-SHA256(key, salt, 10, 16)` |
| Random key | `AES-256-CBC(key, keyIV, secret)` — 32-byte secret |
| Content key | `PBKDF2-SHA256(secret, salt, 1000, 32)` |
| Content IV | `PBKDF2-SHA256(contentKey, salt, 10, 16)` |
| Block | `AES-256-CBC(contentKey, contentIV, PKCS#7)`, ≤ 8 MiB plaintext |
| Block id | lowercase hex `SHA-1(ciphertext)` |
| Ciphertext length | `n + 16 - (n % 16)` |

Required tests: unlock v2 and v3 → `content_key_hex` / `content_iv_hex` exact;
encrypt `plain_hex` → `cipher_hex`; block id matches; empty block matches;
wrong password fails without leaking which check failed; malformed ciphertext
(empty, non-block-multiple, oversized) is rejected.

## Native vault (`mng-vault/v1`)

Source: `crates/mng-core/src/crypto/vault.rs`.

| Parameter | Value |
| --- | --- |
| KDF | `PBKDF2-SHA256`, 310,000 rounds, NFKC-normalized password |
| Cipher | `AES-256-GCM`, 12-byte random nonce, 16-byte tag |
| Blob | `iv ‖ ciphertext ‖ tag` |
| AAD manifest | `mng-vault/v1/{uid}/manifest` |
| AAD verifier | `mng-vault/v1/{uid}/verifier` |
| AAD chunk | `mng-vault/v1/{uid}/file/{file_id}/chunk/{index}/{total}` |
| AAD thumb | `mng-vault/v1/{uid}/file/{file_id}/thumb` |
| Chunk | 4 MiB plaintext |
| Limits | 32 vaults per owner, files up to 16 GiB |

Required tests: unlock with `vault_kat.json` verifies the verifier; decrypt
`manifest_b64` → `manifest_json`; decrypt `chunk_b64` with `chunk_aad` →
`chunk_plain`; decrypt `thumb_b64` with `thumb_aad` → `thumb_plain`; wrong
AAD/nonce/tag fails.

## Swift implementation rules

- Keep key material in `SecureBytes` (raw allocation, `memset_s` on release).
  Never store keys in `String`.
- PBKDF2 via CommonCrypto `CCKeyDerivationPBKDF`; AES-CBC via `CCCrypt` with
  PKCS#7; AES-GCM via CryptoKit; SHA-1 via `Insecure.SHA1` for block ids only.
- Compare magic/verifier in constant time; no early return.
- Never log passwords, keys, plaintext or block contents. Log error codes only.
- Clear password buffers immediately after derivation; previews write to the
  app container and are removed on close (excluded from backup).
- Any change under `Packages/MNGCore/Sources/MNGCore/Crypto/` requires green
  KAT tests and a security-focused review.
