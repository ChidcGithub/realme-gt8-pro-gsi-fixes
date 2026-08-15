#!/system/bin/sh
# spoof.sh — Spoof stock device props so apps with risk-control
# (WeChat's System.exit() self-kill on "unknown devices") behave.
# Runs at boot via /data/adb/service.d/ (or post-fs-data.d).

for p in ro.product.model ro.product.device ro.product.name ro.product.odm.model \
         ro.product.odm.device ro.product.odm.name; do
    resetprop "$p" RMX5200
done
resetprop ro.product.manufacturer realme
resetprop ro.product.brand realme
resetprop ro.product.marketname "realme GT 8 Pro"
