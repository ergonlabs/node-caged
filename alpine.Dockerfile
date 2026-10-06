# Node.js built from its signed release tarball with V8 pointer compression ("caged" heap),
# on Alpine. A drop-in replacement for node:<version>-alpine: same Alpine release, same `node`
# user at uid/gid 1000, Node installed under /usr/local. Published as
# ghcr.io/ergonlabs/node-caged:<version>-alpine.
#
# NODE_VERSION and NODE_SHA256 change together, and only through verify-node-release.sh, which
# checks the release's SHASUMS256.txt signature against the nodejs/release-keys keyring and
# prints the tarball's SHA-256. Every base image is pinned by digest.
ARG NODE_VERSION=26.10.0
ARG NODE_SHA256=7b3a546d33cb7e15a43bdd7a57e0be5d5fd5ffc553e6e4c120033e66f0ba20c5

# ── build: compile Node.js with pointer compression and Temporal ─────────────────────────────
# The official Rust image provides the Rust toolchain Temporal support needs (rustc and
# cargo >= 1.86, per Node's BUILDING.md) without a curl-piped installer.
FROM rust:1.99.0-alpine3.24@sha256:0cce0a5e0e8ba67b455257a3a02a1d99005f382748789d6464460028810f1627 AS build
ARG NODE_VERSION
ARG NODE_SHA256
RUN apk add --no-cache build-base curl linux-headers python3 xz
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

# ── runtime: Alpine with the compiled Node.js and the official image's `node` user ────────────
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ARG NODE_VERSION
ENV NODE_VERSION=${NODE_VERSION}
RUN apk add --no-cache libgcc libstdc++ \
 && addgroup -g 1000 node \
 && adduser -u 1000 -G node -s /bin/sh -D node
COPY --from=build /node-install/usr/local /usr/local
# Fail the build unless this is the requested version, compiled with pointer compression and
# Temporal, with a working npm.
RUN test "$(node --version)" = "v${NODE_VERSION}" \
 && test "$(node -p process.config.variables.v8_enable_pointer_compression)" = "1" \
 && test "$(node -p 'typeof Temporal')" = "object" \
 && npm --version
CMD ["node"]
