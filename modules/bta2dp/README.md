# bta2dp — Bluetooth A2DP silent-audio fix

Fixes "Bluetooth connects but A2DP plays silence" on the realme GT 8 Pro
(RMX5200) running a phh-based GSI (verified on Evolution X Treble,
Android 16).

## What it does

Patches **one string** inside the `com.android.bt` APEX's
`libbluetooth_jni.so` — changes the hard-coded AIDL service suffix
`/sysbta` → `/default` so the GSI Bluetooth stack connects to the *vendor*
QTI provider factory (`audiohalservice.qti`) instead of the phh sysbta
factory (`audioserver`).

Making provider and session client live in the **same process** unblocks
the per-process `BluetoothAudioSessionInstance` notification: the provider's
`OnSessionStarted()` finds the session instance that has the observers from
`audio_sw.so`, `IsSessionReady()` returns true, and PCM data flows.

A Magisk module bind-mounts the patched `.so` over the APEX path
(`/apex/com.android.bt/lib64/libbluetooth_jni.so`) at `post-fs-data` time,
before the BT service starts.

Full root-cause analysis: [`../../patches/bt/patch_libbluetooth_jni.py`](../../patches/bt/patch_libbluetooth_jni.py)

## Software-encoding mode (recommended)

This module also forces the **software A2DP encoding path** (not the
offload path), since this device's offload widgets aren't available on a
GSI and would otherwise cause a second silent-audio failure. Set these
props once via `adb shell` (they persist; the module itself doesn't set
them):

```bash
adb shell su -c 'setprop ro.bluetooth.a2dp_offload.supported false'
adb shell su -c 'setprop persist.bluetooth.enable_bt_offload false'
adb shell su -c 'setprop persist.sys.phh.disable_a2dp_offload true'
adb reboot
```

If your existing `oplusfix` or similar module already runs `resetprop_phh`
with these three props at boot (as the sample `post-fs-data.sh` does), you
don't need to repeat them here.

## Build (from your own device)

```bash
# 1. pull the APEX lib
adb shell su -c 'cp /apex/com.android.bt/lib64/libbluetooth_jni.so /data/local/tmp/'
adb pull /data/local/tmp/libbluetooth_jni.so

# 2. patch it (needs python3; verify the offset is 0xA680F)
python ../../patches/bt/patch_libbluetooth_jni.py \
    -In libbluetooth_jni.so -Out libbluetooth_jni.patched.so

# 3. drop the patched lib into this module tree
cp libbluetooth_jni.patched.so system/lib64/libbluetooth_jni.so

# 4. zip and install
cd .. && zip -r bta2dp.zip bta2dp
adb push bta2dp.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/bta2dp.zip'
adb reboot
```

## Verification

After reboot, pair a Bluetooth A2DP sink and play music. In
`dumpsys media.audio_flinger` the A2DP output thread should show
`Standby: no` and active tracks at 44100 Hz / 16-bit / stereo:

```
Output thread 0x...790, name AudioOut_6D, tid ..., type 0 (MIXER):
    Standby: no
    Sample rate: 44100 Hz
    HAL format: 0x1 (AUDIO_FORMAT_PCM_16_BIT)
    Output devices: 0x80 (AUDIO_DEVICE_OUT_BLUETOOTH_A2DP)
```

If you still see silence, check `service list | grep IBluetoothAudioProviderFactory`
— both `/default` and `/sysbta` will be registered, but only `/default`
should be the one wired up (the BT stack's session client connects there).

## Notes

- The patch offset (`0xA680F`) is verified against the RMX5200
  `com.android.bt` APEX from Evolution X Treble 2026-07-20 (Android 16).
  The script byte-verifies before patching and fails safely on other builds.
- The one-byte overwrite truncates the next rodata string
  (`"BluetoothAudio AIDL implementation does not exist"`) by one leading
  character. This is harmless — that string is only used in a log line when
  the provider factory is missing, which it won't be after this patch.
- If your GSI ever ships a fix that makes the BT stack use `/default` on
  its own (or removes the sysbta service entirely), remove this module.
