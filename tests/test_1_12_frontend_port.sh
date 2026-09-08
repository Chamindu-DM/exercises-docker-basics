#!/usr/bin/env bash
# Verifies exercise 1.12: 1_12/Dockerfile packages the example-frontend
# project (its source lives directly in 1_12/, unlike exercise 1.11's
# separate project directory) into an Ubuntu-based image that builds the
# React app and serves it on port 5001, and 1_12/commands documents how to
# build and run it.
#
# The exercise's own "success" signal is the frontend's exercise-1.12 entry
# (AmIRunning.js), which renders a base64-decoded message -- "Congratulations!
# You configured your ports correctly!" -- once the page loads, so we check
# for exactly that with a real browser (the raw HTML is just an empty React
# shell before its JS bundle runs). We also wait for the
# "Accepting connections at http://localhost:5001" line the exercise
# describes, since it takes a few seconds to appear.
#
# Tolerant of exactly how the build/run commands in 1_12/commands are
# phrased, the same way the 1.10/1.11 tests are.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_12"
DOCKERFILE="$TARGET_DIR/Dockerfile"
COMMANDS_FILE="$TARGET_DIR/commands"
PLAYWRIGHT_DIR="$REPO_ROOT/tests/playwright"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

CONTAINER="dod-1-12-frontend-test"

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

[ -f "$DOCKERFILE" ] || fail "1_12/Dockerfile not found"
[ -f "$COMMANDS_FILE" ] || fail "1_12/commands not found"
pass "1_12/Dockerfile and 1_12/commands exist"

grep -qE '^\s*FROM\s+ubuntu(:|$|@)' "$DOCKERFILE" \
  || fail "Dockerfile does not start FROM ubuntu"
pass "Dockerfile is based on ubuntu"

# Sanity check that the project's own source files are untouched -- the
# exercise explicitly says not to alter them.
[ -f "$TARGET_DIR/package.json" ] || fail "1_12/package.json is missing -- has the project source been altered/removed?"
grep -q '"name": "example-frontend"' "$TARGET_DIR/package.json" \
  || fail "1_12/package.json does not look like the original example-frontend project"
pass "example-frontend project source is present in 1_12/"

grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  || fail "1_12/commands does not contain a docker build command"
BUILD_LINE="$(grep -E 'docker\s+build' "$COMMANDS_FILE" | head -1)"
pass "1_12/commands documents a docker build command"

grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_12/commands does not contain a docker run command"
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
pass "1_12/commands documents a docker run command"

BUILD_IMAGE="$(echo "$BUILD_LINE" | grep -oE '(-t|--tag)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-t|--tag)[[:space:]=]+//')"
[ -n "$BUILD_IMAGE" ] || fail "could not read the image name/tag (a \"-t <name>\" argument) out of the docker build command in 1_12/commands"
pass "build tags the image \"$BUILD_IMAGE\""

# Build context, tolerant of being relative to 1_12/, tehtavat/, the repo
# root, or given as-is (source lives directly in 1_12/, so "." is expected,
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
[ -n "$BUILD_CONTEXT" ] || fail "build context \"$BUILD_CONTEXT_RAW\" from 1_12/commands could not be resolved to an existing directory"
pass "build context resolves to $BUILD_CONTEXT"

# Parsed position-aware: a -p typed after the image name is not a valid
# docker option there, so it must not count.
RUN_PORT_RAW="$(docker_run_parse "$RUN_LINE" | cut -f2)"
[ -n "$RUN_PORT_RAW" ] || fail "1_12/commands' docker run command does not publish a port with -p/--publish before the image name"
HOST_PORT="$(echo "$RUN_PORT_RAW" | grep -oE '^[0-9]+')"
[ -n "$HOST_PORT" ] || fail "could not read the host port out of the -p/--publish argument in 1_12/commands"
[ "$HOST_PORT" = "5001" ] || fail "1_12/commands publishes host port $HOST_PORT, but the app must be accessible on host port 5001"
pass "run command publishes host port $HOST_PORT"

# Container-side port from the same -p/--publish argument (the part after
# ":", or the same value as the host port if no ":" was given).
if [[ "$RUN_PORT_RAW" == *:* ]]; then
  RUN_CONTAINER_PORT="$(echo "$RUN_PORT_RAW" | awk -F: '{print $NF}' | grep -oE '^[0-9]+')"
else
  RUN_CONTAINER_PORT="$HOST_PORT"
fi
[ -n "$RUN_CONTAINER_PORT" ] || fail "could not read the container-side port out of the -p/--publish argument in 1_12/commands"

# The port the image actually serves on, per the Dockerfile's CMD (the
# "serve -l <port>" argument).
DOCKERFILE_PORT="$(grep -oE '"-l"[[:space:]]*,[[:space:]]*"[0-9]+"' "$DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$DOCKERFILE_PORT" ] || DOCKERFILE_PORT="$(grep -oE '\-l[[:space:]]+[0-9]+' "$DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$DOCKERFILE_PORT" ] || fail "could not determine the port 1_12/Dockerfile's CMD serves on (expected a \"serve -l <port>\" argument)"

[ "$RUN_CONTAINER_PORT" = "$DOCKERFILE_PORT" ] \
  || fail "port mismatch: 1_12/commands' docker run publishes container port $RUN_CONTAINER_PORT, but 1_12/Dockerfile serves on port $DOCKERFILE_PORT"
pass "1_12/commands and 1_12/Dockerfile agree the app serves on port $DOCKERFILE_PORT"

echo "Building the frontend image -- this involves an npm install/build and may take a while..."
docker build -t "$BUILD_IMAGE" -f "$DOCKERFILE" "$BUILD_CONTEXT" >/dev/null 2>&1 \
  || fail "docker build failed for 1_12/Dockerfile with context $BUILD_CONTEXT"
pass "$BUILD_IMAGE image builds"

docker run -d --name "$CONTAINER" -p "$HOST_PORT:$RUN_CONTAINER_PORT" "$BUILD_IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for $BUILD_IMAGE, publishing port $HOST_PORT"
pass "$BUILD_IMAGE container started, publishing port $HOST_PORT"

wait_for_log() {
  for _ in $(seq 1 20); do
    docker logs "$CONTAINER" 2>&1 | grep -q "Accepting connections" && return 0
    sleep 1
  done
  return 1
}
wait_for_log \
  || fail "container never logged \"Accepting connections\" (check docker logs $CONTAINER)"
pass "container logged \"Accepting connections ...\""

# The page is a client-side rendered React app -- a real browser is needed
# to see exercise 1.12's own success message (AmIRunning.js decodes and
# renders it once the JS bundle runs), rather than curling the raw HTML.
command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
NODE_MAJOR="$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 20 ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
  # Playwright requires Node 20+; fall back to an nvm-managed version if the
  # default "node" on PATH is older.
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh"
  # Prefer the lowest available >=20 version, not the highest -- a much
  # newer major (e.g. 24.x) has been observed to produce a broken
  # node_modules/.bin/playwright shim (a plain file instead of a symlink,
  # so its relative "require('./lib/program')" resolves to the wrong
  # place) in this environment.
  NEWER_NODE="$(nvm ls --no-colors 2>/dev/null | grep -oE 'v(2[0-9]|[3-9][0-9])\.[0-9]+\.[0-9]+' | sort -V | head -1)"
  [ -n "$NEWER_NODE" ] && nvm use "$NEWER_NODE" >/dev/null 2>&1
fi
command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"

(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

node "$PLAYWRIGHT_DIR/check-page-text.mjs" "http://localhost:$HOST_PORT" \
  "Congratulations! You configured your ports correctly!" \
  || fail "the frontend did not show the expected \"Congratulations!...\" message for exercise 1.12"
pass "frontend shows exercise 1.12's success message in the browser"

echo "All tests passed"
