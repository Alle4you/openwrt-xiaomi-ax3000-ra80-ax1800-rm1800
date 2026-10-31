# Going back to the stock firmware (AX1800 / RM1800)

If you followed [install.md](install.md), the stock firmware is still intact in
slot A (`rootfs`, mtd12) and OpenWrt is in slot B (`rootfs_1`, mtd13). Going back
is a matter of telling U-Boot which slot to boot.

**Status:** the commands below are the ones prepared in the lab. Switching back
to the stock slot has not been exercised on the tested unit yet, and restoring
partitions from the backup was never needed or tested. Have the serial console
at hand before trying.

## Boot the stock slot

From OpenWrt:

```sh
fw_setenv flag_boot_rootfs 0
reboot
```

From the U-Boot console (`IPQ6018#`, see [hardware.md](hardware.md#u-boot)):

```
setenv flag_boot_rootfs 0
saveenv
reset
```

`flag_boot_rootfs=0` selects slot A, `1` selects slot B. OpenWrt stays untouched
in slot B.

## Boot OpenWrt again

From the stock shell, the same flags as in the first install:

```sh
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_boot_success=1
nvram set flag_ota_reboot=0
nvram set flag_try_sys2_failed=0
nvram commit && reboot
```

Or from U-Boot: `setenv flag_boot_rootfs 1; saveenv; reset`. Once OpenWrt boots,
its `bootcount` script rewrites all the slot flags for slot B.

## Removing OpenWrt completely

Not needed: the stock firmware does not use slot B while it runs from slot A.
Keep in mind that the stock OTA updater uses the same two slots, so an update
installed from the stock firmware could overwrite the OpenWrt slot (not tested).
The base port's author turned the stock automatic OTA download
(`otapredownload`) off to avoid that.

## Restoring from the backup (not tested)

None of this was needed on the tested unit. What is known:

- **A damaged slot**: boot the initramfs over TFTP as in
  [install.md](install.md#4-test-the-initramfs-from-ram). From there you can
  rewrite slot B with the OpenWrt `factory.ubi` (step 5 of the install). For the
  stock slot, the backup of mtd12 is a dump of a UBI partition; writing it back
  with `ubiformat /dev/mtd12 -f mtd12.bin -y` is the obvious route but was not
  tested. Check the dump's checksum first.
- **ART (mtd8) and bdata (mtd9)**: OpenWrt marks both read-only in its device
  tree, so it cannot damage them, and it cannot restore them either without a
  modified image. The base port lists restoring ART from the console as a last
  resort. Without a valid ART there is no Wi-Fi calibration.
- **U-Boot environment (mtd6)**: the backup holds the original environment,
  including the original slot flags. Restoring it was not tested; changing only
  the flags as shown above is the safer route.

If the router does not boot at all, the serial console and U-Boot TFTP still
work as long as the boot chain partitions (`0:SBL1` to `0:CDT` and `0:APPSBL`)
are intact. The install and the steps on this page only write the U-Boot
environment (mtd6) and the two rootfs slots (mtd12 and mtd13).
