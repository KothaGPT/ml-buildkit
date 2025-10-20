#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Example wrapper to get container metadata robustly and avoid "unmarshal array" errors.
# Adjust the selection logic to match your action's expectations (first match vs all matches).

debug() {
  echo ">>> $*" >&2
}

# Example: function to inspect a container safely.
# Accepts: container id or name (if empty, tries to find container by label or other criteria)
safe_inspect() {
  local cid="$1"
  if [[ -z "${cid:-}" ]]; then
    debug "safe_inspect: no container id provided"
    return 1
  fi

  # Use --format to force a single JSON object for the inspected container
  # This avoids docker inspect returning an array when multiple IDs passed.
  # If `docker inspect --format '{{json .}}'` fails, fallback to `docker inspect` and normalize arrays.
  local out
  if out="$(docker inspect --format '{{json .}}' "$cid" 2>/dev/null || true)"; then
    if [[ -z "$out" || "$out" == "null" ]]; then
      debug "docker inspect returned empty/null for: $cid"
      return 2
    fi
    # If output starts with '[' it's still an array (some CLI combinations can do that).
    if [[ "${out:0:1}" == "[" ]]; then
      # pick the first element to preserve old single-object behavior
      out="$(echo "$out" | jq '.[0]')"
    fi
    echo "$out"
    return 0
  else
    debug "docker inspect --format failed for: $cid — trying docker inspect raw output"
    out="$(docker inspect "$cid" 2>/dev/null || true)"
    if [[ -z "$out" || "$out" == "null" ]]; then
      debug "docker inspect (raw) returned empty/null for: $cid"
      return 2
    fi
    # If it's an array, jq it
    if echo "$out" | jq -e 'if type == "array" then .[0] else . end' >/dev/null 2>&1; then
      echo "$out" | jq 'if type == "array" then .[0] else . end'
      return 0
    fi
    # else output as-is
    echo "$out"
    return 0
  fi
}

# Example usage: find container id created by the action (adapt the selector)
# Replace the label or filter below with whatever identifies the container your script expects.
container_id="$(docker ps -aq --filter "label=4368e3" | head -n1 || true)"
if [[ -z "${container_id}" ]]; then
  debug "No container id found with the expected filter. Listing matching containers for debugging:"
  docker ps -a --filter "label=4368e3" --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}' || true
  echo "Error: no matching container found" >&2
  exit 1
fi

debug "Found container id: $container_id"

container_json="$(safe_inspect "$container_id")" || {
  rc=$?
  debug "safe_inspect failed with rc=$rc; aborting."
  exit $rc
}

# Example of defensive jq usage:
image=$(echo "$container_json" | jq -r '.Config.Image // empty')
if [[ -z "$image" ]]; then
  debug "Config.Image missing or empty in container JSON"
  debug "Full container JSON:"
  echo "$container_json" | jq '.' >&2 || true
  exit 1
fi

debug "Container image is: $image"

# continue with the rest of the action, using container_json safely...
# e.g. extract Env array:
env_json=$(echo "$container_json" | jq -r '.Config.Env // []')
debug "Env count: $(echo "$env_json" | jq -r 'length' 2>/dev/null || true)"

# ...rest of your script
