//SPDX-License-Identifier: GPL-2.0
package me.phh.ims

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemProperties
import android.telephony.Rlog
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import java.util.concurrent.Executor

/**
 * Publishes "a call is active on SIM slot N" as phhims.call.slot<N>=1/0.
 *
 * Samsung sm7325 (LineageOS sm7325-common audio/impl/PrimaryDevice.cpp) busy-waits in
 * setMode(IN_CALL) until vendor.calls.slot_id<N> == "1". Only the Samsung RIL sets that,
 * and only for CS calls, so a userspace IMS call hangs audioserver until its TimeCheck
 * watchdog aborts it. An init trigger (phhims.rc) mirrors phhims.call.slot<N> into
 * vendor.calls.slot_id<N>; this app may not set vendor properties itself.
 *
 * Driven by Android's per-subscription call state so that every way a call can end
 * (BYE, CANCEL, reject, CS retry, crash of the SIP side) clears the flag.
 */
class CallSlotSignal(private val context: Context) {
    companion object {
        private const val TAG = "PHH CallSlotSignal"
        private const val PROP_PREFIX = "phhims.call.slot"

        /**
         * False when the call-slot property cannot be set (sepolicy snippet missing).
         * Voice over IMS must then not be offered: Telecom's setMode(IN_CALL) would hang
         * the audio HAL. Calls fall back to CS instead.
         */
        @Volatile
        var usable = true
            private set
    }

    private val thread = HandlerThread("PhhCallSlotSignal").apply { start() }
    private val handler = Handler(thread.looper)
    private val executor = Executor { handler.post(it) }
    private val subscriptionManager = context.getSystemService(SubscriptionManager::class.java)
    private val telephonyManager = context.getSystemService(TelephonyManager::class.java)

    // subId -> (slot, registered callback)
    private val callbacks = mutableMapOf<Int, Pair<Int, TelephonyCallback>>()

    private val subscriptionsListener = object : SubscriptionManager.OnSubscriptionsChangedListener() {
        override fun onSubscriptionsChanged() = refresh()
    }

    fun start() {
        // Stale state from a previous process must never keep the HAL believing in a call.
        // This also probes whether the property may be set at all.
        var ok = true
        for (slot in 0 until telephonyManager.activeModemCount) {
            ok = publish(slot, false, "start", force = true) && ok
        }
        usable = ok
        if (!ok) Rlog.e(TAG, "Call-slot property not settable; disabling voice over IMS")
        subscriptionManager.addOnSubscriptionsChangedListener(executor, subscriptionsListener)
        handler.post { refresh() }
    }

    fun stop() {
        handler.post {
            subscriptionManager.removeOnSubscriptionsChangedListener(subscriptionsListener)
            callbacks.forEach { (subId, entry) ->
                telephonyManager.createForSubscriptionId(subId).unregisterTelephonyCallback(entry.second)
                publish(entry.first, false, "stop")
            }
            callbacks.clear()
            thread.quitSafely()
        }
    }

    private fun refresh() {
        val active = try {
            subscriptionManager.activeSubscriptionInfoList.orEmpty()
                .associate { it.subscriptionId to it.simSlotIndex }
        } catch (t: Throwable) {
            Rlog.w(TAG, "Cannot list subscriptions", t)
            return
        }

        (callbacks.keys - active.keys).forEach { subId ->
            callbacks.remove(subId)?.let { (slot, cb) ->
                telephonyManager.createForSubscriptionId(subId).unregisterTelephonyCallback(cb)
                publish(slot, false, "subscription gone")
            }
        }
        active.forEach { (subId, slot) ->
            if (slot < 0 || callbacks[subId]?.first == slot) return@forEach
            callbacks.remove(subId)?.let { (_, old) ->
                telephonyManager.createForSubscriptionId(subId).unregisterTelephonyCallback(old)
            }
            val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    when (state) {
                        TelephonyManager.CALL_STATE_OFFHOOK -> publish(slot, true, "offhook subId=$subId")
                        TelephonyManager.CALL_STATE_IDLE -> publish(slot, false, "idle subId=$subId")
                    }
                }
            }
            try {
                telephonyManager.createForSubscriptionId(subId).registerTelephonyCallback(executor, cb)
                callbacks[subId] = slot to cb
                Rlog.d(TAG, "Watching call state slot=$slot subId=$subId")
            } catch (t: Throwable) {
                Rlog.e(TAG, "Cannot watch call state slot=$slot subId=$subId", t)
            }
        }
    }

    private fun publish(slot: Int, inCall: Boolean, reason: String, force: Boolean = false): Boolean {
        val value = if (inCall) "1" else "0"
        return try {
            if (force || SystemProperties.get("$PROP_PREFIX$slot") != value) {
                SystemProperties.set("$PROP_PREFIX$slot", value)
                Rlog.d(TAG, "$PROP_PREFIX$slot=$value ($reason)")
            }
            true
        } catch (t: Throwable) {
            // Missing sepolicy: without the flag, IN_CALL hangs the Samsung audio HAL.
            Rlog.e(TAG, "Cannot set $PROP_PREFIX$slot=$value ($reason)", t)
            false
        }
    }
}
