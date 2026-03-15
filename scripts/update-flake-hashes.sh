#!/bin/bash
# Updates flake.nix hashes from GitHub release asset digests.
# Usage: ./scripts/update-flake-hashes.sh [version]
# If no version is given, uses the latest release.

set -euo pipefail

# Portable in-place sed (BSD on macOS needs -i '', GNU on Linux needs -i)
sedi() {
    if sed --version &>/dev/null; then
        sedi "$@"
    else
        sed -i '' "$@"
    fi
}

REPO="tw93/Mole"
FLAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flake.nix"

if [[ ! -f "$FLAKE" ]]; then
    echo "Error: flake.nix not found at $FLAKE" >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required" >&2
    exit 1
fi

# Resolve version
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    VERSION=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' | sed 's/^V//')
fi

echo "Updating flake.nix for version $VERSION"

# Fetch digests from GitHub API
get_digest() {
    local name="$1"
    gh api "repos/$REPO/releases/tags/V${VERSION}" \
        --jq ".assets[] | select(.name == \"$name\") | .digest" \
        | sed 's/^sha256:/sha256:/'
}

hex_to_sri() {
    local hex="$1"
    # Convert hex to binary then base64 for SRI format
    local b64
    b64=$(echo "$hex" | sed 's/^sha256://' | xxd -r -p | base64)
    echo "sha256-${b64}"
}

echo "Fetching digests from GitHub..."
ANALYZE_AMD64=$(hex_to_sri "$(get_digest "analyze-darwin-amd64")")
ANALYZE_ARM64=$(hex_to_sri "$(get_digest "analyze-darwin-arm64")")
STATUS_AMD64=$(hex_to_sri "$(get_digest "status-darwin-amd64")")
STATUS_ARM64=$(hex_to_sri "$(get_digest "status-darwin-arm64")")

echo "  analyze-amd64: $ANALYZE_AMD64"
echo "  analyze-arm64: $ANALYZE_ARM64"
echo "  status-amd64:  $STATUS_AMD64"
echo "  status-arm64:  $STATUS_ARM64"

# Update flake.nix using sed
# Version
sedi "s|version = \".*\";|version = \"${VERSION}\";|" "$FLAKE"

# analyzeBin hashes (arm64 line comes first in the if/then/else)
# Pattern: the analyzeBin block has arm64 then amd64
sedi "/analyzeBin/,/};/ {
    s|then \"sha256-[^\"]*\"|then \"${ANALYZE_ARM64}\"|
    s|else \"sha256-[^\"]*\"|else \"${ANALYZE_AMD64}\"|
}" "$FLAKE"

# statusBin hashes
sedi "/statusBin/,/};/ {
    s|then \"sha256-[^\"]*\"|then \"${STATUS_ARM64}\"|
    s|else \"sha256-[^\"]*\"|else \"${STATUS_AMD64}\"|
}" "$FLAKE"

echo ""
echo "Updated flake.nix to version $VERSION"
echo ""
echo "NOTE: If Go dependencies changed, the vendorHash also needs updating."
echo "      Run 'nix build .#from-source' — if it fails, replace vendorHash"
echo "      with the hash from the error message."
