#!/usr/bin/env bash

# Build `ServerContainers/samba` Docker image

# Usage: `DOCKER_REGISTRY='ghcr.io/servercontainers' ./build_ubuntu.sh [...OPTIONS]`

# All variants (`ad`, `avahi`, `full`, `only`, `wsdd2`) will be built by default, unless one or more are selected as command-line arguments, in which case unselected images are not built.

# Options (the order does not matter):
# - `ad`: build `ad` image variant;
# - `avahi`: build `avahi` image variant;
# - `force`: forces build the image regardless of the time when the image was last push to the Git repository. By default, we don't build images if the last commit is older than one hour (in that case the latest image is pulled from the Docker registry).
# - `full`: build `full` image variant;
# - `no-push`: build the image, but don't push it to Docker registry; side effect: image for a single platform (for your host) will be built (cf https://github.com/docker/buildx/issues/59);
# - `only`: build `only` image variant;
# - `plain-log`: set the build progress to `plain`;
# - `use-cache`: use build cache;
# - `wsdd2`: build `wsdd2` image variant;

set -euo pipefail

[ -z "${DOCKER_REGISTRY-}" ] && echo "Error: Specify docker-registry in \`DOCKER_REGISTRY\` please." && exit 1

# Variables
BUILDER_INSTANCE_NAME='samba'
DEPENDANT_PUSH_TO_DOCKER_REGISTRY="$(grep -q 'no-push' <<< "$*" && echo '--load' || echo '--push')"
IMG="$DOCKER_REGISTRY/samba"
PLATFORMS=(
  'linux/amd64'
  'linux/arm/v7'
  'linux/arm/v8'
  'linux/arm64'
)
REPO_ROOT="$(realpath "$(dirname "$0")")"
VARIANTS=('ad' 'avahi' 'full' 'only' 'wsdd2')
VARIANTS_TO_BUILD=()
BASE_IMAGE="$(grep -Pom1 '^FROM \K[^ ]*' "$REPO_ROOT/ubuntu.dockerfile")"

# Get the image source code URL
# Note: This uses the URLs of Git remotes for this. `upstream` remote is preferred, when not found, `origin` remote is used.
# Note: The SSH URL is converted to HTTPS URL. It presumes that the URL is not accessible on unsecure HTTP only.
IMAGE_SOURCE_CODE_URL="$(sed -E 's|^[^@]+@([^:]+):(.*)$|https://\1/\2|;s/\.git$//' <<< "$(git -C "$REPO_ROOT" remote get-url upstream 2> /dev/null || git -C "$REPO_ROOT" remote get-url origin 2> /dev/null)")"

# Check if any of the default array elements are present in the command-line arguments
if grep -qPw "$(IFS=\|; echo "${VARIANTS[*]}")" <<< "$*"; then
  for arg in "$@"; do
    if grep -qw "$arg" <<< "${VARIANTS[*]}"; then
      VARIANTS_TO_BUILD+=("$arg")
    fi
  done
else
  VARIANTS_TO_BUILD=("${VARIANTS[@]}")
fi

echo "Variants to build: ${VARIANTS_TO_BUILD[*]}"

# Get the Samba version
# Note: This step take about 20-30 seconds to complete, not including pulling the image.
SAMBA_VERSION="$(docker run --rm -it "$BASE_IMAGE" bash -c "apt-get update &> /dev/null && apt-cache madison samba | sort -V | tail -1 | sed -z 's/^ *samba \| [^:]*:\([0-9.]\+\).*$/\1/;s/[\n\r]//g'")"
echo "Samba version: $SAMBA_VERSION"

# Get the Ubuntu version
UBUNTU_VERSION="$(docker run --rm -it "$BASE_IMAGE" bash -c "source /etc/os-release && sed -z 's/^\([0-9.]\+\).*$/\1/;s/[\r\n]//g' <<< \"\$VERSION\"")"
echo "Ubuntu version: $UBUNTU_VERSION"

# Version tag suffix
VERSION_TAG_SUFFIX="u$UBUNTU_VERSION-s$SAMBA_VERSION"
echo "Version tag suffix: $VERSION_TAG_SUFFIX"

# Check if an image with `$VERSION_TAG_SUFFIX` already exists
if docker pull "$VERSION_TAG_SUFFIX" &> /dev/null; then
  # Return the `latest` tag with `$1` prefixed
  TAG='latest'
else
  # Return the `$VERSION_TAG_SUFFIX` tag
  TAG="$VERSION_TAG_SUFFIX"
fi

# Check if the `force` option is not specified
if grep -qv 'force\|no-push' <<< "$*"; then
  ONE_HOUR_IN_SECONDS=3600
  ISO_SINCE_LAST_PUSH="$(git -C "$REPO_ROOT" log -1 --format=%cd --date=iso)"
  EPOCH_SINCE_LAST_PUSH="$(date -d "$ISO_SINCE_LAST_PUSH" +%s || date -jf '%Y-%m-%d %H:%M:%S %z' "$ISO_SINCE_LAST_PUSH" +%s)"
  SECONDS_SINCE_LAST_PUSH=$(($(date +%s) - EPOCH_SINCE_LAST_PUSH))

  # If there was a commit within the last hour, rebuild the container, even if it's already built
  if [ "$SECONDS_SINCE_LAST_PUSH" -gt "$ONE_HOUR_IN_SECONDS" ]; then
    # The last commit was not made within the past hour, check if the image tag exists, then create an image only if it does not exist
    echo 'check if image was already build and pushed - skip check on release version'
    # TODO: Check if the base tag (e.g. `a$version-s$version`) exists. Alternatively, check if each variant image for a particular version exists in the build loop below.
    grep -qv 'release' <<< "$*" && docker pull "$IMG:$TAG" &> /dev/null && echo 'image already build' && exit 1
  else
    # The last commit was made within the past hour, build the image without checking if the tag already exists
    echo 'commit within the last hour, we skip the version check and try to overwrite current build'
  fi
fi

# Define variables based on which we will build images where some optional programs are installed and non-installed programs are disabled
# - [0] tag name prefix;
# - [1] value of `AD_INSTALL`: whether to install Active Directory dependencies;
# - [2] value of `AVAHI_INSTALL`: whether to install Avahi;
# - [3] value of `WSDD2_INSTALL`: whether to install WSDD2;
# Note: The config variable name is matching the image tag name prefixes, but hyphens are replaced with underscores, while the full image (that has no prefix) is named `full`.
# shellcheck disable=SC2034 # `samba_ad_config` appears unused. Verify use (or export if used externally).
samba_ad_config=('smbd-ad-' 'true' 'false' 'false')
# shellcheck disable=SC2034 # `samba_avahi_config` appears unused. Verify use (or export if used externally).
samba_avahi_config=('smbd-avahi-' 'false' 'true' 'false')
# shellcheck disable=SC2034 # `samba_full_config` appears unused. Verify use (or export if used externally).
samba_full_config=('' 'true' 'true' 'true')
# shellcheck disable=SC2034 # `samba_only_config` appears unused. Verify use (or export if used externally).
samba_only_config=('smbd-only-' 'false' 'false' 'false')
# shellcheck disable=SC2034 # `samba_wsdd2_config` appears unused. Verify use (or export if used externally).
samba_wsdd2_config=('smbd-wsdd2-' 'false' 'false' 'true')

# Run QEMU hypervisor in a Docker container which enables execution of different multi-architecture containers by QEMU 1 and `binfmt_misc`
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Remove the builder instance if it exists
docker buildx rm "$BUILDER_INSTANCE_NAME" || true

# Create a new builder instance
docker buildx create --name "$BUILDER_INSTANCE_NAME" --driver docker-container --use

# Inspect the current builder instance
docker buildx inspect --bootstrap

# Build the images
for variant in "${VARIANTS_TO_BUILD[@]}"; do
  echo "Building $variant variant ..."

  declare -n config="samba_${variant}_config"

  # Note: This step takes about 130 seconds to complete, with `--no-cache`, not including pulling the image.
  # shellcheck disable=SC2046 # Quote this to prevent word splitting.
  docker buildx build \
    "$DEPENDANT_PUSH_TO_DOCKER_REGISTRY" \
    --build-arg "DOCKER_IMAGE_NAME=$IMG" \
    --build-arg "IMAGE_SOURCE_CODE_URL=$IMAGE_SOURCE_CODE_URL" \
    $([ "${config[1]}" = 'true' ] && echo '--build-arg AD_DISABLE=false' || echo '--build-arg AD_DISABLE=true') \
    $([ "${config[2]}" = 'true' ] && echo '--build-arg AVAHI_DISABLE=false' || echo '--build-arg AVAHI_DISABLE=true') \
    $([ "${config[3]}" = 'true' ] && echo '--build-arg WSDD2_DISABLE=false' || echo '--build-arg WSDD2_DISABLE=true') \
    --build-arg "AD_INSTALL=${config[1]}" \
    --build-arg "AVAHI_INSTALL=${config[2]}" \
    --build-arg "WSDD2_INSTALL=${config[3]}" \
    -f "$REPO_ROOT/ubuntu.dockerfile" \
    $(grep -q 'use-cache' <<< "$*" || echo '--no-cache') \
    $(grep -q 'no-push' <<< "$*" || echo "--platform '$(IFS=,; echo "${PLATFORMS[*]}")'") \
    $(grep -q 'plain-log' <<< "$*" && echo '--progress=plain') \
    --pull \
    -t "$IMG:${config[0]}latest" \
    -t "$IMG:${config[0]}$VERSION_TAG_SUFFIX" \
    "$REPO_ROOT"
done

# Remove any dangling images
dangling_images="$(docker images -f 'dangling=true' -q)"

if [ "$dangling_images" != '' ]; then
  # shellcheck disable=SC2086 # Double quote to prevent globbing and word splitting
  docker rmi -f $dangling_images
fi