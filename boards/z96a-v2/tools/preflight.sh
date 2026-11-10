#!/bin/bash
# Build preflight for z96a-v2: fail before a build starts, not inside chroot.
#
# Checks that every packaging input exists and agrees with the others:
#   board variables, kernel defconfig, rootfs overlay layout, layered package
#   lists vs generated runtime-packages.txt, bundled deb checksums, U-Boot
#   blobs, patch directories, version consistency.
#
# Usage:
#   boards/z96a-v2/tools/preflight.sh [--quiet]
set -u

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BOARD=z96a-v2
BOARD_FILE="lib/boards/$BOARD"
DEFCONFIG="defconfig/${BOARD}_defconfig"
OVERLAY="files/rootfs-overlay/$BOARD"
PKG_DIR="$OVERLAY/opt/z96a/packages"
RUNTIME="$OVERLAY/opt/z96a/runtime-packages.txt"
LAYERS="boards/$BOARD/packages"
UBOOT_DIR="files/boot/uboot/$BOARD"

fail=0
ok()   { [ "$QUIET" -eq 1 ] || printf 'ok    %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
note() { [ "$QUIET" -eq 1 ] || printf 'note  %s\n' "$*"; }

# --- config single source (phase 2 M1) ----------------------------------
if [ -x "boards/$BOARD/tools/gen-board-config.sh" ]; then
    if "boards/$BOARD/tools/gen-board-config.sh" --check >/dev/null 2>&1; then
        ok "config/z96a-v2.toml matches lib/boards/$BOARD"
    else
        bad "config/$BOARD.toml and lib/boards/$BOARD disagree (run --write)"
    fi
fi

# --- board variables ----------------------------------------------------
if [ ! -f "$BOARD_FILE" ]; then
    bad "missing $BOARD_FILE"
else
    if bash -n "$BOARD_FILE" 2>/dev/null; then ok "board file syntax"; else bad "board file syntax"; fi
    get_var() {
        sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$BOARD_FILE" | head -n 1
    }
    for var in BOARD ARCH FAMILY DTB LINUX_DEFCONFIG GIT_REPO GIT_BRANCH \
               GIT_PIN_COMMIT FORCE_LINUX_VERSION FORCE_UBOOT_VERSION; do
        value=$(get_var "$var")
        if [ -n "$value" ]; then ok "board var $var=$value"; else bad "board var $var is empty"; fi
    done
    pin=$(get_var GIT_PIN_COMMIT)
    if printf '%s' "$pin" | grep -Eq '^[0-9a-f]{40}$'; then
        ok "kernel commit pinned"
    else
        bad "GIT_PIN_COMMIT is not a full 40-char commit ($pin)"
    fi
    defconfig_var=$(get_var LINUX_DEFCONFIG)
    [ -n "$defconfig_var" ] && [ -f "defconfig/$defconfig_var" ] \
        && ok "kernel defconfig present" || bad "defconfig/$defconfig_var missing"
fi

# --- kernel defconfig ---------------------------------------------------
if [ -f "$DEFCONFIG" ]; then
    for opt in 'CONFIG_GENERIC_ADC_THERMAL=y' 'CONFIG_MMC=y'; do
        grep -qx "$opt" "$DEFCONFIG" && ok "defconfig $opt" || bad "defconfig lacks $opt"
    done
    for opt in CONFIG_DRM_PANFROST CONFIG_VIDEO_ROCKCHIP_VDEC; do
        grep -Eq "^$opt=[ym]$" "$DEFCONFIG" && ok "defconfig $opt" || bad "defconfig lacks $opt"
    done
else
    bad "missing $DEFCONFIG"
fi

# --- overlay layout -----------------------------------------------------
if [ -d "$OVERLAY" ]; then
    for entry in "$OVERLAY"/*; do
        [ -e "$entry" ] || continue
        case "$(basename "$entry")" in
            etc|home|opt|usr) ;;
            *) bad "overlay has directory the build ignores: $(basename "$entry")" ;;
        esac
    done
    ok "overlay top-level layout"
else
    bad "missing $OVERLAY"
fi

# --- package layering ---------------------------------------------------
for layer in base desktop multimedia applications; do
    [ -f "$LAYERS/$layer.txt" ] && ok "package layer $layer.txt" || bad "missing $LAYERS/$layer.txt"
done

if [ -f "$RUNTIME" ] && [ -d "$LAYERS" ]; then
    tmp=$(mktemp)
    for layer in base desktop multimedia applications; do
        [ -f "$LAYERS/$layer.txt" ] || continue
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$LAYERS/$layer.txt" |
            grep -v '^#' | grep -v '^$' >> "$tmp"
    done
    if diff -q <(sort -u "$tmp") <(grep -v '^#' "$RUNTIME" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' | sort -u) >/dev/null 2>&1; then
        ok "runtime-packages.txt matches layers"
    else
        bad "runtime-packages.txt is out of date; run boards/$BOARD/tools/gen-runtime-packages.sh"
    fi
    dupes=$(sort "$tmp" | uniq -d)
    [ -z "$dupes" ] && ok "no duplicate packages across layers" || bad "duplicate packages: $dupes"
    rm -f "$tmp"
fi

# --- bundled debs and checksums ----------------------------------------
if [ -d "$PKG_DIR" ]; then
    has_debs=0
    for deb in "$PKG_DIR"/*.deb; do [ -e "$deb" ] && has_debs=1 && break; done
    metadata_only=0
    if [ "$has_debs" -eq 0 ] && [ "${Z96A_PREFLIGHT_ALLOW_MISSING_PACKAGES:-0}" = "1" ]; then
        metadata_only=1
        note "binary package blobs absent; validating package metadata only"
    elif [ "$has_debs" -eq 0 ]; then
        bad "no bundled debs present; run boards/$BOARD/tools/fetch-packages.sh"
    fi
    if [ -f "boards/$BOARD/packages-sources.tsv" ]; then
        ok "package sources table present"
        while IFS=$'\t' read -r name sha _rest; do
            case "$name" in ''|'#'*) continue ;; esac
            if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$'; then
                bad "package sources entry has invalid sha256: $name"
                continue
            fi
            if [ "$metadata_only" -eq 1 ]; then
                grep -q "^$sha  $name\$" "$PKG_DIR/SHA256SUMS" 2>/dev/null \
                    || bad "package source missing/mismatched in SHA256SUMS: $name"
            elif [ ! -f "$PKG_DIR/$name" ]; then
                bad "package listed but missing on disk: $name"
            fi
        done < "boards/$BOARD/packages-sources.tsv"
    else
        bad "missing boards/$BOARD/packages-sources.tsv"
    fi
    if [ -f "$PKG_DIR/SHA256SUMS" ]; then
        ok "SHA256SUMS present"
        missing=0
        for deb in "$PKG_DIR"/*.deb; do
            [ -e "$deb" ] || continue
            name=$(basename "$deb")
            grep -q "  $name\$" "$PKG_DIR/SHA256SUMS" || { bad "deb not in SHA256SUMS: $name"; missing=1; }
        done
        [ "$missing" -eq 0 ] && ok "all bundled debs are checksummed"
        if [ "$metadata_only" -eq 1 ]; then
            ok "package metadata and checksum manifest agree"
        elif [ "${Z96A_PREFLIGHT_HASH:-0}" = "1" ]; then
            ( cd "$PKG_DIR" && sha256sum -c --quiet SHA256SUMS >/dev/null 2>&1 ) \
                && ok "deb checksums verify" || bad "deb checksum mismatch"
        else
            note "deep checksum skipped (set Z96A_PREFLIGHT_HASH=1)"
        fi
    else
        bad "missing $PKG_DIR/SHA256SUMS"
    fi
    # every deb referenced by the userscript (main script + modules) must exist
    if [ -f "boards/$BOARD/userscripts/uscripts" ]; then
        refs=$(cat "boards/$BOARD/userscripts/uscripts" $(find "boards/$BOARD/userscripts" -mindepth 2 -name '*.sh' | sort) 2>/dev/null)
        for ref in $(printf '%s\n' "$refs" | grep -o '/opt/z96a/packages/[A-Za-z0-9._+-]*\.deb' | sort -u); do
            if [ "$metadata_only" -eq 1 ]; then
                name=${ref##*/}
                grep -q "  $name\$" "$PKG_DIR/SHA256SUMS" 2>/dev/null \
                    || bad "userscript package absent from checksum manifest: $ref"
            else
                [ -f "$OVERLAY$ref" ] || bad "userscript references missing package: $ref"
            fi
        done
        ok "userscript package references checked"
    fi
fi

# --- boot blobs ---------------------------------------------------------
for blob in u-boot.bin idbloader.bin; do
    [ -f "$UBOOT_DIR/$blob" ] && ok "u-boot blob $blob" || bad "missing $UBOOT_DIR/$blob"
done

# --- patches ------------------------------------------------------------
for dir in "patches/git/$BOARD" "patches/${FAMILY:-rockchip}" "patches/uboot"; do
    [ -d "$dir" ] && ok "patch dir $dir" || bad "missing patch dir $dir"
done

# --- version consistency ------------------------------------------------
board_version=$(sed -n 's/^FORCE_LINUX_VERSION="\([^"]*\)".*/\1/p' "$BOARD_FILE" | head -n 1)
userdata_version=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' userdata.txt | head -n 1)
if [ -n "$board_version" ] && [ "$board_version" = "$userdata_version" ]; then
    ok "kernel version sources agree ($board_version)"
else
    bad "kernel version mismatch: board=$board_version userdata=$userdata_version"
fi

# phase 2 §7.9: defconfig trim applied
if [ -x "boards/$BOARD/tools/trim-defconfig.sh" ]; then
    if "boards/$BOARD/tools/trim-defconfig.sh" --check >/dev/null 2>&1; then
        ok "defconfig trim applied"
    else
        bad "defconfig trim not applied (run boards/$BOARD/tools/trim-defconfig.sh)"
    fi
    [ -f "boards/$BOARD/defconfig-trim.txt" ] && ok "defconfig trim list present" \
        || bad "missing boards/$BOARD/defconfig-trim.txt"
fi

# chroot result cache (build speed)
if [ -x "boards/$BOARD/tools/chroot-cache.sh" ]; then
    ok "chroot cache tool present"
else
    bad "missing boards/$BOARD/tools/chroot-cache.sh"
fi

# prune tool must exist and be executable (run at the end of stage1)
if [ -x "boards/$BOARD/tools/prune-rootfs.sh" ]; then
    ok "rootfs prune tool present"
else
    bad "missing boards/$BOARD/tools/prune-rootfs.sh"
fi

# phase 2 M4: board runtime generator present and syntactically valid
runtime_gen="boards/$BOARD/tools/gen-board-runtime.py"
if [ -f "$runtime_gen" ]; then
    if python3 -c "compile(open('$runtime_gen').read(), '$runtime_gen', 'exec')" 2>/dev/null; then
        ok "board runtime generator present"
    else
        bad "board runtime generator does not compile"
    fi
    staging=lib/function/staging
    if grep -q 'gen-board-runtime.py' "$staging"; then
        ok "customize_image uses the generator"
    else
        bad "customize_image does not call gen-board-runtime.py"
    fi
    if grep -q 'userscripts/${sub}' lib/source; then
        ok "lib/source copies userscript modules into chroot"
    else
        bad "lib/source does not copy userscript modules (chroot will fail)"
    fi
    for hook in scripts/stage1 scripts/stage2; do
        grep -q 'board.runtime' "$hook" && ok "runtime override applied in $hook" \
            || bad "$hook does not apply board.runtime"
    done
else
    bad "missing $runtime_gen"
fi

# derived fields: userdata.txt must agree with the board TOML values
board_uboot=$(sed -n 's/^FORCE_UBOOT_VERSION="\([^"]*\)".*/\1/p' "$BOARD_FILE" | head -n 1)
userdata_uboot=$(sed -n 's/^UBOOT_VERSION="\([^"]*\)".*/\1/p' userdata.txt | head -n 1)
if [ -n "$board_uboot" ] && [ "$board_uboot" = "$userdata_uboot" ]; then
    ok "u-boot version sources agree ($board_uboot)"
else
    bad "u-boot version mismatch: board=$board_uboot userdata=$userdata_uboot"
fi

# board userscript module split (phase 2)
userscript_dir="boards/$BOARD/userscripts"
if [ -f "$userscript_dir/uscripts" ]; then
    ok "board userscript entry point"
    modules=$(find "$userscript_dir" -mindepth 2 -name '*.sh' | sort)
    if [ -z "$modules" ]; then
        bad "no userscript modules under $userscript_dir"
    else
        module_fail=0
        for module in $modules; do
            bash -n "$module" 2>/dev/null || { bad "module syntax: $module"; module_fail=1; }
        done
        module_count=$(printf '%s\n' "$modules" | wc -l)
        [ "$module_fail" -eq 0 ] && ok "userscript modules parse ($module_count files)"
    fi
fi

if [ "$fail" -eq 0 ]; then
    [ "$QUIET" -eq 1 ] || echo "PREFLIGHT: PASS"
    exit 0
fi
echo "PREFLIGHT: FAIL ($fail)"
exit 1
