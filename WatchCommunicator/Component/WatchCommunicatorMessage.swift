//
//  WatchCommunicatorMessage.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 31.08.21.
//

import Foundation

/// A `WatchCommunicatorMessage` is the standardized form with which to transmit data between the Watch and the iPhone in your application.
/// You generally can use the `static` methods that create messages, such as `WatchCommunicatorMessage.request(...)`, `WatchCommunicatorMessage.response(...)`, and `WatchCommunicatorMessage.confirmationResponse(...)` to instantiate a message.
/// You'll likely want to write an extension that leverages the `userInfo` property to provide some context to your .`jsonData` value.  Typically, you could define a `contentType` in such an extension.  See the demo project's `WatchCommunicatorMessage+Application.swift` file for an example of that.
public struct WatchCommunicatorMessage: Codable, Equatable, CustomDebugStringConvertible {
    
    public enum Kind: RawRepresentable, Codable, CustomDebugStringConvertible {
        
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
        
        /// A notification is nothing more than a response that has no associated requestId (i.e. a fire and forget)
        /// Convenience method that simplifies the case let syntax for you
        public var isNotification: Bool {
            if case .response(let requestId) = self, requestId == nil {
                return true
            }
            return false
        }
        /// Convenience method that simplifies the case let syntax for you
        public var isRequest: Bool {
            if case .request = self {
                return true
            }
            return false
        }
        /// Convenience method that simplifies the case let syntax for you
        public var isResponse: Bool {
            if case .response(let requestId) = self, requestId != nil {
                return true
            }
            return false
        }
        
        struct Constants {
            static let request = "Request"
            static let notification = "Notification"
            static let responseTo = "ResponseTo_"
        }
    }
    
    /// Indicates which aspect of a `WCSession` you want to use to transmit a message.  Note, if `isReachable` is true, it will always favour the `sendMessage(...)` APIs
    public enum CommunicationChannel: Int, Codable, CustomDebugStringConvertible {
        /// send the message as an applicationContext update if the session is not reachable.
        case applicationContext
        /// If you need to update your complication, you can use this channel to do it if `isReachable` is false, otherwise it gets send as a 'messageData'
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
    
    /// keys for the `.userInfo` property that are used by `WatchCommunicator`.
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
    
    /// indicates the preferred way of transferring the message if `.isReachable` is false.
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
    
    /// you can provide a dictionary here to provide more context to your `WatchCommunicatorMessage`, such as how to interpret the `.jsonData`
    /// if you need to add your own key-value pairs, it is recommended to add to the current value of `.userInfo`.  (For an example, see the `isConfirmationOnly` accessor method implementation.
    public var userInfo: [String: String]
    
    /// There is nothing preventing you using any data payload and you can configure your userInfo to indicate how you might interpret that data, but in general, it was conceived for you to use JSON-encoded Codable types here.
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
