#!/bin/sh
# Builds Mtile (release) and re-signs it with a stable code-signing identity.
#
# `swift build` signs the binary ad hoc, which pins its identity to the exact build (cdhash). The
# Accessibility grant and the launch constraint macOS attaches to the login LaunchAgent are tied
# to that identity, so after every rebuild Mtile silently loses its permission when started at
# login. Signing with a fixed certificate (even an untrusted self-signed one) makes the identity
# `identifier "com.hollowthorn.mtile" and certificate leaf = ...`, which survives rebuilds: grant
# Accessibility to the binary once and it keeps working.
#
# Usage: MTILE_SIGN_IDENTITY="My Local Signing" scripts/build-mtile.sh
# Without MTILE_SIGN_IDENTITY the first code-signing identity in the keychain is used; with none,
# the ad-hoc signature is kept and a warning is printed.
set -eu
cd "$(dirname "$0")/.."

# SwiftPM keeps dependencies as bare git repos; a global `safe.bareRepository=explicit` makes git
# refuse them. Allow it for SwiftPM's git calls only, without touching the user's git config.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

swift build -c release
bin="$(swift build -c release --show-bin-path)/Mtile"

identity="${MTILE_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/^ *[0-9]+\)/ { print $2; exit }')"
fi
if [ -z "$identity" ]; then
    echo "warning: no code-signing identity found; $bin keeps its ad-hoc signature," >&2
    echo "         so its Accessibility permission must be re-granted after each rebuild." >&2
    exit 0
fi

codesign --force --sign "$identity" --identifier com.hollowthorn.mtile "$bin"
echo "Signed $bin with \"$identity\":"
codesign -d -r- "$bin" 2>&1 | tail -1
