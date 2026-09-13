---
name: rngit
description: >
  Git over Reticulum with rngit and git-remote-rns, plus signed .rsm release
  manifests and .rsg artifact signatures. Use for rns:// remotes, nodes,
  releases, and offline-verifiable distribution.
---

# rngit and RSM

Load this skill for `rns://` Git remotes, rngit nodes, and signed releases.
Requires RNS. Confirm local `rngit --help` and the Git chapter of the Reticulum
manual before asserting subcommand details.

## Agent workflow

1. Confirm RNS is available and the peer destination hash is known
2. Use `rns://DESTINATION_HASH/group/repo` form for remotes
3. For releases: create or obtain a `.rsm`, then `verify` before `fetch`
4. Prefer `--signer IDENTITY_HASH` when a specific publisher is required
5. Never install artifacts that fail manifest or per-file signature checks
6. Treat public mesh hosting as sensitive. Pair with supply-chain for HTTPS registries

Detail: [references/rsm.md](references/rsm.md).
URLs: [references/urls.md](references/urls.md).

## Pieces

| Component | Role |
|-----------|------|
| `rngit` | Repository node / management CLI |
| `git-remote-rns` | Git helper for `rns://` URLs |
| `.rsm` | Signed release manifest (RSM format) |
| `.rsg` | Per-artifact signature material embedded/used with manifests |

URL form:

```
rns://DESTINATION_HASH/group/repo
```

## Releases

Creating a release signs each artifact (Ed25519) and embeds signatures in a
signed `.rsm` manifest with origin info and the creator identity. Anyone with
the manifest can:

1. Verify the manifest signature offline
2. Fetch updates from the origin over Reticulum
3. Verify each downloaded artifact before install

```
rngit release <manifest.rsm> verify
rngit release <manifest.rsm> fetch latest:all
```

Optional `--signer IDENTITY_HASH` to require a specific signer.

Detail: [references/rsm.md](references/rsm.md).

## Node basics

- Config default: `~/.rngit/config` (system: `/etc/rngit/config`)
- `rngit --print-identity` prints peer and destination hashes
- Group permissions via `.allowed` files on the node
- Commit signing helper: `rngcs` with a Reticulum identity

## Related

[reticulum](../reticulum/SKILL.md), [supply-chain](../supply-chain/SKILL.md)

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Git over Reticulum: https://reticulum.network/manual/git.html
- Reticulum manual: https://reticulum.network/manual/
- SLSA (HTTPS registry contrast): https://slsa.dev/spec/v1.2/

