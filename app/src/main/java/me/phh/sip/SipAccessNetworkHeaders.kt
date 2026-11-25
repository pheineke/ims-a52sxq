// SPDX-License-Identifier: GPL-2.0
package me.phh.sip

import android.telephony.AccessNetworkConstants
import android.telephony.CellIdentityLte
import android.os.SystemClock
import android.telephony.NetworkRegistrationInfo
import android.telephony.Rlog
import android.telephony.ServiceState
import android.telephony.TelephonyManager
import android.telephony.ims.stub.ImsRegistrationImplBase.REGISTRATION_TECH_IWLAN
import android.telephony.ims.stub.ImsRegistrationImplBase.REGISTRATION_TECH_LTE

internal object SipAccessNetworkHeaders {
    // Last LTE cell seen on any subscription, for Cellular-Network-Info while on IWLAN
    // (3GPP TS 24.229 7.2A.15): carriers reject Wi-Fi calls without location information,
    // and in airplane mode there is no current cell to read.
    private data class CellSnapshot(val utranCellId: String, val seenAtElapsedMs: Long)

    @Volatile
    private var lastLteCell: CellSnapshot? = null

    /** Called on every service state change (see CallSlotSignal). */
    fun rememberServiceState(serviceState: ServiceState?) {
        lteCellId(serviceState)?.let {
            lastLteCell = CellSnapshot(it, SystemClock.elapsedRealtime())
        }
    }

    private fun lteCellId(serviceState: ServiceState?): String? {
        val registration = serviceState
            ?.networkRegistrationInfoList
            ?.firstOrNull {
                it.transportType == AccessNetworkConstants.TRANSPORT_TYPE_WWAN &&
                    (it.domain and NetworkRegistrationInfo.DOMAIN_PS) != 0 &&
                    it.isNetworkRegistered
            }
        val cell = registration?.cellIdentity as? CellIdentityLte ?: return null
        return utranCellId(cell.mccString, cell.mncString, cell.tac, cell.ci)
    }

    private fun utranCellId(mcc: String?, mnc: String?, tac: Int, ci: Int): String? {
        val normalizedMcc = mcc?.takeIf { it.length == 3 && it.all(Char::isDigit) } ?: return null
        val normalizedMnc =
            mnc?.takeIf { it.length in 2..3 && it.all(Char::isDigit) } ?: return null
        if (tac !in 0..0xffff || ci !in 0..0x0fffffff) return null
        return (normalizedMcc + normalizedMnc + tac.toString(16).padStart(4, '0') +
            ci.toString(16).padStart(7, '0')).uppercase()
    }

    /** P-Access-Network-Info / Cellular-Network-Info for an INVITE sent over IWLAN. */
    internal fun iwlanHeaders(lastCell: String?, cellAgeSeconds: Long): SipHeadersMap {
        val headers = mutableMapOf("P-Access-Network-Info" to listOf("IEEE-802.11"))
        if (lastCell != null) {
            headers["Cellular-Network-Info"] = listOf(
                "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=$lastCell;" +
                    "cell-info-age=${cellAgeSeconds.coerceAtLeast(0)}",
            )
        }
        return headers
    }

    fun forOutgoingInvite(
        logTag: String,
        telephonyManager: TelephonyManager,
        registrationTech: Int,
        policy: SipCarrierPolicy.OutgoingPaniPolicy,
        visitedNetworkPolicy: SipCarrierPolicy.OutgoingVisitedNetworkPolicy,
        visitedNetworkId: String,
    ): SipHeadersMap {
        if (policy != SipCarrierPolicy.OutgoingPaniPolicy.LTE_CELL_IDENTITY) {
            return emptyMap()
        }
        if (registrationTech == REGISTRATION_TECH_IWLAN) {
            try {
                rememberServiceState(telephonyManager.serviceState)
            } catch (e: RuntimeException) {
                Rlog.w(logTag, "Could not read LTE identity for Cellular-Network-Info", e)
            }
            val snapshot = lastLteCell
            val ageSeconds = snapshot?.let {
                (SystemClock.elapsedRealtime() - it.seenAtElapsedMs) / 1000
            } ?: 0
            if (snapshot == null) Rlog.w(logTag, "No LTE cell known for Cellular-Network-Info")
            return iwlanHeaders(snapshot?.utranCellId, ageSeconds)
        }
        if (registrationTech != REGISTRATION_TECH_LTE) {
            return emptyMap()
        }

        return try {
            val registration = telephonyManager.serviceState
                ?.networkRegistrationInfoList
                ?.firstOrNull {
                    it.transportType == AccessNetworkConstants.TRANSPORT_TYPE_WWAN &&
                        (it.domain and NetworkRegistrationInfo.DOMAIN_PS) != 0 &&
                        it.isNetworkRegistered
                }
            val cellIdentity = registration?.cellIdentity as? CellIdentityLte
            utranCellId(cellIdentity?.mccString, cellIdentity?.mncString,
                cellIdentity?.tac ?: -1, cellIdentity?.ci ?: -1)?.let {
                lastLteCell = CellSnapshot(it, SystemClock.elapsedRealtime())
            }
            if (cellIdentity == null) {
                Rlog.w(logTag, "No registered LTE identity for SIP access headers")
                emptyMap()
            } else {
                lteHeaders(
                    mcc = cellIdentity.mccString,
                    mnc = cellIdentity.mncString,
                    tac = cellIdentity.tac,
                    ci = cellIdentity.ci,
                    visitedNetworkId = visitedNetworkId.takeIf {
                        visitedNetworkPolicy ==
                            SipCarrierPolicy.OutgoingVisitedNetworkPolicy.REGISTRATION_REALM
                    },
                )
            }
        } catch (e: RuntimeException) {
            Rlog.w(logTag, "Could not read LTE identity for SIP access headers", e)
            emptyMap()
        }
    }

    internal fun lteHeaders(
        mcc: String?,
        mnc: String?,
        tac: Int,
        ci: Int,
        visitedNetworkId: String?,
    ): SipHeadersMap {
        val normalizedMcc = mcc
            ?.takeIf { it.length == 3 && it.all(Char::isDigit) }
            ?: return emptyMap()
        val normalizedMnc = mnc
            ?.takeIf { it.length in 2..3 && it.all(Char::isDigit) }
            ?: return emptyMap()
        if (tac !in 0..0xffff || ci !in 0..0x0fffffff) return emptyMap()

        val cellIdentity = normalizedMcc + normalizedMnc +
            tac.toString(16).padStart(4, '0') +
            ci.toString(16).padStart(7, '0')
        val headers = mutableMapOf(
            "P-Access-Network-Info" to listOf(
                "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=${cellIdentity.uppercase()}",
            ),
        )
        visitedNetworkId?.takeIf(String::isNotBlank)?.let {
            headers["P-Visited-Network-ID"] = listOf("\"$it\"")
        }
        return headers
    }
}
