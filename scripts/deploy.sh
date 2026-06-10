#!/usr/bin/env bash
set -euo pipefail

api_base="${ASC_API_BASE:-https://api.appstoreconnect.apple.com}"
branch="${1:-${XCODE_CLOUD_BRANCH:-${BRANCH:-master}}}"
key_id="${ASC_KEY_ID:-${APP_STORE_CONNECT_KEY_ID:-}}"
issuer_id="${ASC_ISSUER_ID:-${APP_STORE_CONNECT_ISSUER_ID:-}}"
key_path="${ASC_KEY_PATH:-${APP_STORE_CONNECT_PRIVATE_KEY_PATH:-${APP_STORE_CONNECT_API_KEY_PATH:-}}}"
workflow_id="${XCODE_CLOUD_WORKFLOW_ID:-${CI_WORKFLOW_ID:-}}"
repository_id="${XCODE_CLOUD_REPOSITORY_ID:-${SCM_REPOSITORY_ID:-}}"

usage() {
	cat <<'EOF'
Usage:
  XCODE_CLOUD_WORKFLOW_ID=... ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... scripts/deploy.sh [branch]

Environment:
  XCODE_CLOUD_WORKFLOW_ID       Required Xcode Cloud workflow ID.
  ASC_KEY_ID                    Required App Store Connect API key ID.
  ASC_ISSUER_ID                 Required App Store Connect issuer ID.
  ASC_KEY_PATH                  Required path to the downloaded .p8 API key.
  XCODE_CLOUD_REPOSITORY_ID     Optional SCM repository ID. Inferred from the workflow when omitted.

Aliases:
  APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_PRIVATE_KEY_PATH,
  APP_STORE_CONNECT_API_KEY_PATH, CI_WORKFLOW_ID, SCM_REPOSITORY_ID.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

require_value() {
	local name="$1"
	local value="$2"
	if [[ -z "$value" ]]; then
		printf 'Missing required environment variable: %s\n\n' "$name" >&2
		usage >&2
		exit 1
	fi
}

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf 'Missing required command: %s\n' "$1" >&2
		exit 1
	fi
}

require_value "XCODE_CLOUD_WORKFLOW_ID" "$workflow_id"
require_value "ASC_KEY_ID" "$key_id"
require_value "ASC_ISSUER_ID" "$issuer_id"
require_value "ASC_KEY_PATH" "$key_path"

if [[ ! -f "$key_path" ]]; then
	printf 'ASC_KEY_PATH does not point to a file: %s\n' "$key_path" >&2
	exit 1
fi

require_command curl
require_command openssl
require_command python3

token="$(
	ASC_KEY_ID="$key_id" ASC_ISSUER_ID="$issuer_id" ASC_KEY_PATH="$key_path" python3 <<'PY'
import base64
import json
import os
import subprocess
import time


def b64url(data):
	return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def read_len(data, index):
	first = data[index]
	index += 1
	if first < 0x80:
		return first, index
	count = first & 0x7F
	value = int.from_bytes(data[index:index + count], "big")
	return value, index + count


def read_int(data, index):
	if data[index] != 0x02:
		raise ValueError("Invalid ECDSA signature")
	index += 1
	length, index = read_len(data, index)
	value = data[index:index + length]
	value = value.lstrip(b"\x00")
	if len(value) > 32:
		raise ValueError("Invalid P-256 integer length")
	return value.rjust(32, b"\x00"), index + length


def der_to_raw(signature):
	if signature[0] != 0x30:
		raise ValueError("Invalid ECDSA signature")
	length, index = read_len(signature, 1)
	end = index + length
	r, index = read_int(signature, index)
	s, index = read_int(signature, index)
	if index != end:
		raise ValueError("Invalid ECDSA signature")
	return r + s


now = int(time.time())
header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
payload = {
	"iss": os.environ["ASC_ISSUER_ID"],
	"iat": now,
	"exp": now + 1200,
	"aud": "appstoreconnect-v1",
}
signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}".encode()
signature_der = subprocess.check_output(
	["openssl", "dgst", "-sha256", "-binary", "-sign", os.environ["ASC_KEY_PATH"]],
	input=signing_input,
)
print(f"{signing_input.decode()}.{b64url(der_to_raw(signature_der))}")
PY
)"

api_get() {
	curl --fail-with-body -sS \
		-H "Authorization: Bearer $token" \
		-H "Content-Type: application/json" \
		"$1"
}

if [[ -z "$repository_id" ]]; then
	printf 'Resolving repository from workflow %s...\n' "$workflow_id"
	workflow_json="$(api_get "$api_base/v1/ciWorkflows/$workflow_id?include=repository")"
	repository_id="$(
		python3 -c 'import json, sys; payload = json.load(sys.stdin); repo = payload.get("data", {}).get("relationships", {}).get("repository", {}).get("data", {}); print(repo.get("id", ""))' <<<"$workflow_json"
	)"
	if [[ -z "$repository_id" ]]; then
		printf 'Could not infer repository ID from workflow. Set XCODE_CLOUD_REPOSITORY_ID.\n' >&2
		exit 1
	fi
fi

printf 'Resolving branch %s in repository %s...\n' "$branch" "$repository_id"
git_reference_id=""
refs_url="$api_base/v1/scmRepositories/$repository_id/gitReferences?limit=200"
while [[ -n "$refs_url" && -z "$git_reference_id" ]]; do
	refs_json="$(api_get "$refs_url")"
	git_reference_id="$(
		python3 -c '
import json
import sys

branch = sys.argv[1]
payload = json.load(sys.stdin)
for item in payload.get("data", []):
	attributes = item.get("attributes", {})
	if attributes.get("kind") != "BRANCH":
		continue
	if attributes.get("name") == branch or attributes.get("canonicalName") == f"refs/heads/{branch}":
		print(item["id"])
		break
' "$branch" <<<"$refs_json"
	)"
	if [[ -n "$git_reference_id" ]]; then
		break
	fi
	refs_url="$(
		python3 -c 'import json, sys; payload = json.load(sys.stdin); print(payload.get("links", {}).get("next") or "")' <<<"$refs_json"
	)"
done

if [[ -z "$git_reference_id" ]]; then
	printf 'Could not find branch %s for repository %s.\n' "$branch" "$repository_id" >&2
	exit 1
fi

body="$(
	python3 - "$workflow_id" "$git_reference_id" <<'PY'
import json
import sys

workflow_id, git_reference_id = sys.argv[1:3]
print(json.dumps({
	"data": {
		"type": "ciBuildRuns",
		"attributes": {},
		"relationships": {
			"workflow": {
				"data": {
					"type": "ciWorkflows",
					"id": workflow_id,
				},
			},
			"sourceBranchOrTag": {
				"data": {
					"type": "scmGitReferences",
					"id": git_reference_id,
				},
			},
		},
	},
}, separators=(",", ":")))
PY
)"

printf 'Starting Xcode Cloud workflow %s for %s...\n' "$workflow_id" "$branch"
response="$(
	printf '%s' "$body" | curl --fail-with-body -sS \
		-X POST \
		-H "Authorization: Bearer $token" \
		-H "Content-Type: application/json" \
		--data-binary @- \
		"$api_base/v1/ciBuildRuns"
)"

python3 -c '
import json
import sys

payload = json.load(sys.stdin)
data = payload.get("data", {})
build_id = data.get("id", "")
number = data.get("attributes", {}).get("number")
suffix = f" #{number}" if number is not None else ""
print(f"Started Xcode Cloud build{suffix}: {build_id}")
' <<<"$response"
