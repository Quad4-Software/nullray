# nullray multi-stage image: Debian trixie, Odin build tools, and rootless runtime.
# build tools stay in the builder stage, runtime is rootless and minimal.
#
# Base: debian:trixie-20260824-slim (multi-arch index digest).
# Rebuild when Dependabot bumps the pin.

# hadolint ignore=DL3006
FROM debian:trixie-20260824-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS build

ENV DEBIAN_FRONTEND=noninteractive

# llvm-dev pulls the static archives build_odin.sh needs (plain llvm is not enough).
# hadolint ignore=DL3008
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		ca-certificates \
		clang \
		git \
		libcurl4-openssl-dev \
		llvm-dev \
		make \
		python3 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /src/odin
COPY packaging/odin-pin /tmp/odin-pin
RUN COMMIT="$(grep -E '^[0-9a-f]{40}$' /tmp/odin-pin | head -n1)" \
	&& test -n "${COMMIT}" \
	&& git init -q \
	&& git remote add origin https://github.com/odin-lang/Odin.git \
	&& git fetch --depth 1 origin "${COMMIT}" \
	&& git checkout -q FETCH_HEAD \
	&& echo "${COMMIT}" >.nullray-odin-commit \
	&& ./build_odin.sh

ENV PATH="/src/odin:${PATH}"

WORKDIR /src/nullray
COPY . .
RUN make clean && make \
	&& install -D -m 755 bin/nullray /out/nullray

# Runtime: no compiler, no package manager leftovers beyond curl + CA store.
# hadolint ignore=DL3006
FROM debian:trixie-20260824-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
	TERM=xterm-256color \
	COLORTERM=truecolor \
	HOME=/home/nullray \
	XDG_CONFIG_HOME=/home/nullray/.config

# hadolint ignore=DL3008
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		libcurl4t64 \
		ncurses-base \
		ncurses-term \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --uid 1000 --create-home --home-dir /home/nullray nullray

COPY --from=build /out/nullray /usr/local/bin/nullray

USER nullray
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/nullray"]
