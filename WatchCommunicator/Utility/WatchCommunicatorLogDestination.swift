//
//  WatchCommunicatorLogDestination.swift
//  WatchCommunicator WatchKit Extension
//
//  Created by Stephen O'Connor (MHP) on 15.06.21.
//

import Foundation
import XCGLogger

extension XCGLogger {
    
    class WatchRemoteLogDestination: BaseDestination {
        
        var showLogLevel: Bool = true
        
        let communicator: WatchCommunicator
        
        init(owner: XCGLogger,
             identifier: String = "communicator.remoteLogger.fromWatch",
             communicator: WatchCommunicator) {
            self.communicator = communicator
            super.init(owner: owner, identifier: identifier)
            
            //self.logQueue = XCGLogger.logQueue
        }
        
        override func output(logDetails: LogDetails, message: String) {
            
            var extendedDetails = ""
            if showThreadName {
                extendedDetails += "[" + (Thread.isMainThread ? "main": (Thread.current.name! != "" ? Thread.current.name! : String(format: "%p", Thread.current))) + "] "
            }
            
            extendedDetails += "[" + logDetails.level.description + "] "
            
            if showFileName {
                if let filename = NSURL(fileURLWithPath: logDetails.fileName).lastPathComponent {
                    extendedDetails += "[" + filename + (showLineNumber ? ":" + String(logDetails.lineNumber) : "") + "] "
                }
                
            } else if showLineNumber {
                extendedDetails += "[" + String(logDetails.lineNumber) + "] "
            }
            
            var formattedDate: String = logDetails.date.description
            if let dateFormatter = owner!.dateFormatter {
                formattedDate = dateFormatter.string(from: logDetails.date)
            }
            
            let fullLogMessage: String =  "\(formattedDate) \(extendedDetails)\(logDetails.functionName): [⌚️] \(logDetails.message)\n"
            
            let payload = try? self.communicator.encoder.encode(fullLogMessage)
            
            let message = WatchCommunicatorMessage.response(toMessageId: nil,
                                                         responseType: .message,
                                                         contentType: .remoteLogStatement,
                                                         userInfo: [:],
                                                         jsonData: payload)
            
            DispatchQueue.main.async {
                self.communicator.sendResponseMessage(message)
            }
        }
    }
}


extension XCGLogger.WatchRemoteLogDestination {
    var defaultLogLevel: XCGLogger.Level {
        return .debug
    }
}
