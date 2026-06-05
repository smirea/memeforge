#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir/.."

value_for() {
	key=$1
	env_value=""
	case "$key" in
		GIPHY_API_KEY) env_value=${GIPHY_API_KEY:-} ;;
		GEMINI_API_KEY) env_value=${GEMINI_API_KEY:-} ;;
	esac

	if [ -n "$(printf '%s' "$env_value" | tr -d '[:space:]')" ]; then
		printf '%s\n' "$env_value"
		return
	fi

	if [ ! -f .env.local ]; then
		return
	fi

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
	echo "Missing secrets. Set GIPHY_API_KEY and GEMINI_API_KEY in the environment, or create .env.local with non-empty values." >&2
	exit 1
fi

mkdir -p Config
umask 077
{
	printf "GIPHY_API_KEY = %s\n" "$giphy_api_key"
	printf "GEMINI_API_KEY = %s\n" "$gemini_api_key"
} > Config/LocalSecrets.xcconfig

echo "Wrote Config/LocalSecrets.xcconfig"
