//
//  WatchMessageViewModel.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 20.09.21.
//

import Foundation

#if os(iOS)
import UIKit
#else
import WatchKit
#endif

fileprivate let incomingBackgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
fileprivate let outgoingBackgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

fileprivate let requestColor = UIColor(red: 44.0/255.0, green: 135.0/255.0, blue: 145.0/255.0, alpha: 1.0)
fileprivate let responseColor = UIColor(red: 57.0/255.0, green: 182.0/255.0, blue: 196.0/255.0, alpha: 1.0)
fileprivate let notificationColor = UIColor(red: 214.0/255.0, green: 117.0/255.0, blue: 32.0/255.0, alpha: 1.0)

fileprivate let timestampFormatter: DateFormatter = {
   let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()


struct WatchHistoryItemViewModel {
    
    let timestampText: String
    let timestampColor: UIColor
    
    let messageText: String
    let messageColor: UIColor
    let backgroundColor: UIColor
    
    /// The platform this message originated on.
    let plaformOriginIcon: String
    
    let historyItem: WatchMessageHistoryItem
    init(_ historyItem: WatchMessageHistoryItem) {
        
        self.historyItem = historyItem
        
        let message = historyItem.message
         
        let timestampText = timestampFormatter.string(from: message.timestamp)
        let timestampLabelText = "\(Self.messageTypeSymbol(historyItem: historyItem)) \(timestampText)"
        
        self.timestampText = timestampLabelText
        self.timestampColor = message.timestampLabelColor
        
        var text: String = ""
        switch message.contentType {
        case .redirectToSomeAction:
            text = "Redirect Action"
        case .remoteLogFile:
            text = "Remote File \(message.kind.isRequest ? "req'd" : "recv'd")"
        case .remoteLogStatement:
            let statement = message.decodedTypeFromJSONData(String.self) ?? "(empty)"
            text = "Log: \(statement.truncate(to: 60))"
        case .watchContextData:
            text = "App Context"
        case .unspecified:
            text = "Unspecified"
        case .confirmation:
            text = "✔︎ Tx Receipt"
        case .imageFile:
            text = "Image \(message.kind.isRequest ? "Requested" : "Received")"  // shouldn't happen as ImageRowController handles it
        }
        
        self.messageText = text
        
        self.messageColor = .white
        
        if historyItem.isIncoming {
            self.backgroundColor = incomingBackgroundColor
        } else {
            self.backgroundColor = outgoingBackgroundColor
        }
        
        self.plaformOriginIcon = Self.plaformOriginIcon(of: historyItem)
        
    }
    
    static func plaformOriginIcon(of historyItem: WatchMessageHistoryItem) -> String {
        let watch = "⌚️"
        let phone = "📱"
        
        #if os(iOS)
        if historyItem.isIncoming {
            if historyItem.message.kind.isRequest {
                return watch
            } else if historyItem.message.kind.isResponse {
                return phone
            } else if historyItem.message.kind.isNotification {
                return watch
            }
        } else {
            if historyItem.message.kind.isRequest {
                return phone
            } else if historyItem.message.kind.isResponse {
                return watch
            } else if historyItem.message.kind.isNotification {
                return phone
            }
        }
        #elseif os(watchOS)
        if historyItem.isIncoming {
            if historyItem.message.kind.isRequest {
                return phone
            } else if historyItem.message.kind.isResponse {
                return watch
            } else if historyItem.message.kind.isNotification {
                return phone
            }
        } else {
            if historyItem.message.kind.isRequest {
                return watch
            } else if historyItem.message.kind.isResponse {
                return phone
            } else if historyItem.message.kind.isNotification {
                return watch
            }
        }
        #endif
        return "❗️" // should never happen
    }
    
    static func messageTypeSymbol(historyItem: WatchMessageHistoryItem) -> String {
        if historyItem.isIncoming {
            if historyItem.message.kind.isRequest {
                return "⇩" // a request coming
            } else if historyItem.message.kind.isResponse {
                return "⬇︎"
            } else {
                // notification
                return "⤓"
            }
        } else {
            if historyItem.message.kind.isRequest {
                return "⇧"
            } else if historyItem.message.kind.isResponse {
                return "⬆︎"
            } else {
                // notification
                return "⤒"
            }
        }
    }
}

fileprivate extension WatchCommunicatorMessage {
    
    var timestampLabelColor: UIColor {
        switch self.kind {
        case .request:
            // return some sort of dark cyan
            return requestColor
        case .response(let requestId):
            if requestId != nil {
                // is a response
                // return some sort of lighter Cyan
                return responseColor
            } else {
                // is a notification
                // return some kind of orange
                return notificationColor
            }
        }
    }
}

fileprivate extension String {
  /*
   Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
   - Parameter length: Desired maximum lengths of a string
   - Parameter trailing: A 'String' that will be appended after the truncation.
    
   - Returns: 'String' object.
  */
  func truncate(to length: Int, trailing: String = "…") -> String {
    return (self.count > length) ? self.prefix(length) + trailing : self
  }
}

