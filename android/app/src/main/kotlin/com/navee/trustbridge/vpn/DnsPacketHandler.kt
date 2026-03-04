package com.navee.trustbridge.vpn

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.util.Collections
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
        private const val REWRITE_TTL_SECONDS = 5
        private const val MAX_DOMAIN_IP_CACHE_ENTRIES = 512
        private const val MAX_ACTIVE_BLOCKED_IPS = 256
        private const val ENABLE_TTL_REWRITE = true
        private const val ENABLE_ACTIVE_TCP_RST = true
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
    private val recentDomainIps = LinkedHashMap<String, LinkedHashSet<String>>()
    private val activeBlockedDomains = linkedSetOf<String>()
    private val activelyBlockedIps = linkedSetOf<String>()

    @Synchronized
    fun updateBlockedDomains(domains: Set<String>) {
        activeBlockedDomains.clear()
        domains
            .map(::normalizeDomainForLog)
            .filter { it.isNotEmpty() && it != "<unknown>" }
            .forEach(activeBlockedDomains::add)
        recomputeActivelyBlockedIps()
    }

    @Synchronized
    fun seedActivelyBlockedIps(ips: Set<String>) {
        activelyBlockedIps.clear()
        ips
            .map(::normalizeIpv4)
            .filter { it.isNotEmpty() }
            .take(MAX_ACTIVE_BLOCKED_IPS)
            .forEach(activelyBlockedIps::add)
    }

    @Synchronized
    fun snapshotActivelyBlockedIps(): Set<String> {
        return Collections.unmodifiableSet(LinkedHashSet(activelyBlockedIps))
    }

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
        val sourceIp: String,
        val destPort: Int,
        val destIp: String,
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
            val ipHeaderLength = (packet[0].toInt() and 0x0F) * 4
            val sourceIp = packet.copyOfRange(12, 16)
            val destIp = packet.copyOfRange(16, 20)
            val sourceIpText = try {
                InetAddress.getByAddress(sourceIp).hostAddress ?: ""
            } catch (_: Exception) {
                ""
            }
            val destIpText = try {
                InetAddress.getByAddress(destIp).hostAddress ?: ""
            } catch (_: Exception) {
                ""
            }

            if (protocol == 6) {
                return handleTcpPacket(
                    packet = packet,
                    length = length,
                    ipHeaderLength = ipHeaderLength,
                    sourceIp = sourceIp,
                    destIp = destIp,
                    sourceIpText = sourceIpText,
                    destIpText = destIpText
                )
            }

            if (protocol != 17) { // DNS-over-UDP only
                return null
            }
            if (length < ipHeaderLength + 8) {
                return null
            }

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
                        sourceIp = sourceIpText,
                        destPort = destPort,
                        destIp = destIpText,
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
                Log.i(
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
                forwardToUpstreamDns(
                    query = dnsQuery,
                    queriedDomain = normalizedDomain
                )
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

    private fun forwardToUpstreamDns(
        query: ByteArray,
        queriedDomain: String
    ): ByteArray {
        val primaryResponse = queryUpstream(
            host = upstreamDns,
            query = query,
            timeoutMs = PRIMARY_TIMEOUT_MS
        )
        if (primaryResponse != null) {
            return rewriteAndCacheUpstreamResponse(
                response = primaryResponse,
                queriedDomain = queriedDomain
            )
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
                return rewriteAndCacheUpstreamResponse(
                    response = fallbackResponse,
                    queriedDomain = queriedDomain
                )
            }
        }

        Log.e(
            TAG,
            "Failed to resolve via primary upstream '$upstreamDns'" +
                if (useFallback) " and fallback '$FALLBACK_DNS'" else ""
        )
        return createBlockedResponse(query)
    }

    private fun rewriteAndCacheUpstreamResponse(
        response: ByteArray,
        queriedDomain: String
    ): ByteArray {
        val rewritten = if (ENABLE_TTL_REWRITE) {
            rewriteDnsResponseTtl(
                response = response,
                ttlSeconds = REWRITE_TTL_SECONDS
            )
        } else {
            response
        }
        val resolvedIps = extractIpv4AnswerIps(rewritten)
        if (resolvedIps.isNotEmpty()) {
            rememberDomainIps(
                domain = queriedDomain,
                ips = resolvedIps
            )
        }
        return rewritten
    }

    private fun handleTcpPacket(
        packet: ByteArray,
        length: Int,
        ipHeaderLength: Int,
        sourceIp: ByteArray,
        destIp: ByteArray,
        sourceIpText: String,
        destIpText: String
    ): ByteArray? {
        if (!ENABLE_ACTIVE_TCP_RST) {
            return null
        }
        if (ipHeaderLength < 20 || length < ipHeaderLength + 20) {
            return null
        }

        val normalizedDestIp = normalizeIpv4(destIpText)
        if (normalizedDestIp.isEmpty() || !isActivelyBlockedIp(normalizedDestIp)) {
            return null
        }

        val tcpOffset = ipHeaderLength
        val sourcePort = readUInt16(packet, tcpOffset)
        val destPort = readUInt16(packet, tcpOffset + 2)
        val sequenceNumber = readUInt32(packet, tcpOffset + 4)
        val acknowledgementNumber = readUInt32(packet, tcpOffset + 8)
        val tcpHeaderLength = ((packet[tcpOffset + 12].toInt() ushr 4) and 0x0F) * 4
        if (tcpHeaderLength < 20 || length < tcpOffset + tcpHeaderLength) {
            return null
        }

        val flags = packet[tcpOffset + 13].toInt() and 0xFF
        if ((flags and 0x04) != 0) { // Ignore packets that are already RST.
            return null
        }

        val totalLength = readUInt16(packet, 2)
        val payloadLength = (totalLength - ipHeaderLength - tcpHeaderLength).coerceAtLeast(0)
        val syn = (flags and 0x02) != 0
        val fin = (flags and 0x01) != 0
        val ackIncrement = payloadLength +
            if (syn) 1 else 0 +
            if (fin) 1 else 0

        val rstSequence = if ((flags and 0x10) != 0) { // ACK present.
            acknowledgementNumber
        } else {
            0
        }
        val rstAck = (sequenceNumber + ackIncrement) and 0xFFFFFFFFL

        Log.i(
            TAG,
            "RST active session ip=$normalizedDestIp src=$sourceIpText:$sourcePort dst=$destIpText:$destPort"
        )
        return buildTcpRstResponse(
            sourceIp = sourceIp,
            destIp = destIp,
            sourcePort = sourcePort,
            destPort = destPort,
            sequenceNumber = rstSequence,
            acknowledgementNumber = rstAck
        )
    }

    private fun buildTcpRstResponse(
        sourceIp: ByteArray,
        destIp: ByteArray,
        sourcePort: Int,
        destPort: Int,
        sequenceNumber: Long,
        acknowledgementNumber: Long
    ): ByteArray {
        val ipHeaderLength = 20
        val tcpHeaderLength = 20
        val totalLength = ipHeaderLength + tcpHeaderLength
        val packet = ByteBuffer.allocate(totalLength)

        // IPv4 header
        packet.put(0x45.toByte()) // Version + IHL
        packet.put(0x00.toByte()) // DSCP/ECN
        packet.putShort(totalLength.toShort())
        packet.putShort(0x0000) // Identification
        packet.putShort(0x4000.toShort()) // Don't fragment
        packet.put(64.toByte()) // TTL
        packet.put(6.toByte()) // TCP
        packet.putShort(0x0000) // IPv4 checksum placeholder
        packet.put(destIp) // Response source (remote)
        packet.put(sourceIp) // Response destination (local app)

        // TCP header
        packet.putShort(destPort.toShort()) // Source port (remote)
        packet.putShort(sourcePort.toShort()) // Destination port (local app)
        packet.putInt((sequenceNumber and 0xFFFFFFFFL).toInt())
        packet.putInt((acknowledgementNumber and 0xFFFFFFFFL).toInt())
        packet.put(0x50.toByte()) // Data offset = 5, no options
        packet.put(0x14.toByte()) // RST + ACK
        packet.putShort(0x0000) // Window size
        packet.putShort(0x0000) // TCP checksum placeholder
        packet.putShort(0x0000) // Urgent pointer

        val bytes = packet.array()
        val ipChecksum = calculateIpv4Checksum(bytes, ipHeaderLength)
        bytes[10] = ((ipChecksum ushr 8) and 0xFF).toByte()
        bytes[11] = (ipChecksum and 0xFF).toByte()

        val tcpChecksum = calculateTcpChecksum(
            packet = bytes,
            ipHeaderLength = ipHeaderLength,
            tcpLength = tcpHeaderLength
        )
        bytes[ipHeaderLength + 16] = ((tcpChecksum ushr 8) and 0xFF).toByte()
        bytes[ipHeaderLength + 17] = (tcpChecksum and 0xFF).toByte()
        return bytes
    }

    private fun calculateTcpChecksum(
        packet: ByteArray,
        ipHeaderLength: Int,
        tcpLength: Int
    ): Int {
        val pseudoHeader = ByteBuffer.allocate(12 + tcpLength)
        pseudoHeader.put(packet, 12, 8) // Source + destination IP
        pseudoHeader.put(0x00.toByte())
        pseudoHeader.put(0x06.toByte()) // Protocol TCP
        pseudoHeader.putShort(tcpLength.toShort())
        pseudoHeader.put(packet, ipHeaderLength, tcpLength)

        val checksumData = pseudoHeader.array()
        var sum = 0L
        var index = 0
        while (index + 1 < checksumData.size) {
            val word = ((checksumData[index].toInt() and 0xFF) shl 8) or
                (checksumData[index + 1].toInt() and 0xFF)
            sum += word.toLong()
            while ((sum ushr 16) != 0L) {
                sum = (sum and 0xFFFF) + (sum ushr 16)
            }
            index += 2
        }
        if (index < checksumData.size) {
            sum += ((checksumData[index].toInt() and 0xFF) shl 8).toLong()
            while ((sum ushr 16) != 0L) {
                sum = (sum and 0xFFFF) + (sum ushr 16)
            }
        }
        return sum.inv().toInt() and 0xFFFF
    }

    private fun rewriteDnsResponseTtl(
        response: ByteArray,
        ttlSeconds: Int
    ): ByteArray {
        if (response.size < 12) {
            return response
        }
        val rewritten = response.copyOf()
        val qdCount = readUInt16(rewritten, 4)
        val anCount = readUInt16(rewritten, 6)
        val nsCount = readUInt16(rewritten, 8)
        val arCount = readUInt16(rewritten, 10)

        var offset = 12
        repeat(qdCount) {
            offset = skipDnsName(rewritten, offset) ?: return response
            if (offset + 4 > rewritten.size) {
                return response
            }
            offset += 4 // QTYPE + QCLASS
        }

        val ttlValue = ttlSeconds.coerceAtLeast(0)
        val recordCount = anCount + nsCount + arCount
        repeat(recordCount) {
            offset = skipDnsName(rewritten, offset) ?: return response
            if (offset + 10 > rewritten.size) {
                return response
            }
            rewritten[offset + 4] = ((ttlValue ushr 24) and 0xFF).toByte()
            rewritten[offset + 5] = ((ttlValue ushr 16) and 0xFF).toByte()
            rewritten[offset + 6] = ((ttlValue ushr 8) and 0xFF).toByte()
            rewritten[offset + 7] = (ttlValue and 0xFF).toByte()

            val rdLength = readUInt16(rewritten, offset + 8)
            offset += 10
            if (offset + rdLength > rewritten.size) {
                return response
            }
            offset += rdLength
        }
        return rewritten
    }

    private fun extractIpv4AnswerIps(response: ByteArray): Set<String> {
        if (response.size < 12) {
            return emptySet()
        }
        val qdCount = readUInt16(response, 4)
        val anCount = readUInt16(response, 6)

        var offset = 12
        repeat(qdCount) {
            offset = skipDnsName(response, offset) ?: return emptySet()
            if (offset + 4 > response.size) {
                return emptySet()
            }
            offset += 4
        }

        val resolved = linkedSetOf<String>()
        repeat(anCount) {
            offset = skipDnsName(response, offset) ?: return@repeat
            if (offset + 10 > response.size) {
                return@repeat
            }
            val type = readUInt16(response, offset)
            val rdLength = readUInt16(response, offset + 8)
            val rdataOffset = offset + 10
            if (rdataOffset + rdLength > response.size) {
                return@repeat
            }
            if (type == 0x0001 && rdLength == 4) { // A record
                val ip = try {
                    normalizeIpv4(
                        InetAddress.getByAddress(
                            response.copyOfRange(rdataOffset, rdataOffset + 4)
                        ).hostAddress ?: ""
                    )
                } catch (_: Exception) {
                    ""
                }
                if (ip.isNotEmpty()) {
                    resolved.add(ip)
                }
            }
            offset = rdataOffset + rdLength
        }
        return resolved
    }

    @Synchronized
    private fun rememberDomainIps(
        domain: String,
        ips: Set<String>
    ) {
        val normalizedDomain = normalizeDomainForLog(domain)
        if (normalizedDomain.isEmpty() || normalizedDomain == "<unknown>") {
            return
        }
        if (ips.isEmpty()) {
            return
        }
        val normalizedIps = ips
            .map(::normalizeIpv4)
            .filter { it.isNotEmpty() }
            .toCollection(linkedSetOf())
        if (normalizedIps.isEmpty()) {
            return
        }

        recentDomainIps[normalizedDomain] = LinkedHashSet(normalizedIps)
        while (recentDomainIps.size > MAX_DOMAIN_IP_CACHE_ENTRIES) {
            val oldestKey = recentDomainIps.keys.firstOrNull() ?: break
            recentDomainIps.remove(oldestKey)
        }
        if (activeBlockedDomains.contains(normalizedDomain)) {
            normalizedIps.forEach(activelyBlockedIps::add)
            trimActivelyBlockedIps()
        }
    }

    @Synchronized
    private fun recomputeActivelyBlockedIps() {
        activelyBlockedIps.clear()
        for ((domain, ips) in recentDomainIps) {
            val shouldForceBlock = activeBlockedDomains.contains(domain) || filterEngine.shouldBlock(domain)
            if (!shouldForceBlock) {
                continue
            }
            ips.forEach(activelyBlockedIps::add)
            if (activelyBlockedIps.size >= MAX_ACTIVE_BLOCKED_IPS) {
                break
            }
        }
        trimActivelyBlockedIps()
    }

    @Synchronized
    private fun trimActivelyBlockedIps() {
        while (activelyBlockedIps.size > MAX_ACTIVE_BLOCKED_IPS) {
            val oldest = activelyBlockedIps.firstOrNull() ?: break
            activelyBlockedIps.remove(oldest)
        }
    }

    @Synchronized
    private fun isActivelyBlockedIp(ip: String): Boolean {
        return activelyBlockedIps.contains(normalizeIpv4(ip))
    }

    private fun skipDnsName(packet: ByteArray, startOffset: Int): Int? {
        var offset = startOffset
        var jumps = 0
        while (offset < packet.size) {
            val length = packet[offset].toInt() and 0xFF
            if (length == 0) {
                return offset + 1
            }
            if ((length and 0xC0) == 0xC0) {
                if (offset + 1 >= packet.size) {
                    return null
                }
                return offset + 2
            }
            if (length > 63) {
                return null
            }
            offset += 1 + length
            jumps += 1
            if (jumps > 128) {
                return null
            }
        }
        return null
    }

    private fun normalizeIpv4(rawIp: String): String {
        return rawIp.substringBefore('%').trim()
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

    private fun readUInt32(bytes: ByteArray, offset: Int): Long {
        return ((bytes[offset].toLong() and 0xFF) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
            (bytes[offset + 3].toLong() and 0xFF)
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
