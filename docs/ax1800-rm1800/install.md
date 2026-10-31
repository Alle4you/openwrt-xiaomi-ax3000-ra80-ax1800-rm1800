# Installing OpenWrt on the Xiaomi AX1800 (RM1800)

This is the procedure that was used on the tested unit. The project is
experimental: one unit, running as an access point since 2026-10-29 and stable
since the memory fix of 2026-10-30. Flashing unofficial firmware can brick the
router. Read the whole page first, and read [hardware.md](hardware.md) for the
serial console.

The plan keeps the stock firmware in slot A as a fallback and installs OpenWrt
in slot B:

1. Open SSH on the stock firmware and enable the serial console and `boot_wait`.
2. Back up every flash partition.
3. Boot the OpenWrt initramfs from RAM over TFTP (nothing is written).
4. Write the OpenWrt UBI image to slot B (`rootfs_1`, mtd13) with `ubiformat` and
   point the U-Boot flags at slot B.

## What you need

- A USB serial adapter that can work at **1.8 V** (see
  [hardware.md](hardware.md#serial-console)). It is not strictly needed for the
  install from the stock firmware, but it is the only way to recover if
  something goes wrong, and the TFTP test needs it.
- An Ethernet cable and a computer with a TFTP server (`dnsmasq` was used).
- The three image files, built from this repository or downloaded from its
  releases (see the top-level [README](../../README.md)), with their checksums.

## The release image

| Item | Value |
|---|---|
| OpenWrt | 25.12.4 with patches 0001 (base port), 0002 and 0003 (memory fix), see [changes.md](changes.md) |
| LAN | `192.168.31.1/24`, ports `lan1`-`lan3`, OpenWrt's default DHCP server enabled |
| WAN | port `wan`, DHCP client (OpenWrt default) |
| root password | **none**: set one at first login |
| Wi-Fi | disabled until configured; 802.11k and BSS transition (802.11v) are preset on both default interfaces |
| Extra packages | LuCI, `wpad-mbedtls` (instead of `wpad-basic-mbedtls`), `usteer` + `luci-app-usteer`, `relayd` + `luci-proto-relay` |
| sysctl | `/etc/sysctl.d/90-ax1800.conf`: `vm.min_free_kbytes=4096` (OpenWrt default is 16384), plus TCP buffer caps, `nf_conntrack_max=8192`, `netdev_budget=600`, `dev_weight=128`, `kernel.panic=10` |
| NTP | `/etc/hotplug.d/iface/30-ntp-lan` restarts `sysntpd` when `lan` comes up, so the clock is set even without a `wan` interface |

| File | Use |
|---|---|
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-initramfs-uImage.itb` | boot from RAM over TFTP, for testing and recovery |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-factory.ubi` | first install into a slot with `ubiformat` |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-sysupgrade.bin` | upgrades from an installed OpenWrt with `sysupgrade` |

Both the initramfs and the installed image run a DHCP server on the LAN ports.
Keep the router disconnected from your main network until it is configured.

## 1. Open SSH and enable the console on the stock firmware

The stock firmware (1.0.394 CN on the tested unit) has no SSH, ignores console
input and does not let U-Boot be interrupted (`bootwait is off`).
[xmir-patcher](https://github.com/openwrt-xiaomi/xmir-patcher) fixes all three.
On the computer used, `python3-venv` was missing, so the virtual environment was
created with `uv`; a normal `python3 -m venv venv` works the same way.

```sh
git clone https://github.com/openwrt-xiaomi/xmir-patcher
cd xmir-patcher
uv venv venv
uv pip install --python venv/bin/python -r requirements.txt
./venv/bin/python menu.py
```

Use its menu to connect to the router and install SSH. On the tested unit this
opened SSH as root and also left these variables in the U-Boot environment:

```
uart_en=1
boot_wait=on
bootdelay=3
```

If yours lacks any of them, set them from the stock shell:

```sh
nvram set uart_en=1
nvram set boot_wait=on
nvram set bootdelay=3
nvram commit
```

From now on U-Boot stops at the `IPQ6018#` prompt when it receives a space on
the console during the 3-second delay.

## 2. Back up every partition

Do this before anything else and keep the files offline. `0:ART` (mtd8, Wi-Fi
calibration and MACs) and `bdata` (mtd9, MACs, model, country and serial number)
are **unique to each unit**: if they are lost, nothing else can replace them.
Never publish them.

The tested unit's stock firmware lists 20 mtd devices; the full backup was
20 files, 146 MB. The exact commands used on the bench were not recorded; this
streams every partition over SSH to the computer, which is equivalent:

```sh
R=root@192.168.31.1          # the stock firmware's address
ssh $R cat /proc/mtd > proc_mtd.txt
for n in $(sed -n 's/^mtd\([0-9]*\):.*/\1/p' proc_mtd.txt); do
	ssh $R "dd if=/dev/mtd$n bs=128k 2>/dev/null" > "mtd$n.bin"
done
ls -l mtd*.bin               # each size must match /proc/mtd (hex column 2)
sha256sum mtd*.bin proc_mtd.txt > SHA256SUMS
chmod a-w mtd*.bin proc_mtd.txt SHA256SUMS
```

Also keep `nvram show` (or `fw_printenv` later). Treat the backup as private: it
contains MAC addresses, the serial number and values from the U-Boot
environment.

## 3. Prepare the TFTP server

Give the computer's wired interface the static address `192.168.31.100/24` and
serve the directory that holds the images. With `dnsmasq` as a TFTP-only server
(root is needed for port 69; replace `eth0` with your interface):

```sh
sudo dnsmasq --no-daemon --port=0 --interface=eth0 --bind-dynamic \
	--enable-tftp --tftp-root="$PWD" --user="$USER" --log-facility=-
```

If the computer uses NetworkManager, make sure the static address survives the
link going down and up when the router reboots. On the bench, NetworkManager
switched the interface to another (DHCP) profile at each reboot, the static
address disappeared, and the U-Boot TFTP looked broken on every port. Pin the
static profile (autoconnect on, higher priority) for the duration of the work
and undo that afterwards, otherwise it will grab any wired network.

Connect the computer to any LAN port of the router; U-Boot TFTP works on all of
them.

## 4. Test the initramfs from RAM

Nothing is written to flash in this step. Open the console (see
[hardware.md](hardware.md#settings-and-use)), power the router on and press
space during the boot delay. Then:

```
IPQ6018# setenv ipaddr 192.168.31.10
IPQ6018# setenv serverip 192.168.31.100
IPQ6018# tftpboot 0x44000000 openwrt-qualcommax-ipq60xx-xiaomi_ax1800-initramfs-uImage.itb
IPQ6018# bootm
```

No `saveenv` is needed, so the environment is not changed. If the first
`tftpboot` fails right after power-on with every PHY reported "Down", the link
was not up yet: run the same command again.

OpenWrt boots from RAM at `192.168.31.1`. Check it on the console or over SSH
(no password):

```sh
dmesg | grep -E 'Memory:|FW memory mode'
# Memory: 171284K/262144K available ...      (initramfs with the memory fix)
# ath11k c000000.wifi: FW memory mode: 2
ls /sys/class/ieee80211/                    # phy0 phy1
```

With the original base port layout the same line read `150840K`, and with
OpenWrt's default `min_free_kbytes=16384` the initramfs died of OOM with a kernel
panic 18 seconds after boot. If you see that, the image does not contain this
repository's changes.

## 5. Write OpenWrt to slot B

On the tested unit the stock firmware boots from slot A (`rootfs`, mtd12), so
OpenWrt goes into slot B (`rootfs_1`, mtd13) and slot A keeps the stock firmware
for recovery. Both ways below were used on the tested unit: the first install
was done from the stock firmware on 2026-10-29, and the current image was
written from the initramfs on 2026-10-30.

### From the initramfs (preferred)

Slot B is not in use while the root filesystem is in RAM. If SSH complains about
a changed host key, remove the old one with `ssh-keygen -R 192.168.31.1`.

On the computer:

```sh
F=openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-factory.ubi
ssh root@192.168.31.1 'cat > /tmp/factory.ubi' < "$F"
sha256sum "$F"
ssh root@192.168.31.1 'sha256sum /tmp/factory.ubi'   # must match
```

On the router:

```sh
grep '^mtd13:' /proc/mtd                 # must say "rootfs_1"
ubiformat /dev/mtd13 -f /tmp/factory.ubi -y
fw_setenv flag_boot_rootfs 1
fw_setenv flag_last_success 1
fw_setenv flag_boot_success 1
fw_setenv flag_ota_reboot 0
fw_setenv flag_try_sys2_failed 0
```

Optionally check the volumes, then reboot:

```sh
ubiattach -m 13
ubinfo -a        # volumes kernel, rootfs, rootfs_data
ubidetach -m 13

reboot
```

The router now boots OpenWrt from slot B.

**Do not use `sysupgrade` from the initramfs.** See [Upgrading](#upgrading).

### From the stock firmware

This was the first install on the tested unit. Copy the image the same way
(`ssh root@192.168.31.1 'cat > /tmp/factory.ubi' < "$F"`, then compare the
checksums), and on the stock shell:

```sh
ubiformat /dev/mtd13 -f /tmp/factory.ubi -y
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_boot_success=1
nvram set flag_ota_reboot=0
nvram set flag_try_sys2_failed=0
nvram commit && reboot
```

Before writing, make sure the stock firmware is not running from slot B on your
unit: `grep -E '^mtd1[23]:' /proc/mtd` must show `rootfs` and `rootfs_1`, and
`flag_boot_rootfs` (in `nvram show`) must be `0`. These checks were not part of
the recorded procedure. If your stock firmware runs from slot B, the roles are
swapped (write mtd12 and set the flags to `0`); that case was not tested.

## 6. First boot checks

```sh
cat /proc/cmdline                  # contains ubi.mtd=rootfs_1
logread | grep bootcount           # confirmed boot from rootfs slot 1
fw_printenv | grep '^flag_'        # flag_boot_rootfs=1, flag_boot_success=1, ...
dmesg | grep -E 'Memory:|FW memory mode'
# Memory: 178816K/262144K available ...
# ath11k c000000.wifi: FW memory mode: 2
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin   # 65536 bytes
```

## 7. Set the root password and configure Wi-Fi

Set a root password first: run `passwd` in an interactive session (the serial
console or a normal `ssh root@192.168.31.1` login), or use LuCI at
`http://192.168.31.1`. Do not pipe a password into `passwd` over a
non-interactive SSH command: BusyBox `passwd` needs a terminal, and on the
tested unit that stored a wrong password. A `$6$` hash made with
`openssl passwd -6` and written into `/etc/shadow` also works.

Wi-Fi is off until you configure it, in LuCI (Network, Wireless) or with `uci`:

```sh
for r in radio0 radio1; do
	uci set wireless.$r.country='XX'          # your country code
	uci set wireless.$r.disabled='0'
done
for i in default_radio0 default_radio1; do
	uci set wireless.$i.ssid='your-ssid'
	uci set wireless.$i.encryption='psk2+ccmp'
	uci set wireless.$i.key='your-passphrase'
	uci set wireless.$i.disabled='0'
done
uci commit wireless
wifi reload
```

`radio0` is 5 GHz (HE80 tested) and `radio1` is 2.4 GHz (HE20 tested). Keep
`wpad-mbedtls` installed: the image presets `bss_transition`, which
`wpad-basic-mbedtls` rejects (see [problems.md](problems.md)). Band steering,
802.11r and roaming between access points are covered in
[../roaming.md](../roaming.md).

## Optional: wired access point (the tested setup)

The tested unit runs as a plain bridge between the cable and Wi-Fi: all four
ports, including `wan`, are in `br-lan`, so any port can be the uplink; the
router takes its address from the upstream DHCP server and keeps
`192.168.31.1/24` as a fixed management address on the same bridge; its own
DHCP server, odhcpd and the firewall are off.

```sh
br=$(uci show network | sed -n "s/^network\.\([^.]*\)\.name=.br-lan.$/\1/p")
uci add_list network.$br.ports='wan'
uci -q delete network.wan
uci -q delete network.wan6
uci set network.lan.proto='dhcp'
for o in ipaddr netmask ip6assign; do uci -q delete network.lan.$o; done
uci set network.mgmt=interface
uci set network.mgmt.proto='static'
uci set network.mgmt.device='br-lan'
uci set network.mgmt.ipaddr='192.168.31.1'
uci set network.mgmt.netmask='255.255.255.0'
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'
uci commit
for s in dnsmasq odhcpd firewall; do /etc/init.d/$s disable; done
reboot
```

Set the root password before doing this: with the firewall off, the management
interfaces are reachable from the whole upstream network. If you run more than
one of these access points on the same network, give each one a different
management address (see [../roaming.md](../roaming.md)).

## Upgrading

From an installed OpenWrt, `sysupgrade` is safe:

```sh
grep -o 'ubi.mtd=[^ ]*' /proc/cmdline     # must print ubi.mtd=rootfs_1
sysupgrade -v /tmp/openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-sysupgrade.bin
```

How it works (`/lib/upgrade/platform.sh` from the base port): it takes the slot
from the `ubi.mtd=` argument on the kernel command line and writes the image to
**that same slot**, the one the system booted from. On the tested unit that is
`ubi.mtd=rootfs_1`, so slot B is rewritten and the stock firmware in slot A is
not touched. (The base port's commit message and documentation say "alternate
slot"; the code writes the current one. See [problems.md](problems.md).)

Tested on 2026-10-30: the unit went from the lab build to the release image
with `sysupgrade` (settings kept). It came back in about a minute from slot B
(`ubi.mtd=rootfs_1`), `bootcount` confirmed the boot, the kept settings were
unchanged and both radios came up. In slot A, the blocks of the stock `kernel`
and `ubi_rootfs` volumes were identical to the backup taken before the
installation; the only differences were in the stock firmware's own
`rootfs_data` volume and erase counters, written while the stock firmware was
still running after the backup.

**Never run `sysupgrade` from the initramfs.** A TFTP-booted initramfs has no
`ubi.mtd=` argument, so `platform.sh` falls back to `flag_boot_rootfs` from the
U-Boot environment, the slot that last booted from flash. Before the first
install that is the stock slot, which would be overwritten. From the initramfs,
always flash with `ubiformat` as in step 5.

## Installing packages

This is a custom build, so **kernel module (`kmod-*`) packages from the official
OpenWrt repository will not install**: they are built for a different kernel.
Add what you need to the build configuration instead, or install packages
produced by the same build tree. The package manager does not trust the local
build key, so local packages need `--allow-untrusted`:

```sh
apk add --allow-untrusted --no-network /tmp/<package>.apk
```

On a router with about 180 MB of memory for Linux, keep the number of running
services small.
