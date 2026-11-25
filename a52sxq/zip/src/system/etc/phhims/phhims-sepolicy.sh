#!/sbin/sh
#
# phhims-sepolicy.sh apply|remove|status <system dir>
#
# Adds (or removes) the PhhIms sepolicy snippet: a property type for phhims.call.*
# that the IMS app (priv_app) may set. init mirrors it into vendor.calls.slot_id<N>
# (see /system/etc/init/phhims.rc). Runs in recovery (installer, addon.d).
#
# The snippet goes into a platform-side policy partition (product or system_ext). Its
# *_sepolicy_and_mapping.sha256 is changed so init no longer matches the vendor's
# precompiled_sepolicy and compiles the CIL at boot (secilc -N, ~1-2 s). The original
# hash is kept, so "remove" restores the precompiled fast path exactly.

ACTION="$1"
S="$2"          # e.g. /mnt/system/system
HERE=$(dirname "$0")
BEGIN=';; BEGIN phhims'
END=';; END phhims'
PCTX_BEGIN='# BEGIN phhims'
PCTX_END='# END phhims'

log() { echo "phhims-sepolicy: $*"; }

# Platform-side policy partition to extend, as seen from recovery.
pick_policy_dir() {
  for part in product system_ext; do
    for d in "/$part/etc/selinux" "$S/$part/etc/selinux"; do
      [ -f "$d/${part}_sepolicy.cil" ] && { echo "$d $part"; return 0; }
    done
  done
  return 1
}

PICKED=$(pick_policy_dir) || { log "no product/system_ext sepolicy found"; exit 2; }
DIR="${PICKED% *}"; PART="${PICKED##* }"
CIL="$DIR/${PART}_sepolicy.cil"
PCTX="$DIR/${PART}_property_contexts"
SHA="$DIR/${PART}_sepolicy_and_mapping.sha256"
ORIG_SHA="$DIR/.phhims.orig.sha256"

# sed -i replaces the file: keep owner, mode and SELinux label of the original.
edit_keep_attrs() {
  local f="$1"; shift
  local ctx=$(ls -Z "$f" | grep -o 'u:object_r:[^ ]*' | head -1)
  sed -i "$@" "$f"
  chown root:root "$f"; chmod 0644 "$f"
  [ -n "$ctx" ] && chcon "$ctx" "$f"
}

strip_snippet() {
  edit_keep_attrs "$CIL" "/^$BEGIN\$/,/^$END\$/d"
  [ -f "$PCTX" ] && edit_keep_attrs "$PCTX" "/^$PCTX_BEGIN\$/,/^$PCTX_END\$/d"
}

case "$ACTION" in
  apply)
    [ -f "$HERE/phhims_sepolicy.cil" ] || { log "snippet missing"; exit 3; }
    strip_snippet
    { echo "$BEGIN"; cat "$HERE/phhims_sepolicy.cil"; echo "$END"; } >> "$CIL"
    { echo "$PCTX_BEGIN"; cat "$HERE/phhims_property_contexts"; echo "$PCTX_END"; } >> "$PCTX"
    # Remember the pristine hash once (an update ships a new pristine one: refresh it).
    if [ -f "$SHA" ] && ! grep -q phhims "$SHA"; then cp -p "$SHA" "$ORIG_SHA"; fi
    # Any value that differs from the precompiled copy forces on-device compilation.
    echo "$(sha256sum "$CIL" | cut -d' ' -f1) phhims" > "$SHA"
    log "applied to $CIL"
  ;;
  remove)
    strip_snippet
    if [ -f "$ORIG_SHA" ]; then cp -p "$ORIG_SHA" "$SHA" && rm -f "$ORIG_SHA"; fi
    log "removed from $CIL"
  ;;
  status)
    grep -q "^$BEGIN\$" "$CIL" && log "present in $CIL" || log "absent from $CIL"
  ;;
  *)
    log "usage: $0 apply|remove|status <system dir>"; exit 1
  ;;
esac
