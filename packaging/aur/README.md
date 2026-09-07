# AUR package recipe for nullray-bin (linux amd64 prebuilt).

Publish after a GitHub release exists:

1. Create an AUR account and clone ssh://aur@aur.archlinux.org/nullray-bin.git
2. Copy PKGBUILD from this directory
3. Update sha256sums from the release checksums.txt (replace SKIP)
4. makepkg --printsrcinfo > .SRCINFO
5. git add PKGBUILD .SRCINFO && git commit -m "nullray-bin pkgver" && git push

Omarchy users can Install → AUR → nullray-bin once the package is published.
