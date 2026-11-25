package com.android.telephony.statslib;

import android.util.StatsEvent;

/** Pulled atom: accumulated per dimension and pulled by statsd. */
public abstract class AtomsPulled {
    public abstract int getStatsId();
    public abstract void build(StatsEvent.Builder builder);
    public abstract String getDimension();
    public abstract void accumulate(AtomsPulled info);
    public abstract AtomsPulled copy();
}
