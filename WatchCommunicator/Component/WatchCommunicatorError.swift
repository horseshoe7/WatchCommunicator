//
//  WatchCommunicatorError.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 31.08.21.
//

import Foundation

public enum WatchCommunicatorError: Error, Codable {
    
    /// if 'normal' communication currently not possible.
    case deviceNotReachable
    /// was never designed to handle tons of requests.
    case rateLimitReached
    /// Generally these represent errors that shouldn't happen in production
    case invalidConfiguration(details: String)
    /// for whatever reason a message's delivery was cancelled
    case messageTransmissionWasCancelled
    /// related to an error that occurs with WCSessionDelegate
    case sessionError(details: String)
    /// if you're doing a file transfer and the Message's UserInfo doesn't have a url path provided
    case noURLPathProvided
    /// if you're doing a file transfer and the file could not be found, in order to send it.
    case fileNotFound
    /// took to long to respond.  On MessageOperations, if they don't receive a reply, this mechanism can be used to clean them out of the queue.
    case tookTooLongToRespond
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let kind = try values.decode(String.self, forKey: .kind)
        switch kind {
        case "deviceNotReachable":
            self = .deviceNotReachable
        case "rateLimitReached":
            self = .rateLimitReached
        case "invalidConfiguration":
            let associatedValue = try values.decode(String.self, forKey: .associatedStringValue)
            self = .invalidConfiguration(details: associatedValue)
        case "messageTransmissionWasCancelled":
            self = .messageTransmissionWasCancelled
        case "sessionError":
            let associatedValue = try values.decode(String.self, forKey: .associatedStringValue)
            self = .sessionError(details: associatedValue)
        case "noURLPathProvided":
            self = .noURLPathProvided
        case "fileNotFound":
            self = .fileNotFound
        case "tookTooLongToRespond":
            self = .tookTooLongToRespond
        default:
            fatalError("Case not handled.")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .deviceNotReachable:
            try container.encode("deviceNotReachable", forKey: .kind)
        case .rateLimitReached:
            try container.encode("rateLimitReached", forKey: .kind)
        case .invalidConfiguration(let details):
            try container.encode("invalidConfiguration", forKey: .kind)
            try container.encode(details, forKey: .associatedStringValue)
        case .messageTransmissionWasCancelled:
            try container.encode("messageTransmissionWasCancelled", forKey: .kind)
        case .sessionError(let details):
            try container.encode(details, forKey: .associatedStringValue)
            try container.encode("sessionError", forKey: .kind)
        case .noURLPathProvided:
            try container.encode("noURLPathProvided", forKey: .kind)
        case .fileNotFound:
            try container.encode("fileNotFound", forKey: .kind)
        case .tookTooLongToRespond:
            try container.encode("tookTooLongToRespond", forKey: .kind)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case kind
        case associatedStringValue
    }
}
