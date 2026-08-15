#!/system/bin/sh
# fixfake.sh — Fix Aperture/WeChat crashes caused by a vendor shim jar
# that bundles ancient Kotlin classes (classloader pollution).
# Runs at boot via /data/adb/service.d/ (or post-fs-data.d before Android starts).
#
# An empty jar (scripts/empty.jar, ~22 bytes, valid zip) is bind-mounted over
# the vendor shim. Everything that references the CameraX extensions API keeps
# working: the framework falls back to no-op extensions.

EMPTY_JAR=/data/adb/empty.jar
FAKE_JAR=/odm/framework/androidx.camera.extensions.impl.fake.jar

[ -f "$EMPTY_JAR" ] && [ -f "$FAKE_JAR" ] && mount -o bind "$EMPTY_JAR" "$FAKE_JAR"
