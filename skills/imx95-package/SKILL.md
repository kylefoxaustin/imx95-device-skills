---
name: imx95-package
version: "0.1.0"
platform: imx95
invoke_when:
  - "install a package"
  - "install python"
  - "install numpy"
  - "remove a package"
  - "uninstall a package"
  - "search for a package"
  - "what packages are installed"
  - "list installed packages"
  - "update packages"
  - "package manager"
  - "apt install"
  - "opkg install"
  - "is package X installed"
requires:
  - bash
safe: false
destructive: false
---

# Skill: imx95-package

## Purpose

Detects whether the board uses `apt` (Debian/Ubuntu-based images) or `opkg` (Yocto/OpenEmbedded
images) and wraps install, remove, search, and list-installed operations in a unified interface.

> ## 🔴 ON THE FLEET BOARD, INSTALLING IS EXPECTED TO FAIL — AND THE SKILL NOW SAYS SO
>
> **The FRDM-IMX95-PRO runs a sealed Yocto image with NO WORKING PACKAGE FEED** [MEASURED —
> ground-truth §5]. `opkg update` does not fail here *occasionally*; it fails **every time**.
>
> ⚠️ **This SKILL.md and all four of its scripts previously made zero mention of that** — the
> skill's whole premise contradicted a measured fact in the ground truth. Worse,
> `install_pkg.sh` did:
>
> ```
> opkg update || log_warn "opkg update failed — using cached index"
> opkg install "$PKG"            # ← proceeded regardless
> ```
>
> So on this board it **always** fell through to installing from a stale or empty cache, and
> *"using cached index"* read as a caveat rather than a stop. **That is the delegate bug's shape
> exactly** — the warning was present, correct, and useless, because a warning printed above an
> action is read as a caveat and an exit code is read as a stop.
>
> It now **refuses with exit 4** and names the supported path instead: build on the host and `scp`
> over. A native build is a real option — **gcc 15.2 is on-board**, and
> `/usr/lib/libtensorflow-lite.so.2.19.0` exports the full TFLite C API (no headers ship; fetch the
> v2.19.0 C headers and `-Iinclude` them).
>
> `apt` paths are left intact and untouched — they are for *other* images, and nobody has measured
> one. Treat them as [UNVERIFIED].

Use this skill:
- When the user asks to install or remove a package
- To check if a package is installed
- To search for available packages
- When a skill's `requires:` check fails and a package needs to be installed

**Safety note:** Package installation modifies the root filesystem. Claude presents the
package name and operation to the user before running. On read-only rootfs images, package
installation will fail — the skill detects this and advises the user.

---

## Usage

```bash
# Auto-detect package manager and install
bash skills/imx95-package/scripts/detect_pkg_manager.sh   # shows which PM is active

# Install a package
bash skills/imx95-package/scripts/install_pkg.sh <package-name>

# Remove a package
bash skills/imx95-package/scripts/remove_pkg.sh <package-name>

# Search for a package
bash skills/imx95-package/scripts/search_pkg.sh <search-term>

# List installed packages (optionally filter)
bash skills/imx95-package/scripts/list_installed.sh [filter]
```

---

## Step-by-Step Procedure

1. Run `detect_pkg_manager.sh` to determine `apt` or `opkg`.
2. Check if rootfs is read-write (`mount | grep " on / "` — look for `rw`).
   If read-only, warn the user and stop.
3. For install: confirm package name with user, then run `install_pkg.sh`.
4. For remove: confirm package name with user, then run `remove_pkg.sh`.
5. Verify success by checking if the package is now installed/removed.

---

## Caveats

- Yocto images are often read-only by default. To make rootfs writable:
  `mount -o remount,rw /`
  Note: changes are lost on reboot unless the image is rebuilt.
- `opkg` requires network access to the package feed server. On isolated boards,
  packages must be installed from a local feed or built into the image.
- Package names differ between apt and opkg. The skill uses the name as given;
  if not found, it suggests searching with `search_pkg.sh`.
- Some packages require a BSP-specific feed URL for opkg. Check
  `/etc/opkg/` for configured feeds.
