package com.google.android.iwlan.flags;

/** @hide */
public final class Flags {
    private static final FeatureFlags FEATURE_FLAGS = new FeatureFlagsImpl();
    public static boolean distinctEpdgSelectionForEmergencySessions() {
        return FEATURE_FLAGS.distinctEpdgSelectionForEmergencySessions();
    }
    public static boolean validateUnderlyingNetworkOnNoResponse() {
        return FEATURE_FLAGS.validateUnderlyingNetworkOnNoResponse();
    }
    public static boolean iwlanSilentRestart() { return FEATURE_FLAGS.iwlanSilentRestart(); }
}
