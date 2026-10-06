---
name: opnsense
description: >
  OPNsense firewall operations: WireGuard, CARP high availability, Suricata
  IDS/IPS posture, aliases, and safe rule design. Use when configuring or
  reviewing OPNsense networks and VPN edge devices.
---

# OPNsense

Load this skill for OPNsense firewall, VPN, and HA work.

## Agent workflow

1. Confirm firmware version on all nodes before citing feature availability
2. For WireGuard: assign an interface, open WAN UDP, tighten tunnel aliases
3. For HA: match versions, dedicated sync link, CARP VIP as client gateway
4. Start Suricata in detect-only. Tune before IPS drops
5. Keep management UI off the open internet. Use aliases everywhere
6. Test failover and VPN after upgrades. Read [references/ha-vpn.md](references/ha-vpn.md)

URLs: [references/urls.md](references/urls.md).

## WireGuard

- Built-in as of OPNsense 24.1+ (no separate os-wireguard plugin required)
- Assign an interface when possible for clearer firewall rules
- WAN rule: allow UDP to the WG port
- Tunnel rules: allow only intended sources/destinations via aliases
- Prefer explicit peer AllowedIPs. Avoid casual use of blanket `WireGuard net`
- Add MSS clamping / normalization for TCP over the tunnel
- Optional PSK alongside keypairs for extra mix-in secrecy

## High availability (CARP)

| Piece | Role |
|-------|------|
| CARP VIP | Shared failover address |
| pfsync | State table sync |
| XMLRPC | Config sync master to backup |

Requirements: identical versions, dedicated sync link, clients using CARP VIP
as gateway, outbound NAT using the WAN CARP VIP. Test failover and VPN after
upgrades. WireGuard on HA needs care so backup nodes do not fight tunnels.

Detail: [references/ha-vpn.md](references/ha-vpn.md).

## Suricata

- Start detect-only. Tune before IPS drops
- Disable problematic NIC offloads when IDS demands it
- Watch CPU cost on VPN traffic paths

## Rule hygiene

1. Default deny on WAN
2. Aliases for every reused set
3. Management UI only from trusted nets + MFA if available
4. Document interface roles (WAN/LAN/OPT/sync)

## Related

[mesh-vpn](../mesh-vpn/SKILL.md) when combining OPNsense edges with NetBird or
Tailscale overlays.

## Research URLs

Full list: [references/urls.md](references/urls.md).

- OPNsense docs: https://docs.opnsense.org/
- HA / CARP: https://docs.opnsense.org/manual/hacarp.html
- WireGuard chapter: https://docs.opnsense.org/manual/vpnet.html
- IDS/IPS: https://docs.opnsense.org/manual/ips.html
- NetBird howto: https://docs.opnsense.org/manual/how-tos/netbird.html

