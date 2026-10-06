# Mesh VPN comparison notes

Confirm product versions against vendor docs before citing feature floors.

| Product | Control plane | Client model | Best fit |
|---------|---------------|--------------|----------|
| NetBird | Managed or self-host | Device mesh + ACLs | Self-host WireGuard mesh with SSO |
| Tailscale | Tailscale cloud | Device mesh + policy ACLs | Lowest ops for mesh |
| Headscale | Self-host (community) | Tailscale-protocol clients | Self-host control without Tailscale Inc |
| Pangolin | Cloud or self-host | App connectors (Newt) | Publish HTTP apps without full L3 mesh |

## Shared design rules

1. Default deny between peers. Grow allows with tags/groups
2. Document exit nodes and subnet routers as high blast-radius roles
3. Split DNS only with an explicit leak story
4. Treat coordination servers and IdP links as crown jewels

## NetBird

Docs: https://docs.netbird.io/

- Self-host needs public reachability for management and signal paths. Check
  current port list in docs
- Reverse proxy / L4 proxy features land in specific release lines. Verify the
  version you install before promising UI toggles
- On OPNsense, assign `wt0` and write firewall/NAT rules yourself. NetBird
  policies do not auto-create OPNsense rules

## Tailscale / Headscale

Docs: https://tailscale.com/kb

- ACLs are the primary authorization layer
- Headscale reimplements the control plane. Track compatibility with client
  versions separately from Tailscale Inc releases

## Pangolin

Docs: https://docs.pangolin.net/

- Outbound connectors publish apps without exposing every device as a peer
- Prefer when users need HTTP apps, not full mesh membership

## Decision steps

1. List whether you need device mesh, app publish, or both
2. Decide managed vs self-host control plane
3. Sketch ACL / identity groups before opening routes
4. Pilot one exit node or connector with logging before wide rollout
