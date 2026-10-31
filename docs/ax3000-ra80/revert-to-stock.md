# Xiaomi AX3000 (RA80): going back to the stock firmware

**Nothing on this page has been tested on the unit.** The commands follow
from how the Xiaomi U-Boot selects its boot slot (see
[hardware](hardware.md#boot-slots)) and from the backup made during the
[installation](install.md#4-back-up-every-partition-and-check-the-slot). Have
the serial console connected before you try any of it.

## What the installation leaves in place

If the stock firmware was running from slot B (`rootfs_1`, mtd19) when you
installed OpenWrt, as on the test unit:

| Part | State after installing OpenWrt |
|---|---|
| Slot B (`rootfs_1`, mtd19) | Stock firmware, untouched |
| `overlay` (mtd20) | Stock configuration, untouched. OpenWrt keeps its own settings in the `rootfs_data` volume inside slot A |
| `0:ART` (mtd13), `bdata` (mtd15) | Untouched. ART is read-only in the OpenWrt device tree |
| U-Boot | Not replaced |
| U-Boot environment | Changed: `boot_wait=on`, `uart_en=1` and the `flag_*` variables point at slot A |

So going back to stock only means pointing U-Boot at slot B.

## Boot the stock slot

From a running OpenWrt:

```sh
fw_setenv flag_boot_rootfs 1
fw_setenv flag_last_success 1
reboot
```

Or from the U-Boot prompt (stop autoboot on the serial console, see
[install](install.md#6-stop-u-boot)):

```
IPQ5018# setenv flag_boot_rootfs 1
IPQ5018# setenv flag_last_success 1
IPQ5018# saveenv
IPQ5018# reset
```

U-Boot should then print `boot from rootfs 1` and start the stock firmware.

Not verified:

- How the stock firmware updates the flags once it is running, and whether it
  ever switches back to slot A by itself.
- The stock firmware will not start SSH after this reboot (its firmware
  channel is `release`); use the serial console, which stays enabled because
  `uart_en=1`.

## Boot OpenWrt again

OpenWrt stays in slot A while the stock firmware runs from slot B. From the
U-Boot prompt:

```
IPQ5018# setenv flag_boot_rootfs 0
IPQ5018# setenv flag_last_success 0
IPQ5018# saveenv
IPQ5018# reset
```

Once OpenWrt is up, its `bootcount` script confirms the boot and resets the
failure counters. Repeating the [installation](install.md) from step 5 also
works, since it always writes slot A.

## If the stock slot was overwritten

This happens when the stock firmware was running from slot A at install time.
The only way back is the dump of that partition from your backup (`mtd18.bin`
for slot A). Slot A holds a UBI image, so the natural tool is `ubiformat`,
which is made for writing UBI images to NAND: it skips empty pages, keeps the
erase counters and works around bad blocks. **This outline has not been
tried:**

1. Boot the OpenWrt initramfs over TFTP ([install](install.md), steps 5 to 7).
   It runs from RAM and does not attach the slot partitions, so slot A is not
   in use. The images include `ubi-utils`, so `ubiformat` is there
   (`command -v ubiformat` to check).
2. Confirm on the router that `rootfs` is mtd18 and 0x2400000 bytes long, and
   that the dump has exactly that size:

   ```sh
   ssh root@192.168.31.1 'cat /proc/mtd'
   ls -l mtd18.bin            # 37748736 bytes
   ```

3. Stream the dump into the partition (it does not fit in the initramfs RAM):

   ```sh
   ssh root@192.168.31.1 'ubiformat /dev/mtd18 -y -f - -S 37748736' < mtd18.bin
   ```

4. Point U-Boot at slot A and reboot:

   ```sh
   ssh root@192.168.31.1 'fw_setenv flag_boot_rootfs 0; fw_setenv flag_last_success 0; reboot'
   ```

   On the console, U-Boot should print `boot from rootfs 0`, attach the UBI
   with the volumes `kernel` and `ubi_rootfs`, and start the stock kernel.

Caveats:

- OpenWrt must use the same 8-bit ECC as U-Boot, or U-Boot cannot read what
  it writes. This build does (confirmed by booting the sysupgrade image from
  U-Boot); a build with the 4-bit default does not.
- Only write a dump back to the partition it was read from, and only a dump
  from the same unit.
- Do not write `0:ART`, `bdata`, the U-Boot partitions or the boot chain
  partitions back unless they are actually damaged. OpenWrt does not write
  them during installation, and restoring them was not attempted.

## Not tried

- Xiaomi's own recovery tools and official firmware images.
- Restoring the U-Boot environment (mtd10) from the backup.
