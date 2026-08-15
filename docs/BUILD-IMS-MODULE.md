# Building the Stock IMS Magisk Module

This guide rebuilds the working `stockims` module **from your own device's
firmware**. No proprietary files are distributed with this repository.

## Prerequisites

- realme GT 8 Pro (RMX5200) with unlocked bootloader, Magisk 30.7+
- A backup of the **stock firmware** (at minimum `super.img`), e.g. the full
  partition backup taken before flashing the GSI
- A phh-based GSI (Android 16) — everything in this project was verified on the
  [Evolution X Treble GSI](https://github.com/Doze-off/EvoX_treble),
  release 2026-07-20
- Windows PC with PowerShell 7+, Android platform-tools (`adb`), and
  [lpunpack](https://github.com/Rprop/lpunpack) (Windows builds available)
- Optional but very helpful: a file manager / terminal with root on the phone
  (loop-mounting is much faster than pushing images around)

## Step 1 — Extract the stock IMS app

```powershell
# On PC: unpack super.img
lpunpack.exe super.img .\lp_out

# On phone: push the system_ext image and loop-mount it
adb push .\lp_out\system_ext_a.img /data/local/tmp/
adb shell
su
mkdir -p /data/local/tmp/ims_stock
mount -o loop,ro /data/local/tmp/system_ext_a.img /data/local/tmp/ims_stock
```

You need these files (the module structure in this repo shows where each one goes):

| Source (inside the mount) | Destination in module |
|---|---|
| `system_ext/priv-app/ims/ims.apk` | `system/system_ext/priv-app/ims/ims.apk` |
| `system_ext/priv-app/ims/lib/arm64/*.so` | `system/system_ext/priv-app/ims/lib/arm64/` |
| `system_ext/framework/qti-telephony-hidl-wrapper.jar` | `system/system_ext/framework/` |
| `system_ext/framework/oplus-ims-ext.jar` — **do NOT use; see Step 3** | — |
| `system_ext/lib64/com.qualcomm.qti.imscmservice@*` | `system/system_ext/lib64/` |
| `system_ext/lib64/vendor.qti.ims.*` | `system/system_ext/lib64/` |
| `system_ext/lib64/vendor.qti.hardware.radio.ims@*` | `system/system_ext/lib64/` |
| `system_ext/lib64/lib-imsvt*.so`, `libimscamera_jni.so`, `libimsmedia_jni.so` | `system/system_ext/lib64/` |

Copy everything, then `umount /data/local/tmp/ims_stock`.

## Step 2 — Patch the stock APK

Apply the four scripts in `patches/dex/` **in this order**, chaining the output
of one into the next (each script verifies its own bytes before patching, so a
wrong input fails safely):

```powershell
.\bindexpatch3.ps1 -In ims.apk                 -Out ims_p1.apk   # feature-check bypass
.\finalpatch2.ps1   -In ims_p1.apk             -Out ims_p2.apk   # sLogMgr / sRilInner / make()
.\patchtablet.ps1   -In ims_p2.apk             -Out ims_p3.apk   # isTablet = false
.\encpatch2.ps1     -In ims_p3.apk             -Out ims_p4.apk   # CallEncryption (shipped state)
```

All patches target the **original dex offsets of the API-36 stock APK
(realme UI build BP4A.251205.006)**. If your firmware build differs, every
script will fail its byte verification — update the offsets from your own
disassembly rather than forcing them.

Then re-sign the APK (priv-app APKs must be signed — a debug key is fine):

```powershell
zipalign -f 4 ims_p4.apk ims_aligned.apk
apksigner sign --ks debug.keystore --out ims_final.apk ims_aligned.apk
```

Copy `ims_final.apk` to `modules/stockims/system/system_ext/priv-app/ims/ims.apk`.

## Step 3 — The shared libraries

Three framework jars must be present (with matching permission XMLs, already
included in the module skeleton):

1. **`qti-telephony-hidl-wrapper.jar`** — use the stock jar as-is (it has no
   missing dependencies).
2. **`oplus-ims-ext.jar` (declared as library `ims-ext-common`)** — the stock
   jar shadows the APK's own classes and references missing Oplus framework
   APIs. Replace it with the **minimal jar already provided** in the module
   skeleton (`system/system_ext/framework/oplus-ims-ext.jar`, ~1 KB) — it keeps
   the library name so the APK loads, without any classes.
3. **`qti-telephony-utils.jar`** — the stock jar is unusable on the GSI. Rebuild
   a working one (we called it `qcc10`) containing:
   - the `org.codeaurora.ims.*` classes the GSI framework lacks (recover them
     from the phh GSI's own `org.codeaurora.ims` APK dex);
   - `org.codeaurora.telephony.utils` (`Registrant`, `RegistrantList`,
     `AsyncResult`, …);
   - `IImsCallSessionImplWrapper` from the stock `ims-common.jar`;
   - a stub `com.oplus.nec.OplusNecManager`;
   - `QtiCarrierConfigHelper` with `registerReceiver(..., RECEIVER_NOT_EXPORTED)`
     (Android 16 enforces exported-receiver flags);
   - stubs for `QtiImsExtUtils.getIntArray()`,
     `isGlassesFree3DVideoSupported()`, `isVisualizedVoiceSupported()`
     — **these three stubs are what makes calls connect** (without them the app
     crashes on every call-state update).

   Assemble with `smali`/`apktool`, sign it as a jar, and place it at
   `system/system_ext/framework/qti-telephony-utils.jar`.

## Step 4 — Install and verify

```powershell
# zip the module and install
Compress-Archive -Path modules\stockims\* -DestinationPath stockims.zip
adb push stockims.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/stockims.zip'
adb reboot
```

After reboot:

```bash
adb shell "ps -A | grep codeaurora"        # stock IMS app running as priv_app
adb shell logcat -d | grep -E "MMTEL|ImsServiceController"   # feature READY
adb shell cmd phone ims enable             # if not enabled yet
```

Then check APNs: delete any **"PHH IMS"** APN phh may have injected (it steals
the IMS PDN):

```bash
adb shell content delete --uri content://telephony/carriers/restore --where "name='PHH IMS'"
```

## Known issues after install

- **Call audio**: calls connect, RTP = 0 (modem media plane — see JOURNEY.md)
- **SMS receive**: MT SMS not delivered (same suspect)
- These are under investigation; everything else (registration, SMS send,
  dialing, hangup) works.
