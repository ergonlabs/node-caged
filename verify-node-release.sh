#!/usr/bin/env bash
# Verify a Node.js release and pin it in both node-caged Dockerfiles.
#
# Usage: ./verify-node-release.sh <version>      e.g. 26.10.0
#
# Downloads the release's SHASUMS256.txt.asc from nodejs.org, checks that its signature was
# made by a key listed in the nodejs/release-keys repository (the Node.js project's published
# keyring of release signers), reads the SHA-256 of node-v<version>.tar.xz from the signed
# file, and writes NODE_VERSION and NODE_SHA256 into alpine.Dockerfile and slim.Dockerfile.
# The Docker builds then refuse any tarball whose hash differs. Exits non-zero, changing
# nothing, if the signature does not verify or the signer is not a listed release key.
# Needs curl and gpg; uses a throwaway GnuPG home.
set -euo pipefail

VERSION="${1:?usage: $0 <version, e.g. 26.10.0>}"
VERSION="${VERSION#v}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_KEYS="https://raw.githubusercontent.com/nodejs/release-keys/HEAD"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export GNUPGHOME="${WORK}/gnupg"
mkdir -m 700 "${GNUPGHOME}"

curl -fsSLo "${WORK}/SHASUMS256.txt.asc" "https://nodejs.org/dist/v${VERSION}/SHASUMS256.txt.asc"
curl -fsSLo "${WORK}/keys.list" "${RELEASE_KEYS}/keys.list"

# Import every listed release key, then require a good signature from one of them.
while read -r fingerprint; do
  [ -n "${fingerprint}" ] || continue
  curl -fsSL "${RELEASE_KEYS}/keys/${fingerprint}.asc" | gpg --batch --quiet --import
done < "${WORK}/keys.list"

status="$(gpg --batch --status-fd 1 --verify "${WORK}/SHASUMS256.txt.asc" 2>/dev/null || true)"
signer="$(awk '$2 == "VALIDSIG" { print $NF }' <<<"${status}")"
if [ -z "${signer}" ] || ! grep -qx "${signer}" "${WORK}/keys.list"; then
  echo "error: SHASUMS256.txt for v${VERSION} is not validly signed by a nodejs/release-keys key" >&2
  exit 1
fi

sha256="$(gpg --batch --decrypt "${WORK}/SHASUMS256.txt.asc" 2>/dev/null \
  | awk -v f="node-v${VERSION}.tar.xz" '$2 == f { print $1 }')"
if ! [[ "${sha256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: node-v${VERSION}.tar.xz is not listed in the signed SHASUMS256.txt" >&2
  exit 1
fi

for dockerfile in "${DIR}/alpine.Dockerfile" "${DIR}/slim.Dockerfile"; do
  sed -i.bak -E \
    -e "s/^ARG NODE_VERSION=.*/ARG NODE_VERSION=${VERSION}/" \
    -e "s/^ARG NODE_SHA256=.*/ARG NODE_SHA256=${sha256}/" \
    "${dockerfile}"
  rm "${dockerfile}.bak"
done

echo "v${VERSION}: signed by ${signer}; node-v${VERSION}.tar.xz sha256 ${sha256}"
echo "pinned in alpine.Dockerfile and slim.Dockerfile"
