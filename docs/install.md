# Install

nullray ships as a single static binary for Linux (amd64, arm64), macOS
(arm64), and Windows (amd64).

## Install script

```sh
curl -fsSL https://nullray.xyz/install | sh
```

The script picks the right artifact for your platform and puts it on
your PATH. It is a POSIX sh script, so it runs on a bare system.

## Build from source

Needs an Odin toolchain and a C compiler. `make` first builds
`lib/libnullray_tls.a` from vendored Mbed TLS, nghttp2, and mlkem-native,
then builds the binary at `bin/nullray`.

```sh
git clone https://github.com/Quad4-Software/nullray.git
cd nullray
make
make test
./bin/nullray --self-test
```

Install system-wide or into a user prefix:

```sh
make install                      # PREFIX=/usr/local
make install PREFIX="$HOME/.local"
```

`make install` also drops the man page under `share/man/man1`, shell
completions, packaged skills under `share/nullray/skills`, and scaffold
packs under `share/nullray/scaffolds`.

## Packages

=== "Docker"

    ```sh
    docker pull ghcr.io/quad4-software/nullray:latest
    docker run --rm -it \
      --user 1000:1000 \
      -v "$PWD:/workspace" \
      -v nullray-config:/home/nullray/.config/nullray \
      --cap-drop ALL \
      --security-opt no-new-privileges:true \
      --add-host host.docker.internal:host-gateway \
      -e NULLRAY_PROVIDER=ollama \
      -e OLLAMA_HOST=http://host.docker.internal:11434 \
      ghcr.io/quad4-software/nullray:latest
    ```

    The image is rootless and drops all capabilities. Mount the project
    at `/workspace` and give it a provider through `-e` or a config
    volume.

=== "Flatpak"

    Download the flatpak bundle from a release, then:

    ```sh
    flatpak install --user ./nullray_*_linux_amd64.flatpak
    flatpak run xyz.nullray.code
    ```

=== "AppImage"

    Release builds ship slim and SDK AppImages. The SDK variant bundles
    the pinned Odin toolchain so a built-from-source workspace can build
    with the same compiler as CI.

=== "Release binaries"

    Plain archives for Linux, macOS, and Windows attach to
    [GitHub releases](https://github.com/Quad4-Software/nullray/releases).

## Verify

```sh
nullray --self-test
nullray --doctor
```

`--self-test` runs a headless smoke of tools, MCP, drawing, and the
shell deny path. `--doctor` prints config paths, detected keys, sandbox
posture, and the latest crash dump.

## Completions

```sh
nullray --completions zsh  > ~/.zsh/completions/_nullray
nullray --completions bash > ~/.bash_completion.d/nullray
```

Supported shells: bash, zsh, fish, powershell, elvish, nushell.

## Man page

```sh
man nullray            # after make install
nullray --man | man -l -
```
