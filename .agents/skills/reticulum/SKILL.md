---
name: reticulum
description: >
  Reticulum (RNS) mesh networking concepts: destinations, links, transport,
  LXMF, identities, and operator footguns. Use when building or reviewing
  Reticulum, LXMF, NomadNet, or MeshChatX-related work.
---

# Reticulum

Load this skill for RNS protocol and mesh concepts. For Git over Reticulum,
also load [rngit](../rngit/SKILL.md).

## Agent workflow

1. Read conceptual overview in the manual before inventing addressing models
2. Treat destination hashes as identities, not IP locations
3. Never print private keys or passphrases in tool output
4. Do not restart `rnsd` or rewrite `~/.reticulum/config` unless the user asks
5. Keep responses small. Mesh contexts are bandwidth-scarce
6. For Git remotes and `.rsm` releases, switch to the rngit skill

Detail: [references/concepts.md](references/concepts.md).
URLs: [references/urls.md](references/urls.md).

## Core ideas

- Encrypted, medium-agnostic networking stack
- Destinations are 16-byte hashes derived from identity material. Addresses are
  identities, not IP locations
- Local state under `~/.reticulum` (config, storage, identities)
- Links provide encrypted channels. Transport announces paths across hops

## Related apps

| Name | Role |
|------|------|
| LXMF | Messaging / store-and-forward over RNS |
| NomadNet | Micron page apps + LXMF |
| MeshChat / MeshChatX | Web LXMF clients |
| rngit | Git hosting and signed releases over RNS |

## Operator rules

1. Never return private keys or passphrases in tool output
2. Do not restart `rnsd` or rewrite `~/.reticulum/config` from an agent unless
   the user explicitly asks
3. Keep responses small. Mesh contexts are bandwidth-scarce
4. Prefer destination hashes over hostnames when discussing peers

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Manual: https://reticulum.network/manual/
- Understanding: https://reticulum.network/manual/understanding.html
- Interfaces: https://reticulum.network/manual/interfaces.html
- Git over RNS: https://reticulum.network/manual/git.html
