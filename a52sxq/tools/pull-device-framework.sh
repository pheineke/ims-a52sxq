#!/usr/bin/env bash
# Pulls the framework jars from the connected phone (adb), converts them to class files
# and merges them into a52sxq/platform/platform-api.jar, the compile-only "full android.jar"
# that -PplatformApiJar expects. Compiling against the device's own framework catches
# API differences between the upstream target (LineageOS 23 / Android 16) and the device.
#
# Needs: adb, python3 and dex2jar (https://github.com/ThexXTURBOXx/dex2jar); set D2J to
# its d2j-dex2jar.sh. Output is device/ROM specific and must not be committed.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
D2J=${D2J:?set D2J to the path of d2j-dex2jar.sh}
OUT=$REPO/a52sxq/platform
mkdir -p "$OUT/dex" "$OUT/classes"

JARS="
/system/framework/framework.jar
/system/framework/telephony-common.jar
/system/framework/ims-common.jar
/apex/com.android.tethering/javalib/framework-connectivity.jar
/apex/com.android.tethering/javalib/framework-connectivity-t.jar
/apex/com.android.tethering/javalib/framework-connectivity-b.jar
/apex/com.android.telephonycore/javalib/framework-telephony.jar
/system/framework/framework-location.jar
/apex/com.android.wifi/javalib/framework-wifi.jar
/apex/com.android.ipsec/javalib/android.net.ipsec.ike.jar
/apex/com.android.os.statsd/javalib/framework-statsd.jar
"
for j in $JARS; do
  adb shell "[ -f $j ]" && adb pull "$j" "$OUT/dex/" >/dev/null || echo "skip (not on device): $j"
done

for f in "$OUT"/dex/*.jar; do
  "$D2J" --force -o "$OUT/classes/$(basename "${f%.jar}")-classes.jar" "$f"
done

# Order matters: later jars override earlier ones, the device framework wins over the stubs.
# (framework-location/wifi/ike/statsd are only needed for the VoWiFi apps, see
# a52sxq/tools/make-vowifi-sdk.sh.)
c=$OUT/classes
python3 -I "$REPO/a52sxq/tools/merge-platform-jar.py" "$OUT/platform-api.jar" \
  "$REPO/app/libs/android.jar" \
  $(ls "$c"/framework-connectivity*-classes.jar 2>/dev/null) \
  "$c/ims-common-classes.jar" "$c/telephony-common-classes.jar" "$c/framework-classes.jar" \
  $(ls "$c"/framework-telephony-classes.jar 2>/dev/null)
