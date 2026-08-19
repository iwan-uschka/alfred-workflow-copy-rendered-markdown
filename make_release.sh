#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Usage: bash make_release.sh <version>
if [ -z "${1:-}" ]; then
  echo "error: version required — usage: bash make_release.sh 1.2.0"
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
BUILT="dist/Copy-Rendered-Markdown.alfredworkflow"
RELEASE="dist/Copy-Rendered-Markdown-${TAG}.alfredworkflow"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be x.y.z (got '${VERSION}')"
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean — commit or stash changes before releasing"
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists locally"
  exit 1
fi

if ! remote_tag_check="$(git ls-remote --tags origin "refs/tags/${TAG}" 2>&1)"; then
  echo "error: could not check origin for existing tags: ${remote_tag_check}"
  exit 1
fi
if [ -n "$remote_tag_check" ]; then
  echo "error: tag ${TAG} already exists on origin"
  exit 1
fi

echo "→ Version: ${VERSION} (tag: ${TAG})"

# Bump the root-level version key in info.plist, restoring it if anything
# downstream fails. The keypath has no dots, so plutil targets only the
# top-level key (not the nested per-object version keys).
BACKUP="$(mktemp)"
cp info.plist "$BACKUP"
trap 'cp "$BACKUP" info.plist; rm -f "$BACKUP" "$BUILT"' EXIT

plutil -replace version -string "${VERSION}" info.plist
plutil -lint info.plist

echo "→ Building workflow..."
./build.sh >/dev/null

echo "→ Packaging ${RELEASE}..."
rm -f "${RELEASE}" "${RELEASE}.sha256"
cp "${BUILT}" "${RELEASE}"
shasum -a 256 "${RELEASE}" > "${RELEASE}.sha256"

# Bump succeeded end-to-end — keep the info.plist change.
trap - EXIT
rm -f "$BACKUP"

echo ""
echo "✓ ${RELEASE} is ready ($(du -sh "${RELEASE}" | cut -f1))"
echo "  SHA-256: $(cut -d' ' -f1 "${RELEASE}.sha256")"
echo ""
echo "Next steps:"
echo ""
echo "  1. Commit and push the version bump:"
echo "     git add info.plist && git commit -m 'Release ${VERSION}' && git push"
echo ""
echo "  2. Create the GitHub release:"
echo "     gh release create ${TAG} ${RELEASE} ${RELEASE}.sha256 \\"
echo "       --title \"Copy Rendered Markdown ${VERSION}\" \\"
echo "       --generate-notes"
