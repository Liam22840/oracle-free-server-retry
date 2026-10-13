#!/usr/bin/env bash
# Keeps trying to launch an Always Free Oracle server until it works or time runs out.
# GitHub's scheduler often skips or delays runs, so each run loops by itself:
# one attempt every INTERVAL seconds for up to DURATION seconds.
# Only tries the Ampere A1 (Always Free): the full 2 OCPU / 12 GB first, then 1 OCPU / 6 GB.
# Never launches a second server with the same name.
set -uo pipefail

C="$OCI_TENANCY"
NAME="${INSTANCE_NAME:-marley}"
INTERVAL="${INTERVAL:-300}"
DURATION="${DURATION:-19800}"
out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"; }
now() { date -u +%H:%MZ; }

# How many non-terminated servers named $NAME exist. Empty output means none.
count_existing() {
  local err n
  err=$(mktemp)
  if ! n=$(oci compute instance list -c "$C" --display-name "$NAME" --all \
    --query "length((data || \`[]\`)[?\"lifecycle-state\"!='TERMINATED'])" --raw-output 2>"$err"); then
    grep -m3 -E '"(code|message)"|Error' "$err" >&2 || head -c 300 "$err" >&2
    return 1
  fi
  n=${n:-0}
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "Unexpected answer from Oracle: '$n'" >&2; return 1; }
  echo "$n"
}

AD=$(oci iam availability-domain list -c "$C" --query 'data[0].name' --raw-output) || {
  echo "Couldn't reach Oracle (check the secrets)." >&2
  exit 1
}
SUBNET=$(oci network subnet list -c "$C" --display-name "$SUBNET_NAME" --query 'data[0].id' --raw-output)
if [ -z "$SUBNET" ] || [ "$SUBNET" = "None" ]; then
  echo "Subnet '$SUBNET_NAME' not found." >&2
  exit 1
fi
IMAGE=$(oci compute image list -c "$C" --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --query 'data[0].id' --raw-output)
KEYFILE=$(mktemp)
printf '%s\n' "$SSH_PUBLIC_KEY" > "$KEYFILE"

try() {
  local config=$1 result
  if result=$(oci compute instance launch --no-retry -c "$C" --availability-domain "$AD" \
    --shape VM.Standard.A1.Flex --shape-config "$config" --subnet-id "$SUBNET" --assign-public-ip true \
    --image-id "$IMAGE" --display-name "$NAME" --ssh-authorized-keys-file "$KEYFILE" \
    --query 'data."lifecycle-state"' --raw-output 2>&1); then
    echo "$(now) Launched VM.Standard.A1.Flex $config ($result)."
    out "created=true"
    out "shape=VM.Standard.A1.Flex $config"
    return 0
  fi
  echo "$(now) $config: $(grep -o '"message": "[^"]*"' <<<"$result" | head -1)"
  return 1
}

end=$((SECONDS + DURATION))
failures=0
attempt=0
while :; do
  attempt=$((attempt + 1))
  if existing=$(count_existing); then
    failures=0
    if [ "$existing" -gt 0 ]; then
      echo "$(now) A server named '$NAME' already exists. Nothing to do."
      out "created=exists"
      exit 0
    fi
    if try '{"ocpus":2,"memoryInGBs":12}' || try '{"ocpus":1,"memoryInGBs":6}'; then
      exit 0
    fi
  else
    failures=$((failures + 1))
    echo "$(now) Couldn't check for an existing server ($failures in a row)." >&2
    [ "$failures" -ge 3 ] && { echo "Giving up this run: Oracle keeps failing (check the secrets)." >&2; exit 1; }
  fi
  if [ $((SECONDS + INTERVAL)) -ge "$end" ]; then
    echo "$(now) No capacity after $attempt attempts; the next scheduled run will carry on."
    exit 0
  fi
  sleep "$INTERVAL"
done
