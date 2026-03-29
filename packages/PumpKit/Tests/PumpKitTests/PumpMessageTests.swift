// SPDX-License-Identifier: MIT
//
// PumpMessageTests.swift
// PumpKitTests
//
// Tests for PumpMessage framing
// Trace: RL-PROTO-003 - PumpMessage framing with address/type/CRC

import Testing
import Foundation
@testable import PumpKit

@Suite("PumpMessage Tests")
struct PumpMessageTests {
    
    // MARK: - Packet Type Tests
    
    @Test("Packet type raw values are correct")
    func packetTypeValues() throws {
        #expect(PacketType.mySentry.rawValue == 0xA2)
        #expect(PacketType.meter.rawValue == 0xA5)
        #expect(PacketType.carelink.rawValue == 0xA7)
        #expect(PacketType.sensor.rawValue == 0xA8)
    }
    
    // MARK: - Message Type Tests
    
    @Test("Message type raw values are correct")
    func messageTypeValues() throws {
        #expect(MessageType.pumpAck.rawValue == 0x06)
        #expect(MessageType.getBattery.rawValue == 0x72)
        #expect(MessageType.readRemainingInsulin.rawValue == 0x73)
        #expect(MessageType.getPumpModel.rawValue == 0x8D)
        #expect(MessageType.readPumpStatus.rawValue == 0xCE)
    }
    
    @Test("Expected response lengths are correct")
    func expectedResponseLengths() throws {
        #expect(MessageType.getBattery.expectedResponseLength == 4)
        #expect(MessageType.readRemainingInsulin.expectedResponseLength == 65)
        #expect(MessageType.readPumpStatus.expectedResponseLength == 3)
        #expect(MessageType.getHistoryPage.expectedResponseLength == nil)  // Variable
    }
    
    // MARK: - Message Construction Tests
    
    @Test("Create message with hex address")
    func createMessageWithHexAddress() throws {
        let msg = PumpMessage(
            packetType: .carelink,
            address: "A71234",
            messageType: .readRemainingInsulin,
            body: Data()
        )
        
        #expect(msg.packetType == .carelink)
        #expect(msg.address == Data([0xA7, 0x12, 0x34]))
        #expect(msg.messageType == .readRemainingInsulin)
        #expect(msg.body == Data())
        #expect(msg.addressHex == "A71234")
    }
    
    @Test("Create message with body")
    func createMessageWithBody() throws {
        let bodyData = Data([0x01, 0x02, 0x03])
        let msg = PumpMessage(
            address: "123456",
            messageType: .changeTempBasal,
            body: bodyData
        )
        
        #expect(msg.body == bodyData)
    }
    
    // MARK: - Transmission Data Tests
    
    @Test("TX data format is correct")
    func txDataFormat() throws {
        let msg = PumpMessage(
            packetType: .carelink,
            address: "A71234",
            messageType: .getBattery,
            body: Data()
        )
        
        let txData = msg.txData
        
        // Format: [packetType 1B][address 3B][messageType 1B]
        #expect(txData.count == 5)
        #expect(txData[0] == 0xA7)  // PacketType.carelink
        #expect(txData[1] == 0xA7)  // Address byte 0
        #expect(txData[2] == 0x12)  // Address byte 1
        #expect(txData[3] == 0x34)  // Address byte 2
        #expect(txData[4] == 0x72)  // MessageType.getBattery
    }
    
    @Test("TX data with body includes body bytes")
    func txDataWithBody() throws {
        let msg = PumpMessage(
            address: "A71234",
            messageType: .bolus,
            body: Data([0x00, 0x14])  // 2.0 units (0x14 = 20 strokes)
        )
        
        let txData = msg.txData
        #expect(txData.count == 7)  // 5 header + 2 body
        #expect(txData[5] == 0x00)
        #expect(txData[6] == 0x14)
    }
    
    // MARK: - Parse Response Tests
    
    @Test("Parse valid response")
    func parseValidResponse() throws {
        // [packetType][address 3B][messageType][body...]
        let rxData = Data([0xA7, 0xA7, 0x12, 0x34, 0x06, 0x00])  // ACK response
        
        let msg = PumpMessage(rxData: rxData)
        
        #expect(msg != nil)
        #expect(msg!.packetType == .carelink)
        #expect(msg!.address == Data([0xA7, 0x12, 0x34]))
        #expect(msg!.messageType == .pumpAck)
        #expect(msg!.body == Data([0x00]))
    }
    
    @Test("Parse too short data returns nil")
    func parseTooShort() throws {
        let rxData = Data([0xA7, 0x12, 0x34])  // Only 3 bytes, need 5
        let msg = PumpMessage(rxData: rxData)
        #expect(msg == nil)
    }
    
    @Test("Parse unknown message type")
    func parseUnknownMessageType() throws {
        // Unknown message type 0xFE
        let rxData = Data([0xA7, 0xA7, 0x12, 0x34, 0xFE, 0x01, 0x02])
        
        let msg = PumpMessage(rxData: rxData)
        
        #expect(msg != nil)
        #expect(msg!.messageType == .unknown)
        #expect(msg!.body == Data([0x01, 0x02]))
    }
    
    @Test("Meter packet is rejected")
    func parseMeterPacketRejected() throws {
        // Meter packets (0xA5) have different format, should reject
        let rxData = Data([0xA5, 0x00, 0x00, 0x00, 0x00])
        let msg = PumpMessage(rxData: rxData)
        #expect(msg == nil)
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Message round-trip encode and decode")
    func messageRoundTrip() throws {
        let original = PumpMessage(
            packetType: .carelink,
            address: "A71234",
            messageType: .readPumpStatus,
            body: Data()
        )
        
        // Serialize and parse back
        var rxData = original.txData
        // Add body for response (simulating pump reply)
        rxData.append(contentsOf: [0x03, 0x00, 0x00])  // Status response
        
        let parsed = PumpMessage(rxData: rxData)
        
        #expect(parsed != nil)
        #expect(parsed!.packetType == original.packetType)
        #expect(parsed!.address == original.address)
        #expect(parsed!.messageType == original.messageType)
    }
    
    // MARK: - MinimedPacket Integration
    
    @Test("Message with MinimedPacket encoding")
    func messageWithMinimedPacket() throws {
        let msg = PumpMessage(
            address: "A71234",
            messageType: .getBattery,
            body: Data()
        )
        
        // Wrap in MinimedPacket for 4b6b encoding
        let packet = MinimedPacket(outgoingData: msg.txData)
        let encoded = packet.encodedData()
        
        // Should be able to decode back
        let decoded = MinimedPacket(encodedData: encoded)
        #expect(decoded != nil)
        
        // Parse the message from decoded packet
        let parsedMsg = PumpMessage(rxData: decoded!.data)
        #expect(parsedMsg != nil)
        #expect(parsedMsg!.messageType == .getBattery)
    }
    
    // MARK: - Equatable Tests
    
    @Test("Message equality comparison")
    func messageEquality() throws {
        let msg1 = PumpMessage(address: "A71234", messageType: .getBattery)
        let msg2 = PumpMessage(address: "A71234", messageType: .getBattery)
        let msg3 = PumpMessage(address: "A71234", messageType: .readTime)
        
        #expect(msg1 == msg2)
        #expect(msg1 != msg3)
    }
    
    // MARK: - Message Body Tests
    
    @Test("Empty message body")
    func emptyMessageBody() throws {
        let body = EmptyMessageBody()
        #expect(body.txData == Data())
        #expect(EmptyMessageBody.length == 0)
    }
    
    @Test("Raw message body")
    func rawMessageBody() throws {
        let data = Data([0x01, 0x02, 0x03])
        let body = RawMessageBody(data: data)
        #expect(body.txData == data)
        
        let parsed = RawMessageBody(rxData: data)
        #expect(parsed != nil)
        #expect(parsed!.data == data)
    }
}
