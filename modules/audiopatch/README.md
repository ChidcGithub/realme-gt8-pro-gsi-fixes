# audiopatch — Audio HAL Call State Machine fix

Fixes "calls connect but no audio" on the realme GT 8 Pro (RMX5200) running a
phh-based GSI (verified on Evolution X Treble, Android 16).

## What it does

Patches **one branch** in the vendor QTI audio HAL
(`/vendor/lib64/hw/libaudiocorehal.qti.so`) so the framework's `CallState::DEFAULT`
updates are treated as ACTIVE — the HAL's voice session (and with it the modem's
media plane) comes up and call audio flows.

Full root-cause analysis: [`../../patches/hal/patch_audio_hal.py`](../../patches/hal/patch_audio_hal.py)

## Build (from your own device)

```bash
# 1. pull the vendor lib
adb shell su -c 'cp /vendor/lib64/hw/libaudiocorehal.qti.so /data/local/tmp/'
adb pull /data/local/tmp/libaudiocorehal.qti.so

# 2. patch it (needs python3 + pyelftools; verify output mentions the b.ne rewrite)
python ../../patches/hal/patch_audio_hal.py -In libaudiocorehal.qti.so -Out libaudiocorehal.patched.so

# 3. drop the patched lib into this module tree
cp libaudiocorehal.patched.so system/vendor/lib64/hw/libaudiocorehal.qti.so

# 4. zip and install
cd .. && zip -r audiopatch.zip audiopatch
adb push audiopatch.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/audiopatch.zip'
adb reboot
```

## Verification

After reboot, make a call. Expected logcat:

```
AHAL_Telephony_QTI: updateCalls CallState: INACTIVE -> ACTIVE vsid:VSID_2
AHAL_Telephony_QTI: startCall: Enter ...
```

## Notes

- The patch offsets are verified against the stock RMX5200 vendor lib
  (Android 16, build BP4A.251205.006). The script byte-verifies before
  patching and fails safely on other builds.
- Call teardown is unaffected (driven by the audio-mode switch, not updateCalls).
- If your device gets official `setTelecomConfig` support in a future GSI
  update, remove this module.
