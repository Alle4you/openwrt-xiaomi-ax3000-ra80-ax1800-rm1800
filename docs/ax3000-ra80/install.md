# Xiaomi AX3000 (RA80): installing OpenWrt

This is the procedure that was used on the test unit (RA80, stock 1.0.58 CN).
It needs the serial console: there is no web or SSH-only path here.

**Status: experimental.** One unit has been flashed, and it has been running
as an access point since 2026-10-30. It was first installed with a lab build
of this port (same device support, different first-boot overlay) and then
upgraded to the release image from this repository, keeping its settings, on
2026-10-30 (see [Later upgrades](#later-upgrades)).

## What you need

- A USB to UART adapter that works at **1.8 V** (see
  [hardware](hardware.md#serial-console-j1)), and a 4-pin header soldered into J1.
- A PC with an Ethernet port, an SSH client and a TFTP server.
- [xmir-patcher](https://github.com/openwrt-xiaomi/xmir-patcher) (tested at
  commit `16a46e3`, which lists the RA80 as a supported model).
- About 140 MB of disk space for the backup.
- The three release files and the `sha256sums` file:

| File | Used for |
|---|---|
| `openwrt-qualcommax-ipq50xx-xiaomi_ax3000-initramfs-uImage.itb` | Booting OpenWrt from RAM over TFTP |
| `openwrt-qualcommax-ipq50xx-xiaomi_ax3000-squashfs-sysupgrade.bin` | Writing OpenWrt to slot A, and later upgrades |
| `openwrt-qualcommax-ipq50xx-xiaomi_ax3000-squashfs-factory.ubi` | Built, but **not used or tested** |

Check them before use:

```sh
sha256sum -c --ignore-missing sha256sums
```

## Where OpenWrt goes

The RA80 has two firmware slots, `rootfs` (slot A, mtd18) and `rootfs_1`
(slot B, mtd19); U-Boot boots the one named in `flag_boot_rootfs`. See
[hardware](hardware.md#boot-slots).

**The image always installs into slot A (`rootfs`, mtd18)** and sets the
Xiaomi boot flags to slot A. The stock firmware survives only if it is
running from slot B. On the test unit the stock firmware ran from `rootfs_1`
(slot B) and is still there. **If your stock firmware runs from slot A, it
will be overwritten** and only your backup can bring it back (that case has
not been tested). Step 4 shows how to check.

## Release image defaults

| Item | Value |
|---|---|
| LAN | `192.168.31.1/24` (the stock Xiaomi address), DHCP server on |
| Root password | **None.** Set one on the first login |
| Wi-Fi | Disabled until you configure it. 802.11k and BSS transition are preset on the default interfaces |
| Extra packages | LuCI, `wpad-mbedtls` (full), `usteer` + `luci-app-usteer`, `relayd` + `luci-proto-relay` |

## 1. Enable SSH and the serial console on the stock firmware

Connect the PC to a LAN port of the router and run xmir-patcher's menu from
its directory (set up its Python environment as its README says):

```sh
python3 menu.py
# 1  Set IP-address: the router's address (192.168.31.1 on a default stock setup)
# 2  Connect to device (install exploit)
```

xmir-patcher tries several exploits in turn. On the test unit it opened SSH
(dropbear on port 22) and wrote these variables to the U-Boot environment:
`uart_en=1`, `boot_wait=on`, `bootdelay=3`, `ssh_en=1` and `telnet_en=1`.

What survives a reboot: the environment variables and the root password set
by xmir-patcher. What does not: SSH itself. The stock init script only starts
dropbear when `ssh_en=1` **and** the firmware channel is not `release`, and
this firmware is `release`.

`uart_en=1` is the important part. Without it the console on J1 stays silent,
U-Boot included.

## 2. Connect the serial console

Wire the adapter as described in [hardware](hardware.md#serial-console-j1) and
open it:

```sh
picocom -b 115200 /dev/ttyACM0
```

Reboot the router. The U-Boot banner, the kernel log and finally "Please press
Enter to activate this console" should appear. Press Enter for a root shell
(no password). Check both directions:

```sh
echo SERIAL-OK-$((6*7))      # must print SERIAL-OK-42
```

## 3. Get SSH back after a reboot

From the root shell on the serial console, start dropbear in RAM. The stock
host key file `/etc/dropbear/dropbear_rsa_host_key` is empty (0 bytes), so
create one in `/tmp`. Nothing is written to flash and it is gone after the
next reboot.

```sh
dropbearkey -t rsa -s 2048 -f /tmp/db_rsa_host_key
/usr/sbin/dropbear -r /tmp/db_rsa_host_key -p 22
```

The stock dropbear is old; current OpenSSH clients need `ssh-rsa` enabled:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.31.1
```

Log in with the root password xmir-patcher set.

## 4. Back up every partition, and check the slot

**Do not skip this.** `0:ART` (mtd13) holds the Wi-Fi calibration and MAC
addresses, and `bdata` (mtd15) holds Xiaomi's board data (MACs, model, serial
number). Both are **unique to your unit**: they cannot be downloaded or
copied from another router. Lose them and the radios are uncalibrated for
good. The backup is also the only way back to stock if the stock slot gets
overwritten.

Read mtd0 to mtd23 over SSH and keep the files off the router:

```sh
SSH="ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.31.1"
mkdir ra80-backup && cd ra80-backup
$SSH 'cat /proc/mtd' > proc-mtd.txt
for i in $(seq 0 23); do
	$SSH "cat /dev/mtd$i" > "mtd$i.bin"
done
```

Each `ssh` call asks for the password unless you set up a key or connection
sharing. Notes:

- mtd24 (`data`) is mounted by the stock firmware and cannot be opened
  ("Resource busy"). Its contents are inside the raw dump of mtd20 (`overlay`).
- mtd22 and mtd23 are UBI volumes of the active slot exposed as mtd devices.
  They duplicate data that is already in mtd18 or mtd19, but cost nothing.
- The full set is about 136 MB.

Verify the dumps. The stock firmware has no `sha256sum`, so compare MD5 sums
computed on the router with the local files:

```sh
for i in $(seq 0 23); do
	r=$($SSH "md5sum /dev/mtd$i" | cut -d' ' -f1)
	l=$(md5sum < "mtd$i.bin" | cut -d' ' -f1)
	[ "$r" = "$l" ] && echo "mtd$i OK" || echo "mtd$i MISMATCH"
done
```

Every line must say OK. Then keep at least one more copy of the folder
elsewhere. The backup contains the U-Boot environment (mtd10) and `bdata`,
which hold your Wi-Fi password, the serial number and other private data:
do not publish it.

Now check which slot the stock firmware runs from:

```sh
nvram get flag_boot_rootfs   # 1 = rootfs_1 (slot B), 0 = rootfs (slot A)
cat /proc/cmdline            # ubi.mtd=rootfs_1 means slot B
```

The serial console shows the same thing during boot: `boot from rootfs 1`.

- `1` / `rootfs_1`: the stock firmware stays intact in slot B. Continue.
- `0` / `rootfs`: installing OpenWrt **will overwrite the running stock
  firmware**. That case has not been tested; continue only if you accept that
  your backup is the only way back.

## 5. Prepare the PC

Give the PC's Ethernet port the static address `192.168.31.100/24` (the
`serverip` in the Xiaomi U-Boot) and connect it to a LAN port of the router,
not the blue WAN port. Make sure the address stays assigned when the link
goes down and up while the router reboots; a network manager that drops the
profile on link loss makes the router look unreachable.

Serve the initramfs over TFTP from the folder that holds it. The port used
dnsmasq (replace `eth0` with your interface):

```sh
sudo dnsmasq --no-daemon --port=0 --interface=eth0 --bind-dynamic \
	--enable-tftp --tftp-root="$PWD" --user="$USER" --log-facility=-
```

`--port=0` turns off DNS; only TFTP runs. Root is needed for port 69.

## 6. Stop U-Boot

In the serial console, reboot the router (`reboot` in the stock shell) and
press a key, for example space, as soon as U-Boot prints
"Hit any key to stop autoboot". The countdown is 3 seconds. You should get
the prompt:

```
IPQ5018#
```

Optional check of the network path:

```
IPQ5018# ping 192.168.31.100
host 192.168.31.100 is alive
```

## 7. Boot the OpenWrt initramfs over TFTP

This runs OpenWrt from RAM. Nothing is written to flash.

```
IPQ5018# tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-xiaomi_ax3000-initramfs-uImage.itb
IPQ5018# bootm 0x44000000
```

Right after U-Boot is stopped, the switch is often still negotiating the link
and the first `tftpboot` fails at once (the port shows as down). Wait about
4 seconds and run it again; the port's script retried up to three times.

A good boot shows `Using 'config@mp02.1' configuration` from U-Boot and
`Machine model: Xiaomi AX3000` from the kernel.

## 8. Check the initramfs

Log in over SSH. The release image has no root password yet:

```sh
ssh root@192.168.31.1
```

On the router:

```sh
dmesg | grep -iE 'invalid mac|bad message|assert'   # must print nothing
dmesg | grep fw_build_id                             # both radios: WLAN.HK.2.7.0.1-01744
ls /sys/class/ieee80211                              # phy0  phy1
```

`Invalid MAC` or `Bad message` means the NAND is being read with the wrong
ECC settings, and `Assertion` means the Wi-Fi firmware rejected the board or
calibration data (see [problems](problems.md)). Do not flash in that case.

The initramfs keeps its whole root filesystem in RAM (about 34 MB). With both
radios up as access points, the test unit had only about 25 MB available in
the initramfs, so go on to the flash step rather than using the initramfs for
anything else.

## 9. Write OpenWrt to slot A

From the PC, copy the sysupgrade image. The OpenWrt dropbear has no SFTP
server, so current OpenSSH clients need `-O` (legacy SCP protocol):

```sh
scp -O openwrt-qualcommax-ipq50xx-xiaomi_ax3000-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/sysupgrade.bin
```

On the router, compare the checksum with the one on the PC, test the image
and write it:

```sh
sha256sum /tmp/sysupgrade.bin
sysupgrade -T /tmp/sysupgrade.bin
sysupgrade -n /tmp/sysupgrade.bin
```

What the upgrade does on the RA80:

1. Uses `rootfs` (mtd18) as the target, always. It does not look at
   `flag_boot_rootfs`, which in the initramfs still points at the stock slot.
2. Removes the old `ubi_rootfs` volume that the stock firmware left in slot A.
3. Sets `boot_wait=on`, `uart_en=1`, `flag_boot_rootfs=0`,
   `flag_last_success=0`, `flag_boot_success=1`, `flag_try_sys1_failed=0` and
   `flag_try_sys2_failed=0`.
4. Writes the UBI volumes `kernel`, `rootfs` and `rootfs_data` and reboots.

On the console of the test unit:

```
Volume ID 0, size 33 LEBs (4190208 bytes, 3.9 MiB), ... name "kernel"
Volume ID 1, size 73 LEBs (9269248 bytes, 8.8 MiB), ... name "rootfs"
Volume ID 2, size 158 LEBs (20062208 bytes, 19.1 MiB), ... name "rootfs_data"
sysupgrade successful
```

Volume sizes depend on the build.

## 10. First boot and checks

U-Boot should print `boot from rootfs 0` and boot `config@mp02.1`. Then, over
SSH or on the console:

```sh
cat /proc/cmdline             # contains ubi.mtd=rootfs and root=/dev/ubiblock0_1
logread | grep bootcount      # bootcount: confirmed boot from rootfs slot 0
fw_printenv flag_boot_rootfs flag_last_success flag_boot_success flag_try_sys1_failed flag_try_sys2_failed
                              # 0, 0, 1, 0, 0
df -h /overlay                # UBIFS overlay, about 15.8 MB on the test unit
free                          # see problems.md for the memory figures
```

The `bootcount` line matters: it confirms the boot to U-Boot. Without that
confirmation the Xiaomi U-Boot eventually falls back to the other slot.

## 11. Set a password and configure Wi-Fi

```sh
passwd
```

LuCI is at `http://192.168.31.1/`.

In OpenWrt 25.12 both the radios **and** the default Wi-Fi interfaces
(`default_radio0`, `default_radio1`) are disabled. Enabling only the radio is
not enough. Check which radio is which band first:

```sh
uci show wireless | grep -E "band|disabled"
```

Then, for each radio (replace the placeholders):

```sh
uci set wireless.radio0.country='XX'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0.disabled='0'
uci set wireless.default_radio0.ssid='your-network'
uci set wireless.default_radio0.encryption='psk2+ccmp'
uci set wireless.default_radio0.key='your-passphrase'
uci commit wireless
wifi reload
```

The test unit runs as a wired access point next to a second OpenWrt AP; that
setup (802.11r, usteer) is described in [roaming](../roaming.md).

## Later upgrades

Use a normal sysupgrade with the new `...-squashfs-sysupgrade.bin` (LuCI:
System, Backup / Flash firmware; or `sysupgrade` on the command line). On this
device it always writes slot A and sets the boot flags to slot A again; slot
B is never touched.

Tested on 2026-10-30: the unit went from the lab build to the release image
with `sysupgrade` (settings kept), twice. Each time it came back in under a
minute from slot A (`ubi.mtd=rootfs`), `bootcount` confirmed the boot, the
kept settings were unchanged and both radios came up. Afterwards the data area
of all 288 blocks of slot B (`rootfs_1`, the stock firmware) was identical to
the backup taken before the installation.

## Packages

The images are custom builds. Kernel module packages (`kmod-*`) from the
official OpenWrt package repository will not install on them, because the
kernel hash differs from the official build. Anything that needs a kernel
module has to be added at build time (see `../../scripts/build.sh`).

## Not tested

- The `factory.ubi` image, and any way of flashing without the serial console.
- Installing when the stock firmware runs from slot A.
- The RA82 (international version), and stock firmware versions other than
  1.0.58 CN.
- Going back to the stock firmware: see [revert to stock](revert-to-stock.md).
