#!/usr/bin/env bash
# Verifies exercise 1.11: 1_11/Dockerfile packages the old Java 8 Spring
# Boot project in ../spring-example-project into a runnable image, and
# 1_11/commands documents how to build and run it. The exercise is
# complete when pressing the button in the browser shows a "Success"
# message -- checked here by driving the same GET / then POST /press
# request cycle a browser click would trigger.
#
# Tolerant of exactly how the build/run commands in 1_11/commands are
# phrased: the image name/tag, the build context path, and the published
# port are all read back out of the file instead of assumed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_11"
DOCKERFILE="$TARGET_DIR/Dockerfile"
COMMANDS_FILE="$TARGET_DIR/commands"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

CONTAINER="dod-1-11-spring-example-test"

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

[ -f "$DOCKERFILE" ] || fail "1_11/Dockerfile not found"
[ -f "$COMMANDS_FILE" ] || fail "1_11/commands not found"
pass "1_11/Dockerfile and 1_11/commands exist"

grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  || fail "1_11/commands does not contain a docker build command"
BUILD_LINE="$(grep -E 'docker\s+build' "$COMMANDS_FILE" | head -1)"
pass "1_11/commands documents a docker build command"

grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_11/commands does not contain a docker run command"
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
pass "1_11/commands documents a docker run command"

# Image name/tag -- read it back instead of assuming "spring-example".
BUILD_IMAGE="$(echo "$BUILD_LINE" | grep -oE '(-t|--tag)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-t|--tag)[[:space:]=]+//')"
[ -n "$BUILD_IMAGE" ] || fail "could not read the image name/tag (a \"-t <name>\" argument) out of the docker build command in 1_11/commands"
pass "build tags the image \"$BUILD_IMAGE\""

# Build context -- the last whitespace-separated token on the build line,
# unless -f/--file is used and the context is actually an earlier token
# (docker build [opts] -f <dockerfile> <context> or <context> -f
# <dockerfile>). Try candidate resolutions relative to 1_11/, tehtavat/,
# the repo root, and as given, same as exercise 1.10.
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
[ -n "$BUILD_CONTEXT" ] || fail "build context \"$BUILD_CONTEXT_RAW\" from 1_11/commands could not be resolved to an existing directory"
pass "build context resolves to $BUILD_CONTEXT"

# -f/--file, if present, points at the actual Dockerfile to use -- resolve
# it the same tolerant way, otherwise fall back to 1_11/Dockerfile.
DOCKERFILE_ARG="$(echo "$BUILD_LINE" | grep -oE '(-f|--file)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-f|--file)[[:space:]=]+//')"
if [ -n "$DOCKERFILE_ARG" ]; then
  BUILD_DOCKERFILE=""
  for candidate in \
    "$TARGET_DIR/$DOCKERFILE_ARG" \
    "$REPO_ROOT/$DOCKERFILE_ARG" \
    "$DOCKERFILE_ARG"
  do
    if [ -f "$candidate" ]; then
      BUILD_DOCKERFILE="$candidate"
      break
    fi
  done
  [ -n "$BUILD_DOCKERFILE" ] || fail "-f/--file argument \"$DOCKERFILE_ARG\" from 1_11/commands could not be resolved to an existing file"
else
  BUILD_DOCKERFILE="$DOCKERFILE"
fi
pass "Dockerfile resolves to $BUILD_DOCKERFILE"

# Port -- read out of -p/--publish HOST[:CONTAINER], any spacing/= form.
# Parsed position-aware: a -p typed after the image name is not a valid
# docker option there (docker would pass it as a container argument
# instead), so it must not count -- docker_run_parse enforces that.
RUN_PORT_RAW="$(docker_run_parse "$RUN_LINE" | cut -f2)"
[ -n "$RUN_PORT_RAW" ] || fail "1_11/commands' docker run command does not publish a port with -p/--publish before the image name"
HOST_PORT="$(echo "$RUN_PORT_RAW" | grep -oE '^[0-9]+')"
[ -n "$HOST_PORT" ] || fail "could not read the host port out of the -p/--publish argument in 1_11/commands"
pass "run command publishes host port $HOST_PORT"

echo "Building the Spring image -- this involves a Maven build and may take a while..."
docker build -t "$BUILD_IMAGE" -f "$BUILD_DOCKERFILE" "$BUILD_CONTEXT" >/dev/null 2>&1 \
  || fail "docker build failed for $BUILD_DOCKERFILE with context $BUILD_CONTEXT"
pass "$BUILD_IMAGE image builds"

docker run -d --name "$CONTAINER" -p "$HOST_PORT:8080" "$BUILD_IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for $BUILD_IMAGE, publishing port $HOST_PORT"
pass "$BUILD_IMAGE container started, publishing port $HOST_PORT"

wait_for_http() {
  for _ in $(seq 1 60); do
    curl -s --max-time 2 "http://localhost:$HOST_PORT/" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}
wait_for_http || fail "http://localhost:$HOST_PORT/ never became reachable (Spring Boot startup can be slow -- check docker logs $CONTAINER)"
pass "http://localhost:$HOST_PORT/ is reachable"

GET_BODY="$(curl -s --max-time 5 "http://localhost:$HOST_PORT/")"
echo "$GET_BODY" | grep -qi "press here" \
  || fail "GET / did not return the expected \"Press here\" button page"
pass "GET / shows the button page"

POST_BODY="$(curl -s --max-time 5 -X POST "http://localhost:$HOST_PORT/press")"
echo "$POST_BODY" | grep -q "Success" \
  || fail "POST /press (pressing the button) did not return a \"Success\" message: $POST_BODY"
pass "pressing the button (POST /press) shows the \"Success\" message"

echo "All tests passed"
