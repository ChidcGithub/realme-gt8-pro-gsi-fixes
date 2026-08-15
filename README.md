# realme GT 8 Pro — GSI Fix Toolkit

**Unofficial fix toolkit and field notes** for running the
[Evolution X Treble GSI](https://github.com/Doze-off/EvoX_treble) (Android 16, phh-based)
on the **realme GT 8 Pro (RMX5200, Snapdragon 8 Elite)**.

Restores carrier IMS (VoLTE / SMS / calling), fixes app crashes, unlocks the full 144 Hz
panel and smooths system animations — all while keeping the stock vendor stack untouched.

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
| Call audio | ⚠️ In progress (modem media plane, RTP = 0) |
| SMS — receive | ⚠️ In progress |
| 144 Hz display | ✅ Fixed (was locked to 60 Hz) |
| Camera → Recents stutter | ✅ Fixed |
| Google Camera | ✅ Works |
| Aperture / WeChat crashes | ✅ Fixed |
| WeChat risk-control self-kill | ✅ Fixed |
| Wi-Fi 6 / WPA3 (client) | ✅ Works out of the box |
| Wi-Fi hotspot WPA3 | ⚠️ Vendor hostapd limitation |
| Bluetooth A2DP audio | ⚠️ GSI audio-stack / vendor HAL mismatch |

---

## The headline fix: stock Qualcomm IMS on a GSI

On China Telecom (MCC/MNC 46011) this device routes **SMS and voice over IMS** — no IMS,
no texting, no calling. The GSI ships a phh-built `org.codeaurora.ims` (API 33, HIDL-era)
that cannot bind the API-36 AIDL `ImsRadio` exposed by the stock vendor partition
(no `indCb`, no SIP registration).

The fix ports the **stock `org.codeaurora.ims` (API 36)** into a Magisk module:

1. Extract the stock APK + shared libraries from `system_ext` (see build guide)
2. Binary-patch the dex in 5 verified spots to bypass Oplus-only framework calls
   (offsets + byte patches are documented and scripted in [`patches/dex`](patches/dex))
3. Provide the missing shared libraries — including a minimal stub jar and a
   rebuilt `qti-telephony-utils.jar` with classes recovered from the phh APK
4. Inject SELinux rules for `priv_app ↔ vendor IMS services` with
   `magiskpolicy --live` (module `sepolicy.rule` alone is too early)
5. Remove the phh-injected "PHH IMS" APN so the carrier IMS PDN can attach

Result: framework binds the stock IMS service automatically at boot, `MMTEL` reports
READY, calls connect (DIALING → ALERTING → ACTIVE).

The remaining mile is the **media plane**: calls connect but audio RTP stays at 0 in both
directions, and MT SMS still doesn't surface — both symptoms point at the modem's media
routing, which is the next investigation (see [JOURNEY](docs/JOURNEY.md)).

---

## Other fixes in this repo

| Fix | Root cause | Where |
|---|---|---|
| Aperture + WeChat crash | `/odm/framework/androidx.camera.extensions.impl.fake.jar` ships old Kotlin classes that pollute the classpath | [`scripts/fixfake.sh`](scripts/fixfake.sh) |
| WeChat risk-control self-kill | Unknown device model → WeChat calls `System.exit()` | [`scripts/spoof.sh`](scripts/spoof.sh) |
| 60 Hz lock on a 144 Hz panel | GSI defaults `peak/min_refresh_rate` to 60 | `settings put system peak_refresh_rate 144 && settings put system min_refresh_rate 120` |
| Camera → Recents stutter | GCam pins the display at 60 Hz; switching to Recents forces a 60 → 120/144 mode switch that collides with the animation | `min_refresh_rate = 120` |
| Sluggish animations | Renderer stuck on OpenGL by a leftover Oplus prop | `setprop debug.hwui.renderer skiavk` + restart SystemUI/launcher |
| CPU / GPU / I/O tuning | Vendor `perfd` re-applies its own CPU tunables after boot; safe extras live in the script | [`scripts/01-perf.sh`](scripts/01-perf.sh) |

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
├── patches/experiments/       # Patches tried, measured, and reverted
├── scripts/                   # Boot scripts (perf, spoof, camera jar fix)
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
adb push scripts/01-perf.sh scripts/spoof.sh scripts/fixfake.sh /data/adb/service.d/
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
