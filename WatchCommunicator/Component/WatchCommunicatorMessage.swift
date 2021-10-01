//
//  WatchCommunicatorMessage.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 31.08.21.
//

import Foundation

public struct WatchCommunicatorMessage: Codable, Equatable, CustomDebugStringConvertible {
    
    public enum Kind: RawRepresentable, Codable, CustomDebugStringConvertible {
        
        struct Constants {
            static let request = "Request"
            static let notification = "Notification"
            static let responseTo = "ResponseTo_"
        }
        
        /// a message that expects a response
        case request
        /// a message type that is a response to a request type
        case response(requestId: String?)
        
        public init?(rawValue: String) {
            if rawValue.hasPrefix(Constants.request) {
                self = .request
            } else if rawValue.hasPrefix(Constants.notification) {
                self = .response(requestId: nil)
            } else if rawValue.hasPrefix(Constants.responseTo){
                let startIndex = rawValue.index(rawValue.startIndex, offsetBy: Constants.responseTo.count)
                let requestId = String(rawValue[startIndex...])
                self = .response(requestId: requestId)
            } else {
                return nil
            }
        }

        public var rawValue: String {
            switch self {
            case .request: return Constants.request
            case .response(let requestId):
                if let requestId = requestId {
                    return "\(Constants.responseTo)\(requestId)"
                } else {
                    return Constants.notification
                }
            }
        }
        
        public var debugDescription: String {
            switch self {
            case .request:
                return "Request"
            case .response(let requestId):
                if requestId != nil {
                    return "Response"
                } else {
                    return "Notification"
                }
            }
        }
        
        // MARK: Conveniences
        
        public var isNotification: Bool {
            if case .response(let requestId) = self, requestId == nil {
                return true
            }
            return false
        }
        public var isRequest: Bool {
            if case .request = self {
                return true
            }
            return false
        }
        public var isResponse: Bool {
            if case .response(let requestId) = self, requestId != nil {
                return true
            }
            return false
        }
    }
    
    /// Indicates which aspect of a WCSession you want to use to transmit a message.  Note, if `isReachable` is true, it will always favour the `sendMessage(...)` APIs
    public enum CommunicationChannel: Int, Codable, CustomDebugStringConvertible {
        /// send the message as an applicationContext update if the session is not reachable.
        case applicationContext
        /// If you need to update your complication, you can use this channel to do it if `isReachable` is false
        case complicationUserInfo
        /// send the message as a data message if possible, otherwise it gets sent over the userInfo channel.  Expect a response as a data message too
        case message
        /// send the response message as a file.  The request is sent as a data message.
        case fileTransfer
        
        public var debugDescription: String {
            switch self {
            case .applicationContext:
                return "Application Context"
            case .complicationUserInfo:
                return "Complication UserInfo"
            case .message:
                return "General Message"
            case .fileTransfer:
                return "File Transfer"
            }
        }
    }
    
    
    public struct UserInfoKey {
        static let fileURLPath = "fileURLPath"  // value is a String that you can use to create a local fileURL
        static let error = "error" // just provide anything as a value, otherwise there should be nothing present.
        static let messageId = "messageId"
        
        /// you should also have your own user info keys that you use for helping you sort out your messageHandler
    }
        
    /// A unique identifier
    public let id: String
    /// Whether it is a request or a response, or if it is to send applicationContext, or userInfo
    /// In any case, the same approach should be used to creating your message.
    public let kind: Kind
    
    public let responseType: CommunicationChannel
    
    /// The time at which the message took place
    public let timestamp: Date
    
    /// If this message's `kind` is a `.response`, you can provide context by providing the `messageId` of the `.request` message this is responding to.
    public var requestMessageId: String? {
        guard case let Kind.response(requestId) = self.kind else {
            return nil
        }
        return requestId
    }
    
    // you can provide a dictionary here to provide more context to your WatchCommunicatorMessage, such as how to interpret the jsonData
    public var userInfo: [String: String]
    
    public var jsonData: Data?
    
    /// You use this if you need to provide a response although you don't actually need to send anything back.
    public var isConfirmationOnly: Bool = false {
        didSet {
            if self.isConfirmationOnly {
                var userInfo = self.userInfo
                userInfo["isConfirmation"] = "true"
                self.userInfo = userInfo
            } else {
                var userInfo = self.userInfo
                userInfo["isConfirmation"] = nil
                self.userInfo = userInfo
            }
        }
    }
    
    public var error: WatchCommunicatorError? {
        guard let json = jsonData else { return nil }
        guard userInfo[UserInfoKey.error] != nil else { return nil }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let error = try decoder.decode(WatchCommunicatorError.self, from: json)
            return error
            
        } catch {
            return nil
        }
    }
    
    public var debugDescription: String {
        let description =
        """
        -----------------------\(self.kind.debugDescription.uppercased())--------------------------
        ID: \(id)
        RequestID: \(requestMessageId ?? "(none)")
        type: \(responseType)
        timestamp: \(timestamp)
        isConfirmationMessage: \(self.isConfirmationOnly.truthyString)
        userInfo: \(self.userInfo)
        ---------------------------------------------------------
        """
        
        return description
      }
    
    public static func request(responseType: CommunicationChannel,
                               userInfo: [String: String],
                               jsonData: Data?) -> WatchCommunicatorMessage {
        
        return WatchCommunicatorMessage(id: UUID().uuidString,
                                 kind: .request,
                                 responseType: responseType,
                                 timestamp: Date(),
                                 userInfo: userInfo,
                                 jsonData: jsonData)
    }
    
    public static func response(toMessageId requestMessageId: String?,
                                responseType: CommunicationChannel,
                                userInfo: [String: String],
                                jsonData: Data?)  -> WatchCommunicatorMessage {
        
        return WatchCommunicatorMessage(id: UUID().uuidString,
                                 kind: .response(requestId: requestMessageId),
                                 responseType: responseType,
                                 timestamp: Date(),
                                 userInfo: userInfo,
                                 jsonData: jsonData)
    }
    
    public static func confirmationResponse(toMessageId requestMessageId: String?,
                                            responseType: CommunicationChannel)  -> WatchCommunicatorMessage {
        
        var message = WatchCommunicatorMessage(id: UUID().uuidString,
                                 kind: .response(requestId: requestMessageId),
                                 responseType: responseType,
                                 timestamp: Date(),
                                 userInfo: [:],
                                 jsonData: nil)
        
        message.contentType = .confirmation
        return message
    }
    
    public static func ==(lhs: WatchCommunicatorMessage, rhs: WatchCommunicatorMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

fileprivate extension Bool {
    var truthyString: String {
        return (self == true) ? "true" : "false"
    }
}
