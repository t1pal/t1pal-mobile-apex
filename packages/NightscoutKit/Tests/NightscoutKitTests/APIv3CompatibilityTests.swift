// APIv3CompatibilityTests.swift - NS API v3 compatibility
// Part of NightscoutKit
// Trace: NS-COMPAT-007

import Testing
import Foundation
@testable import NightscoutKit

@Suite("Nightscout API v3 Compatibility")
struct APIv3CompatibilityTests {
    
    // MARK: - API v3 Entry Format
    
    @Test("Parse API v3 entry format")
    func parseV3Entry() throws {
        // API v3 uses different field names
        let json = """
        {
            "identifier": "entry-abc123",
            "date": 1738800000000,
            "utcOffset": -300,
            "app": "xDrip+",
            "device": "DexcomG6",
            "type": "sgv",
            "sgv": 142,
            "direction": "Flat",
            "noise": 1,
            "filtered": 142000,
            "unfiltered": 145000,
            "rssi": -65,
            "sysTime": "2026-02-05T20:00:00.000Z",
            "isValid": true,
            "subject": "glucose"
        }
        """.data(using: .utf8)!
        
        // Test that we can decode v3 format
        struct V3Entry: Decodable {
            let identifier: String?
            let date: Int64
            let utcOffset: Int?
            let app: String?
            let device: String?
            let type: String
            let sgv: Int
            let direction: String?
            let noise: Int?
            let filtered: Int?
            let unfiltered: Int?
            let rssi: Int?
            let sysTime: String?
            let isValid: Bool?
            let subject: String?
        }
        
        let entry = try JSONDecoder().decode(V3Entry.self, from: json)
        
        #expect(entry.identifier == "entry-abc123")
        #expect(entry.sgv == 142)
        #expect(entry.type == "sgv")
        #expect(entry.app == "xDrip+")
        #expect(entry.isValid == true)
    }
    
    @Test("Parse API v3 treatment format")
    func parseV3Treatment() throws {
        let json = """
        {
            "identifier": "treatment-xyz789",
            "date": 1738800000000,
            "utcOffset": -300,
            "app": "Loop",
            "eventType": "Correction Bolus",
            "insulin": 2.5,
            "created_at": "2026-02-05T20:00:00.000Z",
            "enteredBy": "Loop",
            "reason": "High correction",
            "notes": "Auto-bolus",
            "isValid": true,
            "subject": "treatments"
        }
        """.data(using: .utf8)!
        
        struct V3Treatment: Decodable {
            let identifier: String?
            let date: Int64?
            let utcOffset: Int?
            let app: String?
            let eventType: String
            let insulin: Double?
            let created_at: String?
            let enteredBy: String?
            let reason: String?
            let notes: String?
            let isValid: Bool?
            let subject: String?
        }
        
        let treatment = try JSONDecoder().decode(V3Treatment.self, from: json)
        
        #expect(treatment.identifier == "treatment-xyz789")
        #expect(treatment.insulin == 2.5)
        #expect(treatment.eventType == "Correction Bolus")
        #expect(treatment.isValid == true)
    }
    
    // MARK: - API v3 Response Envelope
    
    @Test("Parse API v3 response envelope")
    func parseV3ResponseEnvelope() throws {
        let json = """
        {
            "status": 200,
            "result": [
                {"identifier": "1", "sgv": 120, "date": 1738800000000, "type": "sgv"},
                {"identifier": "2", "sgv": 125, "date": 1738800300000, "type": "sgv"}
            ],
            "lastModified": 1738800300000
        }
        """.data(using: .utf8)!
        
        struct V3Response<T: Decodable>: Decodable {
            let status: Int
            let result: T
            let lastModified: Int64?
        }
        
        struct V3Entry: Decodable {
            let identifier: String
            let sgv: Int
            let date: Int64
            let type: String
        }
        
        let response = try JSONDecoder().decode(V3Response<[V3Entry]>.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.result.count == 2)
        #expect(response.lastModified == 1738800300000)
    }
    
    @Test("Parse API v3 error response")
    func parseV3ErrorResponse() throws {
        let json = """
        {
            "status": 401,
            "message": "Unauthorized",
            "description": "Missing or invalid token"
        }
        """.data(using: .utf8)!
        
        struct V3Error: Decodable {
            let status: Int
            let message: String
            let description: String?
        }
        
        let error = try JSONDecoder().decode(V3Error.self, from: json)
        
        #expect(error.status == 401)
        #expect(error.message == "Unauthorized")
    }
    
    // MARK: - API v3 Profile Format
    
    @Test("Parse API v3 profile format")
    func parseV3Profile() throws {
        let json = """
        {
            "identifier": "profile-001",
            "date": 1738713600000,
            "utcOffset": 0,
            "app": "Nightscout",
            "subject": "profile",
            "isValid": true,
            "profileJson": {
                "defaultProfile": "Default",
                "startDate": "2026-02-05T00:00:00.000Z",
                "store": {
                    "Default": {
                        "dia": 6.0,
                        "basal": [{"time": "00:00", "value": 1.0}],
                        "carbratio": [{"time": "00:00", "value": 10.0}],
                        "sens": [{"time": "00:00", "value": 50.0}]
                    }
                }
            }
        }
        """.data(using: .utf8)!
        
        struct V3Profile: Decodable {
            let identifier: String?
            let date: Int64?
            let utcOffset: Int?
            let app: String?
            let subject: String?
            let isValid: Bool?
            let profileJson: NightscoutProfile?
        }
        
        let profile = try JSONDecoder().decode(V3Profile.self, from: json)
        
        #expect(profile.identifier == "profile-001")
        #expect(profile.subject == "profile")
        #expect(profile.profileJson?.defaultProfile == "Default")
    }
    
    // MARK: - API v3 DeviceStatus Format
    
    @Test("Parse API v3 devicestatus format")
    func parseV3DeviceStatus() throws {
        let json = """
        {
            "identifier": "ds-123",
            "date": 1738800000000,
            "utcOffset": -300,
            "app": "Loop",
            "device": "iPhone14,7",
            "subject": "devicestatus",
            "isValid": true,
            "uploaderBattery": 85,
            "loop": {
                "iob": {"iob": 2.5, "timestamp": "2026-02-05T20:00:00.000Z"},
                "cob": {"cob": 30},
                "predicted": {"values": [120, 115, 110, 105]},
                "enacted": {"received": true}
            }
        }
        """.data(using: .utf8)!
        
        struct V3DeviceStatus: Decodable {
            let identifier: String?
            let date: Int64?
            let utcOffset: Int?
            let app: String?
            let device: String?
            let subject: String?
            let isValid: Bool?
            let uploaderBattery: Int?
            let loop: LoopStatus?
            
            struct LoopStatus: Decodable {
                let iob: IOBStatus?
                let cob: COBStatus?
                let predicted: PredictedStatus?
                let enacted: EnactedStatus?
                
                struct IOBStatus: Decodable {
                    let iob: Double?
                    let timestamp: String?
                }
                struct COBStatus: Decodable {
                    let cob: Double?
                }
                struct PredictedStatus: Decodable {
                    let values: [Int]?
                }
                struct EnactedStatus: Decodable {
                    let received: Bool?
                }
            }
        }
        
        let status = try JSONDecoder().decode(V3DeviceStatus.self, from: json)
        
        #expect(status.identifier == "ds-123")
        #expect(status.uploaderBattery == 85)
        #expect(status.loop?.iob?.iob == 2.5)
        #expect(status.loop?.cob?.cob == 30)
    }
    
    // MARK: - API v3 Field Differences
    
    @Test("Handle v3 identifier vs v1 _id")
    func identifierVsId() throws {
        // v1 format
        let v1Json = """
        {"_id": "abc123", "sgv": 120, "date": 1738800000000, "type": "sgv"}
        """.data(using: .utf8)!
        
        // v3 format
        let v3Json = """
        {"identifier": "abc123", "sgv": 120, "date": 1738800000000, "type": "sgv"}
        """.data(using: .utf8)!
        
        struct FlexibleEntry: Decodable {
            let id: String
            let sgv: Int
            
            enum CodingKeys: String, CodingKey {
                case _id, identifier, sgv
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                sgv = try container.decode(Int.self, forKey: .sgv)
                // Try v3 identifier first, fall back to v1 _id
                if let identifier = try container.decodeIfPresent(String.self, forKey: .identifier) {
                    id = identifier
                } else {
                    id = try container.decode(String.self, forKey: ._id)
                }
            }
        }
        
        let v1Entry = try JSONDecoder().decode(FlexibleEntry.self, from: v1Json)
        let v3Entry = try JSONDecoder().decode(FlexibleEntry.self, from: v3Json)
        
        #expect(v1Entry.id == "abc123")
        #expect(v3Entry.id == "abc123")
    }
    
    @Test("Handle v3 isValid field")
    func isValidField() throws {
        let validJson = """
        {"identifier": "1", "sgv": 120, "date": 1738800000000, "type": "sgv", "isValid": true}
        """.data(using: .utf8)!
        
        let invalidJson = """
        {"identifier": "2", "sgv": 50, "date": 1738800000000, "type": "sgv", "isValid": false}
        """.data(using: .utf8)!
        
        struct V3Entry: Decodable {
            let identifier: String
            let sgv: Int
            let isValid: Bool?
        }
        
        let valid = try JSONDecoder().decode(V3Entry.self, from: validJson)
        let invalid = try JSONDecoder().decode(V3Entry.self, from: invalidJson)
        
        #expect(valid.isValid == true)
        #expect(invalid.isValid == false)
    }
    
    // MARK: - API v3 Authentication
    
    @Test("JWT token structure validation")
    func jwtTokenStructure() throws {
        // JWT format: header.payload.signature
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3NUb2tlbiI6InRlc3QtdG9rZW4iLCJpYXQiOjE3Mzg4MDAwMDAsImV4cCI6MTczODgwMzYwMH0.signature"
        
        let parts = token.split(separator: ".")
        #expect(parts.count == 3)
        
        // Header should be valid base64
        if let headerData = Data(base64Encoded: String(parts[0]) + "==") {
            let header = try JSONDecoder().decode([String: String].self, from: headerData)
            #expect(header["alg"] == "HS256")
            #expect(header["typ"] == "JWT")
        }
    }
    
    // MARK: - API Version Detection
    
    @Test("Detect API version from status endpoint")
    func detectAPIVersion() throws {
        // v1 status response
        let v1Status = """
        {
            "status": "ok",
            "name": "nightscout",
            "version": "14.2.6",
            "serverTime": "2026-02-05T20:00:00.000Z",
            "apiEnabled": true,
            "careportalEnabled": true
        }
        """.data(using: .utf8)!
        
        // v3 status response
        let v3Status = """
        {
            "status": "ok",
            "name": "nightscout",
            "version": "15.0.0",
            "apiVersion": "3.0.0",
            "serverTime": "2026-02-05T20:00:00.000Z"
        }
        """.data(using: .utf8)!
        
        struct StatusResponse: Decodable {
            let status: String
            let version: String
            let apiVersion: String?
        }
        
        let v1 = try JSONDecoder().decode(StatusResponse.self, from: v1Status)
        let v3 = try JSONDecoder().decode(StatusResponse.self, from: v3Status)
        
        #expect(v1.apiVersion == nil)
        #expect(v3.apiVersion == "3.0.0")
    }
}
