#!/system/bin/sh
# Bind-mount the patched libbluetooth_jni.so over the APEX copy.
# The APEX is mounted by the time post-fs-data runs; the BT stack (bluetooth
# service) starts later from zygote, so the override is in place first.
MODDIR=${0%/*}

# SELinux label must match the original APEX file context.
chcon u:object_r:system_lib_file:s0 "$MODDIR/system/lib64/libbluetooth_jni.so"

mount -o bind "$MODDIR/system/lib64/libbluetooth_jni.so" \
    /apex/com.android.bt/lib64/libbluetooth_jni.so

echo "bta2dp mount rc=$?"
