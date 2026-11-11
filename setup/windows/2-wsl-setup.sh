#!/usr/bin/env bash
# Step 2 (inside Ubuntu/WSL): Swift toolchain, usbmuxd + libimobiledevice, and xtool.
# Run from the repo folder:  bash setup/windows/2-wsl-setup.sh
set -euo pipefail

echo "== apt packages (Swift deps, usbmuxd, libimobiledevice, FUSE for the AppImage) =="
sudo apt-get update
sudo apt-get install -y \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
  libz3-dev pkg-config tzdata unzip zlib1g-dev curl rsync \
  usbmuxd libimobiledevice-utils libfuse2t64 python3-pip python3-venv

echo "== Swift (via swiftly) =="
SWIFTLY_ENV="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
if ! command -v swift >/dev/null 2>&1; then
  if [ ! -f "$SWIFTLY_ENV" ]; then
    tmp="$(mktemp -d)"
    curl -fL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" -o "$tmp/swiftly.tar.gz"
    tar zxf "$tmp/swiftly.tar.gz" -C "$tmp"
    "$tmp/swiftly" init --quiet-shell-followup --assume-yes
  fi
  # shellcheck disable=SC1090
  . "$SWIFTLY_ENV"
  hash -r
fi
swift --version   # xtool's docs call for Swift 6.4+

echo "== xtool =="
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o /tmp/xtool
chmod +x /tmp/xtool
sudo mv /tmp/xtool /usr/local/bin/xtool
xtool --help | head -3

cat <<'MSG'

Done. Remaining manual steps (see BUILD.md):
  1. Download Xcode 27.1 (.xip) in your Windows browser from
     https://developer.apple.com/download/all/?q=Xcode  (free Apple ID sign-in)
  2. In Ubuntu, run:  xtool setup
       - login mode 1 (Password) for a free Apple ID
       - Xcode.xip path, e.g. /mnt/c/Users/<you>/Downloads/Xcode_27.1.xip
  3. Plug in the iPhone and run setup\windows\3-attach-iphone.ps1 from an admin PowerShell.
MSG
