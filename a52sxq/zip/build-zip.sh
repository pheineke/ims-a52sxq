#!/usr/bin/env bash
# Builds the PhhIms VoLTE recovery zips (install + uninstall) for LineageOS a52sxq.
# See a52sxq/README.md. Prerequisites:
#   a52sxq/tools/pull-device-framework.sh   (once per LineageOS build, phone via adb)
#   a52sxq/tools/make-local-sdk.sh          (once)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
PLATFORM_JAR=${PLATFORM_JAR:-$REPO/a52sxq/platform/platform-api.jar}
LINEAGE_VERSION=${LINEAGE_VERSION:-24.0}
JAVA_HOME=${JAVA_HOME:?set JAVA_HOME to a JDK 17 (Gradle 8.2 does not run on JDK 21)}
SDK=$REPO/sdk                      # project-local SDK from make-local-sdk.sh
BT=${BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)}
ANDROID_JAR=${ANDROID_JAR:-$(ls -d "$SDK"/platforms/android-3[4-9]* | sort -V | tail -1)/android.jar}
KEYDIR=$HERE/keys                  # gitignored; never commit or share
KEYSTORE=$KEYDIR/phhims-release.jks
KEYPASS_FILE=$KEYDIR/password.txt

[ -f "$PLATFORM_JAR" ] || { echo "missing $PLATFORM_JAR: run a52sxq/tools/pull-device-framework.sh"; exit 1; }
[ -d "$SDK/platforms/android-33" ] || { echo "missing $SDK: run a52sxq/tools/make-local-sdk.sh"; exit 1; }

if [ ! -f "$KEYSTORE" ]; then
  echo "== generating a signing key for this package in $KEYDIR"
  mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
  head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$KEYPASS_FILE"; chmod 600 "$KEYPASS_FILE"
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KEYSTORE" -storepass "$(cat "$KEYPASS_FILE")" \
    -keypass "$(cat "$KEYPASS_FILE")" -alias phhims -keyalg RSA -keysize 4096 -validity 10000 \
    -dname "CN=PhhIms a52sxq VoLTE package"
  chmod 600 "$KEYSTORE"
fi

OUT=$HERE/out
STAGE=$OUT/stage
rm -rf "$STAGE"; mkdir -p "$STAGE/system" "$OUT"

sign() {  # sign <unsigned.apk> <out.apk>
  "$BT/zipalign" -p -f 4 "$1" "$1.aligned"
  "$BT/apksigner" sign --v4-signing-enabled false --ks "$KEYSTORE" --ks-key-alias phhims \
    --ks-pass "file:$KEYPASS_FILE" --out "$2" "$1.aligned"
  rm -f "$1.aligned"
  "$BT/apksigner" verify "$2"
}

echo "== IMS app"
( cd "$REPO" && JAVA_HOME="$JAVA_HOME" ANDROID_HOME="$SDK" ./gradlew --no-daemon -q assembleRelease \
    -PplatformApiJar="$PLATFORM_JAR" )
APK=$REPO/app/build/outputs/apk/release/app-release-unsigned.apk
VERSION_NAME=$("$BT/aapt2" dump badging "$APK" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
mkdir -p "$STAGE/system/priv-app/PhhIms"
sign "$APK" "$STAGE/system/priv-app/PhhIms/PhhIms.apk"

echo "== overlays"
for o in framework:PhhImsFrameworkOverlay phone:PhhImsPhoneOverlay; do
  dir=${o%%:*}; name=${o##*:}; w=$OUT/build-$dir
  rm -rf "$w"; mkdir -p "$w"
  "$BT/aapt2" compile --dir "$HERE/overlays/$dir/res" -o "$w/res.zip"
  "$BT/aapt2" link --manifest "$HERE/overlays/$dir/AndroidManifest.xml" -I "$ANDROID_JAR" \
      --min-sdk-version 34 --target-sdk-version 34 -o "$w/unsigned.apk" "$w/res.zip"
  mkdir -p "$STAGE/system/product/overlay"
  sign "$w/unsigned.apk" "$STAGE/system/product/overlay/$name.apk"
done

echo "== configuration files"
cp -r "$HERE/src/system/." "$STAGE/system/"
( cd "$STAGE/system" && find . -type f | sed 's|^\./||' | sort ) > "$STAGE/files.list"
cp "$HERE/src/addon.d.template" "$STAGE/"
cat "$STAGE/files.list"

make_zip() {  # make_zip <mode> <zipname>
  local mode=$1 zip=$OUT/$2 w=$OUT/zip-$1
  rm -rf "$w" "$zip"; mkdir -p "$w/META-INF/com/google/android"
  sed -e "s/@MODE@/$mode/" -e "s/@LINEAGE_VERSION@/$LINEAGE_VERSION/" \
      "$HERE/src/META-INF/com/google/android/update-binary" > "$w/META-INF/com/google/android/update-binary"
  echo "# Dummy file; update-binary is a shell script." > "$w/META-INF/com/google/android/updater-script"
  cp "$STAGE/files.list" "$w/"
  if [ "$mode" = install ]; then
    cp -r "$STAGE/system" "$STAGE/addon.d.template" "$w/"
  fi
  ( cd "$w" && zip -q -r -X "$zip" . )
  echo "built $zip ($(du -h "$zip" | cut -f1))"
}

STAMP=$(date +%Y%m%d)
make_zip install   "PhhIms-VoLTE-a52sxq-lineage-$LINEAGE_VERSION-$VERSION_NAME-$STAMP.zip"
make_zip uninstall "PhhIms-VoLTE-a52sxq-lineage-$LINEAGE_VERSION-uninstall.zip"
