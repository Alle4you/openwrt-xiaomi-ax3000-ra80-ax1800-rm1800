# Xiaomi AX3000 (RA80): problems found during the port

Everything that went wrong or needed a workaround while porting OpenWrt
25.12.4 to the RA80, roughly in the order it came up. Roaming and usteer
topics are covered in [roaming](../roaming.md).

| # | Problem | Status |
|---|---|---|
| 1 | Serial console silent on the stock firmware | Worked around (xmir-patcher) |
| 2 | Wrong pins on the first wiring attempts | Solved, pinout documented |
| 3 | Stock SSH disappears on reboot; empty host key | Worked around (serial console) |
| 4 | NAND read with 4-bit ECC | Fixed in the device tree |
| 5 | "Failed to find NVMEM device" at boot | Fixed (uboot-envtools) |
| 6 | Wi-Fi firmware assert in `phyrf_bdf.c:605` | Fixed (board data byte 0x45c) |
| 7 | Writing MAC addresses into the calibration data | Fixed (extract only) |
| 8 | 5 GHz calibration entry in the wrong section | Fixed |
| 9 | First `tftpboot` fails right after stopping U-Boot | Worked around (retry) |
| 10 | Default Wi-Fi interfaces disabled in 25.12 | Expected behaviour, documented |
| 11 | Reloading ath11k does not restart the Wi-Fi firmware | Open, reboot needed |
| 12 | RAM is tight | Monitored, no OOM so far |
| 13 | LuCI Status, Firewall is empty in access point mode | Expected behaviour |
| 14 | Upgrade from the initramfs could overwrite the stock slot | Avoided by design |
| 15 | Unconfirmed boots fall back to the other slot | Handled by `bootcount` |
| 16 | Clock not set in access point mode | Fixed in the release overlay |
| 17 | `scp` fails against OpenWrt | Use `scp -O` |
| 18 | PC loses its static address while the router reboots | Host configuration |
| 19 | Two units on one network with the same LAN address | Configuration |
| 20 | Harmless log messages | Not investigated |

## 1. Serial console silent on the stock firmware

- **Symptom:** nothing at all on J1, in either direction, not even the U-Boot
  banner, whatever the wiring.
- **Cause:** the stock firmware and its U-Boot keep the UART off while
  `uart_en=0` in the U-Boot environment, the factory state.
- **Fix:** run xmir-patcher first; it sets `uart_en=1` (plus `boot_wait=on`
  and `bootdelay=3`), and these survive reboots. Wiring tests done before that
  prove nothing.

## 2. Wrong pins on the first wiring attempts

- **Symptom:** with `uart_en=1`, several wirings still gave 0 bytes,
  including the adapter's RX on pin 2 and the reference voltage on pin 4.
- **Cause:** a multimeter shows 1.8 V on pins 1, 2 and 4 at idle, so it cannot
  tell VCC from the data lines. The router's TX is pin 4, not pin 2. Loose
  jumper wires added noise (a loopback test on the adapter alone passed but
  was sensitive to how the wires sat).
- **Fix:** pin 1 VCC (next to C106), pin 2 RX (series R52), pin 3 GND, pin 4 TX
  (series R53). Confirmed by a clean 78 KB boot log on pin 4 and a working
  shell through pin 2. See [hardware](hardware.md#serial-console-j1).

## 3. Stock SSH disappears on reboot; empty host key

- **Symptom:** SSH opened by xmir-patcher is gone after a reboot.
  `dropbear -R` does not start either.
- **Cause:** the stock `/etc/init.d/dropbear` only starts with `ssh_en=1`
  **and** a firmware channel other than `release`; this firmware is `release`.
  The stock host key `/etc/dropbear/dropbear_rsa_host_key` is 0 bytes.
- **Fix:** from the root shell on the serial console, generate a key in
  `/tmp` and start dropbear by hand (see
  [install](install.md#3-get-ssh-back-after-a-reboot)). The stock dropbear also
  needs `-o HostKeyAlgorithms=+ssh-rsa` on current OpenSSH clients.

## 4. NAND read with 4-bit ECC

- **Symptom (first build, initramfs over TFTP):**
  - `GMAC1 ... Invalid MAC@ - using <random>` for both Ethernet MACs;
  - the ART nvmem cells returned `EBADMSG` ("Bad message");
  - `mtdsplit: error occured while reading from "rootfs"`;
  - the 2.4 GHz calibration data got an invalid MAC address;
  - the Wi-Fi firmware asserted (`phyrf_bdf.c:605`), and the 5 GHz
    calibration file `cal-ahb-b00a040.wifi.bin` was never created.
- **Cause:** OpenWrt picked 4-bit ECC, the minimum the GD5F1GQ5 requires,
  but the Xiaomi U-Boot and the stock firmware write with 8-bit ECC. On the
  QPIC controller the position of the data in a page changes with the ECC
  strength, so only the first 512 bytes came out right. 74 ECC failures were
  counted on `0:art`. Reading `/dev/mtd13` with `dd` still returned data
  despite the errors, which is why the calibration header looked plausible.
- **Why it mattered most:** an image written to the slot with 4-bit ECC
  would have been unreadable by U-Boot. Nothing was written in that boot: the
  TFTP boot does not attach UBI, and `fw_setenv` had no configuration yet.
- **Fix:** `nand-ecc-strength = <8>` and `nand-ecc-step-size = <512>` in the
  device tree. Confirmed when U-Boot booted the UBI written by sysupgrade.

## 5. "Failed to find NVMEM device" at boot

- **Symptom:** that line on the console during boot of the first build.
- **Cause:** `fw_printenv` ran without a configuration for the RA80.
- **Fix:** the RA80 joins the Xiaomi AX6000 entry in `uboot-envtools`
  (`0:appsblenv`, 64 KiB, plus `bdata`).

## 6. Wi-Fi firmware assert in `phyrf_bdf.c:605`

- **Symptom:** with the ECC fixed, the Wi-Fi firmware still crashed right
  after the 2.4 GHz board data was sent:

  ```
  qcom-q6-mpd cd00000.remoteproc: fatal error received: err_smem_ver.2.1:
  phyrf_bdf.c:605 Assertion 0 failed param0 :zero,param1 :zero,param2 :zero
  ```

  followed by `start timed out` and `failed to load board data file`.
- **Cause:** the board data files come from the stock firmware, which runs
  WLAN firmware `WLAN.HK.2.5.r4-00683`. OpenWrt ships
  `WLAN.HK.2.7.0.1-01744`, which only accepts 0 in byte 0x45c (antenna chain
  axis). The stock files carry 0x03 there.
- **Fix:** clear byte 0x45c in both files and fix the checksum with
  `scripts/bd-patch.py`. The idea comes from the same failure on the Linksys
  MX2000 in the OpenWrt forum (post #255 of the IPQ5018 MX2000/MX5500
  thread). See [changes](changes.md#wi-fi-board-data-ipq-wifi).

Note that the 4-bit ECC problem (4) produced the same assert through
scrambled calibration data; both causes had to go.

## 7. Writing MAC addresses into the calibration data

- **Symptom:** the 2.4 GHz calibration data ended up with a bogus MAC address.
- **Cause:** the first build patched the radio MACs into the calibration data,
  derived from the label MAC with `macaddr_add`. With the label MAC unreadable
  (problem 4) the result was garbage. It was also unnecessary: Xiaomi already
  stores the radio MACs in the ART calibration data (5 GHz = LAN MAC + 1,
  2.4 GHz = LAN MAC + 2) with the MAC flag set.
- **Fix:** only extract the calibration data, as for the Xiaomi AX6000.

## 8. 5 GHz calibration entry in the wrong section

- **Symptom:** the 5 GHz radio could not load its calibration data:
  `qmi failed to load CAL data file:cal-ahb-b00a040.wifi.bin` and
  `failed to load board data file: -12`.
- **Cause:** in `11-ath11k-caldata` the RA80 case for offset 0x26800 was added
  to the QCN9074 section (the AX6000's PCIe radio uses the same offset)
  instead of the QCN6122 section `cal-ahb-b00a040.wifi.bin`.
- **Fix:** moved to the QCN6122 section.

## 9. First `tftpboot` fails right after stopping U-Boot

- **Symptom:** the first `tftpboot` after stopping autoboot fails at once,
  with the PC's port shown as down.
- **Cause:** the switch is still negotiating the link.
- **Fix:** wait about 4 seconds and run `tftpboot` again (up to three tries
  were needed).

## 10. Default Wi-Fi interfaces disabled in 25.12

- **Symptom:** a radio is enabled but no access point appears.
- **Cause:** in OpenWrt 25.12 the interfaces `default_radio0` and
  `default_radio1` are created with `disabled='1'`, besides the radios.
- **Fix:** enable both the radio and its interface (see
  [install](install.md#11-set-a-password-and-configure-wi-fi)).

## 11. Reloading ath11k does not restart the Wi-Fi firmware

- **Symptom:** after `rmmod` and `insmod` of ath11k, the Q6 does not come
  back: `qcom-q6-mpd cd00000.remoteproc: start timed out`,
  `failed to boot the remote processor Q6`, and the probe fails with -110 on
  both radios.
- **Cause:** not investigated. The remoteproc stops cleanly but cannot be
  started again without a reboot.
- **Status:** open. Every Wi-Fi driver test needs a reboot.

## 12. RAM is tight

The RA80 has less free memory than the Xiaomi AX1800 with the same fixes.
The AX1800's IPQ6018 has both radios in one chip (one `ath11k_base`); the
RA80 has two Wi-Fi chips, so two `ath11k_base` instances, each with its own
rings. The estimate before flashing was about 60 MB available; the
measurements came out lower.

| Situation | `MemAvailable` |
|---|---:|
| Initramfs, both radios up as AP, no clients (34 MB of it is the initramfs root in RAM) | 25.7 MB |
| Installed, 1.5 min after boot, Wi-Fi off | 39.4 MB |
| Installed, access point, both radios on, 1.5 min after boot | 36.5 MB |
| Access point, first hours, up to 5 clients (sampled every minute) | 30.5 to 48.9 MB, no downward trend |
| Xiaomi AX1800 in its first hours, for comparison | 51.9 to 81.4 MB |

Slab stayed at about 52 MB. No OOM kill, firmware crash or reboot in that
period. Other figures from the initramfs: about 43 MB of unreclaimable slab
and about 40 MB used outside slab, page cache and processes (DMA rings and
driver pages). The kernel has no `/proc/slabinfo`, so a finer breakdown is
still missing.

The test unit runs as a wired access point with `dnsmasq`, `odhcpd` and the
firewall disabled, which saves memory (no conntrack, no rule tables). Running
it as a router with the default services has not been measured. A long-term
memory test is still pending.

## 13. LuCI Status, Firewall is empty in access point mode

- **Symptom:** the Status, Firewall page in LuCI is blank.
- **Cause:** that page shows the active nftables rules, and with fw4
  disabled `nft list ruleset` is empty.
- **Status:** expected. The firewall configuration is still under Network,
  Firewall.

## 14. Upgrade from the initramfs could overwrite the stock slot

- **Risk:** the AX1800 port picks the target slot from `flag_boot_rootfs`.
  From the initramfs that flag still points at the slot the stock firmware
  runs from (slot B on the test unit), so the same logic would have written
  OpenWrt over the stock firmware.
- **Fix:** `platform.sh` always writes slot A (`rootfs`). Consequence: if the
  stock firmware runs from slot A, it is overwritten (see
  [install](install.md#where-openwrt-goes)).

## 15. Unconfirmed boots fall back to the other slot

- **Risk:** the Xiaomi U-Boot counts a boot that the system does not confirm
  as failed, and after repeated failures boots the other slot.
- **Fix:** `/etc/init.d/bootcount` confirms every boot from flash
  (`bootcount: confirmed boot from rootfs slot 0` in the log). It also
  creates `/etc/fw_env.config` if it is missing, so the confirmation cannot be
  lost on the first boot.

## 16. Clock not set in access point mode

- **Symptom:** the clock stays at the build date.
- **Cause:** with every port in the LAN bridge there is no `wan` interface,
  which is what normally triggers NTP.
- **Fix:** the release overlay restarts `sysntpd` when `lan` comes up
  (`/etc/hotplug.d/iface/30-ntp-lan`).

## 17. `scp` fails against OpenWrt

- **Cause:** current OpenSSH `scp` uses SFTP, and OpenWrt's dropbear has no
  SFTP server.
- **Fix:** `scp -O` (legacy SCP protocol).

## 18. PC loses its static address while the router reboots

- **Symptom:** after a router power cycle the router seemed unreachable for a
  long time, although it was up.
- **Cause:** on the PC, the connection profile with the static
  192.168.31.100 address was not set to reconnect automatically; when the
  link dropped, the Ethernet port came back without an address.
- **Fix:** make the PC's static profile reconnect automatically for the
  duration of the work.

## 19. Two units on one network with the same LAN address

Both release images (AX3000 and AX1800) use `192.168.31.1` on the LAN. On the
test setup the second AP was first configured with the same management
address, and the two usteer instances did not see each other. Give each unit
its own address; details in [roaming](../roaming.md).

## 20. Harmless log messages

Seen on the working system, with no visible effect. Not investigated further.

| Message | Where |
|---|---|
| `command failed: Not supported (-95)` | netifd, when Wi-Fi starts: antenna configuration, which ath11k does not implement |
| `fdt_fixup_qpic: QPIC: unable to find node '/soc/qpic-nand@79b0000'` | U-Boot, on every OpenWrt boot (TFTP and flash), not with the stock firmware |
| `adpt_mp_port_netdev_change_notify[...]:ERROR:netdev change notify with incorrect port 0` and `ssdk_dev_event[...]:ERROR:netdev change notify failed` | Kernel, on link changes |
| `ath11k c000000.wifi: qmi fail to get qcom,m3-dump-addr, ignore m3 dump mem req` | Kernel, 2.4 GHz radio (only the 5 GHz node has an M3 dump address) |
| `mtdsplit: no squashfs found in "rootfs"` | Kernel, initramfs boot while slot A still holds the stock UBI |
| `psci: [Firmware Bug]: failed to set PC mode: -1` | Kernel, early boot |

## Still open or not verified

- Physical order of the LAN ports and the WAN port.
- Throughput tests, HE160, DFS channels, 5 GHz channels above 144.
- Routing mode (only access point mode has been used).
- Long-term stability and memory (the unit has run for hours, not weeks).
- An upgrade from an installed OpenWrt, and going back to stock.
- The network LEDs and the mesh button under OpenWrt.
