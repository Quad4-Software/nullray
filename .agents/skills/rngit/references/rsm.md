# RSM release manifests

RSM is a general-purpose structured signed message format used by rngit for
release manifests (`.rsm` files).

## Contents (conceptual)

- Release metadata and artifact list
- Embedded per-file signatures (`.rsg` chain)
- Origin node / repository path
- Creator Reticulum identity public key
- Detached signature over the manifest body

## Trust chain

1. Manifest signature proves the manifest came from the claimed identity
2. Embedded artifact signatures prove file integrity
3. Fetch path uses origin data inside the verified manifest

If any verification fails, abort. Do not install partial or unverified files.

## Distribution pattern

Share the `.rsm` widely (even offline). Peers use it to pull verified updates
over Reticulum without a central app store. This complements (does not replace)
web-ecosystem SLSA/cosign for HTTPS package registries.

## Commands (typical)

```
rngit release ... create ... --local
rngit release manifest.rsm verify
rngit release manifest.rsm fetch latest:all --signer IDENTITY_HASH
```

Exact subcommands follow the installed rngit version. Prefer `--help` on the
local binary when unsure.
