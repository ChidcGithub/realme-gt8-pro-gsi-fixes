#!/system/bin/sh
# Live SELinux policy injection for stock IMS app (priv_app domain)
# Vendor policy types don't exist when magisk applies sepolicy.rule,
# so apply them here after the full policy is loaded.
MP=/data/adb/magisk/magiskpolicy
[ -f "$MP" ] || MP="$(magisk --path)/.magisk/busybox/magiskpolicy"
[ -f "$MP" ] || exit 0

$MP --live \
  "allow priv_app vendor_hal_telephony_service2 service_manager find" \
  "allow priv_app vendor_hal_telephony_service2 binder call" \
  "allow priv_app vendor_hal_telephony_service2 binder transfer" \
  "allow priv_app hal_radio_service service_manager find" \
  "allow priv_app hal_radio_service binder call" \
  "allow priv_app hal_radio_service binder transfer" \
  "allow priv_app vendor_aidl_imsfactory_service service_manager find" \
  "allow priv_app vendor_aidl_imsfactory_service binder call" \
  "allow priv_app vendor_aidl_imsfactory_service binder transfer" \
  "allow priv_app vendor_hal_imsrtp_service service_manager find" \
  "allow priv_app vendor_hal_imsrtp_service binder call" \
  "allow priv_app vendor_hal_imsrtp_service binder transfer" \
  "allow priv_app vendor_hal_imsdc_service service_manager find" \
  "allow priv_app vendor_hal_imsdc_service binder call" \
  "allow priv_app vendor_hal_imsdc_service binder transfer" \
  "allow priv_app vendor_aidl_rcsservice service_manager find" \
  "allow priv_app vendor_aidl_rcsservice binder call" \
  "allow priv_app vendor_aidl_rcsservice binder transfer" \
  "allow rild priv_app binder call" \
  "allow rild priv_app binder transfer" \
  "allow vendor_ims_service priv_app binder call" \
  "allow vendor_ims_service priv_app binder transfer" \
  "allow vendor_ims_dcservice priv_app binder call" \
  "allow vendor_ims_dcservice priv_app binder transfer" \
  "allow vendor_hal_imsrtp priv_app binder call" \
  "allow vendor_hal_imsrtp priv_app binder transfer" \
  2>/dev/null
