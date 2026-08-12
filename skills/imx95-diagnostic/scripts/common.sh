#!/bin/bash
# skills/imx95-diagnostic/scripts/common.sh
#
# Local common.sh for the imx95-diagnostic skill.
# Sources the shared lib/common.sh and lib/sysfs.sh from the repo root,
# then sources lib/board_detect.sh to populate BOARD_* variables.
#
# All skill scripts in this directory should source THIS file, not the
# lib/ files directly, so that the relative path resolution is centralised.

# Guard against double-sourcing
[[ -n "${_IMX95_DIAG_COMMON_LOADED:-}" ]] && return 0
_IMX95_DIAG_COMMON_LOADED=1

# Resolve repo root: this file is at skills/imx95-diagnostic/scripts/common.sh
# so repo root is three levels up.
_DIAG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_DIAG_SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${_REPO_ROOT}/lib/common.sh"

# shellcheck source=lib/sysfs.sh
source "${_REPO_ROOT}/lib/sysfs.sh"

# shellcheck source=lib/board_detect.sh
source "${_REPO_ROOT}/lib/board_detect.sh"
