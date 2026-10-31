# What the AX1800 (RM1800) image contains and why

The image is OpenWrt v25.12.4 (`r32933-4ccb782af7`, kernel 6.12.87, target
`qualcommax/ipq60xx`, profile `xiaomi_ax1800`) with three patches from
[`patches/`](../../patches/), a small file overlay and a build configuration.
Feed revisions are pinned in [`configs/feeds.conf`](../../configs/feeds.conf).

| Patch | Author | Purpose |
|---|---|---|
| `0001-ipq60xx-add-Xiaomi-Redmi-AX1800-RM1800-support.patch` | Diego Macario | device support (the base port) |
| `0002-mac80211-ath11k-add-low-memory-RX-profile-for-FW-mem.patch` | this repository | smaller, non-pinning RX buffers in ath11k for FW memory mode 2 |
| `0003-qualcommax-ipq60xx-xiaomi-ax1800-use-the-256-MB-memo.patch` | this repository | the stock 256 MB memory layout |

## Patch 0001: the base port

Device support comes from Diego Macario's port,
[macario1983/ax1800-openwrt](https://github.com/macario1983/ax1800-openwrt),
applied unchanged as patch 0001. It touches nine files:

| File | What it adds |
|---|---|
| `ipq6000-xiaomi-ax1800.dts` | Device tree: 256 MB memory node, NAND on QPIC with the 16 stock partitions, QCA8075 over PSGMII with `lan1`-`lan3` and `wan`, MACs from `0:ART` (`0x6` LAN, `0x18` WAN/label), LEDs, reset button, console, Wi-Fi node with calibration variant `Xiaomi-AX1800` and FW memory mode 1. Includes `ipq6018-512m.dtsi`. |
| `image/ipq60xx.mk` | `Device/xiaomi_ax1800`: FIT kernel + UBI (`Device/FitImage`, `Device/UbiFit`), 128 KiB blocks, 2 KiB pages, FIT configuration `config@cp03-c1` (the one the stock U-Boot boots). Produces the initramfs, `factory.ubi` and `sysupgrade.bin`. |
| `board.d/02_network` | `lan1 lan2 lan3` as LAN, `wan` as WAN |
| `hotplug.d/firmware/11-ath11k-caldata` | Extracts the Wi-Fi calibration from `0:ART` offset `0x1000`, **64 KiB**. The 128 KiB used by other boards picks up erased (`0xFF`) flash and makes the ath11k firmware fail to start. |
| `init.d/bootcount` | Confirms the boot to U-Boot: reads `ubi.mtd=` from the command line and writes the slot flags, so U-Boot does not fall back to the other slot. Also makes sure `/etc/fw_env.config` exists. Does nothing in an initramfs. |
| `lib/upgrade/platform.sh` | `sysupgrade` support: picks the UBI partition from `ubi.mtd=` (fallback: `flag_boot_rootfs`), removes the stock `ubi_rootfs` volume so the new `rootfs` volume gets ID 1 (`root=/dev/ubiblock0_1`), then runs `nand_do_upgrade`. |
| `uboot-envtools` | U-Boot environment on `0:APPSBLENV`, offset `0x0`, size `0x10000`, sector `0x20000` |
| `ipq-wifi/Makefile` | Package `ipq-wifi-xiaomi_ax1800`; also lets the package take a board file from its own `files/` directory |
| `ipq-wifi/files/board-xiaomi_ax1800.ipq6018` | Board data file (65,640 bytes, variant `Xiaomi-AX1800`), installed as `board-2.bin` |

The base port also ships a first-boot script that sets the LAN address with an
explicit netmask (without the netmask OpenWrt applied `/32` and the router
looked dead), and an operations kit for its repeater setup (`relayd` helpers, a
watchdog guard, OOM shielding, memory probes). This repository replaces the
first with its own overlay (below) and does not include the kit.

The base port's author validated boot from both slots, Ethernet, MACs, Wi-Fi,
`sysupgrade` and an 8-hour repeater test. The same test showed the memory
problem described next: 18 watchdog reboots in one night. The author lists
memory stability as limited and does not recommend the device as a single point
of a network. See [problems.md](problems.md).

## Why the memory fix was needed

With the base port, the tested unit (a bridged access point) lost Wi-Fi and
network about 8 minutes after boot: the OOM killer took `hostapd`, then `netifd`
and `wpa_supplicant` in a loop, and the box stayed up without network until it
was power cycled. User space was about 4 MB and the slab about 30 MB at that
point. The rest of the memory was held by drivers.

A probe read `/proc/meminfo` every 5 seconds and computed the memory outside
every counter (`MemTotal - free - cached - slab - anon - kernelstack -
pagetables - vmalloc - percpu`), called `invis` below: page allocations made by
drivers. In kB:

| uptime (s) | MemFree | MemAvailable | Cached | Slab | invis | LAN RX total |
|---:|---:|---:|---:|---:|---:|---:|
| 193 | 12,880 | 28,640 | 23,852 | 30,756 | **76,880** | 33 |
| 237 | 13,728 | 14,088 | 7,348 | 29,680 | **93,436** | 8,497 |
| 303 | 14,320 | 14,824 | 7,492 | 29,880 | **92,492** | 8,533 |
| 383 | 12,408 | 12,908 | 7,492 | 29,916 | **94,984** | 8,543 |
| 443 | 11,840 | 10,588 | 4,108 | 29,796 | **98,992** | 8,654 |
| 483 | 10,304 | 8,868 | 3,712 | 29,848 | **100,924** | 8,662 |
| 496 | 8,276 | 5,980 | 2,244 | 29,608 | **107,728** | 11,333 |
| ~535 | | | | | | OOM |

- A client pulling 8.5 MB raised `invis` by 16 MB.
- Between 303 s and 483 s only about 130 kB crossed the LAN and `invis` still
  grew 8 MB (about 2.7 MB per minute).
- The mac80211 transmit queue (`fq_memory_usage`) stayed at zero and the slab
  was flat (`SUnreclaim` about 23.8 MB), so it was neither a packet queue nor a
  slab leak.

Two causes were found:

1. **A high baseline.** The base port uses the 512 MB layout (81 MB reserved,
   FW memory mode 1), 20 MB more than the stock firmware reserves on the same
   board. On top of that, ath11k sizes its RX rings for 1 GB boards. On IPQ6018
   each radio fills three rings at init:

   | Ring | Buffers per radio | Used by an AP? |
   |---|---:|---|
   | refill (`DP_RXDMA_BUF_RING_SIZE`) | 4096 | yes |
   | monitor buffers (`DP_RXDMA_MONITOR_BUF_RING_SIZE`) | 4096 | no, only with a monitor interface |
   | monitor status (`DP_RXDMA_MON_STATUS_RING_SIZE`) | 1024 | yes (per-station RX statistics) |

   At about 2.5 KB per buffer that is roughly 45 MB for the two radios, about
   20 MB of it in a monitor ring an access point never uses, on a Linux that had
   about 157 MB.

2. **Continuous growth.** The buffers come from `dev_alloc_skb()`, which carves
   them out of 32 KiB `page_frag` pages. A page returns to the system only when
   every buffer carved from it has been freed. The status ring is consumed and
   refilled all the time (every received frame produces status, including
   neighbours' beacons), while a refill buffer can sit in its ring for hours on a
   quiet AP. A long-lived buffer on a page otherwise used by status buffers pins
   the whole page, so pinned pages accumulate even without traffic.

The EDMA (`qca-nss-dp`) rings were also checked: 128 entries each, not
significant.

The base port's author measured the same 90-100 MB of "invisible" memory and
concluded it was not a leak because the visible counters stayed flat. They do
stay flat; what grows is outside them.

## Patch 0002: ath11k low-memory RX profile

Adds `package/kernel/mac80211/patches/ath11k/950-wifi-ath11k-add-low-memory-RX-profile-for-FW-memory-mode-2.patch`.

OpenWrt's existing ath11k patches already read the FW memory mode from the
device tree (`qcom,ath11k-fw-memory-mode`) and, for mode 2, reduce the number of
vdevs and peers. This patch adds a `low_mem_rx` hardware parameter, set only in
mode 2, which changes:

| Setting | Default | FW memory mode 2 |
|---|---:|---:|
| RX refill ring | 4096 | 2048 |
| Monitor buffer ring | 4096 | 256 |
| Monitor destination ring | 2048 | 512 |
| Monitor descriptor ring | 4096 | 1024 |
| Monitor status ring | 1024 | 1024 (unchanged) |
| RX buffer allocation | `dev_alloc_skb()` (32 KiB `page_frag`) | `alloc_skb(..., GFP_ATOMIC)` (one slab object per buffer) |

- Each buffer now costs a 4 KiB slab object (`kmalloc-4k`) instead of about
  2.5 KB, but freed buffers are reused by the slab and memory is bounded by the
  ring sizes: (2048 + 256 + 1024) x 2 radios x 4 KiB = about 26 MB, fixed,
  instead of about 45 MB at boot and growing.
- The status ring keeps 1024 entries because it feeds per-station RX statistics
  (signal and rate).
- Other memory modes are not affected.

## Patch 0003: the stock 256 MB memory layout

The stock firmware's device tree (from the FIT image in the backup, configuration
`config@cp03-c1`) uses the QSDK 256 MB profile. Patch 0003 makes the OpenWrt
device tree match it:

| Setting | Base port | Patch 0003 (= stock) |
|---|---|---|
| Include | `ipq6018-512m.dtsi` | `ipq6018.dtsi` |
| `qcom,ath11k-fw-memory-mode` | 1 | 2 |
| `q6_region` at `0x4ab00000` | 55 MB | 40 MB (`0x2800000`) |
| `nss_region` at `0x40000000` | 16 MB | 8 MB |
| `0x4d300000` | inside `q6_region` | 3 MB reserved (Q6 ETR dump and two stock reserved blocks) |
| Total reserved | 81 MB | 61 MB |

The mode and the region size change together on purpose: the Wi-Fi firmware
computes its own memory from the mode (mode 1 = 55 MB, mode 2 = 40 MB).
Shrinking only the region would let the firmware write into Linux memory
silently. The 3 MB at `0x4d300000` stay reserved because the stock firmware
reserves them right after its 40 MB region. The full map is in
[hardware.md](hardware.md#memory-map).

## Results

Measured on the tested unit (one unit, 2026-10-30).

| | Before (base port) | After (0002 + 0003) |
|---|---:|---:|
| Kernel `Memory:` line, NAND boot | 158,460K | 178,816K |
| Kernel `Memory:` line, initramfs | 150,840K | 171,284K |
| `FW memory mode` | 1 | 2 |
| `MemAvailable` at about 2 min, no clients | 28 MB | 80 MB |
| `invis` at about 2 min | 77 MB, rising about 2.7 MB/min | 22 MB |
| Time to OOM as an access point with clients | about 8 min | none so far |

- **Initramfs, 5 minutes without clients:** `invis` between 21 and 24 MB,
  `MemAvailable` steady at about 56 MB even with about 30 MB of initramfs in RAM.
  Slab rose from about 30 to about 53 MB, as expected now that RX buffers are
  slab objects.
- **Flashed, first 23 minutes, one client per band plus speed tests:** no OOM,
  panic or reboot. Lowest `MemAvailable` 46.7 MB at the traffic peak, highest
  `invis` 53 MB, back to about 24 MB after the peak, several GB forwarded.
- **Heaviest case seen:** two phones on 5 GHz running speed tests at the same
  time (about 700 and 300 Mbit/s, about 1 Gbit/s combined). `MemAvailable`
  dropped to 24.5 MB and `invis` rose to 73.5 MB (buffers in flight), with no
  OOM; one minute later `MemAvailable` was back at 66 MB. Memory rises during
  bursts and comes back when traffic stops.
- **Longer run:** after a reboot at about 10:11 on 2026-10-30, a per-minute
  memory log covered about 9 hours of uptime (32,904 s) with up to four clients:
  no OOM, lowest `MemAvailable` 51.8 MB, highest `invis` 44.6 MB. An overnight
  result was not available when this page was written.

Possible next refinement, not done: limit the transmit descriptors the firmware
keeps pending (`TARGET_NUM_MSDU_DESC`, 2500 per radio today), which hold EDMA
buffers while frames wait to be sent.

Note on the probes: the interface byte counters (`rx_bytes`/`tx_bytes`) appeared
to count double on this device (averages above 1 Gbit/s on a gigabit port), so
they only show when there was traffic, not how much.

## sysctl: `files/ax1800/etc/sysctl.d/90-ax1800.conf`

```
vm.min_free_kbytes=4096
net.ipv4.tcp_rmem=4096 87380 524288
net.ipv4.tcp_wmem=4096 65536 524288
net.core.rmem_max=524288
net.core.wmem_max=524288
net.netfilter.nf_conntrack_max=8192
net.core.netdev_budget=600
net.core.dev_weight=128
kernel.panic=10
```

These are the values of the base port's operations kit, shipped active.

- `vm.min_free_kbytes=4096`: OpenWrt's default of 16384 is a floor that a router
  with this little memory sits on all the time, so every allocation turns into
  direct reclaim. On the tested unit the initramfs (about 30 MB in RAM) plus that
  floor caused an OOM with a kernel panic 18 seconds after boot; with 4096 it
  booted normally. The base port's author tested 16384 (OOM cascades under load),
  8192 (worse when idle, OOM every few minutes) and settled on 4096. This alone
  did not prevent the OOM of the flashed system (its OOM report shows
  `min:4096kB`); patches 0002 and 0003 did.
- TCP buffer caps of 512 KiB and `nf_conntrack_max=8192` limit per-connection
  and table memory peaks.
- `netdev_budget=600` and `dev_weight=128` drain RX bursts faster.
- `kernel.panic=10` reboots 10 seconds after a kernel panic.

## Release overlay and build configuration

Shared with the AX3000 image (`files/common/`):

- `etc/uci-defaults/99-xiaomi-defaults`: LAN at `192.168.31.1` with an explicit
  `255.255.255.0` netmask (the stock Xiaomi address, and the netmask avoids the
  `/32` problem the base port hit); 802.11k and `bss_transition` (802.11v) on both
  default Wi-Fi interfaces. Wi-Fi stays disabled until configured.
- `etc/hotplug.d/iface/30-ntp-lan`: restarts `sysntpd` when `lan` comes up. In
  access point mode there is no `wan` interface, which is what normally triggers
  NTP, and the clock stayed at the build date.

AX1800 only (`files/ax1800/`): the sysctl file above.

[`configs/ax1800.diffconfig`](../../configs/ax1800.diffconfig) on top of the
target defaults:

| Option | Why |
|---|---|
| `TARGET_ROOTFS_INITRAMFS`, zstd compression | the TFTP initramfs used for testing and recovery |
| `KERNEL_DEBUG_FS` | carried over from the base port's configuration; the memory probe reads mac80211 queue statistics from debugfs |
| `luci` | web interface |
| `wpad-mbedtls` instead of `wpad-basic-mbedtls` | the basic build lacks 802.11v (BSS transition), which `usteer` uses and which the overlay enables; also brings 802.11s |
| `usteer`, `luci-app-usteer` | band steering and client steering between access points, see [../roaming.md](../roaming.md) |
| `relayd`, `luci-proto-relay` | the base port's repeater mode needs `relayd`, which its validated image lacked |

The images are built by [`scripts/build.sh`](../../scripts/build.sh) with
`ax1800` as the argument.

## Not included

- The base port's operations kit (watchdog guard, OOM bait and shielding,
  `drop_caches` relief, memory probes, routing fixes for `relayd`, a runtime
  calibration fallback). The calibration fallback is not needed because patch
  0001 fixes the calibration script itself.
- The lab's own telemetry (a per-minute memory logger and a log file on flash),
  used to produce the numbers above.
