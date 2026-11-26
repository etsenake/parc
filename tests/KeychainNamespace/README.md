# Normal encrypted persistence fixture

Browser/app launch is currently prohibited by [AGENTS.md](../../AGENTS.md).
The runtime procedures below are retained for a future explicitly authorized
run. Source/model checks do not grant that authorization.

`cookie_fixture.py` is a backend-independent loopback fixture for a persistent
HttpOnly cookie. It remains useful after removal of the old namespace interposer
and its synthetic provider/client tests.

## Product namespace and existing encrypted data

The outer Parc app declares `Parc/Chromium-v1` as its default engine directory under
Application Support. Profiles and Spaces in that standard physical directory
continue to use their existing encrypted cookies and saved passwords.
Chromium uses a separate encryption format for custom data directories. See
[automation profiles](../../docs/developer-mode.md#automation-profiles).

Direct Chromium startup sets the shared Keychain service and account before
initializing any provider or Profile. Fresh engine roots use `Parc Safe Storage` / `Parc`. An existing root with `Local State`
or restored Profile cookie/password databases and no namespace marker keeps its
encryption key: normal authorized Keychain reads copy the exact Chromium key into `Parc Safe Storage` with account
`Parc (Chromium compatibility)`. The distinct account preserves any previous
Parc key. Create-only `SecItemAdd`, followed by a byte equality check, refuses
denied access, a conflicting destination or an unavailable legacy key. It never
updates/deletes the Chromium item or any existing key, rewrites ciphertext,
changes an ACL, or exports a key to a file. Cancelled/failed preparation stops
initialization and can be retried.

The atomically written `.parc-keychain-namespace` marker contains only a fixed
namespace version, never key bytes. Subsequent launches read the Parc item;
the old Chromium item is needed again only if the migrated item is missing.
A normal macOS Chromium Safe Storage approval can therefore appear once during
migration; leave it to the user. Developer ID signatures retain the same
Team-based app requirement across later builds. The disposable harness's
`--use-mock-keychain` path performs no real Keychain access or marker writes.

Run the inert policy checks, which use fake in-memory Keychain adapters and do
not launch a browser or access a real Keychain:

```sh
swift test --filter KeychainNamespaceTests
```

They cover fresh roots, byte-preserving legacy migration, previous Parc-key
preservation, duplicate-item races, missing/denied/conflicting keys, marker-write
failure and idempotent retry.

## Separately authorized encrypted restart fixture

Run from the repository root and keep the server running across the restart:

```sh
python3 tests/KeychainNamespace/cookie_fixture.py
```

Open the printed URL in a fresh disposable Parc profile with the normal macOS
Keychain. Do **not** pass `--use-mock-keychain`; the former
`--parc-test-keychain` adapter flag is obsolete. Use the same signed app and
profile throughout, keeping the complete packaged development directory intact.
Any macOS authorization must be handled by the user; this fixture neither reads
Keychain material nor bypasses system authorization.

1. Choose **Save test cookie** and confirm the server reports success.
2. Quit Parc normally and verify its parent and helper processes exit.
3. Before reopening, inspect only this disposable profile:

   ```sh
   python3 tests/KeychainNamespace/cookie_fixture.py --inspect-profile /absolute/path/to/disposable-profile
   ```

4. Require at least one fixture row, encrypted storage for every matching row,
   and zero plaintext rows. The inspector opens cookie databases read-only and
   prints aggregate lengths/counts, not cookie values or encryption keys.
5. Reopen the **same signed app and profile**, visit the same running server and
   choose **Check saved cookie** without choosing Save again. Require success.

The server keeps its comparison token only in memory. Restarting the server or
saving again would invalidate the intended restart check. A successful run plus
the database aggregate establishes encrypted storage and cookie recovery for
that app/profile. Keep the app's signing identity stable across a restart or
upgrade so macOS can apply its normal Keychain authorization rules.
