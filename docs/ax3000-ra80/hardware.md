# Xiaomi AX3000 (RA80): hardware

These notes describe the unit used for the port: a Xiaomi Mi Router AX3000,
hardware `RA80` (Chinese market), stock firmware 1.0.58 (CN). Unless a public
source is named, every value was read from that unit: the serial boot log, the
U-Boot prompt, the stock device tree and `/proc/mtd`. Only one unit has been
examined.

The RA80 is not the Redmi AX3000 (RA81), which is a different board. According
to the OpenWrt forum, the RA82 is the international version of the RA80. The
RA82 has not been tested.

## Photos

| Photo | What it shows |
|---|---|
| [Front of the board](../../photos/ax3000-board-front.jpg) | Four Ethernet ports (WAN, blue, J2; LAN J3 to J5), power connector J6, serial header J1 in the top right corner, shields SH1 (centre), SH2 (largest, with thermal pads), SH3 (5 GHz, antenna connectors CN3 `5G_CH0` and CN4 `5G_CH1`), U3 (GigaDevice) in the bottom right corner |
| [Back of the board](../../photos/ax3000-board-back.jpg) | Large BGA area behind SH2, a smaller BGA area in the centre, shield SH4 with the 2.4 GHz antenna connectors CN1 `2G_CH0` and CN2 `2G_CH1`, solder joints of the J1 header |
| [Serial header J1](../../photos/ax3000-serial-j1.jpg) | J1 marked in red, next to button SW2 |

SH2 most likely covers the SoC (largest BGA area on the back, thermal pads)
and U3 is most likely the NAND (GigaDevice marking). Neither was confirmed by
removing the shields.

## Summary

| Item | Value |
|---|---|
| Model | Xiaomi Mi Router AX3000, hardware `RA80`, board marking M80 |
| SoC | Qualcomm IPQ5000 (IPQ5018 family), SoC version 1.1, 2x Cortex-A53 (1.0 GHz according to the public spec sheet) |
| RAM | 256 MiB, at 0x40000000 |
| Flash | GigaDevice GD5F1GQ5REYIG SPI NAND, 1 Gbit (128 MiB), see [NAND](#nand) |
| Wi-Fi 2.4 GHz | Integrated in the IPQ5018, 2x2 802.11ax |
| Wi-Fi 5 GHz | Qualcomm QCN6102 (handled as QCN6122 by both the stock driver and ath11k), 2x2 802.11ax |
| Ethernet | 1 WAN + 3 LAN, gigabit, Qualcomm QCA8337 switch |
| Buttons | Reset, Mesh |
| LEDs | System (blue, yellow), network (blue, yellow) |
| Serial console | J1, **1.8 V**, 115200 8N1 |
| Bootloader | Xiaomi U-Boot 2016.01, secure boot not enabled |

Public spec sheet used for the CPU clock and the radio chains:
[TechInfoDepot: Xiaomi Mi Router AX3000 (RA80)](https://techinfodepot.shoutwiki.com/wiki/Xiaomi_Mi_Router_AX3000_(RA80)).

## NAND

| Item | Value |
|---|---|
| Chip | GigaDevice GD5F1GQ5REYIG, SPI NAND, SLC, ID 0xc8 0x41 |
| Size | 128 MiB (U-Boot prints "Device Size:256 MiB"; Linux and the part number say 1 Gbit) |
| Erase block | 128 KiB |
| Page / OOB | 2048 bytes / 128 bytes (U-Boot reduces the usable OOB to 80 bytes) |
| Controller | Qualcomm QPIC, GPIO 4 to 7 (data), 8 (CS), 9 (clock) |
| ECC | **8-bit**, 512-byte steps, as used by U-Boot and the stock firmware. The chip only requires 4-bit, which is what OpenWrt picks by default. See [changes](changes.md#nand-ecc) and [problems](problems.md) |
| UBI geometry | PEB 128 KiB, LEB 126976 bytes, minimum I/O 2048 bytes, VID header at 2048, data at 4096 |

## Wi-Fi

| | 2.4 GHz | 5 GHz |
|---|---|---|
| Chip | IPQ5018 (integrated) | QCN6102, reported as `qcn6122` |
| Chains | 2x2 | 2x2 |
| Q6 user PD | 1 | 2 |
| ath11k device (OpenWrt) | `c000000.wifi`, `phy0` | `b00a040.wifi`, `phy1` |
| Reset GPIO | | 27 (from the stock `boot-args`) |
| FW memory mode | 2 | 2 |
| QMI chip / board ID | `chip_id 0x0`, `board_id 0xff` | `chip_id 0x0`, `board_id 0xff` |
| Stock board data file | `IPQ5018/bdwlan.b24` (`cnss2.bdf_integrated=0x24`) | `qcn6122/bdwlan.b60` (`cnss2.bdf_pci0=0x60`) |
| Calibration in ART | offset 0x1000, 128 KiB | offset 0x26800, 128 KiB |
| Antenna connectors | CN1 `2G_CH0`, CN2 `2G_CH1` (back, under SH4) | CN3 `5G_CH0`, CN4 `5G_CH1` (front, under SH3) |
| Tested in OpenWrt | HE20, `AP-ENABLED` | channel 36, HE80, `AP-ENABLED` |

HE160 and DFS channels have not been tested.

## Ethernet

```
IPQ5018 MAC1 (dp2, eth1) -- Uniphy, SGMII 1000 Mb/s --------- QCA8337 port 6  (CPU port in OpenWrt)
IPQ5018 MAC0 (dp1, eth0) -- internal GE PHY -- MDI ----------- QCA8337 PHY4 / port 5  (not used by OpenWrt)
```

The QCA8337 sits on MDIO bus 1 at address 17 (0x11), with MDC on GPIO 36,
MDIO on GPIO 37 and reset on GPIO 26. The stock device tree uses the bitmaps
`lan_bmp=0x0e`, `wan_bmp=0x30` and `cpu_bmp=0x40`.

| QCA8337 port | PHY | OpenWrt name | Stock bitmap | Notes |
|---|---|---|---|---|
| 1 | 0 | `lan1` | LAN | |
| 2 | 1 | `lan2` | LAN | |
| 3 | 2 | `lan3` | LAN | "Port3" in U-Boot. The LAN port the PC was on during TFTP |
| 4 | 3 | `wan` | WAN | |
| 5 | 4 | | WAN | Internal link to the IPQ5018 GE PHY |
| 6 | | CPU | CPU | SGMII to the IPQ5018 Uniphy |

**Not verified:** which physical LAN connector (J3 to J5) is `lan1`, `lan2`
and `lan3`, and that the blue connector (J2) is `wan`. The test unit has only
been used as an access point with every port in one bridge.

### MAC addresses

| Location | Used for |
|---|---|
| ART offset 0x0 | U-Boot `ethaddr` (eth0). In OpenWrt: `dp1` and the `wan` port |
| ART offset 0x6 | U-Boot `eth1addr` (eth1, LAN). In OpenWrt: `dp2`, the LAN ports and the label MAC |
| Inside the ART calibration data | 5 GHz radio = LAN MAC + 1, 2.4 GHz radio = LAN MAC + 2, already stored with the MAC flag set |

## LEDs and buttons

| GPIO | Device | Device tree node | Use in OpenWrt |
|---|---|---|---|
| 19 | LED, blue | `system-blue` (function power) | `led-running` |
| 17 | LED, yellow | `system-yellow` (function power) | `led-boot`, `led-failsafe`, `led-upgrade` |
| 22 | LED, blue | `net-blue` | function `wan-online` |
| 20 | LED, yellow | `net-yellow` | function `wan` |
| 25 | Button "reset", active low | `reset-button` | `KEY_RESTART` |
| 23 | Button "mesh", active low | `mesh-button` | `KEY_WPS_BUTTON` |

The GPIOs come from the stock device tree. The behaviour of the network LEDs
and the mesh button under OpenWrt has not been checked.

Other GPIOs: UART on 28 and 29 (`blsp0_uart1`), QCN6102 reset on 27,
QCA8337 reset on 26, MDIO on 36 and 37, NAND on 4 to 9.

## Serial console (J1)

J1 is a 4-hole header in the top right corner of the front side, next to the
button SW2. A 4-pin header was soldered in for the port.

**The console runs at 1.8 V.** A 3.3 V or 5 V adapter will damage the SoC.

| Pin | Function | Board marking nearby | Connect to the adapter |
|---|---|---|---|
| 1 | VCC 1.8 V (reference only) | silkscreen "1", capacitor C106 | VIO / VREF input |
| 2 | RX (router input) | series resistor R52 | TX |
| 3 | GND | | GND |
| 4 | TX (router output) | series resistor R53 | RX |

Settings: 115200 baud, 8N1, no flow control. The console device in Linux is
`ttyMSM0` (UART at 0x78AF000).

### Wiring a 1.8 V adapter

The port used a WCH CH343 adapter with a separate I/O voltage input (VIO):

1. Remove the adapter's VIO jumper. On that board it only selects 5 V or
   3.3 V; leaving it on 3.3 V with VIO connected to J1 would feed 3.3 V into
   the router's 1.8 V rail.
2. Connect J1 pin 1 to VIO, so the adapter's I/O follows the router's 1.8 V.
3. Connect GND to pin 3, adapter RX to pin 4 and adapter TX to pin 2.
4. Open the console, for example `picocom -b 115200 /dev/ttyACM0` (the CH343
   shows up as `ttyACM0`).

If your adapter has a fixed 1.8 V mode instead of a VIO input, leave pin 1
unconnected. Never connect an adapter's power output to pin 1.

A multimeter reads 1.8 V on pins 1, 2 and 4 while the board is idle, so it
cannot tell them apart. The resistors in series (R52, R53) mark the data
pins; the final check is that the boot log appears on the adapter's RX.

### The stock firmware keeps the console off

With `uart_en=0` in the U-Boot environment (the factory state) the stock
firmware prints **nothing** on J1, not even the U-Boot banner, and ignores
input. Running xmir-patcher sets `uart_en=1`, after which U-Boot, the kernel
and init all print, and the stock firmware offers a root shell without a
password after pressing Enter (its inittab has
`ttyMSM0::askfirst:/bin/ash --login`). See [install](install.md).

## U-Boot

| Item | Value |
|---|---|
| Version | U-Boot 2016.01 (Jul 15 2021), Xiaomi build, GCC 5.5.0 |
| Prompt | `IPQ5018#` |
| Secure boot | `is_sec_boot_enabled` reports "secure boot fuse is not enabled": unsigned images boot |
| Autoboot | `bootcmd=bootmiwifi`, `bootdelay=3`, `boot_wait=on`; "Hit any key to stop autoboot" |
| Machine ID | `machid=8040000` |
| FIT configuration it boots | `config@mp02.1` (the stock device tree is `IPQ5018/AP-MP02.1`) |
| FIT load address | 0x44000000 (both `bootmiwifi` and the TFTP procedure) |
| Network | `ipaddr=192.168.31.1`, `serverip=192.168.31.100`, `ethact=eth1`, `ethprime=eth1`. U-Boot brings up the GE PHY (eth0) and the QCA8337 (eth1) before the prompt |
| Environment | `0:APPSBLENV` (mtd10), 64 KiB (65532 bytes + CRC), at offset 0 |
| Other variables | `model=RA80`, `CountryCode=CN`, `fdt_high=0x4A400000`, `bootmenu_delay=5` |

Commands that are present and useful: `tftpboot`, `bootm`, `ping`, `nand`,
`ubi`, `smeminfo`, `mtdparts`, `flash` and `flasherase` (by partition name),
`md`/`mw`, `fdt`, `setenv`/`saveenv`, `printenv`, and `xqup` (Xiaomi's
updater).

**Do not publish `printenv` or `fw_printenv` output.** The Xiaomi environment
holds the Wi-Fi password, a cloud (miot) key, a hash of the admin password and
the serial number in plain text.

## NAND partitions

The table lives in SMEM and is the same in U-Boot (`smeminfo`), in the stock
kernel and in OpenWrt (which reads it with `qcom,smem-part` and shows the
names in lower case, for example `0:art`). The mtd numbers are the ones Linux
uses; U-Boot's own list numbers APPSBL and APPSBL_1 the other way round.

| mtd | Name | Offset | Size | Use |
|---|---|---|---|---|
| 0 | 0:SBL1 | 0x0 | 0x80000 (512 KiB) | Qualcomm boot chain |
| 1 | 0:MIBIB | 0x80000 | 0x80000 | Partition table |
| 2 | 0:BOOTCONFIG | 0x100000 | 0x40000 | Boot chain |
| 3 | 0:BOOTCONFIG1 | 0x140000 | 0x40000 | Boot chain |
| 4 | 0:QSEE | 0x180000 | 0x100000 (1 MiB) | TrustZone |
| 5 | 0:QSEE_1 | 0x280000 | 0x100000 | TrustZone, second copy |
| 6 | 0:DEVCFG | 0x380000 | 0x40000 | Boot chain |
| 7 | 0:DEVCFG_1 | 0x3c0000 | 0x40000 | Boot chain, second copy |
| 8 | 0:CDT | 0x400000 | 0x40000 | Boot chain |
| 9 | 0:CDT_1 | 0x440000 | 0x40000 | Boot chain, second copy |
| 10 | **0:APPSBLENV** | 0x480000 | 0x80000 | **U-Boot environment** (boot slot flags) |
| 11 | 0:APPSBL_1 | 0x500000 | 0x140000 (1.25 MiB) | U-Boot, second copy |
| 12 | 0:APPSBL | 0x640000 | 0x140000 | U-Boot |
| 13 | **0:ART** | 0x780000 | 0x100000 (1 MiB) | **Wi-Fi calibration and MAC addresses. Unique per unit** |
| 14 | 0:TRAINING | 0x880000 | 0x80000 | |
| 15 | **bdata** | 0x900000 | 0x80000 | **Xiaomi board data: MACs, model, serial number. Unique per unit** |
| 16 | crash | 0x980000 | 0x80000 | Crash dump |
| 17 | crash_syslog | 0xa00000 | 0x80000 | Crash log |
| 18 | **rootfs** | 0xa80000 | 0x2400000 (36 MiB) | **Slot A. OpenWrt goes here** (UBI) |
| 19 | **rootfs_1** | 0x2e80000 | 0x2400000 (36 MiB) | **Slot B** (UBI). The stock firmware ran from here on the test unit |
| 20 | **overlay** | 0x5280000 | 0x1f00000 (31 MiB) | **Stock configuration**: a UBI device with one volume `data` (UBIFS), shared by both slots. Not touched by OpenWrt |
| 21 | rsvd0 | 0x7180000 | 0x80000 | Reserved |

The table ends at 0x7200000; the last 14 MiB of the chip are not listed in it
(not investigated).

The stock firmware also exposes UBI volumes as extra mtd devices (gluebi):
mtd22 `kernel`, mtd23 `ubi_rootfs` (of the active slot) and mtd24 `data` (of
the overlay). They do not exist in OpenWrt.

Unlike the Xiaomi AX1800, where the stock overlay is a volume inside each
slot, the RA80 keeps it in its own partition (mtd20).

### Contents of the slots

| | Stock (before) | After installing OpenWrt |
|---|---|---|
| Slot A (`rootfs`, mtd18) | Valid UBI with `kernel` and `ubi_rootfs` from an older stock firmware, not in use | UBI with `kernel` (ID 0), `rootfs` (ID 1, squashfs, `/dev/ubiblock0_1`) and `rootfs_data` (ID 2, UBIFS overlay, about 15.8 MB usable) |
| Slot B (`rootfs_1`, mtd19) | Stock 1.0.58 in use | Unchanged |

## Boot slots

U-Boot's `bootmiwifi` reads `flag_boot_rootfs`, prints `boot from rootfs 0`
or `boot from rootfs 1`, attaches that partition as UBI, loads the volume
`kernel` (a FIT image) to 0x44000000 and boots configuration `config@mp02.1`.
It passes the slot to the kernel in the command line:

```
ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs cnss2.bdf_integrated=0x24 cnss2.bdf_pci0=0x60 cnss2.bdf_pci1=0x60 cnss2.skip_radio_bmap=4 rootwait uart_en=1
```

(`ubi.mtd=rootfs_1` for slot B.) The OpenWrt device tree appends
`root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M`; the last `root=` wins.

| Variable | Stock value | Meaning |
|---|---|---|
| `flag_boot_rootfs` | 1 | Slot to boot: 0 = `rootfs` (mtd18), 1 = `rootfs_1` (mtd19) |
| `flag_last_success` | 1 | Slot that last booted successfully |
| `flag_boot_success` | 1 | The last boot was confirmed by the running system |
| `flag_try_sys1_failed`, `flag_try_sys2_failed` | 0 | Boot failure counters of the two slots |
| `flag_ota_reboot` | 0 | Used by Xiaomi's updater; OpenWrt resets it to 0 |
| `uart_en` | 1 after xmir-patcher | Serial console on |
| `boot_wait`, `bootdelay` | `on`, 3 | Autoboot countdown on the console |
| `ssh_en`, `telnet_en` | 1 after xmir-patcher | Read by the stock init scripts |

U-Boot treats a boot that the running system does not confirm as failed, and
after repeated failures boots the other slot. The exact threshold, and which
counter belongs to which slot, have not been verified. OpenWrt confirms each
boot from flash with its `bootcount` script, see [changes](changes.md).

## Memory map

| Range | Size | Use |
|---|---|---|
| 0x40000000 to 0x4fffffff | 256 MiB | DRAM |
| 0x40000000 to 0x407fffff | 8 MiB | NSS firmware (stock only) |
| 0x41000000 | | OpenWrt kernel load and entry address (stock kernel: 0x41208000) |
| 0x44000000 | | FIT image load address |
| 0x4a400000 to 0x4a7fffff | 4 MiB | `tz_apps` (reserved in OpenWrt) |
| 0x4a800000 to 0x4a9fffff | 2 MiB | `bootloader` (U-Boot relocates itself to 0x4a920000) |
| 0x4aa00000 to 0x4aafffff | 1 MiB | `sbl` |
| 0x4ab00000 to 0x4abfffff | 1 MiB | `smem` |
| 0x4ac00000 to 0x4adfffff | 2 MiB | `tz` |
| 0x4b000000 to 0x4dffffff | 48 MiB | `wcss`, Q6 Wi-Fi firmware (OpenWrt) |
| 0x4c400000 | | 2.4 GHz board data address (stock and OpenWrt) |
| 0x4d100000 | | 5 GHz board data address (OpenWrt) |
| 0x4d300000 | | 5 GHz board data address (stock, Xiaomi's layout) |
| 0x4df00000 | | 5 GHz M3 dump address (OpenWrt) |

The stock device tree reserves 0x4b000000 to 0x4e3fffff for the Q6
(`q6_mem_regions`) and 512 KiB each at 0x4e400000 and 0x4e480000 for the crash
dump and crash log. OpenWrt uses the layout of its other ipq50xx boards (the
same as the I-O DATA WN-DAX3000GR), not Xiaomi's.

| Memory seen by Linux | Value |
|---|---|
| Stock (32-bit kernel) | `MemTotal` 183076 kB |
| OpenWrt, boot from flash | "Memory: 181472K/262144K available", 78996K reserved |
| OpenWrt, initramfs | `MemTotal` 184108 kB |

Memory available in use is covered in [problems](problems.md).

## Firmware versions

| Component | Stock | OpenWrt |
|---|---|---|
| Firmware | Xiaomi 1.0.58, region CN | OpenWrt 25.12.4 |
| Bootloader | U-Boot 2016.01 (Jul 15 2021) | Same, not replaced |
| Kernel | Linux 4.4.60, 32-bit ARMv7 | Linux 6.12.87, AArch64 |
| Wi-Fi driver | Qualcomm proprietary (cnss2, qca-wifi) | ath11k, mac80211 backports from Linux 6.18.26 |
| WLAN firmware | `WLAN.HK.2.5.r4-00683`, `fw_version 0x2503ffff`, built 2023-03-07 | `WLAN.HK.2.7.0.1-01744-QCAHKSWPL_SILICONZ-1`, `fw_version 0x270206d0`, built 2022-08-04 |
| Board data files | `bdwlan.b24` and `bdwlan.b60`, byte 0x45c = 0x03 | The same files with byte 0x45c = 0x00, packed as `board-2.bin` |
