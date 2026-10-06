# Node.js built from its signed release tarball with V8 pointer compression ("caged" heap),
# on Debian trixie-slim (glibc). A drop-in replacement for
# node:<version>-slim: same Debian release, same `node` user at uid/gid 1000, Node installed
# under /usr/local. Published as
# ghcr.io/ergonlabs/node-caged:<version>-slim.
#
# NODE_VERSION and NODE_SHA256 change together, and only through verify-node-release.sh, which
# checks the release's SHASUMS256.txt signature against the nodejs/release-keys keyring and
# prints the tarball's SHA-256. Every base image is pinned by digest.
ARG NODE_VERSION=26.10.0
ARG NODE_SHA256=7b3a546d33cb7e15a43bdd7a57e0be5d5fd5ffc553e6e4c120033e66f0ba20c5

# ── build: compile Node.js with pointer compression and Temporal ─────────────────────────────
# The official Rust image provides the Rust toolchain Temporal support needs (rustc and
# cargo >= 1.86, per Node's BUILDING.md) without a curl-piped installer. Trixie's GCC 14 meets
# Node's GCC >= 13.2 requirement.
FROM rust:1.99.0-trixie@sha256:3745c050d12adc738eff16ebfc81ed044bfb2cc27c6828850ff1666beb1c7a49 AS build
ARG NODE_VERSION
ARG NODE_SHA256
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential ca-certificates curl python3 xz-utils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl -fsSLo node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.xz" \
 && printf "%s  node.tar.xz\n" "${NODE_SHA256}" > node.tar.xz.sha256 \
 && sha256sum -c node.tar.xz.sha256 \
 && tar -xJf node.tar.xz --strip-components=1 \
 && rm node.tar.xz node.tar.xz.sha256
RUN ./configure --prefix=/usr/local --experimental-enable-pointer-compression --v8-enable-temporal-support
RUN make -j"$(nproc)"
# Keep only this architecture's OpenSSL headers (needed to compile native addons), as the
# official image does; the full set is ~60 MB of headers for other platforms.
RUN make install DESTDIR=/node-install \
 && case "$(uname -m)" in \
      x86_64) openssl_arch=linux-x86_64 ;; \
      aarch64) openssl_arch=linux-aarch64 ;; \
      *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac \
 && find /node-install/usr/local/include/node/openssl/archs -mindepth 1 -maxdepth 1 ! -name "${openssl_arch}" -exec rm -rf {} +

# ── runtime: trixie-slim with the compiled Node.js and the official image's `node` user ───────
FROM debian:trixie-20260918-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
ARG NODE_VERSION
ENV NODE_VERSION=${NODE_VERSION}
RUN groupadd --gid 1000 node \
 && useradd --uid 1000 --gid node --shell /bin/bash --create-home node
COPY --from=build /node-install/usr/local /usr/local
# Fail the build unless this is the requested version, compiled with pointer compression and
# Temporal, with a working npm.
RUN test "$(node --version)" = "v${NODE_VERSION}" \
 && test "$(node -p process.config.variables.v8_enable_pointer_compression)" = "1" \
 && test "$(node -p 'typeof Temporal')" = "object" \
 && npm --version
CMD ["node"]
