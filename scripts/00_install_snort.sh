#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 00_install_snort.sh
# RUN THIS ONCE, DAYS BEFORE YOUR PRESENTATION — not live.
#
# Installs the lab tools (nmap, hping3, curl, python3, namespace tools)
# via apt, then installs Snort itself:
#   1. Tries `apt install snort` first — instant, works on Ubuntu
#      releases that still carry the classic Snort 2.9 package
#      (e.g. 22.04/24.04 LTS).
#   2. If that package isn't available (confirmed missing on some
#      newer Ubuntu releases, where it's dropped from the repos),
#      automatically falls back to building Snort 3 from source
#      (libdaq + snort3, ~20-40 minutes).
#
# Because teammates may be on different Ubuntu versions, this script
# self-detects which path it needs — no manual editing required.
#
# Tested on: Ubuntu 22.04 / 24.04 / current-release VMs, run as a user
# with sudo.
# ---------------------------------------------------------------------
set -euo pipefail

echo "[1/4] Updating apt and installing lab tools (nmap, hping3, curl, etc.)..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nmap \
    hping3 \
    curl \
    python3 \
    iproute2 \
    net-tools \
    ethtool \
    tcpdump \
    git

echo "[2/4] Trying apt install snort (fast path, works on some Ubuntu releases)..."
if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y snort 2>/dev/null; then
    echo "Snort installed from apt."
else
    echo "apt package 'snort' is not available on this Ubuntu release."
    echo "[3/4] Falling back to building Snort 3 from source (this takes 20-40 minutes)..."

    echo "Installing build dependencies..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential cmake pkg-config flex bison \
        autoconf automake libtool \
        libpcap-dev libpcre2-dev zlib1g-dev liblzma-dev uuid-dev \
        libssl-dev libhwloc-dev libluajit-5.1-dev luajit \
        libunwind-dev libnghttp2-dev
    # dnet dev package name varies by release — try both
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libdumbnet-dev \
        || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libdnet-dev

    BUILD_DIR="$HOME/snort3-build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [[ ! -d libdaq ]]; then
        echo "Cloning and building LibDAQ..."
        git clone https://github.com/snort3/libdaq.git
    fi
    cd libdaq
    ./bootstrap
    ./configure
    make -j"$(nproc)"
    sudo make install
    sudo ldconfig
    cd "$BUILD_DIR"

    if [[ ! -d snort3 ]]; then
        echo "Cloning Snort 3..."
        git clone https://github.com/snort3/snort3.git
    fi
    cd snort3
    ./configure_cmake.sh --prefix=/usr/local
    cd build
    make -j"$(nproc)"
    sudo make install
    sudo ldconfig
fi

echo "[4/4] Confirming Snort installed and checking DAQ modules..."
snort -V || true
snort --daq-list || true

echo
echo "Done. Next step: sudo bash scripts/01_build_lab_topology.sh"
