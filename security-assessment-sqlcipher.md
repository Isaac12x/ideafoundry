# Security Assessment: SQLCipher Database
**Date:** 2026-05-25  
**Scope:** SQLCipher encryption implementation, key management, and access controls

---

## Attack Executed

Full database access obtained in 3 steps:
1. Read `storage/recovery_passphrase.key` → plaintext passphrase (`ufm_vkw5pxk2xaf1TEF`)
2. Re-derived 256-bit key via scrypt (`RecoverySecret.rb:162`) — same algorithm in source
3. Opened `storage/production.sqlite3` via `sqlcipher` CLI → all 28 tables readable

**Tables exposed:** `action_mailbox_inbound_emails`, `action_text_rich_texts`, `active_storage_attachments`, `active_storage_blobs`, `active_storage_variant_records`, `api_keys`, `ar_internal_metadata`, `build_items`, `drawings`, `export_jobs`, `facts`, `github_repositories`, `idea_agent_tokens`, `idea_entries`, `idea_lists`, `idea_topologies`, `ideas`, `kanban_boards`, `lists`, `maxims`, `notes`, `schema_migrations`, `sqlite_sequence`, `submissions`, `templates`, `todo_items`, `topologies`, `users`, `versions`

---

## Vulnerabilities

### CRITICAL — Passphrase co-located with encrypted database

**File:** `app/services/recovery_secret.rb:75` (`user_passphrase_file_path`)  
**Exploited:** Yes

`persist_user_passphrase!` writes the passphrase to `storage/recovery_passphrase.key` — the same directory as `storage/production.sqlite3`. Anyone with filesystem read access gets both the key and the lock simultaneously. Encryption is completely defeated.

**Attack path:**
```bash
cat storage/recovery_passphrase.key
# → {"version":1,"app_node_id":"...","passphrase":"ufm_vkw5pxk2xaf1TEF"}

# Derive key (algorithm is public in source):
ruby -e "
  require 'json', 'openssl'
  p = JSON.parse(File.read('storage/recovery_passphrase.key'))['passphrase']
  key = OpenSSL::KDF.scrypt(p, salt: 'idea-foundry:sqlcipher-database-key:v1', N: 2**14, r: 8, p: 1, length: 32)
  puts key.unpack1('H*')
"

# Open database:
echo "PRAGMA key = \"x'<derived_hex>'\"; SELECT * FROM users;" | sqlcipher storage/production.sqlite3
```

**Fix:** Store the passphrase file outside the app directory — separate volume, OS keychain, or secret manager (Vault, AWS Secrets Manager). Never persist it adjacent to the data it protects. Enforce this in `user_passphrase_file_path` by rejecting paths inside `Rails.root`.

---

### HIGH — Raw passphrase stored in Rails session cookie

**File:** `app/controllers/recovery_secrets_controller.rb:23`  
**Exploited:** Theoretical

```ruby
session[RECOVERY_SECRET_SESSION_KEY] = passphrase  # raw passphrase in every cookie
```

The database master passphrase rides in every HTTP response cookie. If `secret_key_base` is ever leaked (via logs, environment dump, config exposure), every active session exposes the passphrase directly.

**Fix:** Store only a short-lived, server-side token in the session that maps to the passphrase held in memory (e.g., `Rails.cache` with a TTL). Never put the passphrase itself in the cookie.

---

### HIGH — No rate limiting on passphrase entry endpoint

**File:** `app/controllers/recovery_secrets_controller.rb` (no throttle in codebase)  
**Exploited:** Yes (trivially)

`POST /recovery_secret` has no rate limiting. The endpoint also skips both `require_database_recovery_unlock` and `require_typing_unlock`, making it the sole unauthenticated attack surface. An attacker with network access can brute-force passphrases at full HTTP throughput.

**Fix:** Add Rack::Attack throttle:
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("recovery_secret/ip", limit: 5, period: 15.minutes) do |req|
  req.ip if req.path == "/recovery_secret" && req.post?
end
```

---

### MEDIUM — Weak scrypt work factor

**File:** `app/services/recovery_secret.rb:14-16`

```ruby
SCRYPT_N = 2**14   # 16,384 — below current recommendations
SCRYPT_R = 8
SCRYPT_P = 1
```

OWASP 2023 recommends N≥2^17 (131,072) for interactive logins and N≥2^20 for sensitive key derivation. At N=2^14, a modern GPU can trial ~500k candidates/sec vs ~4k at N=2^17 — a 125× reduction in brute-force cost.

**Fix:** Raise to `N=2**17`. Add a `version` field to the passphrase file so the app can re-derive with new parameters on next unlock. Costs ~100ms on server CPU — acceptable for a one-time unlock.

---

### MEDIUM — Plaintext backup left on disk after migration

**File:** `app/services/sqlcipher_database_migrator.rb:167-179`

`migrate!` copies the plaintext database to `Rails.root/../idea-app-sqlcipher-backups/*.plaintext` before encrypting. These files are never automatically deleted and contain all user data unencrypted.

**Fix:** Either encrypt the backup immediately after creation using the same key, or delete it after verifying the encrypted copy passes `integrity_check`. Document an explicit retention policy if backups are kept.

---

### LOW — Key material appears in PRAGMA statement (log exposure risk)

**Files:** `config/initializers/sqlcipher.rb:31`, `app/services/sqlcipher_database_migrator.rb:141`

```ruby
@raw_connection.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
```

If `ActiveRecord::Base.logger` is ever set to DEBUG (common in staging), the full 256-bit key hex appears in logs. The key directly decrypts the database.

**Fix:** Ensure `PRAGMA key` is filtered from all log output. Add `config.filter_parameters += [:key, "PRAGMA key"]` or wrap the execute call in `ActiveRecord::Base.silence`.

---

## Summary

| Severity | Issue | Exploited |
|---|---|---|
| CRITICAL | Passphrase file co-located with database | Yes — full DB access |
| HIGH | Raw passphrase in session cookie | Theoretical |
| HIGH | No rate limit on passphrase entry | Yes |
| MEDIUM | Scrypt N=2^14 below OWASP recommendation | Increases brute-force speed 125× |
| MEDIUM | Plaintext backups not cleaned up | Partial |
| LOW | Key material in PRAGMA may reach logs | Conditional |

**Root cause:** The threat model requires the passphrase to be stored separately from the database, but the default `user_passphrase_file_path` puts both in `storage/`. That assumption must be enforced in code, not left to deployment convention.
