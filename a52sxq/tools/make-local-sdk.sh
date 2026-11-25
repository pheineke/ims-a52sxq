#!/usr/bin/env bash
# Creates ./sdk (gitignored): symlinks to your Android SDK plus a private copy of
# platforms/android-33 whose android.jar has the android/telephony/ims stubs removed.
# Without that, javac resolves MmTelFeature/ImsFeature from the public SDK stubs (hidden
# constructor, protected CapabilityCallbackProxy) instead of from platform-api.jar.
# Your real SDK is not modified.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC=${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}
[ -d "$SRC/platforms/android-33" ] || { echo "install platforms;android-33 with sdkmanager first"; exit 1; }
[ -d "$SRC/ndk/27.1.12297006" ] || echo "note: app/build.gradle expects NDK 27.1.12297006"

DST=$REPO/sdk
rm -rf "$DST"; mkdir -p "$DST/platforms"
for e in "$SRC"/*; do
  [ "$(basename "$e")" = platforms ] || ln -sfn "$e" "$DST/"
done
for p in "$SRC"/platforms/*; do
  [ "$(basename "$p")" = android-33 ] || ln -sfn "$p" "$DST/platforms/"
done
cp -r "$SRC/platforms/android-33" "$DST/platforms/android-33"
zip -q -d "$DST/platforms/android-33/android.jar" 'android/telephony/ims/*'
echo "local SDK ready in $DST"
