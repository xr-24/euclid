#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root in the dedicated Construct Linux environment."
  exit 1
fi
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build pkg-config git python3-venv \
  libwayland-dev wayland-protocols libxkbcommon-dev \
  libegl1-mesa-dev libgles2-mesa-dev libdrm-dev libgbm-dev \
  libinput-dev libpixman-1-dev libseat-dev libvulkan-dev \
  libxcb1-dev libxcb-composite0-dev libxcb-icccm4-dev libxcb-res0-dev
