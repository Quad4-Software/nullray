---
name: mesh-vpn
description: >
  Compare and configure NetBird, Tailscale, and Pangolin for WireGuard-based
  remote access, mesh overlays, and identity-aware app publishing. Use when
  choosing a zero-trust remote access design or reviewing VPN exposure.
---

# Mesh VPN and app access

Load this skill when picking or reviewing NetBird, Tailscale, or Pangolin.

## Agent workflow

1. Decide device mesh vs app publishing vs both
2. Choose managed vs self-host control plane
3. Draft ACL / identity groups before opening routes
4. Pilot one connector or exit node with logging
5. Confirm product version features against vendor docs (do not invent floors)
6. Harden admin planes with SSO/MFA and enrollment alerts

Detail: [references/compare.md](references/compare.md).
URLs: [references/urls.md](references/urls.md).

## Quick chooser

| Need | Prefer |
|------|--------|
| Device mesh + SSO/ACL + self-host control plane | NetBird |
| Managed mesh with least ops | Tailscale |
| Self-host Tailscale-protocol control plane | Headscale (community, not Tailscale Inc) |
| Publish HTTP apps without full device mesh | Pangolin (Newt connectors) |
| Browser access to internal HTTP via mesh | NetBird reverse proxy or Pangolin (confirm release notes) |

## Shared WireGuard truths

- Prefer least-privilege ACLs / routes over flat full-mesh allow-all
- Split DNS carefully to avoid leaks
- Treat coordination servers as sensitive infrastructure
- Exit nodes and subnet routers expand blast radius. Document owners

## NetBird notes

- Open-source WireGuard overlay with management UI and ACLs
- Self-host needs public reachability for management/signal paths. Confirm
  current ports in https://docs.netbird.io/
- Reverse proxy and L4 proxy features land in specific release lines. Verify
  the installed version before promising UI toggles
- On OPNsense, assign `wt0` and write firewall/NAT rules yourself

## Tailscale notes

- Tailnet mesh coordinated by Tailscale control plane
- ACLs in policy files. Use tags and groups
- Official control plane is cloud. Headscale reimplements for self-host

## Pangolin notes

- Identity-aware publishing via outbound connectors rather than every-device mesh
- Strong fit when users need apps, not full L3 membership
- Self-host or cloud control with optional private nodes

## Hardening

1. SSO/MFA on admin planes
2. Device posture where available
3. No inbound ports on app hosts when connector/mesh paths suffice
4. Log and alert on new peer/node enrollment

## Research URLs

Full list: [references/urls.md](references/urls.md).

- NetBird docs: https://docs.netbird.io/
- Tailscale docs: https://tailscale.com/kb
- Headscale: https://headscale.net/
- Pangolin docs: https://docs.pangolin.net/
- WireGuard protocol: https://www.wireguard.com/protocol/
