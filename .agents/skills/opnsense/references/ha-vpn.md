# OPNsense HA and VPN notes

## CARP checklist

1. Match firmware on both nodes
2. Dedicated sync interface (cable or isolated VLAN)
3. CARP VIPs on LAN/WAN (and others as needed)
4. Firewall rules allow CARP (and pfsync on sync iface)
5. Enable pfsync + XMLRPC on master toward backup
6. Point DHCP/gateway clients at VIP, not node IPs
7. Outbound NAT uses WAN VIP
8. Verify failover, failback, and long-lived sessions

Unicast CARP exists for awkward L2 domains. Multicast remains the usual default.

## WireGuard + HA

XMLRPC may sync peers, but tunnel bring-up on backup can black-hole traffic if
both sides try to own the same paths. Prefer documented OPNsense HA VPN
patterns for your version. Test before production.

## Road warrior

- Unique keys per peer
- Tight AllowedIPs
- DNS settings that prevent leak to bypass resolvers
- Keep WG admin UI off the open internet
