# Building the images

The images in the Releases page were built with [`scripts/build.sh`](../scripts/build.sh)
from this repository, on Ubuntu 24.04 (x86_64).

## Requirements

The usual OpenWrt build dependencies
([list for each distribution](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)).
On Ubuntu 24.04:

```sh
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3-setuptools rsync swig unzip zlib1g-dev file wget
```

About 25 GB of disk. The first build compiles the toolchain and takes about an
hour on an 8-core laptop; the second device reuses it.

## Build

```sh
git clone https://github.com/Alle4you/openwrt-xiaomi-ax3000-ra80-ax1800-rm1800.git
cd openwrt-xiaomi-ax3000-ra80-ax1800-rm1800
scripts/build.sh ax3000      # Xiaomi AX3000 (RA80)
scripts/build.sh ax1800      # Xiaomi AX1800 (RM1800)
```

What the script does:

1. clones OpenWrt into `./openwrt` (or the directory given as the second
   argument), checks out `v25.12.4` and applies [`patches/`](../patches) with
   `git am`; on later runs it only checks that the patches are there;
2. copies [`configs/feeds.conf`](../configs/feeds.conf) (feeds pinned to the
   revisions used for 25.12.4) and installs the feeds;
3. copies the files overlay ([`files/common`](../files/common) and, for the
   AX1800, [`files/ax1800`](../files/ax1800)) and the device's
   `configs/<device>.diffconfig`, then runs `make defconfig`;
4. downloads the sources and builds; if the parallel build fails, it runs again
   on one core with verbose output to show the error;
5. copies the images, the manifest, the `*.buildinfo` files and a `sha256sums`
   file to `out/<device>/`.

## The patches

| Patch | Author | What it does |
|---|---|---|
| `0001-ipq60xx-add-Xiaomi-Redmi-AX1800-RM1800-support.patch` | Diego Macario | AX1800 support: DTS, image, upgrade, calibration |
| `0002-mac80211-ath11k-add-low-memory-RX-profile-for-FW-mem.patch` | this repository | smaller ath11k RX rings and no page-fragment RX buffers in FW memory mode 2 (both devices) |
| `0003-qualcommax-ipq60xx-xiaomi-ax1800-use-the-256-MB-memo.patch` | this repository | AX1800 memory layout matching the stock firmware |
| `0004-qualcommax-ipq50xx-add-support-for-Xiaomi-AX3000-RA8.patch` | this repository | AX3000 (RA80) support |

They apply on top of OpenWrt `v25.12.4`. For a different OpenWrt version,
expect to rebase them, especially patch 0002, which touches the ath11k
driver.

## The files overlay

| File | Device | Why |
|---|---|---|
| `etc/uci-defaults/99-xiaomi-defaults` | both | LAN at 192.168.31.1 like the stock firmware, 802.11k/v enabled. It runs again after every sysupgrade that keeps the settings, so it only changes values that are still at the OpenWrt default |
| `etc/hotplug.d/iface/30-ntp-lan` | both | restarts NTP when `lan` comes up: in access point mode there is no `wan` to trigger it and the clock stays at the build date |
| `etc/sysctl.d/90-ax1800.conf` | AX1800 | `vm.min_free_kbytes=4096` and smaller network buffers: the OpenWrt default (16384) contributed to the out-of-memory crashes |
