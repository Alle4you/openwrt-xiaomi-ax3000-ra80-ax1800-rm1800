#!/usr/bin/env bash
# Builds the release images for one device from a clean OpenWrt v25.12.4 tree.
#
# Usage: scripts/build.sh <ax3000|ax1800> [openwrt-tree]
#
# The tree defaults to ./openwrt next to this repository. On the first run it
# is cloned, checked out at v25.12.4 and the patches from patches/ are applied
# with "git am". Later runs reuse it, so building the second device only
# rebuilds the kernel and the target packages (the toolchain is shared).
#
# Images, checksums and the build configuration end up in out/<device>/.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
TREE="${2:-$REPO/openwrt}"
TAG=v25.12.4

case "$DEVICE" in
ax3000) TARGET=ipq50xx; PROFILE=xiaomi_ax3000 ;;
ax1800) TARGET=ipq60xx; PROFILE=xiaomi_ax1800 ;;
*) echo "usage: $0 <ax3000|ax1800> [openwrt-tree]" >&2; exit 1 ;;
esac
[ "$(id -u)" -ne 0 ] || { echo "Do not build as root." >&2; exit 1; }
umask 022

step() { echo; echo "== $(date '+%F %T') $*"; }

step "OpenWrt $TAG with the patches"
if [ ! -d "$TREE/.git" ]; then
	git clone https://git.openwrt.org/openwrt/openwrt.git "$TREE"
	git -C "$TREE" checkout -q -b xiaomi-ax "$TAG"
	git -C "$TREE" -c user.name=build -c user.email=build@localhost am -q "$REPO"/patches/*.patch
fi
cd "$TREE"
for p in "$REPO"/patches/*.patch; do
	subject="$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$p" | head -n1)"
	git log --format=%s "$TAG"..HEAD | grep -qF "${subject:0:50}" ||
		{ echo "ERROR: patch not found in $TREE: $(basename "$p")" >&2; exit 1; }
done
git log --oneline "$TAG"..HEAD

step "feeds (pinned revisions)"
cp "$REPO/configs/feeds.conf" feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a

step "files and configuration for $DEVICE"
rm -rf files
mkdir -p files
cp -a "$REPO/files/common/." files/
[ -d "$REPO/files/$DEVICE" ] && cp -a "$REPO/files/$DEVICE/." files/
cp "$REPO/configs/$DEVICE.diffconfig" .config
make defconfig
for opt in "TARGET_qualcommax_${TARGET}_DEVICE_$PROFILE" TARGET_ROOTFS_INITRAMFS "PACKAGE_ipq-wifi-$PROFILE" \
	PACKAGE_kmod-ath11k-ahb PACKAGE_luci PACKAGE_wpad-mbedtls PACKAGE_usteer PACKAGE_luci-app-usteer; do
	grep -q "^CONFIG_$opt=y" .config || { echo "ERROR: CONFIG_$opt is not set in .config" >&2; exit 1; }
done

step "download"
make -j8 download

step "build"
if ! make -j"$(nproc)"; then
	step "parallel build failed; running again on one core with verbose output"
	make -j1 V=s
fi

step "images"
OUT="$REPO/out/$DEVICE"
rm -rf "$OUT"
mkdir -p "$OUT"
BIN="bin/targets/qualcommax/$TARGET"
cp "$BIN"/openwrt-qualcommax-"$TARGET-$PROFILE"-* "$OUT/"
cp "$BIN"/*.manifest "$OUT/" 2>/dev/null || true
cp "$BIN"/config.buildinfo "$BIN"/feeds.buildinfo "$BIN"/version.buildinfo "$OUT/" 2>/dev/null || true
cd "$OUT"
sha256sum openwrt-* > sha256sums
cat sha256sums
step "done: $OUT"
