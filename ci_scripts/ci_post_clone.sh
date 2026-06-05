#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

: "${GIPHY_API_KEY:?GIPHY_API_KEY is required}"
: "${GEMINI_API_KEY:?GEMINI_API_KEY is required}"

mkdir -p "$repo_root/Config"
umask 077
{
	printf "GIPHY_API_KEY = %s\n" "$GIPHY_API_KEY"
	printf "GEMINI_API_KEY = %s\n" "$GEMINI_API_KEY"
} > "$repo_root/Config/LocalSecrets.xcconfig"

echo "Wrote Config/LocalSecrets.xcconfig"
