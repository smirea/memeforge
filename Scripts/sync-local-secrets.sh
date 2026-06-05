#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ ! -f .env.local ]; then
	echo "Missing .env.local. Run env-manager down if this project is synced, or create .env.local with GIPHY_API_KEY and GEMINI_API_KEY." >&2
	exit 1
fi

value_for() {
	key=$1
	awk -v key="$key" '
		function trim(value) {
			sub(/^[[:space:]]+/, "", value)
			sub(/[[:space:]]+$/, "", value)
			return value
		}

		/^[[:space:]]*($|#)/ { next }

		{
			line = $0
			sub(/^[[:space:]]*export[[:space:]]+/, "", line)
			pattern = "^[[:space:]]*" key "[[:space:]]*="
			if (line !~ pattern) next

			sub(pattern, "", line)
			value = trim(line)
			if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
				value = substr(value, 2, length(value) - 2)
			} else {
				sub(/[[:space:]]+#.*$/, "", value)
				value = trim(value)
			}
			found = value
		}

		END {
			if (found != "") print found
		}
	' .env.local
}

giphy_api_key=$(value_for GIPHY_API_KEY)
gemini_api_key=$(value_for GEMINI_API_KEY)

if [ -z "$giphy_api_key" ] || [ -z "$gemini_api_key" ]; then
	echo ".env.local must define non-empty GIPHY_API_KEY and GEMINI_API_KEY." >&2
	exit 1
fi

mkdir -p Config
umask 077
{
	printf "GIPHY_API_KEY = %s\n" "$giphy_api_key"
	printf "GEMINI_API_KEY = %s\n" "$gemini_api_key"
} > Config/LocalSecrets.xcconfig

echo "Wrote Config/LocalSecrets.xcconfig"
