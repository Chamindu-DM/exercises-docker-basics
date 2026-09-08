#!/usr/bin/env bash
# Verifies exercise 1.8: 1_08/Dockerfile builds on top of
# devopsdockeruh/simple-web-service:alpine and uses CMD to supply the
# "server" default argument the base image's ENTRYPOINT needs, so that
# running the resulting image starts the web service without any extra
# arguments on the command line. The image name is read from 1_08/commands
# rather than hardcoded (so a build command formatted differently still
# parses), but the exercise explicitly says to tag the image "web-server",
# so that exact name is enforced rather than accepted as tolerant.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_08"
DOCKERFILE="$TARGET_DIR/Dockerfile"
COMMANDS_FILE="$TARGET_DIR/commands"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

CONTAINER="dod-1-8-web-server-test"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1
}
trap cleanup EXIT

[ -f "$DOCKERFILE" ] || fail "1_08/Dockerfile not found"
[ -f "$COMMANDS_FILE" ] || fail "1_08/commands not found"
pass "1_08/Dockerfile and 1_08/commands exist"

# Static checks on the Dockerfile itself.
grep -qE '^\s*FROM\s+devopsdockeruh/simple-web-service' "$DOCKERFILE" \
  || fail "Dockerfile does not start FROM devopsdockeruh/simple-web-service"
pass "Dockerfile is based on devopsdockeruh/simple-web-service"

grep -qE '^\s*CMD\s+.*server' "$DOCKERFILE" \
  || fail "Dockerfile has no CMD instruction supplying the \"server\" argument"
pass "Dockerfile sets CMD to supply the \"server\" argument"

grep -qE '^\s*ENTRYPOINT\s+' "$DOCKERFILE" \
  && fail "Dockerfile overrides ENTRYPOINT -- it should only add CMD on top of the base image's own ENTRYPOINT"
pass "Dockerfile does not override the base image's ENTRYPOINT"

# The commands file should document a docker build and a docker run.
grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  || fail "1_08/commands does not contain a docker build command"
grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_08/commands does not contain a docker run command"
pass "1_08/commands documents both a build and a run command"

BUILD_LINE="$(grep -E 'docker\s+build' "$COMMANDS_FILE" | head -1)"
IMAGE="$(echo "$BUILD_LINE" | grep -oE '\-t[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
[ -n "$IMAGE" ] || fail "could not read the image name/tag (a \"-t <name>\" argument) out of the docker build command in 1_08/commands"
[ "$IMAGE" = "web-server" ] \
  || fail "image is tagged \"$IMAGE\", but the exercise says to tag it \"web-server\""
pass "image is tagged \"web-server\", as the exercise requires"

# The run command has to actually start that same image -- a typo here
# (e.g. "web-serer") would mean the documented answer doesn't actually
# work, even though the build line is correct.
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
RUN_IMAGE="$(docker_run_parse "$RUN_LINE" | cut -f1)"
[ "$RUN_IMAGE" = "web-server" ] \
  || fail "docker run command starts \"$RUN_IMAGE\", not the \"web-server\" image that was built"
pass "run command starts the \"web-server\" image"

docker build -t "$IMAGE" "$TARGET_DIR" >/dev/null 2>&1 \
  || fail "docker build failed for 1_08/Dockerfile"
pass "$IMAGE image builds"

docker run -d --name "$CONTAINER" "$IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for $IMAGE (does it need arguments to start?)"
pass "$IMAGE container started with no extra arguments"

wait_for_log() {
  local pattern="$1"
  for _ in $(seq 1 15); do
    docker logs "$CONTAINER" 2>&1 | grep -q "$pattern" && return 0
    sleep 1
  done
  return 1
}

wait_for_log "GIN-debug" \
  || fail "container output never contained \"GIN-debug\" -- the server does not seem to have started"
pass "container output contains GIN's debug log lines"

wait_for_log "Listening and serving HTTP on :8080" \
  || fail "container output never contained \"Listening and serving HTTP on :8080\""
pass "container output confirms the server is listening on :8080"

echo "All tests passed"
