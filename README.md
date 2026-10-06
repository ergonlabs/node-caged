# node-caged

Node.js container images built with V8 **pointer compression**, published as `ghcr.io/ergonlabs/node-caged`.

Pointer compression stores V8 heap references as 32-bit offsets instead of 64-bit pointers, which shrinks the JavaScript heap. On a test that allocates two million small objects, `node-caged:26.10.0-alpine` used 128 MB of heap where the official `node:26.10.0-alpine` used 224 MB.

The images are drop-in replacements for the official Docker Hub `node` images of the same version: the same Alpine or Debian release, Node.js installed under `/usr/local`, the same `node` user at uid/gid 1000, and npm included. Temporal support is built in, as in the official Node.js 26 images.

## Images

| Tag | Replaces | Base |
|---|---|---|
| `ghcr.io/ergonlabs/node-caged:26.10.0-alpine` | `node:26.10.0-alpine` | Alpine 3.24 (musl) |
| `ghcr.io/ergonlabs/node-caged:26.10.0-slim` | `node:26.10.0-slim` | Debian trixie-slim (glibc) |

Both are published for `linux/amd64` and `linux/arm64`.

```dockerfile
FROM ghcr.io/ergonlabs/node-caged:26.10.0-alpine
```

Pin the digest (`…:26.10.0-alpine@sha256:…`) for builds that must not change under you.

## Before you switch

Pointer compression has two costs. Both come from Node.js's own description of the build flag: "limits max heap to 4GB and breaks ABI compatibility".

- **The heap is capped at 4 GB.** `--max-old-space-size` cannot raise it.
- **Prebuilt native addons for standard Node.js will not load.** An addon that downloads a prebuilt binary must be compiled from source against this image instead. The image includes Node's headers for that; add a compiler toolchain in your build stage.

## How the images are built

- **Source:** the official Node.js release tarball from nodejs.org. Its SHA-256 is pinned in each Dockerfile, and the build fails on any other file.
- **Pinning a release:** `verify-node-release.sh <version>` downloads the release's `SHASUMS256.txt.asc`, checks that it is signed by a key in [nodejs/release-keys](https://github.com/nodejs/release-keys) (the Node.js project's list of release signers), and only then writes the version and tarball hash into both Dockerfiles.
- **Configuration:** `./configure --experimental-enable-pointer-compression --v8-enable-temporal-support`, nothing else.
- **Toolchain:** the official `rust` images (Temporal support needs a Rust compiler), not an installer piped from curl.
- **Base images:** every `FROM` is pinned by digest.
- **Self-check:** the final stage refuses to build unless `node` reports the pinned version, pointer compression and Temporal, and `npm` runs.
- **Publication:** [`.github/workflows/build.yml`](.github/workflows/build.yml) builds each architecture natively, not under emulation, on GitHub-hosted runners, and attaches SLSA provenance and an SBOM. A pull request builds the images once; merging it publishes those same images, after checking that the pull request's final commit has exactly the Dockerfiles and workflow on `main`.

## Files

| File | Builds |
|---|---|
| `alpine.Dockerfile` | `node-caged:<version>-alpine` |
| `slim.Dockerfile` | `node-caged:<version>-slim` |
| `verify-node-release.sh` | Verifies a Node.js release and pins it in both Dockerfiles |
| `.github/workflows/build.yml` | Builds both images for amd64 and arm64 and publishes them |

To build one yourself:

```bash
docker build -f alpine.Dockerfile -t node-caged:26.10.0-alpine .
```

Compiling Node.js takes a long time: about an hour on 8 CPUs, and three to four and a half hours on a 2-CPU CI runner.

## Updating Node.js

```bash
./verify-node-release.sh 26.11.0
```

It needs `curl` and `gpg`, verifies the release, and rewrites `NODE_VERSION` and `NODE_SHA256` in both Dockerfiles. It changes nothing if the signature does not verify. Open a pull request with the result: it builds the new images, and merging it publishes them.

## License

MIT, for the files in this repository. The images contain Node.js, which is distributed under [its own license](https://github.com/nodejs/node/blob/main/LICENSE).
