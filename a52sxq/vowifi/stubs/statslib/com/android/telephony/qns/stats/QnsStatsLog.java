// No-op stand-in for the QnsStatsLog class that AOSP generates with stats-log-api-gen.
// QNS only uses the atom ids as getStatsId() values for the (no-op) StatsLib.
package com.android.telephony.qns.stats;

/** @hide */
public final class QnsStatsLog {
    public static final int QUALIFIED_RAT_LIST_CHANGED = 1;
    public static final int QNS_FALLBACK_RESTRICTION_CHANGED = 2;
    public static final int QNS_RAT_PREFERENCE_MISMATCH_INFO = 3;
    public static final int QNS_HANDOVER_TIME_MILLIS = 4;
    public static final int QNS_HANDOVER_PINGPONG = 5;
    public static final int QNS_IMS_CALL_DROP_STATS = 6;

    private QnsStatsLog() {}
}
