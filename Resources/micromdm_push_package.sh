#!/bin/zsh
set -euo pipefail
PKG=/tmp/JUMP-IN-latest.pkg
curl -L "https://github.com/pathaksomesh06/JUMP-IN/releases/latest/download/JUMP-IN.pkg" -o "$PKG"
productsign --sign "Developer ID Installer: Emily Carr University" "$PKG" "$PKG.signed"
xcrun notarytool submit "$PKG.signed" --keychain-profile ecuad --wait
sudo installer -pkg "$PKG.signed" -target /
/Applications/JUMP-IN.app/Contents/MacOS/JUMP-IN --auto
