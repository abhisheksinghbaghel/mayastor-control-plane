#!/bin/sh

# This is a wrapper script for helm to generate yaml files for deploying
# mayastor control plane. It provides reasonable defaults for helm values based on
# selected profile. Easy to use and minimizing risk of error.
# Keep the script as simple as possible - ad-hoc use cases can be addressed
# by running helm directly.

set -e

SCRIPTDIR="$(realpath "$(dirname "$0")")"

# Internal variables tunable by options
output_dir="$SCRIPTDIR/../deploy"
profile=
pull_policy=
registry=
tag=
helm_string=
helm_file=
helm_flags=

help() {
  cat <<EOF

Usage: $0 [OPTIONS] <PROFILE>

Common options:
  -h/--help        Display help message and exit.
  -o <output_dir>  Directory to store the generated yaml files (default $output_dir)
  -r <registry>    Docker image registry of mayastor images (default none).
  -t <tag>         Tag of mayastor images overriding the profile's default.
  -s <variables>   Set chart values on the command line (can specify multiple or separate values with commas: key1=val1,key2=val2)
  -f <file>        Specify values in a YAML file or a URL (can specify multiple)
  -d               Debug the helm command by specifying --debug
  -c               Run this script only if the helm template directory has changes

Profiles:
  develop:   Used by developers of mayastor.
  release:   Recommended for stable releases deployed by users.
  test:      Used by mayastor e2e tests.
EOF
}

# trim trailing whitespace from yaml files on the provided directories
trim_yaml_whitespace() {
  for dir in "$@"; do
    for file in "$dir"/*.yaml; do
      sed -i '/^[[:space:]]*$/d' "$file"
    done
  done
}

# Parse common options
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      help
      exit 0
      ;;
    -o)
      shift
      output_dir=$1
      ;;
    -r)
      shift
      registry=$1
      ;;
    -s)
      shift
      helm_string=$1
      ;;
    -f)
      shift
      helm_file=$1
      ;;
    -t)
      shift
      tag=$1
      ;;
    -d)
      helm_flags="$helm_flags --debug"
      ;;
    -c)
      git diff --cached --exit-code "$SCRIPTDIR/../chart" 1>/dev/null && exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      help
      exit 1
      ;;
    *)
      profile=$1
      shift
      break
      ;;
  esac
  shift
done

# The space after profile name is reserved for profile specific options which
# we don't have yet.
if [ "$#" -gt 0 ]; then
  help
  exit 1
fi

# In most of the cases the tag will be a specific version that does not change
# so save dockerhub bandwidth and don't always pull the image.
if [ -n "$tag" ] && [ -z "$registry" ]; then
  pull_policy=IfNotPresent
fi

# Set profile defaults
case "$profile" in
  "develop")
    ;;
  "release")
    ;;
  "test")
    ;;
  *)
    echo "Missing or invalid profile name. Type \"$0 --help\""
    exit 1
    ;;
esac

set -u

if ! which helm >/dev/null 2>&1; then
  echo "Install helm (>v3.4.1) to PATH"
  exit 1
fi

if [ ! -d "$output_dir" ]; then
  mkdir -p "$output_dir"
fi

tmpd=$(mktemp -d /tmp/generate-deploy-yamls.sh.XXXXXXXX)
# shellcheck disable=SC2064
trap "rm -fr '$tmpd'" HUP QUIT EXIT TERM INT

template_params=""
if [ -n "$tag" ]; then
    template_params="mayastorCP.tag=$tag"
fi
if [ -n "$pull_policy" ]; then
    template_params="$template_params,mayastorCP.pullPolicy=$pull_policy"
fi
if [ -n "$registry" ]; then
  registry=$(echo "$registry" | sed -e "s;/*$;;")"/"
  template_params="$template_params,mayastorCP.registry=$registry"
fi

# update helm dependencies
( cd "$SCRIPTDIR"/../chart && helm dependency update )
# generate the yaml
helm template --set "$template_params" mayastor "$SCRIPTDIR/../chart" --output-dir="$tmpd" --namespace mayastor \
  -f "$SCRIPTDIR/../chart/$profile/values.yaml" -f "$SCRIPTDIR/../chart/constants.yaml" -f "$helm_file" \
  --set "$helm_string" $helm_flags

# jaeger-operator yaml files
output_dir_jaeger="$output_dir/jaeger-operator"
if [ ! -d "$output_dir_jaeger" ]; then
  mkdir -p "$output_dir_jaeger"
else
  rm -rf "${output_dir_jaeger:?}/"*
fi

# our own autogenerated yaml files
mv -f "$tmpd"/mayastor-control-plane/templates/* "$output_dir/"
# jaeger-operator generated yaml files
mv -f "$tmpd"/mayastor-control-plane/charts/jaeger-operator/templates/* "$output_dir_jaeger/"

trim_yaml_whitespace "$output_dir" "$output_dir_jaeger"