#!/usr/bin/env bash

# From https://github.com/bazelbuild/bazel/blob/8fa6b3fe71f91aac73c222d8082e75c69d814fa7/tools/bash/runfiles/runfiles.bash#L15-L64
# --- begin runfiles.bash initialization v2 ---
# Copy-pasted from the Bazel Bash runfiles library v2.
# set -uo pipefail; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
#   source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
#   source "$0.runfiles/$f" 2>/dev/null || \
#   source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
#   source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
#   { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# # --- end runfiles.bash initialization v2 ---

# Copyright 2020 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

function guess_runfiles() {
    if [ -d ${BASH_SOURCE[0]}.runfiles ]; then
        # Runfiles are adjacent to the current script.
        echo "$( cd ${BASH_SOURCE[0]}.runfiles && pwd )"
    else
        # The current script is within some other script's runfiles.
        mydir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
        echo $mydir | sed -e 's|\(.*\.runfiles\)/.*|\1|'
    fi
}

RUNFILES="${PYTHON_RUNFILES:-$(guess_runfiles)}"

function rlocation() {
  echo $RUNFILES/$1
}

# echo RUNFILES_DIR=$RUNFILES_DIR

set -o nounset
set -o pipefail

PASSTHROUGH_ARGS=()
is_bazel_run=true
TARGET_DIR_PREFIX=%{target_dir_prefix}
WORKSPACE_TARGET=%{workspace_target}
# parse command line parameters
while [[ $# -gt 0 ]]
do
  key="$1"
  case $key in
    --deployment_root|--deployment-root)
    PASSTHROUGH_ARGS+=('--render' "$2/$TARGET_DIR_PREFIX")
    shift # past argument
    shift # past value
    ;;
    --nobazel)
    PASSTHROUGH_ARGS+=('--nobazel')
    is_bazel_run=false
    shift
    ;;
    --nopush|--push_all|--push_sequentially|--list_push_targets)
    PASSTHROUGH_ARGS+=("$1")
    shift
    ;;
    --push_target)
    PASSTHROUGH_ARGS+=("$1" "$2")
    shift
    shift
    ;;
    *)    # unknown option
    echo $(basename $0): unsupported parameter $1
    exit 1
    ;;
  esac
done

: ${BUILD_WORKSPACE_DIRECTORY:=}

if [ -n "$BUILD_WORKSPACE_DIRECTORY" ]; then
  cd $BUILD_WORKSPACE_DIRECTORY
fi

exec $(rlocation $WORKSPACE_TARGET) "${PASSTHROUGH_ARGS[@]}"
