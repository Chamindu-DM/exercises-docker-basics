#!/usr/bin/env bash
# Verifies exercise 1.14: 1_14/Dockerfile.frontend and 1_14/Dockerfile.backend
# are copies of 1_12/Dockerfile and 1_13/Dockerfile respectively, with their
# COPY directive's source path altered (the projects now live in 1_12/ and
# 1_13/, not alongside the Dockerfile in 1_14/ itself) and each project's
# README-required ENV added -- REACT_APP_BACKEND_URL baked into the frontend
# build, and REQUEST_ORIGIN so the backend's CORS check accepts the
# frontend's origin -- so that pressing the frontend's "1.14" exercise
# button (which makes the *browser* call the backend directly, the frontend
# container itself runs no code) succeeds.
#
# Because the Dockerfiles now live in 1_14/ but COPY reaches into 1_12/ and
# 1_13/, the build context must be an ancestor containing 1_12/, 1_13/ and
# 1_14/ all together (in this repo layout, that's the repo root) -- a
# context of 1_14/ itself (as exercises 1.12/1.13 used) cannot work, since
# COPY cannot reach outside the build context.
#
# Rather than pattern-matching exact ENV values (many different port/origin
# combinations can be correct), this drives the actual integration with a
# real browser and checks the button turns green -- the same signal the
# exercise itself names as "done".
#
# Tolerant of exactly how the build/run commands in 1_14/commands are
# phrased (image names, build context, published ports), the same way the
# 1.10-1.13 tests are.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/1_14"
FRONTEND_PROJECT_DIR="$REPO_ROOT/1_12"
BACKEND_PROJECT_DIR="$REPO_ROOT/1_13"
FRONTEND_DOCKERFILE="$TARGET_DIR/Dockerfile.frontend"
BACKEND_DOCKERFILE="$TARGET_DIR/Dockerfile.backend"
COMMANDS_FILE="$TARGET_DIR/commands"
PLAYWRIGHT_DIR="$REPO_ROOT/tests/playwright"

# shellcheck source=lib/docker_run_parse.sh
source "$REPO_ROOT/tests/lib/docker_run_parse.sh"

FRONTEND_CONTAINER="dod-1-14-frontend-test"
BACKEND_CONTAINER="dod-1-14-backend-test"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

cleanup() {
  docker rm -f "$FRONTEND_CONTAINER" "$BACKEND_CONTAINER" >/dev/null 2>&1
}
trap cleanup EXIT

norm_path() {
  (cd "$1" 2>/dev/null && pwd)
}

[ -f "$FRONTEND_DOCKERFILE" ] || fail "1_14/Dockerfile.frontend not found"
[ -f "$BACKEND_DOCKERFILE" ] || fail "1_14/Dockerfile.backend not found"
[ -f "$COMMANDS_FILE" ] || fail "1_14/commands not found"
pass "1_14/Dockerfile.frontend, 1_14/Dockerfile.backend and 1_14/commands exist"

grep -qE '^\s*FROM\s+ubuntu(:|$|@)' "$FRONTEND_DOCKERFILE" \
  || fail "1_14/Dockerfile.frontend does not start FROM ubuntu"
grep -qE '^\s*FROM\s+golang(:|$|@)' "$BACKEND_DOCKERFILE" \
  || fail "1_14/Dockerfile.backend does not start FROM a golang image"
pass "Dockerfile.frontend is based on ubuntu, Dockerfile.backend is based on golang"

# The COPY directive must have been altered to reach the project's real
# location. Docker itself resolves COPY sources against the build context
# root (not the Dockerfile's own directory), clamping any leading ".." back
# to that root -- so e.g. "COPY 1_12 ." and "COPY ../1_12 ." are equivalent
# once the context is the ancestor containing 1_12/, 1_13/ and 1_14/. Since
# we don't know the chosen build context yet at this point in the script,
# accept either convention: resolved relative to the Dockerfile's own
# directory (1_14/) or relative to that common-ancestor context (REPO_ROOT
# here) -- and must land on the real project (checked via a file only that
# project has), not just any existing directory.
check_copy_target() {
  local dockerfile="$1" marker_file="$2" label="$3"
  local copy_src resolved
  copy_src="$(grep -oE '^\s*COPY\s+[^[:space:]]+' "$dockerfile" | grep -v -- '--from' | head -1 | awk '{print $2}')"
  [ -n "$copy_src" ] || fail "$label has no COPY directive"
  [ "$copy_src" != "." ] \
    || fail "$label still has an unaltered \"COPY . .\" -- the project no longer lives alongside this Dockerfile, so the COPY source path needs to point at it"
  resolved="$(cd "$(dirname "$dockerfile")" 2>/dev/null && norm_path "$copy_src")"
  if [ -z "$resolved" ] || [ ! -f "$resolved/$marker_file" ]; then
    resolved="$(cd "$REPO_ROOT" 2>/dev/null && norm_path "$copy_src")"
  fi
  [ -n "$resolved" ] \
    || fail "$label's COPY source \"$copy_src\" does not exist (checked relative to both 1_14/ and the repo root)"
  [ -f "$resolved/$marker_file" ] \
    || fail "$label's COPY source \"$copy_src\" does not resolve to the project directory (expected to find $marker_file there)"
  pass "$label's COPY directive points at the real project ($copy_src)"
}
check_copy_target "$FRONTEND_DOCKERFILE" "package.json" "1_14/Dockerfile.frontend"
check_copy_target "$BACKEND_DOCKERFILE" "go.mod" "1_14/Dockerfile.backend"

grep -qE 'docker\s+build' "$COMMANDS_FILE" \
  || fail "1_14/commands does not contain a docker build command"
grep -qE 'docker\s+run' "$COMMANDS_FILE" \
  || fail "1_14/commands does not contain a docker run command"

BUILD_LINES=()
while IFS= read -r line; do
  [ -n "$line" ] && BUILD_LINES+=("$line")
done < <(grep -E 'docker\s+build' "$COMMANDS_FILE")
RUN_LINES=()
while IFS= read -r line; do
  [ -n "$line" ] && RUN_LINES+=("$line")
done < <(grep -E 'docker\s+run' "$COMMANDS_FILE")

resolve_context() {
  local raw="$1" candidate
  for candidate in \
    "$TARGET_DIR/$raw" \
    "$REPO_ROOT/$raw" \
    "$(dirname "$REPO_ROOT")/$raw" \
    "$raw"
  do
    if [ -d "$candidate" ]; then
      norm_path "$candidate"
      return 0
    fi
  done
  return 1
}

# A build's -f/--file argument tells us which Dockerfile it targets --
# that's what identifies "frontend" vs "backend" here, since (unlike
# exercises 1.12/1.13) both Dockerfiles now share one build context.
FRONTEND_BUILD_IMAGE=""
BACKEND_BUILD_IMAGE=""
FRONTEND_CONTEXT=""
BACKEND_CONTEXT=""
# Any --build-arg given in 1_14/commands is passed through to the test's own
# build, so the values may be supplied there instead of hardcoded in the
# Dockerfile (e.g. "ARG REACT_APP_BACKEND_URL" + "--build-arg ...").
FRONTEND_BUILD_ARGS=()
BACKEND_BUILD_ARGS=()
for line in "${BUILD_LINES[@]}"; do
  file_arg="$(echo "$line" | grep -oE '(-f|--file)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-f|--file)[[:space:]=]+//')"
  [ -n "$file_arg" ] || continue
  role="$(basename "$file_arg")"

  img="$(echo "$line" | grep -oE '(-t|--tag)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-t|--tag)[[:space:]=]+//')"
  [ -n "$img" ] || continue

  raw_ctx="$(echo "$line" | awk '{print $NF}')"
  resolved_ctx="$(resolve_context "$raw_ctx" || true)"
  [ -n "$resolved_ctx" ] || continue

  build_args=()
  while IFS= read -r arg; do
    [ -n "$arg" ] && build_args+=(--build-arg "$arg")
  done < <(echo "$line" | grep -oE -- '--build-arg[[:space:]=]+[^[:space:]]+' | sed -E 's/^--build-arg[[:space:]=]+//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')

  if [ "$role" = "Dockerfile.frontend" ]; then
    FRONTEND_BUILD_IMAGE="$img"
    FRONTEND_CONTEXT="$resolved_ctx"
    FRONTEND_BUILD_ARGS=(${build_args[@]+"${build_args[@]}"})
  elif [ "$role" = "Dockerfile.backend" ]; then
    BACKEND_BUILD_IMAGE="$img"
    BACKEND_CONTEXT="$resolved_ctx"
    BACKEND_BUILD_ARGS=(${build_args[@]+"${build_args[@]}"})
  fi
done

[ -n "$FRONTEND_BUILD_IMAGE" ] || fail "could not find a docker build command in 1_14/commands with -f/--file pointing at Dockerfile.frontend"
[ -n "$BACKEND_BUILD_IMAGE" ] || fail "could not find a docker build command in 1_14/commands with -f/--file pointing at Dockerfile.backend"
pass "found build commands for both Dockerfile.frontend (\"$FRONTEND_BUILD_IMAGE\") and Dockerfile.backend (\"$BACKEND_BUILD_IMAGE\")"

# The chosen context has to be an ancestor that contains 1_12/, 1_13/ and
# 1_14/ together -- otherwise the COPY directives (which reach out of
# 1_14/ into 1_12/ and 1_13/) cannot resolve.
for ctx_name in FRONTEND_CONTEXT BACKEND_CONTEXT; do
  ctx="${!ctx_name}"
  [ -d "$ctx/1_12" ] && [ -d "$ctx/1_13" ] && [ -d "$ctx/1_14" ] \
    || fail "build context \"$ctx\" does not contain 1_12/, 1_13/ and 1_14/ together -- the COPY directives in 1_14/'s Dockerfiles reach into 1_12/ and 1_13/, so the build context must be their common ancestor, not 1_14/ itself"
done
pass "build context(s) contain 1_12/, 1_13/ and 1_14/ together"

# The port the app actually listens on inside each image, read straight out
# of the Dockerfile that built it (frontend: "serve -l <port>"; backend:
# app.go defaults to 8080 unless overridden by ENV PORT). Computed here
# (before the containers are actually built/run) so the docker run lines'
# published ports can be checked against it below.
FRONTEND_APP_PORT="$(grep -oE '"-l"[[:space:]]*,[[:space:]]*"[0-9]+"' "$FRONTEND_DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$FRONTEND_APP_PORT" ] || FRONTEND_APP_PORT="$(grep -oE '\-l[[:space:]]+[0-9]+' "$FRONTEND_DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$FRONTEND_APP_PORT" ] || fail "could not determine the port 1_14/Dockerfile.frontend's CMD serves on (expected a \"serve -l <port>\" argument)"

BACKEND_APP_PORT="$(grep -oE '^\s*ENV\s+PORT[[:space:]=]+[0-9]+' "$BACKEND_DOCKERFILE" | grep -oE '[0-9]+' | tail -1)"
[ -n "$BACKEND_APP_PORT" ] || BACKEND_APP_PORT="8080"

# Parsed position-aware: a -p typed after the image name is not a valid
# docker option there, so it must not count. Captures both sides of
# "-p host:container" -- the host side is what's published on the machine,
# the container side must match the port the app inside the image actually
# listens on (checked below), or the run would publish nothing useful.
FRONTEND_PORT=""
BACKEND_PORT=""
FRONTEND_RUN_CONTAINER_PORT=""
BACKEND_RUN_CONTAINER_PORT=""
# Likewise any -e/--env given to a docker run line is passed through to the
# test's own run of that image.
FRONTEND_RUN_ENVS=()
BACKEND_RUN_ENVS=()
for line in "${RUN_LINES[@]}"; do
  run_parsed="$(docker_run_parse "$line")"
  run_img="$(echo "$run_parsed" | cut -f1)"
  run_port_raw="$(echo "$run_parsed" | cut -f2)"
  run_host_port=""
  run_container_port=""
  if [ -n "$run_port_raw" ]; then
    run_host_port="$(docker_publish_ports "$run_port_raw" | cut -f1)"
    run_container_port="$(docker_publish_ports "$run_port_raw" | cut -f2)"
  fi
  run_envs=()
  while IFS= read -r env; do
    [ -n "$env" ] && run_envs+=(-e "$env")
  done < <(docker_run_env_flags "$line")
  if [ "$run_img" = "$FRONTEND_BUILD_IMAGE" ]; then
    FRONTEND_PORT="$run_host_port"
    FRONTEND_RUN_CONTAINER_PORT="$run_container_port"
    FRONTEND_RUN_ENVS=(${run_envs[@]+"${run_envs[@]}"})
  elif [ "$run_img" = "$BACKEND_BUILD_IMAGE" ]; then
    BACKEND_PORT="$run_host_port"
    BACKEND_RUN_CONTAINER_PORT="$run_container_port"
    BACKEND_RUN_ENVS=(${run_envs[@]+"${run_envs[@]}"})
  fi
done
[ -n "$FRONTEND_PORT" ] || fail "could not find a docker run command starting image \"$FRONTEND_BUILD_IMAGE\" and publishing a port with -p/--publish before it"
[ -n "$BACKEND_PORT" ] || fail "could not find a docker run command starting image \"$BACKEND_BUILD_IMAGE\" and publishing a port with -p/--publish before it"
pass "found matching docker run commands for both images"

[ "$FRONTEND_PORT" != "$BACKEND_PORT" ] \
  || fail "1_14/commands publishes host port $FRONTEND_PORT for both frontend and backend -- they need distinct host ports, or the second docker run will fail because the port is already taken"
pass "frontend publishes host port $FRONTEND_PORT, backend publishes host port $BACKEND_PORT"

[ "$FRONTEND_RUN_CONTAINER_PORT" = "$FRONTEND_APP_PORT" ] \
  || fail "1_14/commands' frontend docker run publishes container port $FRONTEND_RUN_CONTAINER_PORT, but 1_14/Dockerfile.frontend's CMD actually serves on port $FRONTEND_APP_PORT -- the -p mapping's container side (the part after the colon) must match"
[ "$BACKEND_RUN_CONTAINER_PORT" = "$BACKEND_APP_PORT" ] \
  || fail "1_14/commands' backend docker run publishes container port $BACKEND_RUN_CONTAINER_PORT, but 1_14/Dockerfile.backend actually listens on port $BACKEND_APP_PORT -- the -p mapping's container side (the part after the colon) must match"
pass "docker run container ports match what each app actually listens on"

# REACT_APP_BACKEND_URL may be set either as a plain ENV, or as an ARG
# filled in by --build-arg in 1_14/commands. Either way it must be declared
# before "RUN npm run build" -- Create React App only bakes REACT_APP_* vars
# in at build time.
env_line="$(grep -nE '^\s*(ENV|ARG)\s+REACT_APP_BACKEND_URL' "$FRONTEND_DOCKERFILE" | head -1 | cut -d: -f1)"
[ -n "$env_line" ] \
  || fail "1_14/Dockerfile.frontend has no ENV (or ARG) REACT_APP_BACKEND_URL (needed at build time, per the frontend README)"
build_line="$(grep -nE '^\s*RUN\s+npm\s+run\s+build' "$FRONTEND_DOCKERFILE" | head -1 | cut -d: -f1)"
if [ -n "$build_line" ]; then
  [ "$env_line" -lt "$build_line" ] \
    || fail "1_14/Dockerfile.frontend sets REACT_APP_BACKEND_URL after \"RUN npm run build\" -- Create React App only bakes REACT_APP_* vars in at build time, so it must come before the build"
fi
pass "1_14/Dockerfile.frontend sets REACT_APP_BACKEND_URL before the build"

# REQUEST_ORIGIN may be set either as ENV in the Dockerfile or with -e on
# the backend's docker run line.
grep -qE '^\s*ENV\s+REQUEST_ORIGIN' "$BACKEND_DOCKERFILE" \
  || printf '%s\n' ${BACKEND_RUN_ENVS[@]+"${BACKEND_RUN_ENVS[@]}"} | grep -qE '^REQUEST_ORIGIN(=|$)' \
  || fail "REQUEST_ORIGIN is set neither by ENV in 1_14/Dockerfile.backend nor by -e in the backend's docker run (needed for the CORS check, per the backend README)"
pass "REQUEST_ORIGIN is set for the backend"

# The browser's Origin header must match REQUEST_ORIGIN, so open the frontend
# on the same host the student configured (localhost or 127.0.0.1). A -e on
# the docker run line overrides the Dockerfile's ENV.
REQUEST_ORIGIN_VALUE="$(grep -E '^\s*ENV\s+REQUEST_ORIGIN' "$BACKEND_DOCKERFILE" | tail -1 | sed -E 's/^[[:space:]]*ENV[[:space:]]+REQUEST_ORIGIN([[:space:]]*=[[:space:]]*|[[:space:]]+)//' | tr -d '"'"'"'"')"
run_origin="$(printf '%s\n' ${BACKEND_RUN_ENVS[@]+"${BACKEND_RUN_ENVS[@]}"} | grep -E '^REQUEST_ORIGIN=' | tail -1 | sed -E 's/^REQUEST_ORIGIN=//')"
[ -n "$run_origin" ] && REQUEST_ORIGIN_VALUE="$run_origin"
FRONTEND_HOST="localhost"
printf '%s' "$REQUEST_ORIGIN_VALUE" | grep -qE '127\.0\.0\.1' && FRONTEND_HOST="127.0.0.1"

echo "Building both images -- this involves an npm build and a go build, and may take a while..."
docker build ${FRONTEND_BUILD_ARGS[@]+"${FRONTEND_BUILD_ARGS[@]}"} -t "$FRONTEND_BUILD_IMAGE" -f "$FRONTEND_DOCKERFILE" "$FRONTEND_CONTEXT" >/dev/null 2>&1 \
  || fail "docker build failed for 1_14/Dockerfile.frontend with context $FRONTEND_CONTEXT"
pass "$FRONTEND_BUILD_IMAGE image builds"

docker build ${BACKEND_BUILD_ARGS[@]+"${BACKEND_BUILD_ARGS[@]}"} -t "$BACKEND_BUILD_IMAGE" -f "$BACKEND_DOCKERFILE" "$BACKEND_CONTEXT" >/dev/null 2>&1 \
  || fail "docker build failed for 1_14/Dockerfile.backend with context $BACKEND_CONTEXT"
pass "$BACKEND_BUILD_IMAGE image builds"

docker run -d --name "$BACKEND_CONTAINER" ${BACKEND_RUN_ENVS[@]+"${BACKEND_RUN_ENVS[@]}"} -p "$BACKEND_PORT:$BACKEND_APP_PORT" "$BACKEND_BUILD_IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for the backend, publishing port $BACKEND_PORT"
docker run -d --name "$FRONTEND_CONTAINER" ${FRONTEND_RUN_ENVS[@]+"${FRONTEND_RUN_ENVS[@]}"} -p "$FRONTEND_PORT:$FRONTEND_APP_PORT" "$FRONTEND_BUILD_IMAGE" >/dev/null 2>&1 \
  || fail "docker run failed for the frontend, publishing port $FRONTEND_PORT"
pass "both containers started"

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 30); do
    curl -s --max-time 2 "$url" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}
wait_for_http "http://localhost:$BACKEND_PORT/ping" || fail "backend never became reachable on port $BACKEND_PORT (check docker logs $BACKEND_CONTAINER)"
wait_for_http "http://localhost:$FRONTEND_PORT" || fail "frontend never became reachable on port $FRONTEND_PORT (check docker logs $FRONTEND_CONTAINER)"
pass "both containers are reachable"

# Drive the actual browser flow the exercise describes: load the frontend,
# press the "backend" button, and confirm it turns green -- this is what
# actually exercises the ENV configuration (REACT_APP_BACKEND_URL baked
# into the frontend's JS bundle, REQUEST_ORIGIN accepted by the backend's
# CORS check), regardless of the exact values chosen for either.
command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
NODE_MAJOR="$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 20 ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh"
  NEWER_NODE="$(nvm ls --no-colors 2>/dev/null | grep -oE 'v(2[0-9]|[3-9][0-9])\.[0-9]+\.[0-9]+' | sort -V | head -1)"
  [ -n "$NEWER_NODE" ] && nvm use "$NEWER_NODE" >/dev/null 2>&1
fi
command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"

(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "http://$FRONTEND_HOST:$FRONTEND_PORT" backend \
  || fail "pressing the \"1.14\"/backend button in the frontend (opened at http://$FRONTEND_HOST:$FRONTEND_PORT) did not report success -- check that REQUEST_ORIGIN matches that origin exactly (scheme, host and port, no trailing slash)"
pass "pressing the backend button in the frontend reported success (turned green)"

echo "All tests passed"
