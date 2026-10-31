# Problems found on the AX1800 (RM1800) and their status

Everything here was hit on the tested unit, unless it is marked as coming from
the base port's own notes. Roaming and `usteer` topics are covered in
[../roaming.md](../roaming.md).

| # | Problem | Status |
|---|---|---|
| 1 | [J2 serial header gives no output](#1-j2-serial-header-gives-no-output) | hardware; use J3 at 1.8 V |
| 2 | [U-Boot cannot be interrupted, console ignores input](#2-u-boot-cannot-be-interrupted-and-the-console-ignores-input) | fixed from the stock firmware |
| 3 | [U-Boot: "MAC from ART is not valid"](#3-u-boot-mac-from-art-is-not-valid) | harmless warning |
| 4 | [U-Boot TFTP fails on every port](#4-u-boot-tftp-fails-on-every-port) | host-side problem |
| 5 | [First `tftpboot` fails right after power-on](#5-first-tftpboot-fails-right-after-power-on) | retry |
| 6 | [Initramfs: OOM and kernel panic at 18 s](#6-initramfs-oom-and-kernel-panic-at-18-s) | fixed (sysctl) |
| 7 | [Flashed system loses Wi-Fi and network after minutes](#7-flashed-system-loses-wi-fi-and-network-after-minutes) | fixed (patches 0002 and 0003) |
| 8 | [Base port: periodic OOM reboots in repeater mode](#8-base-port-periodic-oom-reboots-in-repeater-mode) | same root cause; repeater mode not retested |
| 9 | [Remaining memory margin under heavy traffic](#9-remaining-memory-margin-under-heavy-traffic) | open, no failure seen |
| 10 | [`sysupgrade` from the initramfs overwrites the stock slot](#10-sysupgrade-from-the-initramfs-overwrites-the-stock-slot) | avoid; use `ubiformat` |
| 11 | [hostapd rejects `bss_transition`](#11-hostapd-rejects-bss_transition) | fixed (full `wpad-mbedtls`) |
| 12 | [`passwd` over SSH stores a wrong password](#12-passwd-over-ssh-stores-a-wrong-password) | use an interactive session |
| 13 | [Clock stuck at the build date in access point mode](#13-clock-stuck-at-the-build-date-in-access-point-mode) | fixed (hotplug script) |
| 14 | [Uplink drops from 1 Gb/s to 100 Mb/s](#14-uplink-drops-from-1-gbs-to-100-mbs) | bad cable, not the router |
| 15 | [Official `kmod` packages do not install](#15-official-kmod-packages-do-not-install) | expected for a custom build |
| 16 | [Problems fixed in the base port](#16-problems-fixed-in-the-base-port) | fixed in patch 0001 and the overlay |
| 17 | [Harmless messages](#17-harmless-messages) | no action |

## 1. J2 serial header gives no output

**Symptom.** A 3.3 V USB serial adapter (CH340) on J2 receives zero bytes at any
baud rate.

**Cause.** J2 is a 3.3 V copy of the real console, J3, through a level shifter
(Q1, Q2, R107, R109) that is not populated on this board. J2 pin 2 shows 3.3 V
only through a pull-up. The base port's documentation describes a "3.3 V UART",
which on this unit matches only the dead J2.

**Fix.** Use J3, which is a **1.8 V** console wired straight to the SoC. Never
connect a 3.3 V adapter to J3. Wiring and the adapter setup are in
[hardware.md](hardware.md#serial-console).

## 2. U-Boot cannot be interrupted, and the console ignores input

**Symptom.** The boot log shows `bootwait is off`; key presses do nothing. On the
stock firmware the Linux console prints messages but does not accept input.

**Cause.** The stock U-Boot environment has `boot_wait` off and no `uart_en`.

**Fix.** From Linux on the stock firmware (SSH opened with xmir-patcher, which
also set these on the tested unit): `uart_en=1`, `boot_wait=on`, `bootdelay=3`,
then `nvram commit`. U-Boot then stops at `IPQ6018#` when it receives a space
during the delay. See [install.md](install.md#1-open-ssh-and-enable-the-console-on-the-stock-firmware).
Before this is done, the serial console alone cannot be used to recover.

## 3. U-Boot: "MAC from ART is not valid"

**Symptom.** U-Boot prints `MAC from ART is not valid` on every boot, with the
stock firmware too.

**Cause.** U-Boot does not find a valid MAC address where it looks in ART. On
Xiaomi devices the factory MAC addresses are kept in `bdata` (mtd9).

**Status.** Harmless: the stock firmware and OpenWrt both boot normally. The
base port reads the LAN and WAN MACs from ART offsets `0x6` and `0x18`. Whether
those offsets hold the same values as `bdata` on every unit was not checked.
Back up both ART and `bdata`.

## 4. U-Boot TFTP fails on every port

**Symptom.** `tftpboot` times out whichever LAN port is used.

**Cause.** Not the router. When the router reboots, the computer's Ethernet link
goes down and up, and NetworkManager switched the interface to a different
(DHCP) profile, so the TFTP server's static `192.168.31.100` was gone.

**Fix.** Pin the static profile (autoconnect on, higher priority) while working
on the router, and revert it afterwards so it does not take over other wired
networks. U-Boot TFTP works on every LAN port.

## 5. First `tftpboot` fails right after power-on

**Symptom.** The first `tftpboot` after interrupting U-Boot fails, with all PHYs
reported "Down".

**Cause.** The command ran before the Ethernet link came up.

**Fix.** Run the same command again.

## 6. Initramfs: OOM and kernel panic at 18 s

**Symptom.** The base port's initramfs, booted over TFTP, runs out of memory and
panics about 18 seconds after boot.

**Cause.** The initramfs keeps about 30 MB of root filesystem in RAM, Linux had
only about 150 MB (`Memory: 150840K/262144K` with the base port's layout), and
OpenWrt's default `vm.min_free_kbytes=16384` keeps another 16 MB as a floor.

**Fix.** `vm.min_free_kbytes=4096` in `/etc/sysctl.d/90-ax1800.conf` (the value
from the base port's kit), shipped active in the image. With the 256 MB layout
of patch 0003 the initramfs also gets 20 MB more (`171284K`).

## 7. Flashed system loses Wi-Fi and network after minutes

This was the main problem with the base port on the tested unit.

**Symptom.** Running from flash as a bridged access point, with a cable uplink
and two clients, the router disappeared from Wi-Fi and from the network and did
not come back on its own (more than 5 minutes the first time). With the serial
console logging, it happened twice more, both times at about 8 minutes of
uptime. `MemAvailable` went from 33 MB to 3 MB in those 8 minutes.

The console showed:

```
[  483.540745] hostapd invoked oom-killer: gfp_mask=0x140dca(GFP_HIGHUSER_MOVABLE|__GFP_COMP|__GFP_ZERO), order=0
[  483.969270] Out of memory: Killed process 1416 (hostapd) ...
[  484.407101] Out of memory: Killed process 1460 (netifd) ...
```

- The kernel killed `hostapd` (Wi-Fi gone), then `netifd`. `procd` restarted
  `netifd` and it was killed again, in a loop, together with `wpa_supplicant`
  and `rpcd`.
- **The router never rebooted.** `procd` kept feeding the hardware watchdog, so
  the box stayed powered and alive without network. Even `reboot -f` typed on
  the serial console did not complete. Only a power cycle recovered it.
- At the time of the OOM all processes together used about 4 MB, the slab about
  30 MB and the page cache almost nothing (`DMA free:8120kB min:4096kB`,
  `managed:161144kB`). The rest of the memory was held by drivers.

**Cause.** Kernel and driver memory, not user space:

- Linux had about 158 MB (`Memory: 158460K/262144K`) against about 194 MB on the
  stock firmware (`Memory: 194292K/204800K`), because the base port uses the
  512 MB layout: 81 MB reserved instead of the stock 61 MB, with the Wi-Fi
  firmware in memory mode 1.
- ath11k filled about 45 MB of RX buffers at boot, sized for 1 GB boards,
  including about 20 MB in a monitor ring that an access point never uses.
- Those buffers were carved from 32 KiB `page_frag` pages, and long-lived refill
  buffers kept whole pages pinned. Memory outside every counter grew by about
  2.7 MB per minute with almost no traffic.

The full analysis and the measurements are in [changes.md](changes.md#why-the-memory-fix-was-needed).

**Fix.** Patch 0002 (smaller RX rings and one slab object per RX buffer in FW
memory mode 2) and patch 0003 (the stock 256 MB layout with FW memory mode 2).
Linux now gets about 178.8 MB, `MemAvailable` two minutes after boot went from
28 MB to 80 MB, and the memory outside the counters stays around 22-24 MB when
idle instead of growing. No OOM has been seen since 2026-10-30.

**Tip.** `logread` lives in RAM and is lost on a power cycle. To catch a failure
like this one, keep the serial console logging to a file (kernel messages of all
levels reach it), or set `log_file` in `/etc/config/system` to keep a copy of the
system log on flash (the last seconds before a hang may not reach it).

## 8. Base port: periodic OOM reboots in repeater mode

Source: the base port's own documentation (validation of 2026-10-18).

**Symptom.** In repeater mode (`relayd`), under load, the router rebooted every
20 to 35 minutes: 18 reboots in one night, each recovering in 1 to 2 minutes.
Each reboot came 30 to 60 seconds after a burst of OOM kills, with no panic in
the remote log. `MemFree` idled at 6 to 20 MB and `MemAvailable` was often below
5 MB.

**Cause, as described there.** OOM storms kept `procd` from feeding the
`qcom_wdt` watchdog (30 s timeout), which then reset the SoC. The author
measured 90 to 100 MB of "invisible" memory, concluded it was not a leak because
the visible counters were flat, and listed memory stability as limited. They do
not recommend the device as a single point of a network. Mitigations in their
kit (OOM shielding of network daemons, a bait process, `drop_caches` relief,
leaner scripts) reduced the storms but did not remove the cause. Disabling the
watchdog exposed a second, slower reset (about 2.5 to 3 minutes), so they kept
it enabled.

**Status here.** The invisible memory is the same driver memory explained in
problem 7, and patches 0002 and 0003 address it. In access point mode the
tested unit hung instead of rebooting. Repeater mode has not been retested with
the fix.

## 9. Remaining memory margin under heavy traffic

**Observation.** With two phones on 5 GHz running speed tests at the same time
(about 1 Gbit/s combined), `MemAvailable` dropped to 24.5 MB and the memory
outside the counters reached 73.5 MB (buffers in flight). There was no OOM, and
`MemAvailable` was back at 66 MB a minute later.

**Status.** Open, no failure seen. A possible refinement is limiting the
transmit descriptors the firmware keeps pending (`TARGET_NUM_MSDU_DESC`, 2500 per
radio), which hold EDMA buffers while frames wait. Not done.

## 10. `sysupgrade` from the initramfs overwrites the stock slot

**Symptom.** None if avoided. The risk is losing the stock firmware in slot A.

**Cause.** The base port's `platform.sh` writes the image to the slot named by
`ubi.mtd=` on the kernel command line, which is the slot the system booted from
(`ubi.mtd=rootfs_1` on the tested unit). A TFTP-booted initramfs has no
`ubi.mtd=`, so it falls back to `flag_boot_rootfs` from the U-Boot environment,
the slot that last booted from flash. Before the first install that is the
stock slot.

The documentation does not agree with the code: the base port's commit message
and docs say `sysupgrade` writes the "alternate" slot, and the bench notes
assumed the same. The code writes the current slot.

**Fix.** From an installed OpenWrt, `sysupgrade` is safe: it rewrites slot B,
which was confirmed on 2026-10-30 by comparing slot A with the backup after an
upgrade (see [install.md](install.md#upgrading)).
From the initramfs, never run `sysupgrade`; write the slot with `ubiformat` as
in [install.md](install.md#5-write-openwrt-to-slot-b).

## 11. hostapd rejects `bss_transition`

**Symptom.** The Wi-Fi interfaces do not come up, and the log shows:

```
hostapd: Line 77: unknown configuration item 'bss_transition'
hostapd: 1 errors found in configuration file '<inline>'
hostapd: hostapd.add_iface failed for phy phy1 ifname=phy1-ap0
```

**Cause.** `bss_transition=1` (802.11v) was set while the image still had
`wpad-basic-mbedtls`, which does not support it.

**Fix.** The release image ships the full `wpad-mbedtls`. If you replace it with
the basic variant, remove `bss_transition` from the wireless configuration
first (the first-boot script sets it on both default interfaces).

## 12. `passwd` over SSH stores a wrong password

**Symptom.** After setting the root password through a non-interactive SSH
command, the expected password does not work.

**Cause.** BusyBox `passwd` reads the password from a terminal; without a tty it
stored something else.

**Fix.** Run `passwd` in an interactive session (serial console or a normal SSH
login), use LuCI, or write a `$6$` hash made with `openssl passwd -6` into
`/etc/shadow`.

## 13. Clock stuck at the build date in access point mode

**Symptom.** With the router configured as an access point (no `wan` interface),
the clock stays at the image build date and log timestamps are wrong.

**Cause.** In OpenWrt it is the `wan` interface coming up that starts NTP.

**Fix.** `/etc/hotplug.d/iface/30-ntp-lan` in the image restarts `sysntpd` when
`lan` comes up. After a reboot the clock still starts from the newest file in
`/etc` (`sysfixtime`), so the first log lines can be a few minutes off until NTP
syncs, about a minute after `lan` is up. Use the kernel uptime when exact timing
matters.

## 14. Uplink drops from 1 Gb/s to 100 Mb/s

**Symptom.** The uplink port negotiates 1 Gb/s and then falls back to 100 Mb/s,
again after reconnecting the cable:

```
Qualcomm QCA8075 90000.mdio-1:03: Downshift occurred from negotiated speed 1Gbps to actual speed 100Mbps, check cabling!
```

**Cause.** The PHY downshifts when one of the four pairs in the cable does not
work. It was the cable, not the router.

**Fix.** Replacing the cable restored 1 Gb/s with no CRC errors and no further
downshift. Check the speed with `cat /sys/class/net/<port>/speed`.

## 15. Official `kmod` packages do not install

**Cause.** This is a custom build; kernel modules from the official OpenWrt
repository are built for a different kernel. In addition, the package manager
does not trust a local build's signing key.

**Fix.** Add modules to the build configuration, or install packages from the
same build tree with `apk add --allow-untrusted`. See
[install.md](install.md#installing-packages).

## 16. Problems fixed in the base port

Found and fixed by the base port's author; listed so they are recognised if they
come back.

| Symptom | Cause | Fix |
|---|---|---|
| Radios detected, but no Wi-Fi interface and the ath11k firmware fails to start | the calibration script had no entry for this board; the family default of 128 KiB includes erased (`0xFF`) flash after the 64 KiB of real calibration | `11-ath11k-caldata` extracts 64 KiB from `0:ART` offset `0x1000` (patch 0001). Check: `cal-ahb-c000000.wifi.bin` is 65536 bytes |
| Router looks dead: answers ARP but not ping, SSH or HTTP; `ip route` is empty | LAN address set without a netmask, so `br-lan` got `/32` | set `network.lan.netmask='255.255.255.0'`; this repository's first-boot script sets it |
| `relayd` missing for repeater mode | the base port's validated image did not include it | `relayd` and `luci-proto-relay` are in this image |

## 17. Harmless messages

| Message | Meaning |
|---|---|
| `MAC from ART is not valid` (U-Boot) | see problem 3 |
| `mtdsplit: no squashfs found in "rootfs"` | seen when booting from slot B; the partition named `rootfs` is slot A, which holds the stock UBI image |
| `ath11k c000000.wifi: qmi fail to get qcom,m3-dump-addr, ignore m3 dump mem req` | seen at boot; Wi-Fi works normally |

Also note that on this device the interface byte counters (`rx_bytes`,
`tx_bytes`) appeared to count double. They are fine for telling whether there
was traffic, not for measuring throughput.
