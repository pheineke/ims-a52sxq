// The Android 17 release configs (platform/build/release, cp1a/cp2a) set none of the
// com.google.android.iwlan.flags flags, so aconfig's default applies: disabled.
package com.google.android.iwlan.flags;

/** @hide */
public final class FeatureFlagsImpl implements FeatureFlags {
    @Override public boolean distinctEpdgSelectionForEmergencySessions() { return false; }
    @Override public boolean validateUnderlyingNetworkOnNoResponse() { return false; }
    @Override public boolean iwlanSilentRestart() { return false; }
}
