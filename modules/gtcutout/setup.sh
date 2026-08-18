#!/system/bin/sh
MODDIR=/data/adb/modules/gtcutout
rm -rf "$MODDIR"
mkdir -p "$MODDIR/system/product/overlay/Gt8proCutoutOverlay"
cp /data/local/tmp/gt8pro_cutout_overlay.apk "$MODDIR/system/product/overlay/Gt8proCutoutOverlay/Gt8proCutoutOverlay.apk"
chmod 644 "$MODDIR/system/product/overlay/Gt8proCutoutOverlay/Gt8proCutoutOverlay.apk"
chmod 755 "$MODDIR/system/product/overlay/Gt8proCutoutOverlay"

cat > "$MODDIR/module.prop" <<EOF
id=gtcutout
name=GT8 Pro Center Cutout
version=v3
versionCode=3
author=chidc
description=Binds a custom RRO overlay defining the realme GT8 Pro center punch hole for GSI displays. Disables built-in hole emulation.
EOF

chcon u:object_r:system_file:s0 "$MODDIR/system/product/overlay/Gt8proCutoutOverlay/Gt8proCutoutOverlay.apk"
chcon u:object_r:system_file:s0 "$MODDIR/system/product/overlay/Gt8proCutoutOverlay"

# Install service.sh to disable built-in hole cutout overlay
cp /data/local/tmp/service.sh "$MODDIR/service.sh"
chmod 755 "$MODDIR/service.sh"
chcon u:object_r:system_file:s0 "$MODDIR/service.sh"

echo "=== module.prop ==="
cat "$MODDIR/module.prop"
echo "=== APK ==="
ls -lZ "$MODDIR/system/product/overlay/Gt8proCutoutOverlay/"
echo "=== service.sh ==="
cat "$MODDIR/service.sh"