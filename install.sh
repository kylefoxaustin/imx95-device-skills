#!/bin/bash
# install.sh — imx95-device-skills bootstrap installer
#
# Run this ONCE on the FRDM-IMX95 EVK board (or any i.MX 95 board running
# a Yocto NXP BSP image). It is idempotent — safe to re-run after updates.
#
# Usage:
#   bash install.sh [--prefix /opt/imx95-device-skills] [--skip-packages] [--dry-run]
#
# Environment overrides:
#   CLAUDE_SKILLS_DIR   — override install prefix (default: /opt/imx95-device-skills)
#   SKIP_PACKAGES=1     — skip apt/opkg package installation
#   DRY_RUN=1           — print actions without executing them

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PREFIX="/opt/imx95-device-skills"
INSTALL_PREFIX="${CLAUDE_SKILLS_DIR:-${DEFAULT_PREFIX}}"
SKIP_PACKAGES="${SKIP_PACKAGES:-0}"
DRY_RUN="${DRY_RUN:-0}"
PROFILE_D="/etc/profile.d/imx95-skills.sh"
SYMLINK_TARGET="/usr/local/bin/imx95-skill"
MIN_KERNEL_MAJOR=6
MIN_KERNEL_MINOR=6

# ---------------------------------------------------------------------------
# Colour helpers (safe — fall back to plain text if no tty)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

log_info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}==> $*${RESET}"; }
run_cmd()   {
    if [ "${DRY_RUN}" = "1" ]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
    else
        eval "$@"
    fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)       INSTALL_PREFIX="$2"; shift 2 ;;
        --skip-packages) SKIP_PACKAGES=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--prefix DIR] [--skip-packages] [--dry-run]"
            exit 0
            ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 1 — Verify this is an i.MX 95 board
# ---------------------------------------------------------------------------
log_step "Step 1/7 — Verifying board identity"

COMPATIBLE_FILE="/sys/firmware/devicetree/base/compatible"
MODEL_FILE="/sys/firmware/devicetree/base/model"

if [ ! -f "${COMPATIBLE_FILE}" ]; then
    log_error "Cannot read ${COMPATIBLE_FILE} — is this a Linux device-tree board?"
    log_error "This installer is designed for the NXP FRDM-IMX95 EVK."
    exit 1
fi

# /proc/device-tree/compatible is NUL-separated; use strings or tr
COMPATIBLE=$(tr '\0' '\n' < "${COMPATIBLE_FILE}" 2>/dev/null || cat "${COMPATIBLE_FILE}")
if ! echo "${COMPATIBLE}" | grep -qi "imx95"; then
    log_error "Board does not appear to be i.MX 95."
    log_error "compatible string: ${COMPATIBLE}"
    log_error "This repo targets i.MX 95 only. Aborting."
    exit 1
fi

BOARD_MODEL="unknown"
if [ -f "${MODEL_FILE}" ]; then
    BOARD_MODEL=$(cat "${MODEL_FILE}" | tr -d '\0')
fi
log_info "Board detected: ${BOARD_MODEL}"

# ---------------------------------------------------------------------------
# Step 2 — Verify kernel version >= 6.6
# ---------------------------------------------------------------------------
log_step "Step 2/7 — Checking kernel version"

KERNEL_VER=$(uname -r)
KERNEL_MAJOR=$(echo "${KERNEL_VER}" | cut -d. -f1)
KERNEL_MINOR=$(echo "${KERNEL_VER}" | cut -d. -f2 | cut -d- -f1)

if [ "${KERNEL_MAJOR}" -lt "${MIN_KERNEL_MAJOR}" ] || \
   { [ "${KERNEL_MAJOR}" -eq "${MIN_KERNEL_MAJOR}" ] && [ "${KERNEL_MINOR}" -lt "${MIN_KERNEL_MINOR}" ]; }; then
    log_warn "Kernel ${KERNEL_VER} is older than recommended ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR}."
    log_warn "Some sysfs paths may not exist. Proceeding anyway."
else
    log_info "Kernel ${KERNEL_VER} — OK"
fi

# ---------------------------------------------------------------------------
# Step 3 — Install system packages
# ---------------------------------------------------------------------------
log_step "Step 3/7 — Installing system packages"

if [ "${SKIP_PACKAGES}" = "1" ]; then
    log_info "Skipping package installation (--skip-packages)"
else
    # Detect package manager
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
        log_info "Package manager: apt"
        run_cmd "apt-get update -qq"
        PKGS="python3 python3-pip libgpiod2 gpiod v4l-utils gstreamer1.0-tools \
              gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
              media-ctl util-linux procps"
        for pkg in ${PKGS}; do
            if dpkg -l "${pkg}" &>/dev/null 2>&1; then
                log_info "  ${pkg} — already installed"
            else
                log_info "  Installing ${pkg}..."
                run_cmd "apt-get install -y -qq ${pkg}" || log_warn "  Could not install ${pkg} — skipping"
            fi
        done
    elif command -v opkg &>/dev/null; then
        PKG_MGR="opkg"
        log_info "Package manager: opkg"
        run_cmd "opkg update" || log_warn "opkg update failed — continuing with cached index"
        PKGS="python3 python3-pip libgpiod gpiod v4l-utils gstreamer1.0"
        for pkg in ${PKGS}; do
            if opkg list-installed | grep -q "^${pkg} "; then
                log_info "  ${pkg} — already installed"
            else
                log_info "  Installing ${pkg}..."
                run_cmd "opkg install ${pkg}" || log_warn "  Could not install ${pkg} — skipping"
            fi
        done
    else
        log_warn "No supported package manager found (apt or opkg). Skipping package install."
        log_warn "Ensure these tools are available: python3, gpioinfo, v4l2-ctl, gst-launch-1.0"
    fi
fi

# ---------------------------------------------------------------------------
# Step 4 — Copy skills and lib into install prefix
# ---------------------------------------------------------------------------
log_step "Step 4/7 — Installing skills to ${INSTALL_PREFIX}"

if [ "${SCRIPT_DIR}" != "${INSTALL_PREFIX}" ]; then
    run_cmd "mkdir -p '${INSTALL_PREFIX}'"
    run_cmd "cp -r '${SCRIPT_DIR}/skills'    '${INSTALL_PREFIX}/'"
    run_cmd "cp -r '${SCRIPT_DIR}/lib'       '${INSTALL_PREFIX}/'"
    run_cmd "cp -r '${SCRIPT_DIR}/agents'    '${INSTALL_PREFIX}/'"
    run_cmd "cp    '${SCRIPT_DIR}/CLAUDE.md' '${INSTALL_PREFIX}/'"
    run_cmd "cp    '${SCRIPT_DIR}/README.md' '${INSTALL_PREFIX}/'"
    log_info "Files copied to ${INSTALL_PREFIX}"
else
    log_info "Running from install prefix — no copy needed"
fi

# Make all scripts executable
log_info "Setting execute permissions on all scripts..."
run_cmd "find '${INSTALL_PREFIX}' -name '*.sh' -exec chmod +x {} \;"
run_cmd "find '${INSTALL_PREFIX}' -name '*.py' -exec chmod +x {} \;"

# ---------------------------------------------------------------------------
# Step 5 — Create /usr/local/bin/imx95-skill convenience symlink
# ---------------------------------------------------------------------------
log_step "Step 5/7 — Creating imx95-skill command"

RUNNER="${INSTALL_PREFIX}/lib/skill_runner.sh"

# Write a minimal skill runner if it doesn't exist yet
if [ ! -f "${RUNNER}" ]; then
    log_info "Writing skill_runner.sh..."
    if [ "${DRY_RUN}" != "1" ]; then
        mkdir -p "${INSTALL_PREFIX}/lib"
        cat > "${RUNNER}" << 'RUNNER_EOF'
#!/bin/bash
# skill_runner.sh — convenience wrapper: imx95-skill <skill-name> [args...]
set -euo pipefail
SKILLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills"
SKILL_NAME="${1:-}"
if [ -z "${SKILL_NAME}" ]; then
    echo "Usage: imx95-skill <skill-name> [args...]"
    echo "Available skills:"
    ls "${SKILLS_ROOT}"
    exit 1
fi
SKILL_DIR="${SKILLS_ROOT}/${SKILL_NAME}"
if [ ! -d "${SKILL_DIR}" ]; then
    echo "Error: skill '${SKILL_NAME}' not found in ${SKILLS_ROOT}" >&2
    exit 1
fi
shift
exec "${SKILL_DIR}/scripts/main.sh" "$@"
RUNNER_EOF
        chmod +x "${RUNNER}"
    fi
fi

if [ -L "${SYMLINK_TARGET}" ] || [ -f "${SYMLINK_TARGET}" ]; then
    log_info "${SYMLINK_TARGET} already exists — updating"
    run_cmd "ln -sf '${RUNNER}' '${SYMLINK_TARGET}'"
else
    run_cmd "ln -sf '${RUNNER}' '${SYMLINK_TARGET}'" || \
        log_warn "Could not create ${SYMLINK_TARGET} — you may need root. Run manually: ln -sf ${RUNNER} ${SYMLINK_TARGET}"
fi

# ---------------------------------------------------------------------------
# Step 6 — Add skills to PATH via /etc/profile.d
# ---------------------------------------------------------------------------
log_step "Step 6/7 — Configuring PATH"

if [ "${DRY_RUN}" != "1" ]; then
    cat > "${PROFILE_D}" << PROFILE_EOF
# imx95-device-skills — added by install.sh
export IMX95_SKILLS_ROOT="${INSTALL_PREFIX}"
export PATH="\${PATH}:${INSTALL_PREFIX}/lib"
PROFILE_EOF
    chmod 644 "${PROFILE_D}"
    log_info "Written ${PROFILE_D}"
else
    echo "[DRY-RUN] Would write ${PROFILE_D}"
fi

# ---------------------------------------------------------------------------
# Step 7 — Smoke test: run imx95-print-device-info
# ---------------------------------------------------------------------------
log_step "Step 7/7 — Smoke test"

SMOKE_SCRIPT="${INSTALL_PREFIX}/skills/imx95-print-device-info/scripts/print_info.sh"

if [ -f "${SMOKE_SCRIPT}" ]; then
    log_info "Running smoke test: ${SMOKE_SCRIPT}"
    if [ "${DRY_RUN}" != "1" ]; then
        if bash "${SMOKE_SCRIPT}"; then
            log_info "Smoke test PASSED"
        else
            log_warn "Smoke test returned non-zero — check output above"
        fi
    else
        echo "[DRY-RUN] Would run: bash ${SMOKE_SCRIPT}"
    fi
else
    log_warn "Smoke test script not found at ${SMOKE_SCRIPT} — skipping"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  imx95-device-skills installed successfully!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "  Install prefix : ${BOLD}${INSTALL_PREFIX}${RESET}"
echo -e "  CLI command    : ${BOLD}imx95-skill <skill-name>${RESET}"
echo -e "  Claude command : ${BOLD}claude --ssh root@<board-ip> --repo ${INSTALL_PREFIX}${RESET}"
echo ""
echo -e "  Source the new PATH now (or open a new shell):"
echo -e "    ${CYAN}source ${PROFILE_D}${RESET}"
echo ""
echo -e "  Available skills:"
if [ -d "${INSTALL_PREFIX}/skills" ]; then
    for d in "${INSTALL_PREFIX}/skills"/*/; do
        skill_name=$(basename "${d}")
        echo -e "    • ${skill_name}"
    done
fi
echo ""
