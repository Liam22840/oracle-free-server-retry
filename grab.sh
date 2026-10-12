#!/usr/bin/env bash
# Tries once to launch an Always Free Oracle server. Run on a schedule until it works.
# Tries Ampere A1 (1 OCPU / 6 GB) first, then the AMD E2.1.Micro.
# Only ever launches Always Free shapes, and never a second server with the same name.
set -uo pipefail

C="$OCI_TENANCY"
NAME="${INSTANCE_NAME:-marley}"
out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"; }

# Stop if the server already exists (any state except terminated).
existing=$(oci compute instance list -c "$C" --display-name "$NAME" \
  --query "length(data[?\"lifecycle-state\"!='TERMINATED'])" --raw-output 2>/dev/null || echo "?")
if [ "$existing" != "0" ]; then
  echo "A server named '$NAME' already exists (or the check failed: '$existing'). Nothing to do."
  [ "$existing" != "?" ] && out "created=exists"
  exit 0
fi

AD=$(oci iam availability-domain list -c "$C" --query 'data[0].name' --raw-output)
SUBNET=$(oci network subnet list -c "$C" --display-name "$SUBNET_NAME" --query 'data[0].id' --raw-output)
if [ -z "$SUBNET" ] || [ "$SUBNET" = "None" ]; then
  echo "Subnet '$SUBNET_NAME' not found." >&2
  exit 1
fi
KEYFILE=$(mktemp)
printf '%s\n' "$SSH_PUBLIC_KEY" > "$KEYFILE"

try() {
  local shape=$1 config=$2 image result
  image=$(oci compute image list -c "$C" --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
    --shape "$shape" --sort-by TIMECREATED --query 'data[0].id' --raw-output)
  local args=(compute instance launch --no-retry -c "$C" --availability-domain "$AD" --shape "$shape"
    --subnet-id "$SUBNET" --assign-public-ip true --image-id "$image" --display-name "$NAME"
    --ssh-authorized-keys-file "$KEYFILE" --query 'data."lifecycle-state"' --raw-output)
  [ -n "$config" ] && args+=(--shape-config "$config")
  if result=$(oci "${args[@]}" 2>&1); then
    echo "Launched $shape ($result)."
    out "created=true"
    out "shape=$shape"
    return 0
  fi
  echo "$shape: $(grep -o '"message": "[^"]*"' <<<"$result" | head -1)"
  return 1
}

try VM.Standard.A1.Flex '{"ocpus":1,"memoryInGBs":6}' ||
  try VM.Standard.E2.1.Micro '' ||
  echo "No capacity this time; will try again on the next run."
exit 0
