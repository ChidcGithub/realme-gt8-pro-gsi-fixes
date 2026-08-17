# patch_libbluetooth_jni.py
#
# Fixes "Bluetooth A2DP connects but plays silence" on the realme GT 8 Pro
# (RMX5200) running a phh-based GSI (verified on Evolution X Treble
# 2026-07-20, Android 16).
#
# ## Root cause
#
# On a GSI + vendor split, two Bluetooth audio provider factories coexist:
#
#   /sysbta  — registered by the phh sysbta service (android.hardware.bluetooth
#              .audio-service-system) in the *audioserver* process
#   /default — registered by the vendor QTI audio HAL (audiohalservice.qti)
#              in the *audiohalservice.qti* process
#
# The Bluetooth stack (libbluetooth_jni.so inside the com.android.bt APEX)
# hard-codes the AIDL service name suffix "/sysbta":
#
#   kDefaultAudioProviderFactoryInterface =
#       IBluetoothAudioProviderFactory::descriptor + "/sysbta";
#
# So the provider runs in audioserver. Meanwhile the vendor audio HAL's
# BluetoothAudioPortAidl (audio_sw.so) connects to "/default" — a different
# process. BluetoothAudioSessionInstance uses a *per-process* static map
# (sessions_map_E); when the provider calls OnSessionStarted() in
# audioserver, the session instance it finds has no observers. The session
# instance in audiohalservice.qti (the one with observers from audio_sw.so)
# is never notified → IsSessionReady() returns false forever → A2DP sink
# receives no PCM frames → silence.
#
# ## The patch
#
# Change the "/sysbta" string literal inside the APEX's libbluetooth_jni.so
# to "/default" so the BT stack connects to the *same* provider factory as
# the vendor audio HAL. Now provider and session live in the same process
# (audiohalservice.qti); OnSessionStarted() finds the session instance that
# has the observers → ReportSessionStatus() fires → IsSessionReady() = true.
#
# The strings sit in .rodata. "/sysbta" is 7 bytes + NUL = 8 bytes. "/default"
# is 8 bytes + NUL = 9 bytes — one byte longer. We overwrite the NUL
# terminator of "/sysbta" with 't' and the next byte (the 'B' of the
# following error-message string "BluetoothAudio AIDL implementation does
# not exist") becomes the new NUL. That error message is truncated by one
# leading byte — harmless, it is only used in a log line when the provider
# factory is missing (which it won't be after this patch).
#
# Offset (file offset == virtual address, segment 0 is identity-mapped):
#   0xA680F:  2F 73 79 73 62 74 61 00  /sysbta\0
#          -> 2F 64 65 66 61 75 6C 74 00  /default\0
#   0xA6817:  42 -> 00  (collateral: truncates next string's first byte)
#
# ## Usage
#
#   python patch_libbluetooth_jni.py \
#       -In libbluetooth_jni.so -Out libbluetooth_jni.patched.so
#
# Then ship via a Magisk module that bind-mounts the patched lib over
#   /apex/com.android.bt/lib64/libbluetooth_jni.so
# (see modules/bta2dp/ in this repo)
#
# Verified against the RMX5200 com.android.bt APEX
# (Evolution X Treble 2026-07-20, Android 16). The script byte-verifies
# before patching and fails safely on other builds.

import argparse, sys

SYSBTA_OFF  = 0xA680F
SYSBTA_ORIG = b'/sysbta\x00'
DEFAULT_NEW = b'/default\x00'

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-In",  dest="src", required=True)
    ap.add_argument("-Out", dest="out", required=True)
    args = ap.parse_args()

    data = bytearray(open(args.src, 'rb').read())

    # Verify
    actual = bytes(data[SYSBTA_OFF:SYSBTA_OFF + len(SYSBTA_ORIG)])
    if actual != SYSBTA_ORIG:
        sys.exit(
            f"verify failed: bytes at {SYSBTA_OFF:#x} are {actual.hex(' ')},\n"
            f"  expected {SYSBTA_ORIG.hex(' ')} — wrong APEX build?"
        )

    # Show context for the human
    ctx_before = data[SYSBTA_OFF - 16:SYSBTA_OFF]
    ctx_after  = data[SYSBTA_OFF + len(SYSBTA_ORIG):SYSBTA_OFF + len(SYSBTA_ORIG) + 32]
    print(f"offset {SYSBTA_OFF:#x}")
    print(f"  before : {bytes(ctx_before).hex(' ')} | {bytes(ctx_before)}")
    print(f"  original: {SYSBTA_ORIG.hex(' ')} | {SYSBTA_ORIG}")
    print(f"  after  : {bytes(ctx_after).hex(' ')} | {bytes(ctx_after)}")

    # Patch: overwrite /sysbta\0 with /default\0 (9 bytes, 1 byte longer)
    data[SYSBTA_OFF:SYSBTA_OFF + len(DEFAULT_NEW)] = DEFAULT_NEW

    # Verify patch
    patched = bytes(data[SYSBTA_OFF:SYSBTA_OFF + len(DEFAULT_NEW) + 8])
    print(f"  patched : {patched[:9].hex(' ')} | {patched[:9]}")
    assert patched[:9] == DEFAULT_NEW, "patch verification failed"

    # The byte at SYSBTA_OFF + 9 was 'B' (0x42) of "BluetoothAudio AIDL
    # implementation does not exist"; it is now 0x00 (NUL) — the error
    # message is truncated by one leading character. Confirm:
    collateral = data[SYSBTA_OFF + 9:SYSBTA_OFF + 9 + 40]
    print(f"  collateral (error msg now starts with NUL): {bytes(collateral)}")

    open(args.out, 'wb').write(bytes(data))
    print(f"\nwritten: {args.out}")
    print("bind-mount over /apex/com.android.bt/lib64/libbluetooth_jni.so")

if __name__ == '__main__':
    main()
