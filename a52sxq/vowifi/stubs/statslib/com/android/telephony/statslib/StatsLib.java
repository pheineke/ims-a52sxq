package com.android.telephony.statslib;

import android.content.Context;

/** No-op: QualifiedNetworksService works the same without telephony metrics. */
public class StatsLib {
    public StatsLib(Context context) {}
    public void write(AtomsPushed atom) {}
    public void append(AtomsPulled atom) {}
}
