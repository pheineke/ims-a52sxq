// Hand-written replacement for the aconfig-generated library (iwlan_telephony_flags_lib)
// from flags/main.aconfig. Gradle builds have no aconfig step.
package com.google.android.iwlan.flags;

/** @hide */
public interface FeatureFlags {
    boolean distinctEpdgSelectionForEmergencySessions();
    boolean validateUnderlyingNetworkOnNoResponse();
    boolean iwlanSilentRestart();
}
