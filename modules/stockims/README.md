# stockims — Magisk module skeleton

This folder is the module skeleton for the ported stock `org.codeaurora.ims`
(API 36). **Proprietary binaries are intentionally absent** — extract them
from your own firmware backup and drop them in, following
[`docs/BUILD-IMS-MODULE.md`](../../docs/BUILD-IMS-MODULE.md).

## What's already here

```
module.prop                                      # Magisk metadata
system.prop                                      # persist.oplus.qspa.modem=enabled (overlay gate)
post-fs-data.sh                                  # live SELinux injection (magiskpolicy --live)
sepolicy.rule                                    # best-effort early rules (reference only)
system/system_ext/etc/permissions/*.xml          # shared-library declarations
system/system_ext/framework/oplus-ims-ext.jar    # minimal stub jar (keeps library name only)
```

## What you must add (from your own device)

```
system/system_ext/priv-app/ims/ims.apk           # stock APK, dex-patched, re-signed
system/system_ext/priv-app/ims/lib/arm64/*.so
system/system_ext/framework/qti-telephony-hidl-wrapper.jar   # stock, as-is
system/system_ext/framework/qti-telephony-utils.jar          # rebuilt "qcc10" jar
system/system_ext/lib64/…                        # all stock ims/imsmedia/imsRtp .so files
```

## Install

```bash
# from this repo root
cd modules/stockims
zip -r ../stockims.zip .                 # or Compress-Archive on Windows
adb push ../stockims.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/stockims.zip'
adb reboot
```
