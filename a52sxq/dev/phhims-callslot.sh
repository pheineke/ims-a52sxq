#!/system/bin/sh
# a52sxq-proto: mirror IMS call state into vendor.calls.slot_id<N>.
#
# LineageOS's Samsung audio HAL wrapper (sm7325-common audio/impl/PrimaryDevice.cpp)
# busy-waits in setMode(IN_CALL) until the Samsung RIL reports a call on a SIM slot
# via vendor.calls.slot_id0/1. The RIL only does that for CS calls, so with a
# userspace IMS stack Telecom's setMode(IN_CALL) hangs audioserver until its
# TimeCheck watchdog aborts it. This helper sets the property for the slot that
# has an IMS call, exactly as the RIL does for CS calls, and clears it afterwards.
#
# Must run as root (vendor_radio_prop). Log: /data/local/tmp/phhims-callslot.log

log() { echo "$(date +%T) $*"; }

set_slot() {
    setprop "vendor.calls.slot_id$1" "$2"
    log "slot_id$1=$2 ($3)"
}

log "started pid $$"
logcat -b main -b radio -b system -T 1 -v brief \
    ImsPhoneCallTracker:D Telecom:I '*:S' 2>&1 |
while IFS= read -r line; do
    case "$line" in
        *"ImsPhoneCallTracker"*"[0] dial"*|*"ImsPhoneCallTracker"*"[0] acceptCall"*)
            set_slot 0 1 "IMS call start" ;;
        *"ImsPhoneCallTracker"*"[1] dial"*|*"ImsPhoneCallTracker"*"[1] acceptCall"*)
            set_slot 1 1 "IMS call start" ;;
        *"ImsPhoneCallTracker"*"[0] onCallTerminated"*)
            set_slot 0 0 "IMS call end" ;;
        *"ImsPhoneCallTracker"*"[1] onCallTerminated"*)
            set_slot 1 0 "IMS call end" ;;
        *"UnfocusedState: enter"*)
            # Telecom: no calls left. Only clear what is still set.
            [ "$(getprop vendor.calls.slot_id0)" = 1 ] && set_slot 0 0 "no calls"
            [ "$(getprop vendor.calls.slot_id1)" = 1 ] && set_slot 1 0 "no calls" ;;
    esac
done
log "logcat ended"
