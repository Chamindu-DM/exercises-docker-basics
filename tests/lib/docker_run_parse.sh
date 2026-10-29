#!/usr/bin/env bash
# Shared parsing helpers for "docker run ..." lines used by the test suite.
#
# Real docker requires all options (including -p/--publish) to appear
# BEFORE the image name -- anything typed after the image name is passed as
# the command/arguments for the container itself and is NOT interpreted by
# docker at all. A naive scan of the whole line for "-p" (or assuming the
# image name is simply the last token) can be fooled by a flag placed after
# the image name, or by an image name that isn't actually the last token,
# so this walks the tokens respecting that boundary instead.

# Flags that consume a following token as their value, unless given in the
# "--flag=value" form. Not necessarily exhaustive, but covers what this
# course's exercises use.
_DOCKER_RUN_VALUE_FLAGS=(
  -p --publish -e --env --name -v --volume --mount -w --workdir --network
  --entrypoint -u --user --add-host --platform --hostname --label -l
  --restart -m --memory --cpus --env-file --link --ip --dns --log-driver
  --log-opt -a --attach --cap-add --cap-drop --device --pid --ipc --uts
  --security-opt --stop-signal --tmpfs --volumes-from --expose --group-add
  --gpus --health-cmd --health-interval --health-retries --health-timeout
)

_docker_run_is_value_flag() {
  local f="$1" candidate
  for candidate in "${_DOCKER_RUN_VALUE_FLAGS[@]}"; do
    [ "$f" = "$candidate" ] && return 0
  done
  return 1
}

# Walks a "docker run ..." line's tokens (after "run") and echoes one
# tab-separated line: <image>\t<port-flag-value-or-empty>\t<saw -P before image: 0|1>
# The port value is whatever followed -p/--publish (e.g. "8080:8080" or
# just "8080"), taken only if it appeared strictly before the image name --
# one placed after is correctly ignored, matching real docker.
docker_run_parse() {
  local line="$1"
  local rest
  rest="$(echo "$line" | sed -E 's/^.*docker[[:space:]]+run[[:space:]]*//')"

  local -a toks
  read -r -a toks <<< "$rest"

  local image="" port="" publish_all=0
  local i=0 tok flagname flagvalue skip_next=0
  while [ "$i" -lt "${#toks[@]}" ]; do
    tok="${toks[$i]}"
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      i=$((i + 1))
      continue
    fi
    case "$tok" in
      -*)
        if [[ "$tok" == *=* ]]; then
          flagname="${tok%%=*}"
          flagvalue="${tok#*=}"
        else
          flagname="$tok"
          flagvalue=""
        fi
        # Strip a single layer of surrounding quotes, if any.
        flagvalue="$(echo "$flagvalue" | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"

        if [ "$flagname" = "-p" ] || [ "$flagname" = "--publish" ]; then
          if [ -n "$flagvalue" ]; then
            port="$flagvalue"
          else
            port="${toks[$((i + 1))]}"
            port="$(echo "$port" | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
          fi
        elif [ "$flagname" = "-P" ] || [ "$flagname" = "--publish-all" ]; then
          publish_all=1
        fi

        if [ -z "$flagvalue" ] && _docker_run_is_value_flag "$flagname"; then
          skip_next=1
        fi
        ;;
      *)
        image="$tok"
        break
        ;;
    esac
    i=$((i + 1))
  done

  printf '%s\t%s\t%s\n' "$image" "$port" "$publish_all"
}

# Splits a -p/--publish value into its host and container ports and echoes
# them tab-separated: <host-port-or-empty>\t<container-port>
# Accepts every form docker does: CONTAINER, HOST:CONTAINER,
# IP:HOST:CONTAINER, IP::CONTAINER, [IPv6]:HOST:CONTAINER, each optionally
# with a /tcp or /udp suffix. The host port is empty when none was given,
# in which case docker picks a random one.
docker_publish_ports() {
  local spec="${1%/*}"
  local container="${spec##*:}" host=""
  if [[ "$spec" == *:* ]]; then
    local rest="${spec%:*}"
    host="${rest##*:}"
  fi
  printf '%s\t%s\n' "$host" "$container"
}

# Echoes the value of every -e/--env flag given to a "docker run ..." line
# before the image name, one per line (e.g. "REQUEST_ORIGIN=http://..."),
# with a single layer of surrounding quotes stripped. Flags after the image
# name are container arguments, not docker options, so they are ignored.
docker_run_env_flags() {
  local line="$1"
  local rest
  rest="$(echo "$line" | sed -E 's/^.*docker[[:space:]]+run[[:space:]]*//')"

  local -a toks
  read -r -a toks <<< "$rest"

  local i=0 tok flagname flagvalue
  while [ "$i" -lt "${#toks[@]}" ]; do
    tok="${toks[$i]}"
    case "$tok" in
      -*)
        if [[ "$tok" == *=* ]]; then
          flagname="${tok%%=*}"
          flagvalue="${tok#*=}"
        else
          flagname="$tok"
          flagvalue=""
        fi

        if [ -z "$flagvalue" ] && _docker_run_is_value_flag "$flagname"; then
          i=$((i + 1))
          flagvalue="${toks[$i]}"
        fi

        if [ "$flagname" = "-e" ] || [ "$flagname" = "--env" ]; then
          echo "$flagvalue" | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
        fi
        ;;
      *)
        break
        ;;
    esac
    i=$((i + 1))
  done
}
