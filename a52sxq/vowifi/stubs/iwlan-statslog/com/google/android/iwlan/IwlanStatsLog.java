// No-op stand-in for the IwlanStatsLog class that AOSP generates with stats-log-api-gen.
// It only reports metrics to statsd; Iwlan behaves the same without it.
package com.google.android.iwlan;

/** @hide */
public final class IwlanStatsLog {
    // Atom ids from frameworks/proto_logging (atoms.proto); only compared, never sent.
    public static final int IWLAN_SETUP_DATA_CALL_RESULT_REPORTED = 1;
    public static final int IWLAN_PDN_DISCONNECTED_REASON_REPORTED = 2;
    public static final int IWLAN_UNDERLYING_NETWORK_VALIDATION_RESULT_REPORTED = 3;

    private IwlanStatsLog() {}

    public static void write(int code, Object... fields) {}
}
