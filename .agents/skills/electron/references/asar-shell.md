# ASAR integrity and shell footguns

## ASAR

- Package with `@electron/asar` (all current versions support integrity hashing)
- Toggle fuse `EnableEmbeddedAsarIntegrityValidation` at build time
- Pair with `OnlyLoadAppFromAsar` or unpacked `app/` can bypass checks
- macOS: `ElectronAsarIntegrity` in Info.plist (SHA256 of ASAR header)
- Windows: Integrity resource `ElectronAsar` JSON with header hash
- Forge `>=7.4.0` / Packager `>=18.3.1` automate when asar enabled

Mismatch or missing hash terminates the app when validation is on.

Past bypass via resource modification (CVE-2025-55305) affected older
Electron with both fuses on. Stay on patched releases.

## shell / protocol footguns

| Bad | Better |
|-----|--------|
| `shell.openExternal(userString)` | Allowlisted `https:` after `new URL` |
| Default grant openExternal | Permission handler denies for untrusted |
| `target=_blank` unchecked | `setWindowOpenHandler` deny + optional safe open |
| Loading remote with nodeIntegration | Separate session, no Node in that world |

## Preload

Expose a minimal `contextBridge` API. Do not mirror all of Electron into the
page.
