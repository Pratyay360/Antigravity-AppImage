#!/usr/bin/env bash

set -euo pipefail

# --- Configuration ---
readonly APP_NAME="antigravity"
readonly DISPLAY_NAME="AntiGravity"
readonly INSTALL_DIR_NAME=".tarball-installations"
readonly INSTALL_BASE="${HOME}/${INSTALL_DIR_NAME}"
readonly APP_DIR="${INSTALL_BASE}/${APP_NAME}"
readonly LOCAL_BIN="${HOME}/.local/bin"
readonly LOCAL_APPS="${HOME}/.local/share/applications"
readonly BIN_LINK="${LOCAL_BIN}/${APP_NAME}"
readonly DESKTOP_FILE="${LOCAL_APPS}/${APP_NAME}.desktop"
readonly METADATA_URL="https://antigravity-auto-updater-974169037036.us-central1.run.app/api/update/linux-x64/stable/latest"

# --- Desktop entry metadata ---
readonly DESKTOP_KEYWORDS="web,development,antigravity,api,text,editor"
readonly DESKTOP_TERMINAL="false"
readonly DESKTOP_TYPE="Application"
readonly DESKTOP_CATEGORIES="Development;"
readonly DESKTOP_STARTUP_WM_CLASS="AntiGravity"

# --- Colors for output (optional, falls back gracefully) ---
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly NC=''
fi

# --- Functions ---
cleanup() {
    local exit_antigravity=$?
    # Clean up temp files if they exist
    [[ -n "${TAR_FILE:-}" && -f "$TAR_FILE" ]] && rm -f "$TAR_FILE"
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    exit $exit_antigravity
}

error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT ERR

# --- Main installation process ---
info "Welcome to ${DISPLAY_NAME} tarball installer..."

# Check dependencies
if ! command -v curl &>/dev/null; then
    error_exit "curl is required but not installed"
fi

if ! command -v jq &>/dev/null; then
    error_exit "jq is required but not installed (sudo apt install jq / sudo pacman -S jq / brew install jq)"
fi

info "Fetching latest metadata..."
metadata="$(curl -fsSL "$METADATA_URL")"

version="$(jq -r '.productVersion' <<<"$metadata")"
package_url="$(jq -r '.url | select(endswith(".tar.gz"))' <<<"$metadata" | head -n 1)"

[[ -z "$version" || "$version" == "null" ]] && error_exit "Unable to determine version from metadata"
[[ -z "$package_url" || "$package_url" == "null" ]] && error_exit "Unable to determine package URL from metadata"

info "Latest version: ${version}"
info "Package URL: ${package_url}"

# --- Cleanup old installation ---
if [[ -L "$BIN_LINK" ]]; then
    info "Removing old symlink..."
    rm "$BIN_LINK"
elif [[ -f "$BIN_LINK" ]]; then
    warn "Removing old file at ${BIN_LINK}..."
    rm "$BIN_LINK"
fi

if [[ -d "$APP_DIR" ]]; then
    info "Removing old installation directory..."
    rm -rf "$APP_DIR"
fi

if [[ -f "$DESKTOP_FILE" ]]; then
    info "Removing old desktop entry..."
    rm "$DESKTOP_FILE"
fi

# --- Download ---
info "Downloading package..."
TAR_FILE="$(mktemp /tmp/antigravity.XXXXXX.tar.gz)"
wget -q "$package_url" -O "$TAR_FILE"
info "Downloaded to ${TAR_FILE}"

# --- Extract ---
info "Extracting..."
WORK_DIR="$(mktemp -d)"
tar -xzf "$TAR_FILE" -C "$WORK_DIR" --strip-components=1

# --- Verify and read version from package.json ---
if [[ -f "$WORK_DIR/resources/app/package.json" ]]; then
    app_version="$(jq -r '.version' "$WORK_DIR/resources/app/package.json")"
    info "Detected app version inside package: ${app_version}"
else
    warn "package.json not found in extracted archive"
fi

# Verify expected structure
if [[ ! -f "$WORK_DIR/antigravity" ]]; then
    error_exit "Expected executable 'antigravity' not found in extracted archive"
fi

if [[ ! -f "$WORK_DIR/resources/app/resources/linux/antigravity.png" ]]; then
    warn "Icon file not found at expected location"
fi

# --- Install ---
info "Installing to ${APP_DIR}..."
mkdir -p "$INSTALL_BASE"
mv "$WORK_DIR" "$APP_DIR"

# --- Create symlink ---
mkdir -p "$LOCAL_BIN"
ln -sf "${APP_DIR}/antigravity" "$BIN_LINK"
info "Binary linked to ${BIN_LINK}"

# --- Create desktop entry ---
mkdir -p "$LOCAL_APPS"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=${DISPLAY_NAME}
Keywords=${DESKTOP_KEYWORDS}
Exec=${APP_DIR}/antigravity %u
Icon=${APP_DIR}/resources/app/resources/linux/code.png
Terminal=${DESKTOP_TERMINAL}
Type=${DESKTOP_TYPE}
StartupWMClass=${DESKTOP_STARTUP_WM_CLASS}
Categories=${DESKTOP_CATEGORIES}
EOF
info "Desktop entry created at ${DESKTOP_FILE}"

# --- Update desktop database (if available) ---
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$LOCAL_APPS" 2>/dev/null || true
fi

info "Installation successful!"
info "${DISPLAY_NAME} ${version} is now installed."
info "Run with: ${APP_NAME} or from your application menu"

exit 0
