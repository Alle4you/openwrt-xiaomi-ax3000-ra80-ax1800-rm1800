# Xiaomi AX3000 (RA80): changes to OpenWrt v25.12.4

Everything the RA80 needs on top of OpenWrt v25.12.4 is in two patches and
the release overlay:

| Source | Content |
|---|---|
| [`patches/0004-qualcommax-ipq50xx-add-support-for-Xiaomi-AX3000-RA8.patch`](../../patches/0004-qualcommax-ipq50xx-add-support-for-Xiaomi-AX3000-RA8.patch) | Device support: device tree, image recipe, network and LED setup, calibration data, boot confirmation, upgrade, U-Boot environment, Wi-Fi board files |
| [`patches/0002-mac80211-ath11k-add-low-memory-RX-profile-for-FW-mem.patch`](../../patches/0002-mac80211-ath11k-add-low-memory-RX-profile-for-FW-mem.patch) | ath11k low-memory RX profile, shared with the AX1800. Active on the RA80 because both radios use FW memory mode 2 |
| `files/common/`, `configs/ax3000.diffconfig` | First-boot defaults and package selection of the release image |

Patches 0001 and 0003 only touch the AX1800 (ipq60xx) and do not affect this
image.

## Starting point

The device tree was written from the CMCC PZ-L8, which is already in
OpenWrt and has the **same topology**: IPQ5000 with a QCN6102, a QCA8337
switch on SGMII, the WAN on QCA8337 PHY3, PHY4 linked to the IPQ5018 GE PHY,
and the switch reset on GPIO 26.

Every RA80-specific value was checked on the unit: against the stock device
tree (the `fdt@mp02.1` blob from the stock FIT image in the backup, the same
one U-Boot loads, matching CRC32), the serial boot log of the stock firmware
and the U-Boot environment.

## Device tree: `ipq5018-ax3000.dts`

New file:
`target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-ax3000.dts`.
It includes `ipq5018.dtsi`, `ipq5018-ess.dtsi` and `ipq5018-qcn6122.dtsi`;
the compatible string is `xiaomi,ax3000`.

### Command line

```
bootargs-append = " root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M";
```

The Xiaomi U-Boot builds the command line itself. It passes `ubi.mtd=rootfs`
or `ubi.mtd=rootfs_1` for the active slot, plus `root=mtd:ubi_rootfs`, which
only fits the stock layout. Appending `root=/dev/ubiblock0_1` (UBI device 0,
volume 1, the squashfs written by sysupgrade) makes the last `root=` win. The
same line is used by the PZ-L8; `swiotlb=1` is also on the stock command line.

### NAND ECC

```
nand-ecc-strength = <8>;
nand-ecc-step-size = <512>;
```

The GD5F1GQ5 only requires 4-bit ECC, and that is what OpenWrt chooses by
default. Xiaomi's U-Boot and the stock firmware use **8-bit** ECC
(U-Boot prints `ECC:8-bit`). With the QPIC controller the position of the data
inside a page depends on the ECC strength, so with 4 bits only the first 512
bytes of each page came out right: every read of the ART and UBI returned
`-EBADMSG`, the MAC addresses were random and the calibration data was
garbage. Worse, an image written with 4-bit ECC would not be readable by
U-Boot. With the value fixed at 8, U-Boot boots the UBI written by
sysupgrade. Details in [problems](problems.md#4-nand-read-with-4-bit-ecc).

### Partitions and MAC addresses

The partitions use `qcom,smem-part`: the kernel reads the same SMEM partition
table as U-Boot, so the names match what U-Boot and `fw_setenv` expect
(`0:art`, `0:appsblenv`, `bdata`, `rootfs`, `rootfs_1`). No fixed offsets are
needed.

`0:art` is read-only and gets an nvmem layout with two cells:

| Cell | ART offset | Used by |
|---|---|---|
| `macaddr_art_0` | 0x0 | `dp1` (GE PHY) and the `wan` port, as `ethaddr` in U-Boot |
| `macaddr_art_6` (`mac-base`) | 0x6 | `dp2` (SGMII to the switch), so the LAN ports, and `label-mac-device`, as `eth1addr` in U-Boot |

U-Boot uses the same two addresses for its eth0 and eth1.

### Switch and Ethernet

Taken from the PZ-L8, identical topology:

- `switch_mac_mode = MAC_MODE_SGMII_CHANNEL0`; `port_phyinfo` describes MAC0
  on the GE PHY (MDIO 0, address 7) and MAC1 on the Uniphy, forced to
  1000 Mb/s full duplex.
- `dp2` has a 1000 Mb/s fixed link to QCA8337 port 6, the DSA CPU port
  (`phy-mode = "sgmii"`, `qca,sgmii-enable-pll`).
- The QCA8337 is on MDIO 1 (address 17), reset on GPIO 26. Ports 1 to 3
  (PHY0 to PHY2) are `lan1` to `lan3`, port 4 (PHY3) is `wan`. This matches
  the stock bitmaps (`lan_bmp=0x0e`, `wan_bmp=0x30`, `cpu_bmp=0x40`).
- The second path, MAC0 through the GE PHY to QCA8337 PHY4 (port 5), is not
  part of the DSA setup, as on the PZ-L8. `ge_phy` keeps
  `qcom,dac-preset-short-cable`.

The PZ-L8 numbers its LAN ports in the opposite order (port 1 is `lan3`). The
RA80 uses ascending order. The physical order of the ports has not been
checked yet.

### Buttons, LEDs, pins

From the stock device tree:

- Buttons: reset on GPIO 25 (`KEY_RESTART`), mesh on GPIO 23
  (`KEY_WPS_BUTTON`), both active low with pull-up.
- LEDs: GPIO 19 (blue) and 17 (yellow) for the system LED, GPIO 22 (blue) and
  20 (yellow) for the network LED. Yellow is used for boot, failsafe and
  upgrade, blue for running.
- UART on GPIO 28 and 29 (`blsp0_uart1`), MDIO 1 on GPIO 36 and 37, SPI NAND
  on GPIO 4 to 9. `sleep_clk` (32 kHz) and `xo_board_clk` as on the PZ-L8.

### Wi-Fi

```
&q6v5_wcss {
	boot-args = <0x2 4 2 27 0 0>; /* pcie:1, len:4, updid:2, reset:gpio27 */
};
```

The stock device tree has `boot-args = <0x2 4 2 0x1b 0 0>`: the QCN6102 is in
user PD 2 and is reset through GPIO 27 (0x1b).

| Property | 2.4 GHz (`&wifi`) | 5 GHz (`&wifi1`) |
|---|---|---|
| `qcom,rproc` | `q6_wcss_pd1` | `q6_wcss_pd2` (`q6v5_wcss_userpd2`) |
| `qcom,ath11k-calibration-variant` | `Xiaomi-AX3000` | `Xiaomi-AX3000` |
| `qcom,ath11k-fw-memory-mode` | 2 | 2 |
| `qcom,bdf-addr` | 0x4c400000 | 0x4d100000 |
| `qcom,m3-dump-addr` | | 0x4df00000 |
| `ieee80211-freq-limit` | 2400 to 2483 MHz | 5150 to 5730 MHz |

Why these values:

- **FW memory mode 2** is what the stock firmware uses on both radios
  (`tgt-mem-mode = 2`, and `mem mode : [2]` in its boot log). Mode 2 is the
  firmware's layout for boards with 256 MB of RAM. In this tree it also turns
  on the low-memory RX profile from patch 0002 (below).
- **Board data and M3 addresses** follow OpenWrt's ipq50xx layout (the same
  values as the I-O DATA WN-DAX3000GR, which already runs memory mode 2 with
  Wi-Fi enabled), not Xiaomi's, which loads the 5 GHz board data at
  0x4d300000. The reserved `wcss` region in OpenWrt is 0x4b000000 to
  0x4dffffff.
- **Wi-Fi stays enabled.** Two 256 MB ipq50xx boards in the tree, the PZ-L8
  and the ELECOM WRC-X3000GS2, disable Wi-Fi because of memory. The RA80 keeps both radios on and relies on memory mode 2 plus
  patch 0002. Measured memory is in [problems](problems.md).
- The 5 GHz frequency limit comes from the PZ-L8, so channels above 144
  (5.8 GHz) are not offered. Whether the RA80's 5 GHz front end supports
  them has not been checked.

## Image recipe: `ipq50xx.mk`

```make
define Device/xiaomi_ax3000
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Xiaomi
	DEVICE_MODEL := AX3000
	DEVICE_VARIANT := RA80
	DEVICE_DTS_CONFIG := config@mp02.1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	NAND_SIZE := 128m
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-xiaomi_ax3000 uboot-envtools
endef
```

- The Xiaomi U-Boot loads the UBI volume `kernel` as a FIT image and boots the
  configuration `config@mp02.1`, so the kernel is an lzma-compressed FIT with
  that configuration name, and the image is a UBI with `kernel`, `rootfs` and
  `rootfs_data` (`UbiFit`).
- Block and page size match the NAND (128 KiB, 2048 bytes).
- `ath11k-firmware-ipq5018-qcn6122` provides the WLAN firmware for both chips
  (`WLAN.HK.2.7.0.1-01744`); `uboot-envtools` is needed by the upgrade and
  boot confirmation scripts.

## Network: `02_network`

`target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network`: the RA80
joins the existing case for `lan1 lan2 lan3` plus `wan` (the same as the
Linksys MX2000 and the Xiaomi AX6000).

## Calibration data: `11-ath11k-caldata`

`target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`:

| Firmware file | Action |
|---|---|
| `ath11k/IPQ5018/hw1.0/cal-ahb-c000000.wifi.bin` (2.4 GHz) | `caldata_extract "0:art" 0x1000 0x20000`, joined to the Xiaomi AX6000 case |
| `ath11k/QCN6122/hw1.0/cal-ahb-b00a040.wifi.bin` (5 GHz) | `caldata_extract "0:art" 0x26800 0x20000`, new case |

The offsets are the ones the stock firmware uses (it copies 128 KiB from the
ART for each radio). **The calibration data is only extracted, not patched.**
Xiaomi already stores the radio MAC addresses inside it (5 GHz = LAN MAC + 1,
2.4 GHz = LAN MAC + 2) with the MAC flag set, the same situation as the
AX6000. A first attempt that wrote MAC addresses into the calibration data
produced invalid addresses.

## Boot confirmation: `bootcount`

`target/linux/qualcommax/ipq50xx/base-files/etc/init.d/bootcount`, new case
for `xiaomi,ax3000`. The Xiaomi U-Boot counts a boot that the running system
does not confirm as failed, and after repeated failures boots the other slot.
On every boot from flash the script:

1. makes sure `/etc/fw_env.config` points at `0:appsblenv`
   (`/dev/mtdN 0x0 0x10000 0x20000`), because that file is only generated on
   the first boot and the confirmation must reach the bootloader;
2. reads the slot from `ubi.mtd=` on the kernel command line (`rootfs` = 0,
   `rootfs_1` = 1); with no `ubi.mtd=` (initramfs over TFTP) it does nothing;
3. writes `flag_boot_rootfs`, `flag_boot_success=1`, `flag_last_success`,
   `flag_ota_reboot=0`, `flag_try_sys1_failed=0` and `flag_try_sys2_failed=0`
   in one `fw_setenv -s` call;
4. logs `bootcount: confirmed boot from rootfs slot N`.

This is the same logic as the AX1800 port.

## Upgrade: `platform.sh`

`target/linux/qualcommax/ipq50xx/base-files/lib/upgrade/platform.sh`, new
case:

```sh
CI_UBIPART="rootfs"
remove_oem_ubi_volume ubi_rootfs
fw_setenv -s - <<-EOF
	boot_wait on
	uart_en 1
	flag_boot_rootfs 0
	flag_last_success 0
	flag_boot_success 1
	flag_try_sys1_failed 0
	flag_try_sys2_failed 0
EOF
nand_do_upgrade "$1"
```

- **The target is always slot A (`rootfs`).** The first install runs from the
  initramfs, where `flag_boot_rootfs` still points at the stock slot. Following
  that flag, as the AX1800 port does to pick the other slot, would have
  written OpenWrt over the running stock firmware on the test unit. A fixed
  slot keeps the stock firmware in `rootfs_1` as a fallback.
- `remove_oem_ubi_volume ubi_rootfs` removes the volume left in slot A by an
  older stock firmware, so `nand_do_upgrade` has room for `kernel`, `rootfs`
  and `rootfs_data`.
- The flags point U-Boot at slot A and clear the failure counters;
  `boot_wait` and `uart_en` keep the serial console and the autoboot prompt
  usable for recovery.

## U-Boot environment: `uboot-envtools`

`package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq50xx`: the RA80
joins the Xiaomi AX6000 case:

```sh
ubootenv_add_mtd "0:appsblenv" "0x0" "0x10000" "0x20000"
ubootenv_add_sys_mtd "bdata" "0x0" "0x10000" "0x20000"
```

The environment is 64 KiB at the start of `0:appsblenv` (U-Boot reports
"Environment size: .../65532 bytes"), in 128 KiB erase blocks. Without this
entry `fw_printenv` has no configuration (the first test build printed
"Failed to find NVMEM device" at boot) and neither the upgrade nor the boot
confirmation can set the flags.

## Wi-Fi board data: `ipq-wifi`

`package/firmware/ipq-wifi/Makefile` gets the package
`ipq-wifi-xiaomi_ax3000` ("Xiaomi AX3000"), with two local files:

| File | Source |
|---|---|
| `package/firmware/ipq-wifi/files/board-xiaomi_ax3000.ipq5018` | Stock `IPQ5018/bdwlan.b24` |
| `package/firmware/ipq-wifi/files/board-xiaomi_ax3000.qcn6122` | Stock `qcn6122/bdwlan.b60` |

Both use the board name
`bus=ahb,qmi-chip-id=0,qmi-board-id=255,variant=Xiaomi-AX3000` (the stock log
shows `chip_id 0x0` and `board_id 0xff` on both radios) and are packed in the
`board-2.bin` format of `ath11k-bdencoder`. The encoder used was checked
first by regenerating three official board files from `qca-wireless`
byte for byte.

**Byte 0x45c is cleared in both files.** The stock firmware uses WLAN
firmware `WLAN.HK.2.5.r4-00683`; OpenWrt ships `WLAN.HK.2.7.0.1-01744`. With
the stock board data unchanged, the 2.7 firmware asserts right after receiving
it:

```
qcom-q6-mpd cd00000.remoteproc: fatal error received: err_smem_ver.2.1:
phyrf_bdf.c:605 Assertion 0 failed param0 :zero,param1 :zero,param2 :zero
```

The same error with the same firmware was reported for the Linksys MX2000 on
the OpenWrt forum
([post #255](https://forum.openwrt.org/t/ipq5018-support-for-linksys-mx2000-atlas-6-mx5500-atlas-6-pro/164055?page=13)),
where another variant of the message reads
`phyrf_bdf.c:6245 Assertion axis_value == ANTENNACHAIN_AXIS_Z`. The 2.7
firmware only accepts 0 in byte 0x45c (the antenna chain axis), while these
newer board files carry 3. The fix from that thread, setting 0x45c to 0, works
on both RA80 radios.

| Board data | Byte 0x45c |
|---|---|
| Stock RA80 `bdwlan.b24` (2.4 GHz) and `bdwlan.b60` (5 GHz) | 0x03 |
| Xiaomi AX6000 (IPQ5018) and I-O DATA (QCN6122) files in `qca-wireless` | 0x00 |

[`scripts/bd-patch.py`](../../scripts/bd-patch.py) changes the byte and
fixes the checksum (a 16-bit XOR at offset 0xa; the XOR of all 16-bit words of
the 128 KiB file must be 0xffff). It refuses input whose checksum is already
wrong. Only byte 0x45c and the checksum differ from the stock files; the
checksums of all stock board files and of the calibration data were checked
and found intact first.

```sh
scripts/bd-patch.py bdwlan.b24 bdwlan.b24.axis0 0x45c 0x00
scripts/bd-patch.py bdwlan.b60 bdwlan.b60.axis0 0x45c 0x00
```

## ath11k low-memory RX profile (patch 0002)

Adds `package/kernel/mac80211/patches/ath11k/950-wifi-ath11k-add-low-memory-RX-profile-for-FW-memory-mode-2.patch`.
It was written for the AX1800, where ath11k's RX buffers kept growing until
the OOM killer took `hostapd` and `netifd` down. When the device tree selects
FW memory mode 2 it:

| Ring | Default | Low-memory profile |
|---|---:|---:|
| RX refill | 4096 | 2048 |
| Monitor buffer | 4096 | 256 |
| Monitor destination | 2048 | 512 |
| Monitor descriptor | 4096 | 1024 |

and allocates RX buffers with `alloc_skb()` (one slab object each) instead of
`dev_alloc_skb()`, whose 32 KiB page fragments stay pinned while any buffer
carved from them is in a ring. Other memory modes are not affected.

On the RA80 both radios select mode 2, so the profile applies to both
`ath11k_base` instances. No OOM was seen in the first hours as an access
point; see [problems](problems.md#12-ram-is-tight).

## Release overlay and configuration

`files/common/` goes into both release images (the AX1800-only
`files/ax1800/`, with its `sysctl` settings, is not part of the RA80 image):

| File | What it does | Why |
|---|---|---|
| `etc/uci-defaults/99-xiaomi-defaults` | LAN `192.168.31.1/24`; `ieee80211k=1` and `bss_transition=1` on `default_radio0` and `default_radio1`; Wi-Fi left disabled | Same address as the stock firmware and the U-Boot default, instead of OpenWrt's usual default, so it is less likely to collide with the upstream network. 802.11k/v are used by usteer (see [roaming](../roaming.md)) |
| `etc/hotplug.d/iface/30-ntp-lan` | Restarts `sysntpd` when `lan` comes up | In access point mode there is no `wan` interface, which normally triggers NTP; without this the clock stays at the build date |

`configs/ax3000.diffconfig`:

| Option | Why |
|---|---|
| `CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_xiaomi_ax3000=y` | The device |
| `CONFIG_TARGET_ROOTFS_INITRAMFS=y`, `CONFIG_TARGET_INITRAMFS_COMPRESSION_ZSTD=y` | The initramfs image is needed for the TFTP install |
| `CONFIG_KERNEL_DEBUG_FS=y` | debugfs, used during the port to read mac80211 and ath11k state |
| `CONFIG_PACKAGE_luci=y` | Web interface |
| `wpad-mbedtls` instead of `wpad-basic-mbedtls` | Full hostapd, for the roaming setup |
| `usteer`, `luci-app-usteer` | Band and AP steering, see [roaming](../roaming.md) |
| `relayd`, `luci-proto-relay` | Relay bridge option |

Feeds are pinned in `configs/feeds.conf`. The build itself is
[`scripts/build.sh`](../../scripts/build.sh).
