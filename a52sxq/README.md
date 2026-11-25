# VoLTE on LineageOS for the Galaxy A52s 5G (a52sxq)

This branch brings voice over LTE to the official LineageOS build for the Samsung Galaxy
A52s 5G (SM-A528B, `a52sxq`, Snapdragon 778G / SM7325). It uses the open-source userspace
IMS stack from [krazey/ims](https://github.com/krazey/ims) (package `me.phh.ims`), adapted
so it can be installed on an **unmodified, officially signed** LineageOS build with a
recovery zip, the same way GApps are installed.

> [!WARNING]
> Experimental. Read [Be careful about](#be-careful-about) before flashing anything.
> Keep another way to make calls until you have tested your SIM and your daily use.

**Status (2026-11-25), LineageOS 24.0 nightly (Android 17):**

| | Result |
| --- | --- |
| IMS registration (AKA + IPsec) | works with 1&1 (sim24 brand, 1&1 network with Vodafone national roaming) and LIDL Connect (Vodafone) |
| Outgoing VoLTE call | works on 1&1: HD (AMR-WB), two-way audio, mobile data during the call |
| Incoming VoLTE call | rings and can be answered; audio after the audio-HAL fix **not verified yet** |
| Calls on LIDL Connect | not tested yet (registration only) |
| Location off, update via `addon.d`, uninstall zip | not tested yet |

Why bother: LineageOS has no IMS stack on Samsung devices, because Samsung's IMS service
only ships with One UI. Without VoLTE, every call falls back to 2G. In Germany 3G is
already gone, and the operators switch off 2G in 2028 (Telekom June, Vodafone September,
o2 by year end). After that, a phone without VoLTE cannot make or receive normal calls.

## Contents

- [Be careful about](#be-careful-about)
- [Installing](#installing)
- [How it works](#how-it-works)
- [Building](#building)
- [Troubleshooting](#troubleshooting)
- [How we got here](#how-we-got-here)
- [Credits and license](#credits-and-license)

## Be careful about

- **Emergency calls.** Numbers that Android classifies as emergency numbers are *not*
  sent over IMS: the app answers them with "retry over circuit switched" and Android
  dials them over 2G as before. This path was not tested with a real emergency call
  (do not test it with one). Once 2G is switched off there is no fallback, and this
  package does not implement IMS emergency calls.
- **It changes the SELinux policy.** A small snippet is appended to
  `/product/etc/selinux/product_sepolicy.cil` so the IMS app may set one property type
  (`phhims_prop`). This deliberately goes against an Android `neverallow` (apps may not
  write the property socket). The grant is narrow, only `phhims.call.*` can be set,
  but it is a change to the security policy of your phone.
- **A broken policy means no boot.** Init recompiles the policy at every boot (see
  below). The snippet was compiled against the full device policy with the device's own
  `secilc` before release, but if a future build breaks it, the phone stops at boot.
  Recovery: boot to recovery and sideload the uninstall zip, which restores the original
  policy files. Keep the uninstall zip on your computer.
- **Only for LineageOS 24.0 on a52sxq.** The installer refuses anything else. It is built
  against this exact Android version's internal telephony APIs and this device's audio HAL.
  Do not adapt it to another device blindly: the audio HAL quirk handled here is specific
  to LineageOS's Samsung sm7325 audio wrapper.
- **Updates.** An `addon.d` script keeps the package through LineageOS 24.0 updates and
  re-applies the policy snippet. LineageOS's backuptool refuses to restore across major
  versions, so an upgrade to 25 removes the package. That is intended: rebuild it for the
  new version. After every update, check the HD icon on your first call.
- **Never run `adb enable-verity`** after installing. The system and product partitions
  are modified (LineageOS on Samsung runs with verity disabled anyway); turning it on can
  make the phone unbootable.
- **Signatures.** Recovery shows "Signature verification failed" because the zip is not
  signed by LineageOS. Build the package yourself (it generates your own signing key) or
  only flash zips from people you trust. The key in `a52sxq/zip/keys/` is gitignored:
  never commit or share it.
- **Privacy in logs.** The app logs SIP traffic at debug level, including phone numbers,
  IMSI-based identities and the IMEI. Scrub logcat output before posting it anywhere.
- **Location.** The app reads the serving cell for the `P-Access-Network-Info` SIP header.
  It is granted location permission and added to the framework's location bypass list
  (`config_serviceStateLocationAllowedPackages`), like the stock Phone app.
- **Not certified.** Carriers never approved this stack. It may stop registering, behave
  differently on other carriers, or be blocked. Your carrier must provision VoLTE for your
  SIM; 1&1 and Vodafone-network SIMs registered here, others are untested on this device.
- **Not done:** VoWiFi (no Iwlan/QNS on the ROM), video calls, conference calls, RCS. Audio
  can be a little choppy (jitter concealment), echo cancellation is off by default.

## Installing

1. Boot LineageOS Recovery (`adb reboot recovery`, or power off and hold Power +
   Volume Up with USB connected).
2. Apply update → Apply from ADB, then on the computer:
   `adb sideload PhhIms-VoLTE-a52sxq-lineage-24.0-<version>-<date>.zip`
3. Accept "Signature verification failed → install anyway". The installer prints `Done.`
4. Reboot. The first boot takes a few seconds longer (policy compilation).
5. Check: VoLTE should register within a minute; the dialer shows **HD** during calls and
   mobile data keeps working. `*#*#4636#*#*` → Phone info shows IMS status too.

To remove: sideload `PhhIms-VoLTE-a52sxq-lineage-24.0-uninstall.zip` the same way.

If you used `adb remount` or other overlays on `/system` before, remove those copies of
`me.phh.ims` first, and `adb uninstall me.phh.ims` any development build in `/data`.

## How it works

The upstream app is meant to be built into a ROM: platform-signed, running as the system
user, with device tree overlays and audio HAL fixes. An official LineageOS build has none of
that, so the package works around every missing piece.

| Problem on stock LineageOS a52sxq | What the package does |
| --- | --- |
| No IMS service at all; telephony only creates its `ImsResolver` when the device declares IMS | `etc/permissions/android.hardware.telephony.ims.xml` declares the feature |
| The app must normally be platform-signed (`sharedUserId=android.uid.system`); the LineageOS platform key is private | It runs as a privileged app instead: manifest without `sharedUserId`, plus the permissions system uid had implicitly (`INTERNET`, location, `MODIFY_PHONE_STATE`, `CONNECTIVITY_USE_RESTRICTED_NETWORKS`), a privapp allowlist (enforced on this build), default runtime grants, and a hidden-API allowlist entry in `etc/sysconfig` |
| Telephony must bind the app as the MMTEL (voice/SMS) service | Static RRO on `com.android.phone`: `config_ims_mmtel_package = me.phh.ims`. ImsResolver reads the app's MMTEL metadata only for this "device" package; a runtime override is not enough |
| VoLTE hidden by carrier config defaults | `persist.dbg.volte_avail_ovr=1` at boot, framework RRO `config_device_volte_available` / `config_carrier_volte_available` |
| **Samsung audio HAL hangs on calls** (see below) | Framework RRO `config_use_voip_mode_for_ims=true`, plus the call-slot signal |

### The Samsung audio HAL hang

This was the hard part. LineageOS's Samsung audio HAL wrapper
([`sm7325-common/audio/impl/PrimaryDevice.cpp`](https://github.com/LineageOS/android_device_samsung_sm7325-common/blob/lineage-24.0/audio/impl/PrimaryDevice.cpp))
does this in `setMode()`:

```cpp
// Wait until one sim slot reports a call
if (mode == AudioMode::IN_CALL) {
    while (strcmp(simSlot1, "0") == 0 && strcmp(simSlot2, "0") == 0) {
        property_get("vendor.calls.slot_id0", simSlot1, "");
        property_get("vendor.calls.slot_id1", simSlot2, "");
    }
}
```

Only the Samsung RIL sets `vendor.calls.slot_id<N>`, and only for circuit-switched calls.
With a userspace IMS stack, Telecom's `setMode(MODE_IN_CALL)` spins there forever, the
audioserver watchdog (TimeCheck) aborts audioserver after a few seconds, and the call
loses its audio and drops.

Two parts avoid it:

1. `config_use_voip_mode_for_ims=true` makes Telecom use `MODE_IN_COMMUNICATION` (the
   VoIP audio path the app needs anyway) for IMS calls. Telecom still sends a short
   `MODE_IN_CALL` while an outgoing call is connecting, before it knows it is VoIP.
2. The app reports "a call is active on slot N", exactly as the RIL does for CS calls:
   `CallSlotSignal.kt` follows Android's per-subscription call state (`OFFHOOK`/`IDLE`)
   and sets `phhims.call.slot<N>`, and `etc/init/phhims.rc` copies it into
   `vendor.calls.slot_id<N>` (the app may not set vendor properties; init may). The HAL
   then continues with the right SIM slot after a few milliseconds.

The sepolicy snippet (`etc/phhims/phhims_sepolicy.cil`) defines `phhims_prop` and lets
`priv_app` and `priv_app_36` set it. On Android 17, privileged apps that target an SDK
below 37 run in `priv_app_36`, not `priv_app` (`plat_seapp_contexts`).

**Fail-safe:** if the property cannot be set (for example the snippet is missing after a
failed update), `CallSlotSignal.usable` turns false and the app stops reporting voice
capability. Calls then go over 2G as on a stock build instead of hanging. The `addon.d`
script additionally removes the phone overlay if re-applying the snippet fails.

### How the policy change is applied

`etc/phhims/phhims-sepolicy.sh` (run by the installer and by `addon.d` in recovery)
appends the snippet between `;; BEGIN phhims` / `;; END phhims` markers to
`product_sepolicy.cil`, adds the property context to `product_property_contexts`, and
changes `product_sepolicy_and_mapping.sha256`. Because that hash no longer matches
`/odm/etc/selinux/precompiled_sepolicy.product_sepolicy_and_mapping.sha256`, init compiles
the policy from CIL at boot (`secilc ... -N`, neverallow checks disabled, as in AOSP's
`init/selinux.cpp`). The original hash is kept, so the uninstaller restores the
precompiled fast path exactly.

### Installer details worth knowing

- Recovery's clock is years behind. PackageManager trusts its package cache while the
  cache entry is newer than the package, and for directory packages it compares the
  *directory* timestamp. The installer sets files and directories to a fixed future mtime
  (2037), otherwise an update over an existing install is silently ignored.
- RRO APKs need `<application android:hasCode="false"/>`, or PackageManager drops them
  without logging anything useful.
- On this build `ro.lineage.version` is in `/product/etc/build.prop`, not
  `/system/build.prop`.

## Building

Requirements: a Linux PC, Android SDK with `platforms;android-33`, build-tools and NDK
`27.1.12297006`, JDK 17 (Gradle 8.2 does not run on JDK 21), `adb`, `zip`, `python3` and
[dex2jar](https://github.com/ThexXTURBOXx/dex2jar). The phone must run the LineageOS
build you are targeting, with USB debugging.

```sh
git clone -b a52sxq <this repository> ims && cd ims
git submodule update --init --recursive        # rnnoise, webrtc-aec3

# 1. Compile against the phone's own framework (catches Android 16 -> 17 API changes).
#    Writes a52sxq/platform/platform-api.jar (device specific, gitignored).
D2J=/path/to/dex-tools/d2j-dex2jar.sh ./a52sxq/tools/pull-device-framework.sh

# 2. Project-local SDK in ./sdk with the IMS stubs removed from android-33 (gitignored).
ANDROID_HOME=/path/to/android-sdk ./a52sxq/tools/make-local-sdk.sh

# 3. App, overlays, both zips. Generates your own signing key on first run.
JAVA_HOME=/path/to/jdk-17 ./a52sxq/zip/build-zip.sh
ls a52sxq/zip/out/*.zip
```

Repeat step 1 after LineageOS updates that change the framework, and bump `versionCode`
in `app/build.gradle` for every package you release.

Changes to the app compared with upstream (see the commits on this branch):

- `app/build.gradle`: NDK 27.1, arm64 only, `versionCode 1001` (must be higher than any
  development build on the phone).
- `AndroidManifest.xml`: no `sharedUserId`; `INTERNET`, location, `MODIFY_PHONE_STATE`,
  `CONNECTIVITY_USE_RESTRICTED_NETWORKS`.
- `CallSlotSignal.kt` (new), hooked up in `PhhImsService.kt`; voice capability is dropped
  in `PhhMmTelFeature.kt` when the signal cannot be published.

## Troubleshooting

All of this needs USB debugging; `adb root` needs "Rooted debugging" in developer options.

```sh
# Is the app bound as the IMS service? ("Active controllers" lists PhhImsService)
adb shell dumpsys phone | sed -n '/ImsResolver:/,/Connection Repository/p'

# Registration and capabilities (9 = voice + SMS)
adb logcat -d | grep -E 'IMS SIP registered|Final MMTEL capabilities|isVolteEnabled'

# Call-slot signal: both must change to 1 during a call and back to 0 after it
adb shell 'getprop phhims.call.slot0; getprop vendor.calls.slot_id0'

# Policy and overlays
adb shell getprop -Z phhims.call.slot0       # u:object_r:phhims_prop:s0
adb shell cmd overlay list | grep phh        # both [x]
adb shell dmesg | grep 'avc:.*me.phh.ims'    # should be empty

# The audio HAL hang, if it ever comes back
adb logcat -d | grep -E 'TimeCheck timeout|SimCallFocusState|VoipCallFocusState'
```

- **No HD icon, calls work over 2G:** the fail-safe kicked in or the app is not bound.
  Look for `Cannot set phhims.call.slot` (policy missing) and check the overlays.
- **Calls drop after a few seconds, audioserver restarts:** the call-slot signal did not
  reach `vendor.calls.slot_id<N>`. Check `phhims.rc` and the properties above.
- **Registration fails:** location permission or the bypass list, the IMS APN, or the
  carrier not provisioning VoLTE for the SIM. `connect/register attempt failed` lines
  give the reason.
- **Package changes not picked up:** stale package cache; check that the installed
  files and `/system/priv-app/PhhIms` have the 2037 mtime.

## How we got here

Short version of the bring-up, in case you want to repeat it on another device:

1. Checked over adb: no `android.telephony.ims.ImsService` anywhere, `ImsResolver` empty,
   default carrier config without VoLTE. The Samsung vendor side, however, is complete:
   `ISehRadio` and `ISehChannel/imsd` are registered. Only the system-side IMS stack is
   missing.
2. Built krazey/ims with Gradle against the phone's own framework classes (dex2jar of
   `framework.jar`, `telephony-common.jar`, `ims-common.jar`, the connectivity and
   telephony module jars). The checked-in stubs were too old, and javac preferred the public
   SDK stubs until the IMS classes were removed from the SDK jar.
3. Prototype without reflashing: `adb remount` (scratch overlay; LineageOS defaults to a
   `/cache` backed overlay that is mounted too late at boot), privileged install,
   `cmd phone ims set-ims-service`, debug properties. Each failure pointed at something
   system uid used to cover: socket `EPERM` (INTERNET), `Not allowed to access cell info`
   (location), the privapp allowlist, the missing IMS feature declaration.
4. Both SIMs registered (AKA + IPsec). The first calls signalled fine but died after six
   seconds. Tombstones of the audio HAL showed `PrimaryDevice::setMode` spinning in
   `property_get`, which led to the wrapper code above.
5. Telecom would avoid `MODE_IN_CALL` entirely for phone accounts carrying
   `EXTRA_ALWAYS_USE_VOIP_AUDIO_MODE`, but TeleService never sets it and cannot be
   patched without the platform key. So the slot property was mirrored instead: first by a
   root helper (`a52sxq/dev/phhims-callslot.sh`, development only), then by the app plus
   an init trigger and a sepolicy snippet, which became the recovery zip.
6. Flash testing turned up the remaining issues: wrong file for the ROM version check,
   RROs without `hasCode=false`, the package cache vs. recovery's clock, and the
   `priv_app_36` domain.

A proper ROM-level fix would be a timeout in the HAL wrapper's wait loop plus
`EXTRA_ALWAYS_USE_VOIP_AUDIO_MODE` on the SIM phone accounts; then no policy change is
needed.

## Credits and license

- IMS stack: [phhusson/ims](https://github.com/phhusson/ims) by Pierre-Hugues Husson,
  Samsung work in [amikhasenko/ims](https://github.com/amikhasenko/ims), maintained in
  [krazey/ims](https://github.com/krazey/ims). This branch only adds the a52sxq adaptation.
- Installer partition handling follows [MindTheGapps](https://gitlab.com/MindTheGapps);
  `addon.d` follows LineageOS backuptool.
- GPL-2.0, like the upstream project (see `LICENSE`).
