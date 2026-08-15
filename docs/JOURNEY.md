# The Journey

Field notes from two very long days of debugging a realme GT 8 Pro (RMX5200)
running a phh-based Android 16 GSI. Written so future me (or you) doesn't have
to re-derive any of this.

---

## Day 0 — A clean GSI, a broken phone

The plan was simple: unlock the bootloader, back up every partition (18 GB
`super.img` — always do this), flash a phh-based "ossi" GSI, keep the stock
vendor/odm/my_product partitions, root with Magisk 30.7, install TWRP 3.7.1.

It booted. Then the problem list started:

1. Aperture camera crashed instantly.
2. WeChat crashed instantly.
3. WeChat (after fixing the crash) killed itself — risk control.
4. **No SMS. No phone calls.** China Telecom routes both over IMS.
5. Bluetooth A2DP: pairs, plays silence.
6. System animations were "fine" — we thought. (Spoiler: the 144 Hz panel was
   running at 60 Hz the whole time.)

## Fix 1 — The camera crash was never about the camera

Aperture died with a Kotlin `NoSuchMethodError`. The stack pointed at
`androidx.camera.extensions.impl.*`, loaded from
`/odm/framework/androidx.camera.extensions.impl.fake.jar` — a vendor shim that
bundles a very old Kotlin stdlib copy. The GSI's classloader found the vendor's
classes first and everything downstream exploded. WeChat crashed for the same
reason (it uses CameraX for QR scanning).

Fix: bind-mount an empty jar over the shim at boot. One line, three crashes gone.

## Fix 2 — WeChat's risk control

With the crash fixed, WeChat launched... and called `System.exit()` a few
seconds later. Its risk-control module treats "unknown device model" as a
sandbox. The GSI's generic `ro.product.*` props were the trigger.

Fix: `resetprop` the model props to `RMX5200 / realme` at boot.

## The IMS saga — five layers deep

This consumed most of two days. Each fix revealed the next failure.

### Layer 1: the wrong dialect

The GSI bundles phh's `org.codeaurora.ims` — API 33, HIDL-era. The stock vendor
partition (untouched, from Android 16) exposes an **API-36 AIDL** `ImsRadio`.
The phh app binds, sends its HIDL-flavored calls, and gets nothing back:
`indCb null`, zero SIP registration. No SMS, no calls.

Conclusion: port the stock IMS app.

### Layer 2: extraction

The stock APK lives in `system_ext` (EROFS), not `system`. `super.img` was
unpacked with `lpunpack` (Rprop fork, Windows binaries), `system_ext_a.img`
loop-mounted on the phone (`/data/local/tmp`), and the APK + its library set
pulled out: `org.codeaurora.ims`, API 36, self-contained AIDL classes.

### Layer 3: manifest demands

The stock APK refuses to boot on a GSI unless:
- `persist.oplus.qspa.modem=enabled` (its `<overlay>` declaration) — solved with `system.prop`
- three shared libraries exist: `qti-telephony-hidl-wrapper`, `qti-telephony-utils`,
  `ims-ext-common` — shipped as framework jars + permission XMLs

### Layer 4: the class-shadowing trap

The stock `oplus-ims-ext.jar` (required as `ims-ext-common`) turns out to embed
**70+ `org.codeaurora.ims.*` classes and 74 `com.oplus.ims.*` classes** that
shadow the APK's own classes and reference framework APIs that don't exist on
the GSI. Replaced it with a 983-byte minimal jar that only keeps the library name.

`qti-telephony-utils.jar` went through ten iterations (`qcc.jar` → `qcc10.jar`):
classes recovered from the phh APK's dex, `org.codeaurora.telephony.utils`
(Registrant/RegistrantList/AsyncResult), `IImsCallSessionImplWrapper` from the
stock `ims-common.jar`, a handwritten `OplusNecManager` stub, a patched
`QtiCarrierConfigHelper` (`registerReceiver` needs `RECEIVER_NOT_EXPORTED` on
Android 16), dozens of synthetic inner classes, and three stub methods in
`QtiImsExtUtils` (`getIntArray`, `isGlassesFree3DVideoSupported`,
`isVisualizedVoiceSupported`). Those last three stubs were the difference
between "IMS app boots and registers" and "calls actually connect" — the app
crashed on every call-state update without them.

### Layer 5: binary patching the stock dex

The stock app calls Oplus-only framework classes in six places. Instead of
smali round-trips (apktool rebuilds of priv-app APKs are fragile), each call
site was patched **in place on the dex**, byte-verified, then the Adler-32
checksum recalculated. Every patch script in `patches/dex` follows this
verify → patch → checksum → rezip discipline.

| Offset | What it did | Patch |
|---|---|---|
| `0x4A15A` | `OplusFeatureConfigManager` gate in `ImsApp.onCreate` | `const-string v1, "ImsApp"` + `goto +30` |
| `0x4A1B0` | `sLogMgr` missing-class fetch | `sget-object DEFAULT` + `sput` + nops |
| `0x4A1CA` | `sRilInner` missing-class fetch | `sget-object DEFAULT` + `sput` + nops |
| `0x4A1E6` | `make()` on missing `OplusImsServiceControllerExt` | 22-byte nop |
| `0x6A5B0` | `isTablet` via missing `OplusFeatureHelper` | `const/4 v4, 0` + nops |
| `0x52F18` | `CallEncryption` extra read | see the encryption story below |

### Layer 6: SELinux

`priv_app` isn't allowed to talk to vendor IMS services on a stock policy.
`sepolicy.rule` in the module did nothing — Magisk applies it before vendor
policy types exist. The working approach: `post-fs-data.sh` runs
`magiskpolicy --live` after the full policy is loaded. Two days of "why is it
still denied" condensed into one comment.

### Layer 7: the APN

Once registration worked, SMS/calls still failed until we noticed phh had
injected a "PHH IMS" APN that grabbed the IMS PDN first. Deleting it let the
carrier's own IMS APN attach. (`content delete --uri content://telephony/carriers/restore`)

### The encryption detour — a real debugging story

Calls now initiated but died instantly with
`1502 = IMSA_VERBOSE_CALL_END_REASON_DIAL_FAILED_CS_RETRY_REQUIRED`. Packet
captures showed the modem sending INVITEs that the network ignored. Suspicion:
the carrier gateway rejects unencrypted offers, and the GSI framework never
sets the `CallEncryption` extra, so the app dialed with `isEncrypted=false`.

We patched `0x52F18` (`move-result v11` → `const/4 v11, 1`) and... calls
connected! Triumph! Until a verification dump showed the dexdump reading
`const/4 v11, 0`. We had written the **wrong instruction encoding**:
`12 0B` is `const/4 v0, 11`, not `const/4 v11, 1` (that's `12 B1`). The patch
had done nothing — calls connected because of the Layer 4 stubs, not encryption.

Corrected to `12 B1`, forced `isEncrypted=true`... and the call **hung at
DIALING**. So: `false` → connects (no audio), `true` → hangs. The encryption
flag was a red herring for connectivity either way. Reverted to the shipped
state (`12 0B`, effectively false) and moved on.

**Lesson:** binary patch, then verify the *semantics* of your bytes, not just
the presence of the bytes.

### Where it stands

- IMS registered, SMS send works, calls connect and hang up cleanly.
- **Call audio: RTP = 0 in both directions.** The media stack lives entirely in
  the vendor side (modem ↔ `ims_rtp_daemon` ↔ audio HAL); the app never touches
  RTP. The modem reports `isEncrypted=false` and the QTI audio HAL never gets a
  voice session. Everything points at the modem's media SA (SRTP/IPsec) not
  being established — next step is Qualcomm diag capture.
- **SMS receive**: MT SMS never surfaces — likely the same modem routing.

## Wi-Fi

Wi-Fi 6 (11ax, 864 Mbps) and WPA3-SAE client both work out of the box.
Hotspot WPA3 is missing because the vendor hostapd never reports AP
capabilities (`cmd wifi get-softap-supported-features` returns empty), so the
framework hides the option. WPA2 + strong passphrase is the workaround; lowest
priority.

## Display — the 60 Hz conspiracy

For weeks the phone felt "okay but not flagship-smooth". Diagnostics showed
why: the GSI defaults `peak_refresh_rate` and `min_refresh_rate` to **60** on a
**144 Hz** panel. One settings write unlocked 144/120. GPU load at 144 Hz:
10%. The hardware was never the problem.

## The GCam → Recents stutter

Even at 144 Hz, opening Google Camera and switching to Recents stuttered.
`dumpsys display` while GCam was open showed the smoking gun: **GCam pins the
whole display to 60 Hz** (a common camera power/anti-flicker behavior), and the
moment you hit Recents the display has to switch 60 → 120/144 — a MIPI
re-configuration that collides with the Recents animation. CPU cores were all
parked at 883–998 MHz (camera preview runs on the ISP, not the CPU), so the
animation's sudden CPU demand added insult to injury.

Fix: `min_refresh_rate = 120` — the camera can't drop the panel to 60 anymore,
no mode switch, no stutter. Cost: a bit more screen-on power. Worth it.

## Renderer

A leftover Oplus prop was keeping Skia on OpenGL. `debug.hwui.renderer=skiavk`
+ restarting SystemUI/launcher moved everything to Vulkan. (SystemUI/launcher
are long-lived processes — the prop only applies to new ones.)

## What I'd tell someone starting this today

1. **Back up the full `super.img` first.** Every fix here came back to it.
2. On a GSI, the vendor partition is law: read its HAL versions before trusting
   the bundled apps.
3. Binary-patch with byte verification + checksum repair beats apktool rebuilds
   for priv-app APKs.
4. When a "fix" appears to work, verify *which* fix actually worked before
   celebrating. (See: the encryption detour.)
5. Two days in, a phone that texts, calls, and scrolls at 144 Hz beats the
   stock ROM — and the remaining two bugs have a common suspect: the modem.
