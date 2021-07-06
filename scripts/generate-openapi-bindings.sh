#!/usr/bin/env bash

set -e

SCRIPTDIR=$(dirname "$0")
TARGET="$SCRIPTDIR/../openapi"
SPEC="$SCRIPTDIR/../control-plane/rest/openapi-specs/v0_api_spec.yaml"

# Regenerate the bindings only if the rest src changed
check_spec="no"

case "$1" in
    --changes)
        check_spec="yes"
        ;;
esac

if [[ $check_spec = "yes" ]]; then
    git diff --cached --exit-code "$SPEC" 1>/dev/null && exit 0
fi

# Cleanup the existing autogenerated code
if [ ! -d "$TARGET" ]; then
  mkdir -p "$TARGET"
else
  rm -rf "${TARGET:?}/"*
fi

tmpd=$(mktemp -d /tmp/openapi-gen-XXXXXXX)

# Generate a new openapi crate
openapi-generator-cli generate -i "$SPEC" -g rust-actix-mayastor -o "$tmpd" --additional-properties actixWebVersion="3.2.0"

# Format the files
# Note, must be formatted on the tmp directory as we've ignored the autogenerated code within the workspace
( cd "$tmpd" && cargo fmt --all )
mv "$tmpd"/* "$TARGET"/
rm -rf "$tmpd"


# If the openapi bindings were modified then fail the check
git diff --exit-code "$TARGET"
