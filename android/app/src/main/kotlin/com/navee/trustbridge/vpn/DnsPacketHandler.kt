package com.navee.trustbridge.vpn

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.LinkedHashMap
import kotlin.math.min

class DnsPacketHandler(
    private val filterEngine: DnsFilterEngine,
    private val upstreamDns: String = "1.1.1.1",
    private val protectSocket: ((DatagramSocket) -> Unit)? = null,
    private val onBlockedDomain: ((String) -> Unit)? = null,
    private val onQueryObserved: ((QueryObservation) -> Unit)? = null
) {
    companion object {
        private const val TAG = "DnsPacketHandler"
        private const val DNS_PORT = 53
        private const val FALLBACK_DNS = "8.8.8.8"
        private const val PRIMARY_TIMEOUT_MS = 450
        private const val FALLBACK_TIMEOUT_MS = 350
        private const val RECEIVE_BUFFER_SIZE = 4096
        private const val MAX_QUERY_LOG_ENTRIES = 250
        private const val BLOCKED_DEDUP_WINDOW_MS = 1_000L
        private const val MAX_BLOCKED_DEDUP_ENTRIES = 512
    }

    @Volatile
    private var processedQueries: Long = 0

    @Volatile
    private var blockedQueries: Long = 0

    @Volatile
    private var allowedQueries: Long = 0

    @Volatile
    private var upstreamFailures: Long = 0

    @Volatile
    private var fallbackQueries: Long = 0

    private val recentQueries = ArrayDeque<QueryLogEntry>()
    private val recentBlockedDomains = LinkedHashMap<String, Long>()

    data class PacketStats(
        val processedQueries: Long,
        val blockedQueries: Long,
        val allowedQueries: Long,
        val upstreamFailures: Long,
        val fallbackQueries: Long
    )

    data class QueryLogEntry(
        val domain: String,
        val sourcePort: Int,
        val blocked: Boolean,
        val reasonCode: String,
        val matchedRule: String?,
        val timestampEpochMs: Long
    )

    data class QueryObservation(
        val domain: String,
        val sourcePort: Int,
        val blocked: Boolean,
        val reasonCode: String,
        val matchedRule: String?
    )

    fun handlePacket(packet: ByteArray, length: Int): ByteArray? {
        try {
            if (length < 28) {
                return null
            }

            val ipVersion = (packet[0].toInt() ushr 4) and 0x0F
            if (ipVersion != 4) {
                return null
            }

            val protocol = packet[9].toInt() and 0xFF
            if (protocol != 17) { // UDP only
                return null
            }

            val ipHeaderLength = (packet[0].toInt() and 0x0F) * 4
            if (length < ipHeaderLength + 8) {
                return null
            }

            val sourceIp = packet.copyOfRange(12, 16)
            val destIp = packet.copyOfRange(16, 20)

            val udpOffset = ipHeaderLength
            val sourcePort = readUInt16(packet, udpOffset)
            val destPort = readUInt16(packet, udpOffset + 2)
            val udpLength = readUInt16(packet, udpOffset + 4)
            if (destPort != DNS_PORT || udpLength < 8) {
                return null
            }

            val dnsOffset = udpOffset + 8
            val dnsLength = min(udpLength - 8, length - dnsOffset)
            if (dnsLength <= 0 || dnsOffset + dnsLength > length) {
                return null
            }

            val dnsQuery = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
            val parsedDomain = parseDomainName(dnsQuery)
            val normalizedDomain = normalizeDomainForLog(parsedDomain)
            val decision = filterEngine.evaluateBlockDecision(parsedDomain)
            val isBlocked = decision.blocked

            if (isBlocked) {
                incrementBlockedQuery(normalizedDomain)
            } else {
                incrementAllowedQuery()
            }
            if (normalizedDomain != "<unknown>") {
                onQueryObserved?.invoke(
                    QueryObservation(
                        domain = normalizedDomain,
                        sourcePort = sourcePort,
                        blocked = isBlocked,
                        reasonCode = decision.reasonCode,
                        matchedRule = decision.matchedRule
                    )
                )
            }
            appendQueryLog(
                domain = normalizedDomain,
                sourcePort = sourcePort,
                blocked = isBlocked,
                reasonCode = decision.reasonCode,
                matchedRule = decision.matchedRule
            )

            val dnsResponse = if (isBlocked) {
                Log.d(
                    TAG,
                    "BLOCKED domain=$normalizedDomain reason=${decision.reasonCode}" +
                        (decision.matchedRule?.let { " rule=$it" } ?: "")
                )
                if (normalizedDomain != "<unknown>") {
                    onBlockedDomain?.invoke(normalizedDomain)
                }
                createBlockedResponse(dnsQuery)
            } else {
                Log.d(
                    TAG,
                    "ALLOWED domain=$normalizedDomain reason=${decision.reasonCode}" +
                        (decision.matchedRule?.let { " rule=$it" } ?: "")
                )
                forwardToUpstreamDns(dnsQuery)
            }

            return buildResponsePacket(
                sourceIp = sourceIp,
                destIp = destIp,
                sourcePort = sourcePort,
                destPort = destPort,
                dnsResponse = dnsResponse
            )
        } catch (error: Exception) {
            Log.e(TAG, "Error handling DNS packet", error)
            return null
        }
    }

    @Synchronized
    fun statsSnapshot(): PacketStats {
        return PacketStats(
            processedQueries = processedQueries,
            blockedQueries = blockedQueries,
            allowedQueries = allowedQueries,
            upstreamFailures = upstreamFailures,
            fallbackQueries = fallbackQueries
        )
    }

    @Synchronized
    fun recentQueriesSnapshot(limit: Int = 100): List<Map<String, Any>> {
        if (recentQueries.isEmpty()) {
            return emptyList()
        }

        val safeLimit = if (limit <= 0) 1 else limit
        val snapshot = recentQueries.toList().asReversed().take(safeLimit)
        return snapshot.map { entry ->
            buildMap<String, Any> {
                put("domain", entry.domain)
                put("sourcePort", entry.sourcePort)
                put("blocked", entry.blocked)
                put("reasonCode", entry.reasonCode)
                if (!entry.matchedRule.isNullOrBlank()) {
                    put("matchedRule", entry.matchedRule)
                }
                put("timestampEpochMs", entry.timestampEpochMs)
            }
        }
    }

    @Synchronized
    fun clearRecentQueries() {
        recentQueries.clear()
    }

    fun close() {
        // No shared socket to close. Per-query sockets are created on demand.
    }

    private fun parseDomainName(dnsQuery: ByteArray): String {
        if (dnsQuery.size < 17) {
            return ""
        }

        val labels = mutableListOf<String>()
        var offset = 12
        while (offset < dnsQuery.size) {
            val labelLength = dnsQuery[offset].toInt() and 0xFF
            offset += 1
            if (labelLength == 0) {
                break
            }
            if (labelLength > 63 || offset + labelLength > dnsQuery.size) {
                return ""
            }
            labels.add(String(dnsQuery, offset, labelLength))
            offset += labelLength
        }
        return labels.joinToString(".").lowercase()
    }

    private fun createBlockedResponse(query: ByteArray): ByteArray {
        if (query.size < 12) {
            return query
        }

        val questionEnd = findQuestionEndOffset(query) ?: return query
        val queryTypeOffset = questionEnd - 4
        val queryClassOffset = questionEnd - 2
        val queryType = readUInt16(query, queryTypeOffset)
        val queryClass = readUInt16(query, queryClassOffset)

        val header = query.copyOfRange(0, questionEnd)

        // Set response flags: QR=1, AA=1, RCODE=0 (no error)
        header[2] = (header[2].toInt() or 0x84).toByte() // QR=1 + AA=1
        header[3] = (header[3].toInt() and 0xF0.toInt()).toByte() // RCODE=0

        // We only include the question section in this synthetic response.
        // Reset section counts to match the payload we actually return.
        header[4] = 0x00 // QDCOUNT = 1 (single-question queries only)
        header[5] = 0x01
        header[8] = 0x00 // NSCOUNT = 0
        header[9] = 0x00
        header[10] = 0x00 // ARCOUNT = 0 (drop EDNS/additional records)
        header[11] = 0x00

        val answer = when (queryType) {
            0x0001 -> buildBlockedAnswerSection( // A
                queryType = queryType,
                queryClass = queryClass,
                rdata = byteArrayOf(0x00, 0x00, 0x00, 0x00) // 0.0.0.0
            )
            0x001C -> buildBlockedAnswerSection( // AAAA
                queryType = queryType,
                queryClass = queryClass,
                rdata = ByteArray(16) // ::
            )
            else -> null
        }

        if (answer == null) {
            // Valid NOERROR/NODATA response. This avoids malformed answer-type
            // mismatches that can cause resolvers to retry or bypass.
            header[6] = 0x00 // ANCOUNT = 0
            header[7] = 0x00
            return header
        }

        // Valid answer response with TTL=0 so policy flips are not cached.
        header[6] = 0x00 // ANCOUNT = 1
        header[7] = 0x01
        val result = ByteArray(header.size + answer.size)
        System.arraycopy(header, 0, result, 0, header.size)
        System.arraycopy(answer, 0, result, header.size, answer.size)
        return result
    }

    private fun buildBlockedAnswerSection(
        queryType: Int,
        queryClass: Int,
        rdata: ByteArray
    ): ByteArray {
        val rdLength = rdata.size
        val answer = ByteBuffer.allocate(2 + 2 + 2 + 4 + 2 + rdLength)
        answer.put(0xC0.toByte()) // name pointer to question
        answer.put(0x0C)
        answer.putShort(queryType.toShort())
        answer.putShort(queryClass.toShort())
        answer.putInt(0) // TTL = 0 seconds
        answer.putShort(rdLength.toShort())
        answer.put(rdata)
        return answer.array()
    }

    private fun forwardToUpstreamDns(query: ByteArray): ByteArray {
        val primaryResponse = queryUpstream(
            host = upstreamDns,
            query = query,
            timeoutMs = PRIMARY_TIMEOUT_MS
        )
        if (primaryResponse != null) {
            return primaryResponse
        }

        incrementUpstreamFailure()

        val useFallback = !upstreamDns.equals(FALLBACK_DNS, ignoreCase = true)
        if (useFallback) {
            incrementFallbackQuery()
            val fallbackResponse = queryUpstream(
                host = FALLBACK_DNS,
                query = query,
                timeoutMs = FALLBACK_TIMEOUT_MS
            )
            if (fallbackResponse != null) {
                Log.w(
                    TAG,
                    "Primary upstream DNS failed for '$upstreamDns'. Served via fallback '$FALLBACK_DNS'."
                )
                return fallbackResponse
            }
        }

        Log.e(
            TAG,
            "Failed to resolve via primary upstream '$upstreamDns'" +
                if (useFallback) " and fallback '$FALLBACK_DNS'" else ""
        )
        return createBlockedResponse(query)
    }

    private fun queryUpstream(host: String, query: ByteArray, timeoutMs: Int): ByteArray? {
        if (timeoutMs <= 0) {
            return null
        }
        return try {
            val upstreamAddress = InetAddress.getByName(host)
            val expectedTransactionId = readUInt16(query, 0)
            var matchedResponse: ByteArray? = null
            DatagramSocket().use { socket ->
                socket.soTimeout = timeoutMs
                protectSocket?.invoke(socket)

                val outboundPacket =
                    DatagramPacket(query, query.size, upstreamAddress, DNS_PORT)
                socket.send(outboundPacket)

                val receiveBuffer = ByteArray(RECEIVE_BUFFER_SIZE)
                val deadline = System.currentTimeMillis() + timeoutMs.toLong()
                while (true) {
                    val now = System.currentTimeMillis()
                    if (now >= deadline) {
                        break
                    }

                    val remainingMs = (deadline - now).coerceAtLeast(1L).toInt()
                    socket.soTimeout = remainingMs
                    val inboundPacket = DatagramPacket(receiveBuffer, receiveBuffer.size)
                    try {
                        socket.receive(inboundPacket)
                    } catch (_: SocketTimeoutException) {
                        break
                    }

                    if (inboundPacket.length < 2) {
                        continue
                    }
                    val response = receiveBuffer.copyOf(inboundPacket.length)
                    val responseTransactionId = readUInt16(response, 0)
                    if (responseTransactionId != expectedTransactionId) {
                        // Ignore stale/unrelated responses and keep waiting.
                        continue
                    }
                    matchedResponse = response
                    break
                }
            }
            matchedResponse
        } catch (_: Exception) {
            null
        }
    }

    private fun buildResponsePacket(
        sourceIp: ByteArray,
        destIp: ByteArray,
        sourcePort: Int,
        destPort: Int,
        dnsResponse: ByteArray
    ): ByteArray {
        val totalLength = 20 + 8 + dnsResponse.size
        val packet = ByteBuffer.allocate(totalLength)

        // IPv4 header
        packet.put(0x45.toByte()) // version + IHL
        packet.put(0x00.toByte()) // DSCP/ECN
        packet.putShort(totalLength.toShort())
        packet.putShort(0x0000) // identification
        packet.putShort(0x4000.toShort()) // don't fragment
        packet.put(64.toByte()) // TTL
        packet.put(17.toByte()) // UDP
        packet.putShort(0x0000) // checksum placeholder
        packet.put(destIp) // source for response
        packet.put(sourceIp) // destination for response

        // UDP header
        packet.putShort(destPort.toShort()) // source port (53)
        packet.putShort(sourcePort.toShort()) // destination port
        packet.putShort((8 + dnsResponse.size).toShort())
        packet.putShort(0x0000) // checksum omitted

        packet.put(dnsResponse)

        val bytes = packet.array()
        val checksum = calculateIpv4Checksum(bytes, 20)
        bytes[10] = ((checksum ushr 8) and 0xFF).toByte()
        bytes[11] = (checksum and 0xFF).toByte()
        return bytes
    }

    private fun calculateIpv4Checksum(packet: ByteArray, headerLength: Int): Int {
        var sum = 0L
        var i = 0
        while (i < headerLength) {
            val high = packet[i].toInt() and 0xFF
            val low = packet[i + 1].toInt() and 0xFF
            sum += ((high shl 8) or low).toLong()
            i += 2
        }
        while ((sum ushr 16) != 0L) {
            sum = (sum and 0xFFFF) + (sum ushr 16)
        }
        return sum.inv().toInt() and 0xFFFF
    }

    private fun readUInt16(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 8) or
            (bytes[offset + 1].toInt() and 0xFF)
    }

    private fun findQuestionEndOffset(query: ByteArray): Int? {
        var offset = 12
        while (offset < query.size) {
            val labelLength = query[offset].toInt() and 0xFF
            offset += 1
            if (labelLength == 0) {
                break
            }
            if (labelLength > 63 || offset + labelLength > query.size) {
                return null
            }
            offset += labelLength
        }
        if (offset + 4 > query.size) {
            return null
        }
        return offset + 4
    }

    @Synchronized
    private fun incrementBlockedQuery(domain: String) {
        processedQueries += 1
        val now = System.currentTimeMillis()
        val lastBlockedAt = recentBlockedDomains[domain]
        if (lastBlockedAt == null || now - lastBlockedAt >= BLOCKED_DEDUP_WINDOW_MS) {
            blockedQueries += 1
        }
        recentBlockedDomains[domain] = now
        if (recentBlockedDomains.size > MAX_BLOCKED_DEDUP_ENTRIES) {
            val iterator = recentBlockedDomains.entries.iterator()
            if (iterator.hasNext()) {
                iterator.next()
                iterator.remove()
            }
        }
    }

    @Synchronized
    private fun incrementAllowedQuery() {
        processedQueries += 1
        allowedQueries += 1
    }

    @Synchronized
    private fun appendQueryLog(
        domain: String,
        sourcePort: Int,
        blocked: Boolean,
        reasonCode: String,
        matchedRule: String?
    ) {
        if (recentQueries.size >= MAX_QUERY_LOG_ENTRIES) {
            recentQueries.removeFirst()
        }
        recentQueries.addLast(
            QueryLogEntry(
                domain = domain,
                sourcePort = sourcePort,
                blocked = blocked,
                reasonCode = reasonCode,
                matchedRule = matchedRule?.trim()?.takeIf { it.isNotEmpty() },
                timestampEpochMs = System.currentTimeMillis()
            )
        )
    }

    @Synchronized
    private fun incrementUpstreamFailure() {
        upstreamFailures += 1
    }

    @Synchronized
    private fun incrementFallbackQuery() {
        fallbackQueries += 1
    }

    private fun normalizeDomainForLog(rawDomain: String): String {
        val normalized = rawDomain.trim().lowercase()
        return if (normalized.isEmpty()) "<unknown>" else normalized
    }
}
