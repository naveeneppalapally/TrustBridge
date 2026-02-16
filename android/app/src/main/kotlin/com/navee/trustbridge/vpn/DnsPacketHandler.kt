package com.navee.trustbridge.vpn

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import kotlin.math.min

class DnsPacketHandler(
    private val filterEngine: DnsFilterEngine,
    private val upstreamDns: String = "8.8.8.8",
    private val protectSocket: ((DatagramSocket) -> Unit)? = null
) {
    companion object {
        private const val TAG = "DnsPacketHandler"
        private const val DNS_PORT = 53
        private const val TIMEOUT_MS = 5_000
    }

    private val upstreamSocket: DatagramSocket = DatagramSocket().apply {
        soTimeout = TIMEOUT_MS
        protectSocket?.invoke(this)
    }

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
            val domain = parseDomainName(dnsQuery)
            val isBlocked = filterEngine.shouldBlock(domain)

            val dnsResponse = if (isBlocked) {
                Log.d(TAG, "BLOCKED domain=$domain")
                createBlockedResponse(dnsQuery)
            } else {
                Log.d(TAG, "ALLOWED domain=$domain")
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

    fun close() {
        try {
            upstreamSocket.close()
        } catch (_: Exception) {
            // ignore
        }
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
        val responseHeaderAndQuestion = query.copyOfRange(0, questionEnd)

        // Set response flags (QR=1, RD copied, RA=1, RCODE=0)
        responseHeaderAndQuestion[2] =
            (responseHeaderAndQuestion[2].toInt() or 0x80).toByte()
        responseHeaderAndQuestion[3] = 0x80.toByte()

        // ANCOUNT = 1
        responseHeaderAndQuestion[6] = 0x00
        responseHeaderAndQuestion[7] = 0x01

        val answer = byteArrayOf(
            0xC0.toByte(), 0x0C.toByte(), // Name pointer
            0x00, 0x01, // Type A
            0x00, 0x01, // Class IN
            0x00, 0x00, 0x00, 0x3C, // TTL 60s
            0x00, 0x04, // RDLENGTH
            0x00, 0x00, 0x00, 0x00 // 0.0.0.0
        )

        return responseHeaderAndQuestion + answer
    }

    private fun forwardToUpstreamDns(query: ByteArray): ByteArray {
        return try {
            val upstreamAddress = InetAddress.getByName(upstreamDns)
            val outboundPacket = DatagramPacket(query, query.size, upstreamAddress, DNS_PORT)
            upstreamSocket.send(outboundPacket)

            val receiveBuffer = ByteArray(4096)
            val inboundPacket = DatagramPacket(receiveBuffer, receiveBuffer.size)
            upstreamSocket.receive(inboundPacket)

            receiveBuffer.copyOf(inboundPacket.length)
        } catch (error: Exception) {
            Log.e(TAG, "Failed to forward DNS query. Falling back to blocked response.", error)
            createBlockedResponse(query)
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
}
