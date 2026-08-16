# patch_audio_hal.py
#
# Fixes "calls connect but no audio" on the realme GT 8 Pro (RMX5200) with a
# phh-based GSI (verified on Evolution X Treble 2026-07-20, Android 16).
#
# ## Root cause
# Android 16 audio frameworks introduced HAL-owned call state machines:
# the framework sends `updateCalls` with `CallState::DEFAULT` for every call
# and expects the HAL to advance its own state machine from `setTelecomConfig`
# events. The GSI's audiopolicy never sends `setTelecomConfig`, while the
# vendor QTI audio HAL (libaudiocorehal.qti.so) only advances its state
# machine on explicit ACTIVE states. Result: the voice session never starts,
# the modem never brings up its media plane, and the network's RTP is
# rejected with ICMP port-unreachable. Calls connect, zero audio.
#
# ## The patch
# In the HAL's updateCalls loop, framework state "1" (the Default/inactive
# request) is ignored when the machine is IN_ACTIVE — the code just logs
# "CallState: Default cannot be handled in state IN_ACTIVE" and skips.
# One branch redirects that path into the ACTIVE handling (which starts the
# PAL voice session: log "INACTIVE -> ACTIVE", startCall, etc.):
#
#   0x124110: b.ne  #0x1241bc   (log + skip)
#       ->
#   0x124110: b.ne  #0x124024   (run the activation path)
#
# Call teardown is unaffected: it is driven by the audio-mode switch to
# NORMAL (VoiceStop), not by updateCalls.
#
# ## Usage
#   python patch_audio_hal.py -In libaudiocorehal.qti.so -Out libaudiocorehal.patched.so
#
# Then ship the patched lib through a Magisk module at:
#   <module>/system/vendor/lib64/hw/libaudiocorehal.qti.so
# (see modules/audiopatch/ in this repo)
#
# Verified against the RMX5200 vendor lib
# (SHA-256 of the original: see modules/audiopatch/README.md). The script
# re-verifies the branch encoding before patching and fails safely otherwise.

import argparse, struct, io, sys
from elftools.elf.elffile import ELFFile

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-In", dest="src", required=True)
    ap.add_argument("-Out", dest="out", required=True)
    args = ap.parse_args()

    data = bytearray(open(args.src, 'rb').read())
    elf = ELFFile(io.BytesIO(bytes(data)))
    text = elf.get_section_by_name('.text')
    tbase = text.header.sh_addr
    text_off = text.header.sh_offset

    def read_word(va):
        return struct.unpack_from('<I', data, text_off + (va - tbase))[0]

    def write_word(va, w):
        struct.pack_into('<I', data, text_off + (va - tbase), w)

    def bcond(cond, va_from, va_to):
        off = (va_to - va_from) >> 2
        assert -(1 << 18) <= off < (1 << 18), "branch out of range"
        return 0x54000000 | ((off & 0x7FFFF) << 5) | (cond & 0xF)

    SITE = 0x124110
    OLD_TARGET = 0x1241BC
    NEW_TARGET = 0x124024

    orig = read_word(SITE)
    expected = bcond(1, SITE, OLD_TARGET)   # b.ne to the log-and-skip path
    if orig != expected:
        sys.exit(f"verify failed: word at {SITE:#x} is {orig:#010x}, expected {expected:#010x} — wrong lib build?")

    new = bcond(1, SITE, NEW_TARGET)
    write_word(SITE, new)
    open(args.out, 'wb').write(bytes(data))
    print(f"patched {SITE:#x}: b.ne {OLD_TARGET:#x} -> b.ne {NEW_TARGET:#x}")
    print(f"written: {args.out}")

if __name__ == '__main__':
    main()
