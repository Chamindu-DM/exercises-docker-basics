#!/usr/bin/env bash
# Verifies exercise 1.7: 1_07/Dockerfile builds an ubuntu:24.04 based image
# that has curl installed, copies in 1_07/script.sh, and runs it as the
# container's CMD. The script prompts for a website, curls it, and loops.
# Checked by building the image, spinning up a local HTTP server the
# container can reach (instead of depending on a real external website,
# which would make the test flaky / require internet access), feeding the
# server's address into the running container's stdin, and confirming the
# container's output contains the prompts and the actual curled response
# body.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_07"
DOCKERFILE="$TARGET_DIR/Dockerfile"
SCRIPT_FILE="$TARGET_DIR/script.sh"

IMAGE="dod-1-7-curler:test"
CONTAINER="dod-1-7-curler-test"
HTTP_PORT=8917
HTTP_DIR="$(mktemp -d)"
HTTP_PID=""

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  [ -n "$HTTP_PID" ] && kill "$HTTP_PID" >/dev/null 2>&1
  rm -rf "$HTTP_DIR"
}
trap cleanup EXIT

[ -f "$DOCKERFILE" ] || fail "1_07/Dockerfile not found"
[ -f "$SCRIPT_FILE" ] || fail "1_07/script.sh not found"
pass "1_07/Dockerfile and 1_07/script.sh exist"

# Static checks on the Dockerfile itself.
grep -qE '^\s*FROM\s+ubuntu:24\.04' "$DOCKERFILE" \
  || fail "Dockerfile does not start FROM ubuntu:24.04"
pass "Dockerfile is based on ubuntu:24.04"

grep -qE '(apt-get|apt)[^\n]*install[^\n]*curl' "$DOCKERFILE" \
  || fail "Dockerfile does not install curl"
pass "Dockerfile installs curl"

grep -qE '^\s*COPY\s+' "$DOCKERFILE" \
  || fail "Dockerfile does not COPY the script into the image"
pass "Dockerfile copies the script into the image"

grep -qE '^\s*(CMD|ENTRYPOINT)\s+' "$DOCKERFILE" \
  || fail "Dockerfile has no CMD or ENTRYPOINT instruction to run the script"
pass "Dockerfile sets a CMD or ENTRYPOINT"

docker build -t "$IMAGE" "$TARGET_DIR" >/dev/null 2>&1 \
  || fail "docker build failed for 1_07/Dockerfile"
pass "curler image builds"

# Serve a unique marker string over HTTP on the host so the container has
# something real (but not internet-dependent) to curl.
MARKER="dod-1-7-marker-$RANDOM-$RANDOM"
echo "$MARKER" > "$HTTP_DIR/index.html"
python3 -m http.server "$HTTP_PORT" --directory "$HTTP_DIR" >/dev/null 2>&1 &
HTTP_PID=$!

wait_for_http() {
  for _ in $(seq 1 15); do
    curl -s --max-time 2 "http://localhost:$HTTP_PORT" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}
wait_for_http || fail "local test HTTP server never came up"
pass "local test HTTP server is up"

# Feed the running container the host's address as the "website" input via a
# FIFO, then give it a few seconds to curl it before force-killing the
# (infinitely looping) container with "docker rm -f" -- a plain SIGTERM (as
# sent by e.g. the "timeout" command) is not reliably forwarded by the
# docker CLI to the container process, so we kill it the same, guaranteed
# way the cleanup trap does.
STDIN_FIFO="$HTTP_DIR/stdin.fifo"
OUTPUT_FILE="$HTTP_DIR/output.log"
mkfifo "$STDIN_FIFO"

docker run -i --rm --name "$CONTAINER" \
  --add-host=host.docker.internal:host-gateway "$IMAGE" \
  <"$STDIN_FIFO" >"$OUTPUT_FILE" 2>&1 &
RUN_PID=$!

exec 3>"$STDIN_FIFO"
printf 'host.docker.internal:%s\n' "$HTTP_PORT" >&3
exec 3>&-

# Poll for the marker to show up instead of guessing a fixed delay -- how
# long the container takes to start and run its first curl varies.
for _ in $(seq 1 30); do
  grep -q "$MARKER" "$OUTPUT_FILE" 2>/dev/null && break
  sleep 0.5
done

docker rm -f "$CONTAINER" >/dev/null 2>&1
wait "$RUN_PID" 2>/dev/null
OUTPUT="$(cat "$OUTPUT_FILE")"

echo "$OUTPUT" | grep -q "Input website:" \
  || fail "container output did not contain the \"Input website:\" prompt"
pass "container prompts for a website"

echo "$OUTPUT" | grep -q "Searching.." \
  || fail "container output did not contain the \"Searching..\" message"
pass "container prints \"Searching..\" after reading input"

echo "$OUTPUT" | grep -q "$MARKER" \
  || fail "container did not curl the given website and print its response (marker not found in output)"
pass "container actually curled the given website and printed the response"

echo "All tests passed"
