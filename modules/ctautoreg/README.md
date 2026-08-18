# ctautoreg — stock `com.oppo.ctautoregist` as a priv-app

Magisk module that installs the **stock OPPO CT auto-registration app**
(`com.oppo.ctautoregist`, carved from your own `my_product` image) as a
`/system_ext/priv-app` with privileged permissions, so it can read the real
IMSI and send the CT SMS-over-IMS registration by itself.

> The APK is **not** in this repo (proprietary). Build it from your own firmware
> backup — see below.

## Why (as of 2026-08-18)

- The `ctreg` clone needs manual permission grants and manual triggers; the
  stock app has proper retry/ACK logic (`RECEIVE_SMS_REG_ACK`), a 30-day
  re-registration timer and dual-SIM handling.
- However, on the GSI the stock app currently **cannot run by itself**:
  - its `RegisterReceiver` manifest filter requires broadcasting apps to hold
    `oppo.permission.OPPO_COMPONENT_SAFE` (OPPO signature permission) — shell
    broadcasts get dropped with "skipped by policy";
  - it depends on `android.telephony.OplusTelephonyManager` /
    `OplusOSTelephonyManager` (oplus-framework) for IMSI/registration checks —
    absent on AOSP GSIs, the receiver crashes on boot.

  So today it is deployed but dormant; `ctreg` remains the working sender.
  Kept in the tree because it is the reference for the exact stock XML format
  (see `modules/ctreg/README.md`).

## Layout

```
system/priv-app/CTAutoRegist/CTAutoRegist.apk                          # you add this
system/priv-app/CTAutoRegist/privapp-permissions-com.oppo.ctautoregist.xml
system/etc/sysconfig/hiddenapi-package-whitelist.xml
```

## Building from your own backup

1. Extract the stock `my_product` image from your `super.img` backup
   (`lpunpack.py -p my_product_a super.img out/`).
2. Carve the APK: scan the image for `PK\x03\x04` zip starts whose central
   directory contains `AndroidManifest.xml` + `classes.dex` and whose entry
   list matches the CTAutoRegist package (see `patches/experiments` for the
   carving script).
3. Drop it at `system/priv-app/CTAutoRegist/CTAutoRegist.apk`, zip the module
   (or copy the folder to `/data/adb/modules/ctautoreg/` directly) and reboot.

## Deployment (manual copy, no update-binary needed)

```bash
adb push system /data/local/tmp/ct_stage/
adb shell su -c 'mkdir -p /data/adb/modules/ctautoreg && \
    cp -r /data/local/tmp/ct_stage/* /data/adb/modules/ctautoreg/ && \
    chmod -R 755 /data/adb/modules/ctautoreg'
adb reboot
```

Trigger attempt (currently blocked by `OPPO_COMPONENT_SAFE`, see above):

```bash
adb shell am broadcast -a oppo.intent.action.ims_regist \
    -n com.oppo.ctautoregist/.RegisterReceiver
```
