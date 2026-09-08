#!/usr/bin/env bash
# Verifies exercise 1.10: the exercise explicitly reuses the image already
# built in exercise 1.8 ("In Exercise 1.8 you already did an image...") --
# it's about adding -p to an existing setup, not building anything new -- so
# 1_10/commands must document only a docker run command, no docker build.
# It must run the very same image exercise 1.8 built (that name is read
# back out of 1_08/commands, not assumed to be "web-server"), with its
# port 8080 published to the host -- and the exercise names the exact URL
# to check, http://localhost:8080, so the host port has to actually be
# 8080, not just any port. The port-flag spelling (-p vs --publish, space
# vs "=") is read back out of 1_10/commands instead of being assumed,
# since the exercise only asks for "command(s) used to start the service"
# in whatever form the student wrote them.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_10"
COMMANDS_FILE="$TARGET_DIR/commands"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

CONTAINER="dod-1-10-web-server-test"

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

[ -f "$COMMANDS_FILE" ] || fail "1_10/commands not found"
pass "1_10/commands exists"

grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_10/commands does not contain a docker run command"
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
pass "1_10/commands documents a docker run command"

# Parsed position-aware -- a flag typed after the image name (a real docker
# mistake this test used to be fooled by) is correctly NOT treated as a
# docker option, matching actual docker behaviour.
RUN_PARSED="$(docker_run_parse "$RUN_LINE")"
RUN_IMAGE="$(echo "$RUN_PARSED" | cut -f1)"
RUN_PORT_RAW="$(echo "$RUN_PARSED" | cut -f2)"
RUN_PUBLISH_ALL="$(echo "$RUN_PARSED" | cut -f3)"
[ -n "$RUN_IMAGE" ] || fail "could not read the image name out of the docker run command in 1_10/commands"

# The image run here must be the one exercise 1.8 actually built and
# tagged -- read that name back out of 1_08/commands rather than assuming
# "web-server", so this still works if a different (but consistent) name
# was used there.
BUILD08_COMMANDS="$REPO_ROOT/1_08/commands"
[ -f "$BUILD08_COMMANDS" ] || fail "1_08/commands not found -- needed to know what image name exercise 1.8 built"
BUILD08_LINE="$(grep -E 'docker\s+build' "$BUILD08_COMMANDS" | head -1)"
[ -n "$BUILD08_LINE" ] || fail "1_08/commands has no docker build command to read the image name from"
EXPECTED_IMAGE="$(echo "$BUILD08_LINE" | grep -oE '(-t|--tag)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-t|--tag)[[:space:]=]+//')"
[ -n "$EXPECTED_IMAGE" ] || fail "could not read the image name/tag out of 1_08/commands' docker build command"

[ "$RUN_IMAGE" = "$EXPECTED_IMAGE" ] \
  || fail "1_10/commands runs image \"$RUN_IMAGE\", but exercise 1.8 built \"$EXPECTED_IMAGE\" -- exercise 1.10 must reuse that same image"
pass "1_10/commands runs the same image (\"$EXPECTED_IMAGE\") that exercise 1.8 built"

# Exercise 1.10 reuses the image already built in exercise 1.8 -- a docker
# build command here means the answer rebuilds instead of reusing it, which
# the exercise explicitly says not to do.
grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  && fail "1_10/commands documents a docker build command, but exercise 1.10 says to reuse the image already built in exercise 1.8, not rebuild it"
pass "1_10/commands has no docker build command -- reuses the image from exercise 1.8, as the exercise says"

# The referenced image has to actually exist for the run command to work.
# If it's not present locally (e.g. a fresh checkout that never ran
# exercise 1.8's build), build it from 1_08/ ourselves so the test stays
# self-contained -- this is the test's own bootstrapping, not something
# 1_10/commands is expected to do.
if docker image inspect "$RUN_IMAGE" >/dev/null 2>&1; then
  pass "image \"$RUN_IMAGE\" already exists locally"
else
  FALLBACK_CONTEXT="$REPO_ROOT/1_08"
  [ -d "$FALLBACK_CONTEXT" ] \
    || fail "image \"$RUN_IMAGE\" does not exist locally and there is no 1_08/ directory to build it from"
  docker build -t "$RUN_IMAGE" "$FALLBACK_CONTEXT" >/dev/null 2>&1 \
    || fail "image \"$RUN_IMAGE\" did not exist locally and building it from 1_08/ failed"
  pass "image \"$RUN_IMAGE\" did not exist locally -- built it from 1_08/ for this test run"
fi
IMAGE_TO_RUN="$RUN_IMAGE"

# The run command must publish a host port to the container's 8080, either
# with -p/--publish HOST[:CONTAINER] or with -P (publish all exposed ports,
# in which case Docker picks the host port itself and we read it back with
# "docker port" after starting the container). Both were already parsed
# above, respecting docker's requirement that such flags appear before the
# image name.
if [ -n "$RUN_PORT_RAW" ]; then
  HOST_PORT="$(echo "$RUN_PORT_RAW" | grep -oE '^[0-9]+')"
  [ -n "$HOST_PORT" ] || fail "could not read the host port out of the -p/--publish argument in 1_10/commands"
  pass "run command publishes host port $HOST_PORT"

  docker run -d --name "$CONTAINER" -p "$HOST_PORT:8080" "$IMAGE_TO_RUN" >/dev/null 2>&1 \
    || fail "docker run failed, publishing port $HOST_PORT"
  pass "container started, publishing port $HOST_PORT"
elif [ "$RUN_PUBLISH_ALL" = "1" ]; then
  pass "run command publishes all exposed ports with -P"

  docker run -d --name "$CONTAINER" -P "$IMAGE_TO_RUN" >/dev/null 2>&1 \
    || fail "docker run failed with -P"

  HOST_PORT=""
  for _ in $(seq 1 10); do
    HOST_PORT="$(docker port "$CONTAINER" 8080/tcp 2>/dev/null | head -1 | sed -E 's/^.*:([0-9]+)$/\1/')"
    [ -n "$HOST_PORT" ] && break
    sleep 1
  done
  [ -n "$HOST_PORT" ] || fail "could not determine which host port docker assigned via -P"
  pass "container started, -P assigned host port $HOST_PORT"
else
  fail "1_10/commands' docker run command does not publish a port with -p/--publish or -P"
fi

# The exercise names the exact URL to check -- http://localhost:8080 -- so
# the host port has to actually be 8080, not just some port (which also
# rules out -P in practice, since docker assigns that one itself).
[ "$HOST_PORT" = "8080" ] \
  || fail "host port is $HOST_PORT, but the exercise says to access the service at http://localhost:8080"
pass "host port is 8080, matching the URL the exercise names"

wait_for_http() {
  for _ in $(seq 1 20); do
    curl -s --max-time 2 "http://localhost:$HOST_PORT/" 2>/dev/null | grep -q "You connected to the following path" && return 0
    sleep 1
  done
  return 1
}
wait_for_http \
  || fail "http://localhost:$HOST_PORT/ never returned the expected \"You connected to the following path\" message"
pass "http://localhost:$HOST_PORT/ responds with the expected message"

# Confirm the path in the response reflects the actual requested path, not
# a hardcoded string.
RESPONSE="$(curl -s --max-time 2 "http://localhost:$HOST_PORT/hello")"
echo "$RESPONSE" | grep -q "/hello" \
  || fail "response to /hello did not mention the requested path: $RESPONSE"
pass "service reflects the requested path back in its response"

echo "All tests passed"
