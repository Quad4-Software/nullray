# Install

There are no pre-built binaries. You need git, the Odin compiler, make, and a C compiler (cc, clang, or gcc).
Linux, macOS, and Windows (Git Bash) are supported.

## Install script

```sh
curl -fsSL https://nullray.xyz/install | sh
```

The script clones the repo into `~/.local/src/nullray` (or updates that
checkout), builds, and installs into `~/.local`. It warns and exits if
git or Odin is missing. Re-run to pull and rebuild. Override paths with
`NULLRAY_SRC_DIR`, `NULLRAY_PREFIX`, `NULLRAY_REF`, and `NULLRAY_REPO`.

## Build from source

`make` first builds `lib/libnullray_tls.a` from vendored Mbed TLS,
nghttp2, and mlkem-native, then builds `bin/nullray`.

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

`make install` also drops the man page under `share/man/man1` and shell
completions. Later updates:

```sh
git -C ~/.local/src/nullray pull
make -C ~/.local/src/nullray install PREFIX="$HOME/.local"
```

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

    Build a bundle from this tree, then:

    ```sh
    make flatpak
    flatpak install --user ./dist/nullray_*_linux_amd64.flatpak
    flatpak run xyz.nullray.code
    ```

=== "AppImage"

    Slim and SDK AppImages build with `make appimage` and
    `make appimage-sdk`. The SDK variant can bundle the pinned Odin
    toolchain so a workspace builds with the same compiler as CI.

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
