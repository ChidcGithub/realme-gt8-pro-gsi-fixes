# realme GT 8 Pro — GSI Fix Toolkit

**Unofficial fix toolkit and field notes** for running the
[Evolution X Treble GSI](https://github.com/Doze-off/EvoX_treble) (Android 16, phh-based)
on the **realme GT 8 Pro (RMX5200, Snapdragon 8 Elite)**.

Restores carrier IMS (VoLTE / SMS / calling), fixes app crashes, unlocks the full 144 Hz
panel, smooths system animations, and enables under-display fingerprint — all while keeping
the stock vendor stack untouched.

## Verified on

Developed and verified against the Evolution X Treble GSI —
release [**2026-07-20**](https://github.com/Doze-off/EvoX_treble/releases/tag/2026-07-20)
(Android 16), on a realme GT 8 Pro (RMX5200) with stock vendor/odm/my_product
partitions, Magisk 30.7 and TWRP 3.7.1.

> This project started as a personal repair log. It is published so other RMX5200 owners
> (or GSI tinkerers on similar Qualcomm devices) can reproduce the fixes.
> **No proprietary binaries are redistributed here** — everything is rebuilt from
> *your own* firmware backup. See [BUILD-IMS-MODULE](docs/BUILD-IMS-MODULE.md).

---

## Status

| Feature | Status |
|---|---|
| IMS registration (VoLTE) | ✅ Fixed |
| SMS — send | ✅ Fixed |
| Calls — dial / connect / hang up | ✅ Fixed |
| Call audio (two-way) | ✅ Fixed |
| SMS — receive | ⚠️ Under investigation — CT SMSC requires the Oplus "CT IMS SMS auto-registration" flow (see JOURNEY) |
| Under-display fingerprint (UDFPS) | ✅ Fixed |
| Auto-brightness | ✅ Fixed (sensor switch + brightness curve + display config) |
| 144 Hz display | ✅ Fixed (was locked to 60 Hz) |
| Camera → Recents stutter | ✅ Fixed |
| Google Camera | ✅ Works |
| Aperture / WeChat crashes | ✅ Fixed |
| WeChat risk-control self-kill | ✅ Fixed |
| Lockscreen fingerprint icon | ✅ Fixed (UdfpsIcons.apk + udfps_icon=1) |
| Wi-Fi 6 / WPA3 (client) | ✅ Works out of the box |
| Wi-Fi hotspot WPA3 | ⚠️ Vendor hostapd limitation |
| Bluetooth A2DP audio | ✅ Fixed (/sysbta → /default in APEX lib) |

---

## The headline fix: stock Qualcomm IMS on a GSI

On China Telecom (MCC/MNC 46011) this device routes **SMS and voice over IMS** — no IMS,
no texting, no calling. The GSI ships a phh-built `org.codeaurora.ims` (API 33, HIDL-era)
that cannot bind the API-36 AIDL `ImsRadio` exposed by the stock vendor partition
(no `indCb`, no SIP registration).

The fix ports the **stock `org.codeaurora.ims` (API 36)** into a Magisk module:

1. Extract the stock APK + shared libraries from `system_ext` (see build guide)
2. Binary-patch the dex in 6 verified spots to bypass Oplus-only framework calls
   (offsets + byte patches are documented and scripted in [`patches/dex`](patches/dex))
3. Provide the missing shared libraries — including a minimal stub jar and a
   rebuilt `qti-telephony-utils.jar` with classes recovered from the phh APK
4. Inject SELinux rules for `priv_app ↔ vendor IMS services` with
   `magiskpolicy --live` (module `sepolicy.rule` alone is too early)
5. Remove the phh-injected "PHH IMS" APN so the carrier IMS PDN can attach

Result: framework binds the stock IMS service automatically at boot, `MMTEL` reports
READY, calls connect (DIALING → ALERTING → ACTIVE).

The last mile was **call audio**: calls connected but RTP stayed at 0 — the
network's media packets were rejected by the modem with ICMP port-unreachable,
and the vendor audio HAL never started a voice session. Root cause: the Android 16
audio framework expects HAL-owned call state machines (`CallState::DEFAULT` +
`setTelecomConfig`), but the GSI's audiopolicy never sends `setTelecomConfig` and
the vendor HAL only advances on explicit ACTIVE states. Fixed by rewriting one
branch in `libaudiocorehal.qti.so` (see [`patches/hal`](patches/hal)) so Default
updates start the voice session — two-way audio confirmed. The only remaining IMS
item is **MT SMS receive**.

### Bluetooth A2DP — silence across three processes

A separate bug easy to mistake for the call-audio one: earbuds pair, A2DP
connects, but media audio is silent. Root cause: the GSI's
`libbluetooth_jni.so` (inside the `com.android.bt` APEX) hard-codes the
provider-factory suffix `"/sysbta"`, so the BT audio provider starts in
**audioserver**. The vendor `audio_sw.so` connects to `"/default"`, in
**audiohalservice.qti**. `BluetoothAudioSessionInstance` stores its
observers in a *per-process* static map — the provider's
`OnSessionStarted()` fires in audioserver (no observers there), and the
observers in audiohalservice.qti are never notified → `IsSessionReady()`
returns false forever → A2DP sink gets no PCM frames.

Fix: patch the APEX's `libbluetooth_jni.so` to use `"/default"` instead of
`"/sysbta"` (`patches/bt` — one 8-byte string rewrite with one byte of
collateral truncation of an adjacent log-only error string). After patching,
provider + session live in the same process, `IsSessionReady()` flips true,
audio flows. Three props force the software encoding path as a guardrail
(the offload widgets aren't available on the GSI anyway).

---

## Other fixes in this repo

| Fix | Root cause | Where |
|---|---|---|
| Under-display fingerprint (UDFPS) | HIDL path missing; framework reported sensor as POWER_BUTTON | [`modules/oplusfix/`](modules/oplusfix/) — framework.jar smali patch (sensorType=3, location, HAL flags) |
| Auto-brightness | Vendor sensor configured as module_ignore; missing display config + brightness curve | [`modules/oplusfix/`](modules/oplusfix/) — services.jar patch + display_id XML + sensor_config.json |
| Lockscreen fingerprint icon | EvoX default UDFPS icon renders as white rectangle | `settings put system udfps_icon 1` + UdfpsIcons.apk from EvoX ROM |
| Aperture + WeChat crash | `/odm/framework/androidx.camera.extensions.impl.fake.jar` ships old Kotlin classes that pollute the classpath | [`scripts/fixfake.sh`](scripts/fixfake.sh) |
| WeChat risk-control self-kill | Unknown device model → WeChat calls `System.exit()` | [`scripts/spoof.sh`](scripts/spoof.sh) |
| 60 Hz lock on a 144 Hz panel | GSI defaults `peak/min_refresh_rate` to 60 | `settings put system peak_refresh_rate 144 && settings put system min_refresh_rate 120` |
| Camera → Recents stutter | GCam pins the display at 60 Hz; switching to Recents forces a 60 → 120/144 mode switch | `min_refresh_rate = 120` |
| Calls connect but no audio | GSI framework sends `CallState::DEFAULT` and never `setTelecomConfig` | [`patches/hal`](patches/hal) + [`modules/audiopatch`](modules/audiopatch) |
| Bluetooth A2DP — pairs, plays silence | BT stack connects to `/sysbta` (audioserver); vendor audio HAL connects to `/default` (audiohalservice.qti) — per-process session map prevents `OnSessionStarted()` from ever flagging the observers | [`patches/bt`](patches/bt) + [`modules/bta2dp`](modules/bta2dp) |
| Sluggish animations | Renderer stuck on OpenGL by a leftover Oplus prop | `setprop debug.hwui.renderer skiavk` + restart SystemUI/launcher |
| CPU / GPU / I/O tuning | Vendor `perfd` re-applies its own CPU tunables after boot | [`scripts/01-perf.sh`](scripts/01-perf.sh) |
| Auto performance profiles | Need automatic balance/gaming/battery switching based on foreground app | [`scripts/02-auto-profile.sh`](scripts/02-auto-profile.sh) |

---

## Repository layout

```
├── modules/stockims/          # Magisk module skeleton (drop in your own binaries)
│   ├── system/system_ext/     #   framework jars, permissions XMLs, priv-app placeholder
│   ├── post-fs-data.sh        #   live SELinux injection
│   ├── sepolicy.rule          #   best-effort early rules (kept for reference)
│   └── system.prop            #   persist.oplus.qspa.modem=enabled
├── patches/dex/               # Verified binary patch scripts for the stock ims.apk
│   ├── bindexpatch3.ps1       #   0x4A15A  bypass OplusFeatureConfigManager
│   ├── finalpatch2.ps1        #   0x4A1B0/CA/E6  sLogMgr, sRilInner, make() nop-out
│   ├── patchtablet.ps1        #   0x6A5B0  force isTablet = false
│   └── encpatch2.ps1          #   0x52F18  CallEncryption experiment (shipped state)
├── patches/hal/               # Verified binary patch for the vendor audio HAL
│   └── patch_audio_hal.py     #   one branch: Default call state -> activate voice session
├── patches/bt/                # Verified binary patch for the Bluetooth APEX
│   └── patch_libbluetooth_jni.py  # one string: /sysbta -> /default in BT stack
├── patches/experiments/       # Patches tried, measured, and reverted
├── modules/audiopatch/        # Magisk module skeleton for the audio HAL fix
├── modules/bta2dp/            # Magisk module skeleton for the BT A2DP fix
├── modules/ctreg/             # CT SMS-over-IMS registration sender (protocol v4)
├── scripts/                   # Boot scripts (perf, spoof, camera jar fix, auto-profile)
│   ├── 01-perf.sh             #   WALT + GPU + IO + VM tuning (balance/gaming/battery)
│   ├── 02-auto-profile.sh     #   Foreground-app-aware auto profile switching
│   ├── fixfake.sh             #   Bind-mount empty jar over vendor camera shim
│   └── spoof.sh               #   Spoof device model for WeChat
├── docs/
│   ├── JOURNEY.md             # The full exploration story (English)
│   ├── BUILD-IMS-MODULE.md    # Reproducible build guide
│   └── progress-zh.md         # Original Chinese field notes (personal info redacted)
└── LICENSE                    # MIT (original code only)
```

---

## Quick start (the parts that don't need a build)

```bash
# Unlock the panel (persists across reboots)
adb shell settings put system peak_refresh_rate 144
adb shell settings put system min_refresh_rate 120

# Vulkan renderer for SystemUI / launcher
adb shell setprop debug.hwui.renderer skiavk   # or via Developer options
adb shell su -c 'killall com.android.systemui'

# Install the boot scripts (Magisk)
adb push scripts/01-perf.sh scripts/02-auto-profile.sh scripts/spoof.sh scripts/fixfake.sh /data/adb/service.d/
```

The IMS module requires a build step — see [docs/BUILD-IMS-MODULE.md](docs/BUILD-IMS-MODULE.md).

---

## Disclaimer

- **Unofficial.** Not affiliated with, endorsed by, or approved by realme, OPLUS,
  Qualcomm, or Google. All trademarks belong to their owners.
- Unlocking the bootloader and rooting **voids your warranty**; flashing GSIs carries
  a real bricking risk. You are responsible for your own device.
- Proprietary binaries extracted from stock firmware are **for personal use on your own
  device only** and are deliberately **not redistributed** in this repository.
- Original code in this repo is MIT-licensed; everything else follows its upstream license.

## Credits

- **[Doze-off / EvoX_treble](https://github.com/Doze-off/EvoX_treble)** — the Evolution X
  Treble GSI project and its author, for the excellent base system this entire toolkit was
  built on and verified against (release 2026-07-20).
- **DeepSeek** — the AI pair-programming partner that co-reverse-engineered the IMS stack,
  designed the dex patches and debugged most of the fixes documented here.

## License

[MIT](LICENSE)
