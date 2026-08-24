#!/bin/sh

# =========================================================================
# One-liner execution command:
# wget -qO - https://raw.githubusercontent.com/tarekzoka/audioselectionpatcher/refs/heads/main/myinstaller.sh | /bin/sh
# =========================================================================

PLUGIN_NAME="AudioSelectionPatcher"
USERNAME="popking159"
REPO="audioselectionpatcher"

# 1. PYTHON DEPENDENCIES (Core module names without prefixes)
PY_DEPENDS="requests"

# 2. SYSTEM DEPENDENCIES
SYS_DEPENDS=""

# Workspace paths
TMP_DIR="/var/volatile/tmp"
[ -d "$TMP_DIR" ] || TMP_DIR="/tmp"

PKG_MANAGER=""
PYTHON_VERSION=""
PY_VER=""
ARCH=""
FINAL_DEPENDS=""

log() {
    echo "$1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

is_pkg_installed() {
    pkg="$1"
    if [ "$PKG_MANAGER" = "opkg" ]; then
        if [ -f /var/lib/opkg/status ]; then
            grep -q "^Package: $pkg$" /var/lib/opkg/status && return 0
        fi
        opkg list-installed 2>/dev/null | grep -q "^$pkg[[:space:]-]" && return 0
        return 1
    fi
    
    if [ "$PKG_MANAGER" = "apt" ]; then
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" && return 0
        return 1
    fi
    return 1
}

echo "===================================================="
echo "         $PLUGIN_NAME INSTALLER UTILITY             "
echo "===================================================="

# 1. Detect Package Manager
if has_cmd opkg; then
    PKG_MANAGER="opkg"
elif has_cmd apt-get; then
    PKG_MANAGER="apt"
fi
log "[INFO] Package manager detected: ${PKG_MANAGER:-None}"

# 2. Detect Python Version
if has_cmd python3; then
    PYTHON_VERSION="3"
    PY_PREFIX="python3-"
    PY_VER=$(python3 -c 'import sys; print("%d%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
elif has_cmd python; then
    PYTHON_VERSION="2"
    PY_PREFIX="python-"
    PY_VER=$(python -c 'import sys; print("%d%d" % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
fi

# Fallback for Python version from enigma.info if python command returned blank
if [ -z "$PY_VER" ] && [ -f /usr/lib/enigma.info ]; then
    PY_VER_RAW=$(grep "^python=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"" | tr -d ".")
    if [ -n "$PY_VER_RAW" ]; then
        PY_VER="$PY_VER_RAW"
    fi
fi

log "[INFO] Detected Python Version: Python $PY_VER (Major: $PYTHON_VERSION)"

# 3. Detect STB Architecture
# Method A: Check /usr/lib/enigma.info (Most reliable for modern boxes like Novaler, Octagon, etc.)
if [ -f /usr/lib/enigma.info ]; then
    INFO_ARCH=$(grep "^architecture=" /usr/lib/enigma.info | cut -d"=" -f2 | tr -d "'\"")
    case "$INFO_ARCH" in
        cortexa15hf-neon-vfpv4|armv7ahf-neon|aarch64)
            ARCH="$INFO_ARCH"
            ;;
    esac
fi

# Method B: Check /etc/opkg/arch.conf or opkg.conf if still unset
if [ -z "$ARCH" ] && [ -f /etc/opkg/arch.conf ]; then
    if grep -q "cortexa15hf-neon-vfpv4" /etc/opkg/arch.conf; then
        ARCH="cortexa15hf-neon-vfpv4"
    elif grep -q "armv7ahf-neon" /etc/opkg/arch.conf; then
        ARCH="armv7ahf-neon"
    elif grep -q "aarch64" /etc/opkg/arch.conf; then
        ARCH="aarch64"
    fi
fi

# Method C: Kernel architecture fallback
if [ -z "$ARCH" ]; then
    UNAME_M=$(uname -m)
    case "$UNAME_M" in
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l|arm*)
            ARCH="cortexa15hf-neon-vfpv4"
            ;;
    esac
fi

log "[INFO] Detected Architecture: ${ARCH:-Unknown}"

# Verify supported arch and python
case "$ARCH" in
    cortexa15hf-neon-vfpv4|armv7ahf-neon|aarch64)
        ;;
    *)
        log "[ERROR] Unsupported STB architecture: '$ARCH'. Aborting installation."
        exit 1
        ;;
esac

case "$PY_VER" in
    313|314)
        ;;
    *)
        log "[WARN] Detected Python version is $PY_VER (Official pre-builds are for 313/314)."
        ;;
esac

# 4. Construct File Name and Download URL
ARCHIVE_NAME="${PLUGIN_NAME}_${ARCH}_${PY_VER}.tar.gz"
PLUGIN_URL="https://github.com/${USERNAME}/${REPO}/raw/refs/heads/main/${ARCHIVE_NAME}"
TMP_FILE="$TMP_DIR/$ARCHIVE_NAME"

log "[INFO] Target Package: $ARCHIVE_NAME"
log "[INFO] Download Link: $PLUGIN_URL"

# 5. Build Dependency List
for dep in $PY_DEPENDS; do
    [ -n "$dep" ] && FINAL_DEPENDS="$FINAL_DEPENDS ${PY_PREFIX}${dep}"
done
for dep in $SYS_DEPENDS; do
    [ -n "$dep" ] && FINAL_DEPENDS="$FINAL_DEPENDS $dep"
done

# 6. Update Package Feeds & Install Dependencies
if [ -n "$FINAL_DEPENDS" ] && [ -n "$PKG_MANAGER" ]; then
    log "[INFO] Updating package feeds..."
    if [ "$PKG_MANAGER" = "opkg" ]; then
        opkg update >/dev/null 2>&1 || log "[WARN] opkg update failed, attempting installation anyway..."
    elif [ "$PKG_MANAGER" = "apt" ]; then
        apt-get update >/dev/null 2>&1 || log "[WARN] apt-get update failed, attempting installation anyway..."
    fi

    log "[INFO] Verifying required dependencies: $FINAL_DEPENDS"
    for pkg in $FINAL_DEPENDS; do
        if is_pkg_installed "$pkg"; then
            log "[OK] Dependency already installed: $pkg"
        else
            log "[INFO] Installing: $pkg"
            if [ "$PKG_MANAGER" = "opkg" ]; then
                opkg install "$pkg" >/dev/null 2>&1
            elif [ "$PKG_MANAGER" = "apt" ]; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1
            fi
            
            if is_pkg_installed "$pkg"; then
                log "[OK] Successfully installed: $pkg"
            else
                log "[WARN] Could not install '$pkg', continuing..."
            fi
        fi
    done
fi

# 7. Download Plugin Archive
log "[INFO] Downloading package archive..."
rm -f "$TMP_FILE"

if has_cmd wget; then
    wget -q --no-check-certificate "$PLUGIN_URL" -O "$TMP_FILE"
elif has_cmd curl; then
    curl -s -k -L "$PLUGIN_URL" -o "$TMP_FILE"
fi

if [ ! -s "$TMP_FILE" ]; then
    log "[ERROR] Download failed or file not found on GitHub!"
    log "[ERROR] Checked URL: $PLUGIN_URL"
    rm -f "$TMP_FILE"
    exit 1
fi

# 8. Extract Archive directly to Root (/)
log "[INFO] Extracting files..."
tar -xzf "$TMP_FILE" -C /
if [ $? -ne 0 ]; then
    log "[ERROR] Extraction failed!"
    rm -f "$TMP_FILE"
    exit 1
fi

# 9. Cleanup and Finalize
rm -f "$TMP_FILE"
sync

echo "===================================================="
echo "          $PLUGIN_NAME INSTALLATION COMPLETE        "
echo "===================================================="
echo "[INFO] Installed successfully for $ARCH (Python $PY_VER)."
echo "[INFO] Please restart GUI / Enigma2 to activate changes."

exit 0
