//
//  WatchCommunicatorTests.swift
//  WatchCommunicatorTests
//
//  Created by Stephen O'Connor (MHP) on 10.06.21.
//

import XCTest
@testable import WatchCommunicator

struct DummyObject: JSONSerializable {
    var testString: String = "TestString"
}

enum TestError: Error {
    case failedCodable
}

class WatchCommunicatorTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // This method demonstrates how you could pass your own custom types
    func testSerializationOfAppMessageWithCodableInJSON() throws {
        
        let string = "DidItWork"
        
        let result = try verifyDecodingOfDummyObject(testString: string, ignoreTypeChecking: true)
        
        guard let decodedObject = result else {
            return XCTFail("Should have decoded this object")
        }
        
        XCTAssertEqual(decodedObject.testString, string)
    }
    
    func testIgnoreTypeCheckingWorks() throws {
        
        let string = "DidItWork"
        
        let result = try verifyDecodingOfDummyObject(testString: string, ignoreTypeChecking: false)
        
        guard result == nil else {
            return XCTFail("Should have not decoded this object because DummyObject is not a valid type for AppWatchMesage")
        }
    }
    
    private func verifyDecodingOfDummyObject(testString: String,
                                             ignoreTypeChecking: Bool) throws -> DummyObject? {
        
        
        let dummyObject = DummyObject(testString: testString)

        let type = AppWatchMessage.DataType.applicationContext
        let message = AppWatchMessage(kind: .responseMessage,
                                      dataType: type,
                                      json: dummyObject.asJSON)
        
        let encoder = JSONEncoder()
        let messageData = try encoder.encode(message)
        XCTAssertNotNil(messageData)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(AppWatchMessage.self, from: messageData)
        XCTAssertNotNil(decodedMessage)
        
        guard let decodedDummyObject = decodedMessage.decodedTypeFromJSON(DummyObject.self, ignoreTypeChecking: ignoreTypeChecking) else {
            
            return nil
        }
        return decodedDummyObject
    }
    
    func testSerializationOfMessageWithStringValue() throws {
        
        let testString = "DidIEncode"
        let type = AppWatchMessage.DataType.remoteLogStatement
        let message = AppWatchMessage(kind: .responseMessage,
                                      dataType: type,
                                      json: testString)
        
        let encoder = JSONEncoder()
        let messageData = try encoder.encode(message)
        XCTAssertNotNil(messageData)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(AppWatchMessage.self, from: messageData)
        XCTAssertNotNil(decodedMessage)
        
        guard let decodedValue = decodedMessage.decodedTypeFromJSON(String.self, ignoreTypeChecking: false) else {
            return XCTFail("Should have decoded a String")
        }
        XCTAssertEqual(decodedValue, testString)
    }
    
    func testSerializationOfMessageWithEmptyData() throws {
        
    }

}
