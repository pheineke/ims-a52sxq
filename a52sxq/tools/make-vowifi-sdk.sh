#!/usr/bin/env bash
# Builds a52sxq/vowifi/sdk for the Iwlan/QNS Gradle build. Both apps are Java and use hidden
# members of public classes (TelephonyManager, CarrierConfigManager, ...), so javac must see
# the device framework *as* android.jar, not next to the public SDK stubs:
#   android.jar                = API 36 SDK jar (java.*, resources.arsc) + device framework
#   core-for-system-modules.jar = API 36 (Records, SequencedCollection for Java 17+ sources)
# Needs a52sxq/tools/pull-device-framework.sh first. Output is gitignored.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC=${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}
P=$REPO/a52sxq/platform; c=$P/classes
for f in "$P/platform-api.jar" "$c"/framework-location-classes.jar "$c"/framework-wifi-classes.jar \
         "$c"/android.net.ipsec.ike-classes.jar "$c"/framework-statsd-classes.jar \
         "$SRC/platforms/android-36/android.jar" "$SRC/platforms/android-33/android.jar"; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
DST=$REPO/a52sxq/vowifi/sdk
rm -rf "$DST"; mkdir -p "$DST/platforms"
for e in "$SRC"/*; do [ "$(basename "$e")" = platforms ] || ln -sfn "$e" "$DST/"; done
for p in "$SRC"/platforms/*; do [ "$(basename "$p")" = android-33 ] || ln -sfn "$p" "$DST/platforms/"; done
cp -r "$SRC/platforms/android-33" "$DST/platforms/android-33"
J=$DST/platforms/android-33/android.jar
python3 -I "$REPO/a52sxq/tools/merge-platform-jar.py" "$J" "$SRC/platforms/android-36/android.jar" \
  "$P/platform-api.jar" "$c/framework-location-classes.jar" "$c/framework-wifi-classes.jar" \
  "$c/android.net.ipsec.ike-classes.jar" "$c/framework-statsd-classes.jar"
python3 -I - "$J" "$SRC/platforms/android-36/android.jar" <<'PY'
import sys, zipfile
full, sdk = sys.argv[1:]
with zipfile.ZipFile(sdk) as zs, zipfile.ZipFile(full, 'a') as zf:
    have = set(zf.namelist())
    for e in zs.namelist():
        if not e.endswith(('.class', '/')) and e not in have:
            zf.writestr(e, zs.read(e))
PY
cp "$SRC/platforms/android-36/core-for-system-modules.jar" "$DST/platforms/android-33/"
echo "VoWiFi SDK ready in $DST"
