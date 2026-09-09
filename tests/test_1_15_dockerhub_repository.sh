#!/usr/bin/env bash
# Verifies exercise 1.15: 1_15/repository contains a link to a public Docker
# Hub repository, in the form "username/repository", the image actually
# exists (and is public), and the repository has a non-empty overview
# (the Docker Hub "full_description").
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_FILE="$REPO_ROOT/1_15/repository"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$REPO_FILE" ] || fail "1_15/repository not found"
pass "1_15/repository exists"

CONTENT="$(tr -d '[:space:]' < "$REPO_FILE")"
[ -n "$CONTENT" ] || fail "1_15/repository is empty"

# Docker Hub repo names: lowercase letters, digits, underscores, dashes,
# periods, exactly one "/" separating namespace and repository name.
NAME_RE='[a-z0-9]+([._-][a-z0-9]+)*'
[[ "$CONTENT" =~ ^${NAME_RE}/${NAME_RE}$ ]] \
  || fail "1_15/repository content \"$CONTENT\" is not of the form username/repository"
pass "1_15/repository content \"$CONTENT\" is of the form username/repository"

API_URL="https://hub.docker.com/v2/repositories/$CONTENT/"
HTTP_CODE="$(curl -s -o /tmp/dockerhub_1_15_response.json -w '%{http_code}' "$API_URL")"
[ "$HTTP_CODE" = "200" ] \
  || fail "Docker Hub repository \"$CONTENT\" does not exist or is not reachable (HTTP $HTTP_CODE from $API_URL)"
pass "Docker Hub repository \"$CONTENT\" exists"

BODY="$(cat /tmp/dockerhub_1_15_response.json)"
rm -f /tmp/dockerhub_1_15_response.json

IS_PRIVATE="$(echo "$BODY" | grep -oE '"is_private"\s*:\s*(true|false)' | grep -oE 'true|false')"
[ "$IS_PRIVATE" = "false" ] \
  || fail "Docker Hub repository \"$CONTENT\" is private -- it must be public"
pass "Docker Hub repository \"$CONTENT\" is public"

FULL_DESCRIPTION="$(echo "$BODY" | grep -oE '"full_description"\s*:\s*"([^"\\]|\\.)*"' | sed -E 's/^"full_description"\s*:\s*"//; s/"$//')"
[ -n "$FULL_DESCRIPTION" ] \
  || fail "Docker Hub repository \"$CONTENT\" has no overview (full_description) -- add a description and usage instructions on the Docker Hub page"
pass "Docker Hub repository \"$CONTENT\" has a non-empty overview"

echo "$FULL_DESCRIPTION" | grep -qiE 'docker run' \
  || fail "Docker Hub repository \"$CONTENT\" overview does not contain an example \"docker run\" command"
pass "Docker Hub repository \"$CONTENT\" overview contains a \"docker run\" example"

echo "All tests passed"
