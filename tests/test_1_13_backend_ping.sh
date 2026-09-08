#!/usr/bin/env bash
# Verifies exercise 1.13: 1_13/Dockerfile packages the example-backend Go
# project (source lives directly in 1_13/) into an image that builds and
# runs the "server" binary, and 1_13/commands documents how to build and
# run it with port 8080 published. The exercise's own success check is
# GET /ping returning "pong".
#
# Tolerant of exactly how the build/run commands in 1_13/commands are
# phrased (image name, build context, published port), the same way the
# 1.10/1.11/1.12 tests are.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_13"
DOCKERFILE="$TARGET_DIR/Dockerfile"
COMMANDS_FILE="$TARGET_DIR/commands"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

CONTAINER="dod-1-13-backend-test"

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

[ -f "$DOCKERFILE" ] || fail "1_13/Dockerfile not found"
[ -f "$COMMANDS_FILE" ] || fail "1_13/commands not found"
pass "1_13/Dockerfile and 1_13/commands exist"

grep -qE '^\s*FROM\s+golang(:|$|@)' "$DOCKERFILE" \
  || fail "Dockerfile does not start FROM a golang image"
pass "Dockerfile is based on golang"

# Sanity check that the project's own source files are untouched -- the
# exercise explicitly says not to alter them.
[ -f "$TARGET_DIR/go.mod" ] || fail "1_13/go.mod is missing -- has the project source been altered/removed?"
grep -q '^module server$' "$TARGET_DIR/go.mod" \
  || fail "1_13/go.mod does not look like the original example-backend project"
pass "example-backend project source is present in 1_13/"

grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  || fail "1_13/commands does not contain a docker build command"
BUILD_LINE="$(grep -E 'docker\s+build' "$COMMANDS_FILE" | head -1)"
pass "1_13/commands documents a docker build command"

grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_13/commands does not contain a docker run command"
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
pass "1_13/commands documents a docker run command"

BUILD_IMAGE="$(echo "$BUILD_LINE" | grep -oE '(-t|--tag)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-t|--tag)[[:space:]=]+//')"
[ -n "$BUILD_IMAGE" ] || fail "could not read the image name/tag (a \"-t <name>\" argument) out of the docker build command in 1_13/commands"
pass "build tags the image \"$BUILD_IMAGE\""

# Build context, tolerant of being relative to 1_13/, tehtavat/, the repo
# root, or given as-is (source lives directly in 1_13/, so "." is expected,
# but don't assume it).
BUILD_CONTEXT_RAW="$(echo "$BUILD_LINE" | awk '{print $NF}')"
BUILD_CONTEXT=""
for candidate in \
  "$TARGET_DIR/$BUILD_CONTEXT_RAW" \
  "$REPO_ROOT/$BUILD_CONTEXT_RAW" \
  "$(dirname "$REPO_ROOT")/$BUILD_CONTEXT_RAW" \
  "$BUILD_CONTEXT_RAW"
do
  if [ -d "$candidate" ]; then
    BUILD_CONTEXT="$candidate"
    break
  fi
done
[ -n "$BUILD_CONTEXT" ] || fail "build context \"$BUILD_CONTEXT_RAW\" from 1_13/commands could not be resolved to an existing directory"
pass "build context resolves to $BUILD_CONTEXT"

# Parsed position-aware: a -p typed after the image name is not a valid
# docker option there, so it must not count.
RUN_PORT_RAW="$(docker_run_parse "$RUN_LINE" | cut -f2)"
[ -n "$RUN_PORT_RAW" ] || fail "1_13/commands' docker run command does not publish a port with -p/--publish before the image name"
HOST_PORT="$(echo "$RUN_PORT_RAW" | grep -oE '^[0-9]+')"
[ -n "$HOST_PORT" ] || fail "could not read the host port out of the -p/--publish argument in 1_13/commands"
[ "$HOST_PORT" = "8080" ] || fail "1_13/commands publishes host port $HOST_PORT, but the app must be accessible on host port 8080"
pass "run command publishes host port $HOST_PORT"

# Container-side port from the same -p/--publish argument (the part after
# ":", or the same value as the host port if no ":" was given).
if [[ "$RUN_PORT_RAW" == *:* ]]; then
  RUN_CONTAINER_PORT="$(echo "$RUN_PORT_RAW" | awk -F: '{print $NF}' | grep -oE '^[0-9]+')"
else
  RUN_CONTAINER_PORT="$HOST_PORT"
fi
[ -n "$RUN_CONTAINER_PORT" ] || fail "could not read the container-side port out of the -p/--publish argument in 1_13/commands"

# The port the app actually listens on: app.go defaults to 8080 but honors
# a PORT env var, so an ENV PORT=... set in the Dockerfile overrides that
# default.
APP_PORT="$(grep -oE '^\s*ENV\s+PORT[[:space:]=]+[0-9]+' "$DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$APP_PORT" ] || APP_PORT="8080"

[ "$RUN_CONTAINER_PORT" = "$APP_PORT" ] \
  || fail "port mismatch: 1_13/commands' docker run publishes container port $RUN_CONTAINER_PORT, but the app listens on port $APP_PORT"
pass "1_13/commands and the app agree it listens on port $APP_PORT"

# Respect an explicit --platform on the build command (M1/M2 Macs may need
# it per the exercise's own tip), but don't require one.
PLATFORM_MATCH="$(echo "$BUILD_LINE" | grep -oE -- '--platform[[:space:]=]+[^[:space:]]+' | head -1)"
BUILD_PLATFORM_ARGS=()
if [ -n "$PLATFORM_MATCH" ]; then
  PLATFORM_VALUE="$(echo "$PLATFORM_MATCH" | sed -E 's/^--platform[[:space:]=]+//')"
  BUILD_PLATFORM_ARGS=(--platform "$PLATFORM_VALUE")
  pass "build command specifies --platform $PLATFORM_VALUE"
fi

echo "Building the backend image -- this involves a Go build and may take a while..."
docker build ${BUILD_PLATFORM_ARGS[@]+"${BUILD_PLATFORM_ARGS[@]}"} -t "$BUILD_IMAGE" -f "$DOCKERFILE" "$BUILD_CONTEXT" >/dev/null 2>&1 \
  || fail "docker build failed for 1_13/Dockerfile with context $BUILD_CONTEXT"
pass "$BUILD_IMAGE image builds"

docker run -d --name "$CONTAINER" -p "$HOST_PORT:$RUN_CONTAINER_PORT" "$BUILD_IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for $BUILD_IMAGE, publishing port $HOST_PORT"
pass "$BUILD_IMAGE container started, publishing port $HOST_PORT"

wait_for_pong() {
  for _ in $(seq 1 30); do
    local body
    body="$(curl -s --max-time 2 "http://localhost:$HOST_PORT/ping" 2>/dev/null)"
    [ "$body" = "pong" ] && return 0
    sleep 1
  done
  return 1
}
wait_for_pong \
  || fail "http://localhost:$HOST_PORT/ping never returned \"pong\" (check docker logs $CONTAINER)"
pass "GET /ping returns \"pong\""

echo "All tests passed"
