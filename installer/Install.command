#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/Vinegar303.app"
INSTALL_DIR="$HOME/Applications"
DESTINATION="$INSTALL_DIR/Vinegar303.app"
STAGING="$INSTALL_DIR/.Vinegar303.installing.$$"
BACKUP="$INSTALL_DIR/.Vinegar303.previous.$$"

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "Vinegar303.app was not found next to this installer." >&2
    echo "Run this script from the mounted Vinegar303 disk image." >&2
    exit 1
fi

cleanup() {
    /bin/rm -rf "$STAGING"
    if [[ -d "$BACKUP" && ! -d "$DESTINATION" ]]; then
        /bin/mv "$BACKUP" "$DESTINATION" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Installing Vinegar303 for $(whoami)..."
echo "Destination: $DESTINATION"

# The app is sandboxed. Its entitlement covers the preset folder, but it
# cannot create the missing parent after a clean uninstall. The installer
# runs outside the sandbox, so create the shared root before first launch.
PRESET_ROOT="$HOME/Library/Application Support/Vinegar303/Presets"
/bin/mkdir -p "$PRESET_ROOT/User"

/bin/mkdir -p "$INSTALL_DIR"
/bin/rm -rf "$STAGING" "$BACKUP"
/usr/bin/ditto "$APP_SOURCE" "$STAGING"

# Remove the download quarantine from the copied app and its AUv3 extension.
/usr/bin/xattr -dr com.apple.quarantine "$STAGING" 2>/dev/null || true

# The app is ad-hoc signed. This checks bundle integrity; it is not Apple
# notarization and does not replace the user's one-time Gatekeeper approval.
/usr/bin/codesign --verify --deep --strict "$STAGING"

if [[ -d "$DESTINATION" ]]; then
    /bin/mv "$DESTINATION" "$BACKUP"
fi

if ! /bin/mv "$STAGING" "$DESTINATION"; then
    echo "Could not move the new app into place." >&2
    exit 1
fi

/bin/rm -rf "$BACKUP"
trap - EXIT

echo "Installed: $DESTINATION"
echo
echo "Launching Vinegar303 once to register the AUv3 extension..."
if [[ "${VINEGAR303_SKIP_LAUNCH:-0}" == "1" ]]; then
    echo "Launch skipped (VINEGAR303_SKIP_LAUNCH=1)."
else
    /usr/bin/open "$DESTINATION"
fi

echo
echo "Done. Restart your DAW, then rescan AU plug-ins if needed."
echo "Validate with: auval -v aumu Vg03 Vngr"
