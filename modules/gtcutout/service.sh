#!/system/bin/sh
# service.sh - runs at late_start service stage
# Disable built-in hole cutout emulation overlay so our custom overlay takes effect
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3
cmd overlay disable com.android.internal.display.cutout.emulation.hole
