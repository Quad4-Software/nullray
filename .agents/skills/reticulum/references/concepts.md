# Reticulum concepts

## Identity and destination

An identity holds key material. A destination hash is computed from the public
key and destination aspects. Peers discover paths via announces. There is no
central directory authority.

## Interfaces

RNS runs over many carriers (TCP, UDP, I2P, radios, etc.). Interface config
lives in the Reticulum config. Path discovery works across mixed media.

## LXMF

Lightweight message format with optional propagation nodes for offline
delivery. Attachments and tickets have size costs. Cap what tools display.

## Security posture

- Encryption is default, not optional
- Assume hostile networks
- Identity compromise is catastrophic. Back up and protect identity files
- Announce traffic can leak metadata about presence. Plan accordingly

## Tooling

Common binaries: `rnsd`, `rnstatus`, `rnpath`, `rnprobe`, `rncp`, `rnid`.
Install via `pip install rns` or distribution packages.
