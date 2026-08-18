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

## Protocol (reverse-engineered from stock `com.oppo.ctautoregist`)

- Destination: `10659401`
- Payload: `[0x04] [0x03] [len] [0x00]` + UTF-8 XML
  (`0x04` = IMS-SMS protocol version 4, matching the stock app's
  `PROTOCOL_VERSION_IMS_SMS = 4`)

Stock XML layout (`p/l.smali` of the carved CTAutoRegist APK):

```
<a><b>{A()}<c>{IMSI}<d>{other-slot IMSI or 000000000000000}<e>{p/l.c()=LTE IMSI}<f>{Build.DISPLAY}<g>{p/p.N()="01" single-SIM}</a>
```

- `<b>` = `"RLM-" + Build.MODEL` when `Build.BRAND == "realme"` (else `"OB-..."`)
- `<e>` = LTE IMSI (`p/p.R(slot)[1]`, "getsimLteImsi") — same as `<c>` on modern single-profile CT cards
- `<f>` = **stock** `Build.DISPLAY` — GSI values (e.g. `BP4A.251205.006`) look nothing like an
  OPPO build id; this repo hardcodes the real stock value `RMX5200_16.0.9.402(CN01)`
  (source: `backup/userdata-*/buildprop.txt`)
- `<g>` = `"01"` for a single-SIM device (`p/p.N()`)

**ACK protocol** (stock `OplusInboundSmsHandlerImpl.isSmsFromCTAutoRegServer` in
oplus telephony-common): CT replies from `10659401` with a data SMS whose user data
starts `[0x01|0x02][0x03]` = CDMA reg, `[0x03][0x03]` = **IMS-SMS registration ACK**
(stock broadcasts `android.intent.action.RECEIVE_SMS_REG_ACK` when it sees it),
`[0x09][0x03]` = satellite reg. If registration was accepted you should eventually
see this ACK arrive as a normal MT SMS.

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

- **Critical (2026-08-18): the IMSI fields were silently EMPTY in all earlier
  registrations.** `TelephonyManager.getSubscriberId()` throws `SecurityException`
  on Android 11+ unless the app holds `READ_PRIVILEGED_PHONE_STATE` *or* has the
  `READ_DEVICE_IDENTIFIERS` appop. The receiver's `catch` swallowed the exception
  and sent `<c></c>` — CT can't register an empty IMSI. Grant it once:

  ```bash
  adb shell su -c 'pm grant com.chidc.ctreg android.permission.READ_PHONE_STATE'
  adb shell su -c 'pm grant com.chidc.ctreg android.permission.SEND_SMS'
  adb shell su -c 'appops set com.chidc.ctreg READ_DEVICE_IDENTIFIERS allow'
  ```

  (Watch for `TelephonyPermissions: reportAccessDeniedToReadIdentifiers` in logcat —
  if it appears, the XML went out empty again.)

- Verification status of the registration itself: MO SMS is accepted by the CT
  SMSC end-to-end (recipient receives), MT calls work, but MT SMS still never
  arrives — not even as a QMI unsol (`ImsRadioIndicationAidl.onIncomingSms()`
  never fires). The remaining suspect is the modem-side SIP REGISTER missing the
  `+g.3gpp.smsip` feature tag under the GSI, or CT-side activation lag. See
  JOURNEY.md "MT SMS — session 3" for the full evidence chain.
- If MT SMS still doesn't arrive after registration, check the QCRIL legacy
  UNSOL path (`Failed to send RIL_UNSOL_*` in the radio log) — that's the
  channel `UNSOL_NEW_SMS` travels over.
