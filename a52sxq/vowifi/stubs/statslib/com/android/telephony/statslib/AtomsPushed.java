// No-op stand-in for AOSP's TelephonyStatsLib (com.android.telephony.statslib), which only
// reports metrics to statsd. Same API as used by QualifiedNetworksService; nothing is sent.
package com.android.telephony.statslib;

import android.util.StatsEvent;

/** Pushed atom: written once. */
public abstract class AtomsPushed {
    public abstract int getStatsId();
    public abstract void build(StatsEvent.Builder builder);
    public abstract AtomsPushed copy();
}
