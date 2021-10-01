//
//  AppWatchMessage.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 10.06.21.
//

import Foundation
import WatchConnectivity

let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()


enum WatchApplicationMessageError: Swift.Error {
    case invalidJSONFormat
}

extension WatchCommunicatorMessage.UserInfoKey {
    static let contentType = "ContentType"
}

extension WatchCommunicatorMessage {
    
    // indicates how to parse the json
    // also functions as a json key for the data you want to parse
    public enum ContentType: String {
        
        /// Sort of legacy; what the old Phone-/WatchSession would send
        case watchContextData
        
        /// generally sent as a .response so that no answer is expected
        case redirectToSomeAction
        
        /// generally sent as a response since no answer is expected
        case remoteLogStatement
        
        /// if you are transferring a file
        case remoteLogFile
        
        /// If it's imageData that was transferred via a file transfer
        case imageFile
        
        /// if you're just confirming you received a message
        case confirmation
        
        // something for infusions here
        case unspecified
    }
    
    public var contentType: ContentType {
        get {
            guard let rawDataType = self.userInfo[UserInfoKey.contentType] else {
                logger.warning("UserInfo did not contain a contentType (value for key not present)")
                return .unspecified
            }
            
            guard let dataType = ContentType(rawValue: rawDataType) else {
                logger.warning("UserInfo did not contain a valid contentType.  Got: \(rawDataType)")
                return .unspecified
            }
            return dataType
        }
        set {
            var userInfo = self.userInfo
            userInfo[UserInfoKey.contentType] = newValue.rawValue
            self.userInfo = userInfo
            
            if newValue == .confirmation {
                self.isConfirmationOnly = true
            }
        }
        
    }
    
    public var fileURL: URL? {
        set {
            
            if let fileURL = newValue, fileURL.isFileURL {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(fileURL) {
                    self.jsonData = data
                    var userInfo = self.userInfo
                    userInfo[UserInfoKey.fileURLPath] = fileURL.path
                    self.userInfo = userInfo
                }
                if self.responseType != .fileTransfer {
                    logger.warning("You're setting a fileURL on a message that is not set up for file transfers.  Behaviour undefined.")
                }
                
            } else {
                var userInfo = self.userInfo
                userInfo[UserInfoKey.fileURLPath] = nil
                self.userInfo = userInfo
                self.jsonData = nil
            }
            
        } get {
            guard let path = self.userInfo[UserInfoKey.fileURLPath] else { return nil }
            return URL(fileURLWithPath: path)
        }
    }
}

extension WatchCommunicatorMessage {
    
    var decodingType: Any.Type? {
        switch contentType {
        case .watchContextData:
            return [String: Any].self // JSON.  In production use a Codable
        case .redirectToSomeAction, .remoteLogStatement, .unspecified:
            return String.self
        case .remoteLogFile, .imageFile:
            return URL.self
        case .confirmation:
            return nil
        }
    }
    
    /// This is how you get an actual type back from an `AppWatchMessage`.  If you've implemented `decodingType`, then you know what type you need to decode to get the value you're looking for.
    func decodedTypeFromJSONData<T: Codable>(_ type: T.Type, ignoreTypeChecking: Bool = false) -> T? {
        
        if !ignoreTypeChecking {
            guard type == self.decodingType else {
                logger.error("You specified the wrong type for this data type.  Expected \(String(describing: self.decodingType)) but got \(String(describing: type))")
                return nil
            }
        }
        
        guard let data = self.jsonData else {
            logger.error("Could not get JSON from message")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedObject = try decoder.decode(type, from: data)
            return decodedObject
            
        } catch let e {
            logger.error("Error decoding JSON: \(e.localizedDescription)")
            return nil
        }
    }
}

extension WatchCommunicatorMessage {
    
    public static func request(responseType: CommunicationChannel,
                               contentType: ContentType,
                               userInfo: [String: String],
                               jsonData: Data?) -> WatchCommunicatorMessage {
        
        var message = WatchCommunicatorMessage(id: UUID().uuidString,
                                            kind: .request,
                                            responseType: responseType,
                                            timestamp: Date(),
                                            userInfo: userInfo,
                                            jsonData: jsonData)
        message.contentType = contentType
        return message
    }
    
    public static func response(toMessageId requestMessageId: String?,
                                responseType: CommunicationChannel,
                                contentType: ContentType,
                                userInfo: [String: String],
                                jsonData: Data?)  -> WatchCommunicatorMessage {
        
        var message =  WatchCommunicatorMessage(id: UUID().uuidString,
                                             kind: .response(requestId: requestMessageId),
                                             responseType: responseType,
                                             timestamp: Date(),
                                             userInfo: userInfo,
                                             jsonData: jsonData)
        
        message.contentType = contentType
        return message
    }
}
