# The Journey

Field notes from two very long days of debugging a realme GT 8 Pro (RMX5200)
running a phh-based Android 16 GSI. Written so future me (or you) doesn't have
to re-derive any of this.

---

## Day 0 — A clean GSI, a broken phone

The plan was simple: unlock the bootloader, back up every partition (18 GB
`super.img` — always do this), flash the
[Evolution X Treble GSI](https://github.com/Doze-off/EvoX_treble) (phh-based,
release 2026-07-20), keep the stock vendor/odm/my_product partitions, root
with Magisk 30.7, install TWRP 3.7.1.

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

- IMS registered, SMS send works, calls connect and hang up cleanly,
  **two-way call audio works** (fixed via the audio HAL patch below).
- **SMS receive**: MT SMS never surfaces — the modem never delivers an
  incoming SMS to the app. Under investigation.

## The audio saga — chasing zero RTP

Calls connected, but there was no sound. Diagnostics, in order:

1. **Modem counters**: `QnsCallStatusTracker` showed `numRtpPacketsTransmitted=0`
   and `numRtpPacketsReceived=0` for the whole call.
2. **The smoking gun (tcpdump)**: during a call, the network sent media UDP
   packets to the port the phone advertised in SDP — and the modem answered
   **ICMP6 port unreachable**. The network was sending audio; the modem's
   media plane never bound its port.
3. **Both directions**: MO and MT calls behaved identically — not an
   app-dial-parameter issue.
4. **Audio HAL**: `AHAL_Telephony_QTI` logged `updateCalls CallState: Default
   cannot be handled in state IN_ACTIVE` and never opened a voice session.

Root cause: Android 16 audio frameworks moved to **HAL-owned call state
machines** — the framework sends `CallState::DEFAULT` and expects the HAL to
advance its own state from `setTelecomConfig` events. The GSI's audiopolicy
**never sends `setTelecomConfig`**, while the vendor QTI HAL only advances on
explicit ACTIVE states. Deadlock: Default states → "cannot be handled" →
voice session never starts → the modem's media engine (which waits for the
audio glink) never comes up → RTP rejected.

Fix: reverse-engineered the HAL binary (`libaudiocorehal.qti.so`, capstone +
pyelftools), found the `updateCalls` state loop, and rewrote **one branch**
(`b.ne` from the log-and-skip path to the activation path) so Default updates
start the voice session. Installed via a Magisk module. Two-way audio works.

**Lesson:** when two Android components disagree on who owns a state machine,
you don't need to fix both — find the smallest place where the ownerless
event can be routed to the state machine that actually runs.

## The Bluetooth A2DP saga — chasing silence across three processes

Bluetooth earbuds paired fine and A2DP connected, but the "audio routing"
was totally silent — no media audio coming through. Diagnostics:

1. **`dumpsys media.audio_flinger`**: A2DP output thread shown as
   `Standby: yes`, samples written = 0, no active tracks despite AVRC
   PLAYING and the BT profile reporting connected.
2. **The AIDL provider factory list**: `service list` showed both
   `IBluetoothAudioProviderFactory/sysbta` (registered by the phh sysbta
   service in audioserver) and `IBluetoothAudioProviderFactory/default`
   (registered by the vendor QTI audio HAL in audiohalservice.qti).
3. **`audio_sw.so` symbol scan**: the vendor `BluetoothAudioPortAidl::start()`
   calls `BluetoothAudioSessionInstance::GetSessionInstance()` then
   `IsSessionReady()` — was returning **false**.
4. **AOSP source confirmed the trap**: `BluetoothAudioSessionInstance` uses
   a **per-process static `sessions_map_`**. `GetSessionInstance()` returns
   the instance in the *calling* process. When the BT stack calls
   `openProvider()` on `/sysbta`, the provider starts in **audioserver**.
   When the provider's session is ready, it runs
   `BluetoothAudioSessionReport::OnSessionStarted()` *in its own process*
   — the instance found there has **no observers** (nobody in audioserver
   registered any). The observers are in **audiohalservice.qti**, where
   `audio_sw.so` registered on the instance keyed to `/default`. Wrong
   session instance, never notified → `IsSessionReady()` stuck at false.

Root cause: the GSI's BT stack (the `libbluetooth_jni.so` inside the
`com.android.bt` APEX) hard-codes the service-name suffix `"/sysbta"`:

```cpp
static inline const std::string kDefaultAudioProviderFactoryInterface =
    IBluetoothAudioProviderFactory::descriptor + "/sysbta";
```

So the provider and the session client live in different processes — the
per-process notification can never bridge them.

### Two dead ends

1. **Round 1 — fasten the AHAL to `/sysbta`**: patched the vendor session
   libraries (`libbluetooth_audio_session_aidl.so` and
   `libbluetooth_audio_session_aidl_qti.so`) to connect to `/sysbta`
   instead of `/default`. **No effect.** Even with both sides pointing
   at the same service name, provider and session client still run in
   different processes (audioserver vs audiohalservice.qti); the
   per-process static map stays partitioned. `IsSessionReady()` doesn't
   care about service name — it cares about which *process* the
   `OnSessionStarted()` call fires in.

2. **Round 2 — `libbluetooth_audio_session_aidl_system.so` on `/system/lib64/`**:
   patched the system-side session lib to switch to `/default`. **No effect**
   either, because the BT stack doesn't load that library from the system
   partition: it runs entirely inside the APEX, pulling libraries from
   `/apex/com.android.bt/lib64/`. Nothing outside the APEX is hittable.

### The working patch — one string in the real binary

The actual fix was patched in the APEX-*resident* `libbluetooth_jni.so`.
The string `"/sysbta"` lives in `.rodata` at file offset `0xA680F`. Replace
it with `"/default"` and the BT stack connects to the vendor's provider
factory — so the provider starts in `audiohalservice.qti`, **same process**
as `audio_sw.so`, and `OnSessionStarted()` finds the instance with the
observers → `ReportSessionStatus()` fires → `IsSessionReady()` becomes
true → A2DP sink receives PCM frames → audio.

One byte of overlap: `"/sysbta"` (7 + NUL = 8 bytes) is shorter than
`"/default"` (8 + NUL = 9 bytes). The next rodata byte was the 'B' of the
log-only error string `"BluetoothAudio AIDL implementation does not
exist"` — we overwrote it with NUL to be the new terminator. That error
string is truncated by one leading character; harmless, it only prints if
the provider factory is missing (which it isn't anymore after the patch).

Installed via a Magisk module that `post-fs-data` bind-mounts the patched
lib over `/apex/com.android.bt/lib64/libbluetooth_jni.so` (on Phh APEX
mounts the BT stack starts via zygote, well after `post-fs-data`). The
`audioout_*` mixer thread flipped from `Standby: yes` to
`Standby: no, Sample rate: 44100 Hz, Output devices: 0x80
(AUDIO_DEVICE_OUT_BLUETOOTH_A2DP)` — sound out of the earbuds confirmed.

### Forced software encoding

A secondary guardrail: this device's offload widgets aren't wired up on a
GSI, so even with the session ready, A2DP would still be silent if the
offload path were selected. Three props force the **software encoding**
path instead (already applied by the `oplusfix` module's
`post-fs-data.sh` via `resetprop_phh`):

```bash
ro.bluetooth.a2dp_offload.supported=false
persist.bluetooth.enable_bt_offload=false
persist.sys.phh.disable_a2dp_offload=true
```

**Lesson:** when two Android modules share state through a *static* map
keyed by name, "everyone uses the same name" isn't enough — they also
have to be in the same process. And on a phh GSI, "the BT stack" is a
separate APEX; you can't patch it from outside the APEX.

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

## Fingerprint — five layers deep

The under-display fingerprint sensor (UDFPS) appeared to work in settings but
couldn't actually authenticate. The root cause ran five layers deep.

### Layer 1: sensor type misreporting

The vendor fingerprint HAL uses a **new AIDL path**, but the framework's
`FingerprintSensorPropertiesInternal` constructor was still checking the
**old HIDL path** — which doesn't exist on this device. Without the HIDL
path, the framework fell back to reporting the sensor as
`POWER_BUTTON` (type 1) instead of `UNDER_DISPLAY_ULTRASONIC` (type 3).

### Layer 2: wrong sensor location

Even with the correct type, the default sensor location coordinates were
wrong — the framework had no idea where the sensor actually sat on the
display. The stock Oplus config specifies `Rect(570, 2202, 870, 2502)`,
a 300×300 px region at roughly 75% of the display height.

### Layer 3: HAL control flags

Two boolean flags — `halControlsIllumination` and `halHandlesDisplayTouches`
— were both `false` in the GSI's fallback path. On this device, the vendor
HAL **does** manage the illumination LED and the touch overlay. Without these
flags set, the framework tried to handle illumination itself, causing the
fingerprint icon to appear as a white rectangle on the lock screen.

### Layer 4: the odex problem

The framework.jar binary was modified via apktool (smali), but framework
code lives in a pre-compiled `.odex` file. The system loads the `.odex`
first; the `.jar` is only a fallback. So patching the `.jar` without
regenerating the `.odex` did nothing.

Fix: run `dex2oat` on-device to rebuild `services.odex` from the patched
`.jar`, then bind-mount both.

### Layer 5: framework resource loss

When the `.jar` was rebuilt with apktool, it lost embedded resources
(`res/debian.mime.types`, etc.) that other parts of the system depend on.
This caused `WeChat` and `QQ` media storage to crash every 2 seconds in a
NPE loop.

Fix: rebuild the `.jar` by only replacing the `.dex` inside the original
archive (zip surgery), preserving all original resources.

### The lockscreen icon

After fingerprint worked, a white rectangle remained on the lock screen
over the fingerprint sensor area. Investigation revealed:

- `com.android.systemui.gsi.overlay` was disabled (only changes a dimen,
  not relevant to the issue)
- `config_udfpsColor = 0xffffffff` (white) — the HBM illumination color
- The real culprit: `device_entry_icon_view` FrameLayout background
  rendering as solid white when `udfps_icon=0` (stock icon mode)

Fix: `settings put system udfps_icon 1` — enables the
`org.evolution.udfps.icons` package (pre-installed from the EvoX ROM) which
provides a proper fingerprint icon drawable that replaces the white rectangle.

---

## Auto-brightness — a three-part puzzle

The auto-brightness system had three independent problems, each of which
would prevent it from working.

### Part 1: the disabled flag

`framework-res.apk` shipped `config_automatic_brightness_available=false`.
The `AutomaticBrightnessStrategy` checks this flag and immediately bails
out: `mIsAutoBrightnessEnabled` stays `false`, the brightness controller
never starts.

Fix: patch `DisplayDeviceConfig.isAutoBrightnessAvailable()` in
`services.jar` to always return `true`.

### Part 2: the missing display config

The vendor's display configuration lives in XML files named by display ID.
The actual display ID on this device (`4630947180293509523`) had no matching
config file — the system fell back to defaults that didn't match the panel's
brightness characteristics.

Fix: create a matching `display_id_4630947180293509523.xml` with the correct
`screenBrightnessMap` and `luxToBrightnessMapping` from the vendor's original
config, adapted for the `high_pwm_rgb` sensor.

### Part 3: the wrong sensor

The Oplus vendor configured `android.sensor.light` as `module_ignore`
(because ColorOS uses its own sensor stack). The GSI's ABC tried to use
`light_rear` (tcs3449), but the AutomaticBrightnessStrategy kept falling
back to a manual path.

Fix: hardcode the sensor name in `SensorData.smali` to
`qti.sensor.high_pwm_rgb` — the front-facing ambient light sensor that
actually reflects the user's environment.

### The brightness curve

The original `luxToBrightnessMapping` used **nits** (2.0, 4.5, 9.0, ...)
as the `<second>` values, but the framework expects **0–1 brightness
scale**. The result was wildly dim auto-brightness.

Fix: remap to a proper 0–1 curve: `0.0→0.01, 10→0.05, 50→0.15,
100→0.25, 200→0.38, 400→0.52, 800→0.65, 1500→0.78, 3000→0.88,
5000→0.94, 8000→0.97, 12000→1.00`. Verified: 1030 lux → 69% brightness.

---

## Performance — three profiles, automatic switching

### The WALT tuning

The stock `perfd` daemon re-applies its own CPU tunables after boot,
overriding any manual settings. The fix runs `01-perf.sh` from
`/data/adb/service.d/` at boot:

- **WALT scheduler**: `up_rate_limit_us=0` (instant ramp-up),
  `down_rate_limit_us=20000/25000` (gradual ramp-down)
- **CPU frequencies**: `hispeed_load=60%`, `hispeed_freq=1.9G/2.88G`
  per cluster
- **GPU**: `min_clock=342MHz`, `idle_timer=800`
- **I/O readahead**: 1024 KB (balance) / 2048 KB (perf)

### Three profiles

| Profile | CPU min | GPU min | Use case |
|---|---|---|---|
| `balance` | 998 MHz / 1.27 GHz | 342 MHz | Daily use |
| `gaming` | 1.27 GHz / 1.9 GHz | 520 MHz | Heavy games |
| `battery` | 300 MHz / 300 MHz | 152 MHz | Screen off |

### Automatic switching

`02-auto-profile.sh` runs as a daemon, polling every 3 seconds:

- **Screen off** → `battery` profile
- **Game in foreground** (checked against a list of 30+ package names) →
  `gaming` profile
- **Anything else** → `balance` profile

Profile changes are logged to `/data/adb/perf_profile.log`.

---

## What I'd tell someone starting this today

1. **Back up the full `super.img` first.** Every fix here came back to it.
2. On a GSI, the vendor partition is law: read its HAL versions before trusting
   the bundled apps.
3. Binary-patch with byte verification + checksum repair beats apktool rebuilds
   for priv-app APKs.
4. When a "fix" appears to work, verify *which* fix actually worked before
   celebrating. (See: the encryption detour.)
5. **Smali modifications to framework classes are extremely fragile.** The
   dex verifier may accept the bytecode but the runtime may crash. Test
   incrementally — one change at a time.
6. Two days in, a phone that texts, calls, scrolls at 144 Hz, and has working
   fingerprint beats the stock ROM — and the remaining two bugs have a common
   suspect: the modem.
