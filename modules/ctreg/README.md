# ctreg — China Telecom SMS-over-IMS registration sender

Tiny priv-app that performs the China Telecom **"CT IMS SMS auto-registration"**:
it sends one binary data SMS to `10659401` over IMS, which activates MT SMS delivery
to the device on CT's IMS network.

## Background

China Telecom's SMSC only routes MT (incoming) SMS over IMS to devices that
completed this registration. On stock realme/OPPO firmware the job is done by
`com.oppo.ctautoregist` (in `/product/priv-app/CTAutoRegist`), triggered by
TeleService's `CTAutoRegisterChecker` broadcast 120 s after network attach.

GSIs have neither component. This app replaces both.

## Protocol

- Destination: `10659401`
- Payload: `[0x04] [0x03] [len] [0x00]` + UTF-8 XML
  `<a><b>RLM-CN<c><sim-operator><d>000000000000000<e><sim-operator><f><build-display><g></a>`
  (`0x04` = IMS-SMS protocol version 4, matching the stock app's
  `PROTOCOL_VERSION_IMS_SMS = 4`)

## Build / install

```bash
# with apktool + zipalign + apksigner:
apktool b ctreg -o ctreg.apk
zipalign -f 4 ctreg.apk ctreg_z.apk
apksigner sign --ks debug.keystore --out CTReg.apk ctreg_z.apk

# magisk module (this folder):
adb push ctreg.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/ctreg.zip'
adb reboot

# grant runtime permissions once (privapp XML is ignored by some GSIs):
adb shell su -c 'pm grant com.chidc.ctreg android.permission.READ_PHONE_STATE'
adb shell su -c 'pm grant com.chidc.ctreg android.permission.SEND_SMS'

# trigger:
adb shell su -c 'am broadcast -n com.chidc.ctreg/.SendReceiver -a com.chidc.ctreg.SEND'
```

Success looks like (logcat tag `CTReg`):

```
CTReg: REGISTER SMS SENT
QImsService: ImsSmsImpl : sendSms:: ... 
QImsService: onSendSmsResult:: ... mSendSmsResult = 1
```

`mSendSmsResult = 1` means the SMSC accepted the message over IMS.

## Notes

- The IMSI fields are left empty (or set to the sim operator): reading the IMSI
  needs `READ_PRIVILEGED_PHONE_STATE`, whose privapp grant is ignored by some
  GSI builds. The stock app sends the same message structure; device telemetry
  fields may be optional.
- If MT SMS still doesn't arrive after registration, check the QCRIL legacy
  UNSOL path (`Failed to send RIL_UNSOL_*` in the radio log) — that's the
  channel `UNSOL_NEW_SMS` travels over.
