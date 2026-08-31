#!/usr/bin/env bash

set -euo pipefail
unset CDPATH

mode="${1:-verify}"
case "$mode" in
  verify | publish) ;;
  *)
    echo "Usage: $0 [verify|publish]" >&2
    exit 64
    ;;
esac

script_directory=$(cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(cd -- "$script_directory/.." && pwd)

database_path="${IP2ASN_DATABASE_PATH:-$repository_root/Sources/SwiftIP2ASN/Resources/ip2asn.ultra}"
manifest_path="${IP2ASN_MANIFEST_PATH:-$repository_root/Sources/SwiftIP2ASN/Resources/ip2asn.manifest.json}"
bucket="${IP2ASN_R2_BUCKET:-networkweather-pkgs}"
database_key="${IP2ASN_R2_DATABASE_KEY:-db/ip2asn-v2.ultra}"
manifest_key="${IP2ASN_R2_MANIFEST_KEY:-db/ip2asn-v2.manifest.json}"
public_database_url="${IP2ASN_PUBLIC_DATABASE_URL:-https://pkgs.networkweather.com/db/ip2asn-v2.ultra}"
public_manifest_url="${IP2ASN_PUBLIC_MANIFEST_URL:-https://pkgs.networkweather.com/db/ip2asn-v2.manifest.json}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 69
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available." >&2
    exit 69
  fi
}

verify_pair() {
  local database="$1"
  local manifest="$2"
  local expected_sha expected_bytes actual_sha actual_bytes

  expected_sha=$(jq -er '.output.artifact.sha256' "$manifest")
  expected_bytes=$(jq -er '.output.artifact.byteCount' "$manifest")
  actual_sha=$(sha256_file "$database")
  actual_bytes=$(wc -c < "$database" | tr -d '[:space:]')

  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Database SHA-256 does not match the manifest." >&2
    echo "Expected: $expected_sha" >&2
    echo "Actual:   $actual_sha" >&2
    exit 65
  fi

  if [[ "$actual_bytes" != "$expected_bytes" ]]; then
    echo "Database byte count does not match the manifest." >&2
    echo "Expected: $expected_bytes" >&2
    echo "Actual:   $actual_bytes" >&2
    exit 65
  fi

  jq -e '
    .schemaVersion == 1 and
    .output.formatVersion == 2 and
    (.output.buildIdentifier | test("^[0-9a-f]{64}$")) and
    (.sources | length >= 1) and
    all(.sources[];
      (.url | startswith("https://")) and
      (.downloadedArtifact.sha256 | test("^[0-9a-f]{64}$")) and
      (.builderInput.sha256 | test("^[0-9a-f]{64}$"))
    )
  ' "$manifest" >/dev/null

  echo "Verified database: $actual_bytes bytes, SHA-256 $actual_sha"
  echo "Build identifier: $(jq -r '.output.buildIdentifier' "$manifest")"
}

require_command jq
require_command curl
require_command awk

if [[ ! -f "$database_path" ]]; then
  echo "Database not found: $database_path" >&2
  exit 66
fi

if [[ ! -f "$manifest_path" ]]; then
  echo "Manifest not found: $manifest_path" >&2
  exit 66
fi

verify_pair "$database_path" "$manifest_path"

if [[ "$mode" == "verify" ]]; then
  echo "Verification complete; no objects were uploaded."
  exit 0
fi

require_command wrangler

echo "Publishing database to r2://$bucket/$database_key"
wrangler r2 object put "$bucket/$database_key" \
  --remote \
  --file "$database_path" \
  --content-type application/octet-stream \
  --cache-control 'public, max-age=300, must-revalidate'

echo "Publishing manifest to r2://$bucket/$manifest_key"
wrangler r2 object put "$bucket/$manifest_key" \
  --remote \
  --file "$manifest_path" \
  --content-type application/json \
  --cache-control 'public, max-age=300, must-revalidate'

downloaded_database=$(mktemp /tmp/swift-ip2asn-database.XXXXXX)
downloaded_manifest=$(mktemp /tmp/swift-ip2asn-manifest.XXXXXX)
trap 'rm -f "$downloaded_database" "$downloaded_manifest"' EXIT

curl --fail --silent --show-error --location \
  "$public_database_url" --output "$downloaded_database"
curl --fail --silent --show-error --location \
  "$public_manifest_url" --output "$downloaded_manifest"
verify_pair "$downloaded_database" "$downloaded_manifest"

etag=$(curl --fail --silent --show-error --head "$public_database_url" \
  | awk 'BEGIN { IGNORECASE = 1 } /^etag:/ { sub(/\r$/, "", $2); print $2; exit }')
if [[ -z "$etag" ]]; then
  echo "Published database did not return an ETag." >&2
  exit 65
fi

conditional_status=$(curl --silent --show-error --output /dev/null \
  --write-out '%{http_code}' --header "If-None-Match: $etag" \
  "$public_database_url")
if [[ "$conditional_status" != "304" ]]; then
  echo "Expected conditional database request to return 304; received $conditional_status." >&2
  exit 65
fi

echo "Published artifacts verified through pkgs.networkweather.com (conditional GET: 304)."
