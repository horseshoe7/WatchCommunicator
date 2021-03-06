//
//  ApplicationLogLevelFormatter.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 15.06.21.
//

import Foundation
import XCGLogger

class ApplicationLogLevelFormatter: LogFormatterProtocol {
    
    func format(logDetails: inout LogDetails, message: inout String) -> String {
        
        #if os(watchOS)
        let platformPrefix = "[โ๏ธ] "
        #else
        let platformPrefix = ""
        #endif
        
        return "\(platformPrefix)\(logDetails.level.emoji) \(message)"
    }
    
    var debugDescription: String {
        get {
            var description: String = "\(String(describing: ApplicationLogLevelFormatter.self)): "
            for level in XCGLogger.Level.allCases {
                description += "\n\t- \(level) > \(level.emoji)"
            }

            return description
        }
    }
}

extension XCGLogger.Level {
    var emoji: String {
        switch self {
        case .verbose, .debug:
            return "๐"
        case .info:
            return "๐"
        case .notice, .warning:
            return "๐งก"
        case .error:
            return "โค๏ธ"
        case .severe, .alert, .emergency: // aka critical
            return "๐"
        case .none:
            return ""
        }
    }
}
