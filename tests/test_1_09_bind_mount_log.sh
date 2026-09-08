#!/usr/bin/env bash
# Verifies exercise 1.9: 1_09/commands bind-mounts a host file named
# service.log (in the 1_09/ directory itself) to
# /usr/src/app/text.log inside a devopsdockeruh/simple-web-service
# container, so the timestamps the (command-less) image writes every two
# seconds land on the host filesystem.
#
# Tolerant in two ways, per the exercise's own note about needing the host
# file to already exist before the bind mount (otherwise Docker creates a
# directory there instead of a file):
#  - the *way* the file gets created ahead of time (touch, "> file",
#    "type nul > file", whatever) -- 1_09/commands is not required to use
#    any particular command for it, we just require *some* line before the
#    docker run that isn't itself the run command.
#  - the file *already existing* with content in it (e.g. left over from a
#    previous run of this exercise, or created by a different method) --
#    the app appends rather than truncates, so we don't require the file to
#    start out empty, only that new timestamp lines get appended to
#    whatever was already there.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_09"
COMMANDS_FILE="$TARGET_DIR/commands"
LOG_FILE="$TARGET_DIR/service.log"

CONTAINER="dod-1-9-bind-mount-test"

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

[ -f "$COMMANDS_FILE" ] || fail "1_09/commands not found"
pass "1_09/commands exists"

grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_09/commands does not contain a docker run command"
RUN_LINE="$(grep -E 'docker\s+run' "$COMMANDS_FILE" | head -1)"
pass "1_09/commands documents a docker run command"

# No command/argument should be given to the image -- the exercise relies
# on its default (no-argument) behaviour of logging timestamps, unlike
# exercise 1.8 which supplies "server".
IMAGE_REF="$(echo "$RUN_LINE" | grep -oE 'devopsdockeruh/simple-web-service[^[:space:]]*')"
[ -n "$IMAGE_REF" ] || fail "1_09/commands' docker run command does not reference devopsdockeruh/simple-web-service"
AFTER_IMAGE="$(echo "$RUN_LINE" | sed -E "s#.*${IMAGE_REF}##")"
echo "$AFTER_IMAGE" | grep -qE '[A-Za-z0-9]' \
  && fail "docker run command passes an extra argument/command after the image ($AFTER_IMAGE) -- exercise 1.9 relies on the image's default logging behaviour"
pass "docker run command gives the image no extra argument (uses its default logging behaviour)"

# Read the bind mount out of -v/--volume or --mount, in whichever form was
# used, and check it maps some host path named service.log to
# /usr/src/app/text.log in the container.
MOUNT_HOST=""
MOUNT_CONTAINER=""
if echo "$RUN_LINE" | grep -qE '(--mount)[[:space:]=]'; then
  MOUNT_ARG="$(echo "$RUN_LINE" | grep -oE '\-\-mount[[:space:]=]+[^[:space:]]+(["'"'"'][^"'"'"']*["'"'"'])?' | head -1)"
  MOUNT_HOST="$(echo "$MOUNT_ARG" | grep -oE 'source="?[^,[:space:]"]+' | sed -E 's/^source="?//')"
  MOUNT_CONTAINER="$(echo "$MOUNT_ARG" | grep -oE 'target="?[^,[:space:]"]+' | sed -E 's/^target="?//')"
else
  VOL_ARG="$(echo "$RUN_LINE" | grep -oE '(-v|--volume)[[:space:]=]+"?[^[:space:]"]+' | head -1 | sed -E 's/^(-v|--volume)[[:space:]=]+"?//')"
  [ -n "$VOL_ARG" ] || fail "1_09/commands' docker run command does not bind-mount anything with -v/--volume/--mount"
  MOUNT_HOST="$(echo "$VOL_ARG" | awk -F: '{print $1}')"
  MOUNT_CONTAINER="$(echo "$VOL_ARG" | awk -F: '{print $2}')"
fi
[ -n "$MOUNT_HOST" ] && [ -n "$MOUNT_CONTAINER" ] \
  || fail "could not parse the host:container paths out of 1_09/commands' bind mount"

echo "$MOUNT_HOST" | grep -qE '(^|/)service\.log$' \
  || fail "bind mount's host side (\"$MOUNT_HOST\") is not named service.log"
pass "bind mount's host side is named service.log"

echo "$MOUNT_CONTAINER" | grep -qE '^/usr/src/app/text\.log$' \
  || fail "bind mount's container side (\"$MOUNT_CONTAINER\") is not /usr/src/app/text.log"
pass "bind mount's container side is /usr/src/app/text.log"

# Exercise the actual commands from 1_09/, since the exercise says the file
# is created "in the same directory where you start the service" -- but
# don't require the file to start out empty (tolerant of it already
# existing, e.g. left over from a previous run).
if [ -f "$LOG_FILE" ]; then
  pass "service.log already exists in 1_09/ -- keeping its existing content instead of requiring a fresh file"
else
  touch "$LOG_FILE" || fail "could not create $LOG_FILE"
  pass "service.log did not exist yet -- created an empty one (any creation method is accepted, we just need it to exist as a regular file before the bind mount)"
fi
PRE_EXISTING_CONTENT="$(cat "$LOG_FILE")"

docker run -d --name "$CONTAINER" \
  -v "$LOG_FILE:/usr/src/app/text.log" \
  devopsdockeruh/simple-web-service >/dev/null 2>&1 \
  || fail "docker run failed to start the container with the bind mount"
pass "container started with service.log bind-mounted to /usr/src/app/text.log"

wait_for_new_content() {
  for _ in $(seq 1 20); do
    local current
    current="$(cat "$LOG_FILE" 2>/dev/null)"
    [ "$current" != "$PRE_EXISTING_CONTENT" ] && [ -n "$current" ] && return 0
    sleep 1
  done
  return 1
}
wait_for_new_content \
  || fail "service.log never received new content from the container"
pass "service.log received new content written by the container"

grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$LOG_FILE" \
  || fail "service.log's new content does not look like the expected timestamps"
pass "service.log contains the expected timestamp lines"

if [ -n "$PRE_EXISTING_CONTENT" ]; then
  grep -qF "$PRE_EXISTING_CONTENT" "$LOG_FILE" \
    || fail "pre-existing content in service.log was overwritten instead of appended to"
  pass "pre-existing content in service.log was preserved, not overwritten"
fi

echo "All tests passed"
