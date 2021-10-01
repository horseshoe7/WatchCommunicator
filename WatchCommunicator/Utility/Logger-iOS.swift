//
//  Logger-iOS.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 15.06.21.
//

import Foundation
import XCGLogger
import UIKit

let printFileLogBeforeInitializing: Bool = false

// Create a logger object with no destinations
var logger: XCGLogger = {
    
    let log = XCGLogger(identifier: "WatchCommunicatorLogger", includeDefaultDestinations: false)
    
    var formatters = log.formatters ?? []
    formatters.append(ApplicationLogLevelFormatter())
    log.formatters = formatters
    
    // Create a destination for the system console log (via NSLog)
    //let systemDestination = AppleSystemLogDestination(identifier: "advancedLogger.systemDestination")
    
    let systemDestination = ConsoleDestination(owner: log, identifier: "WatchCommunicatorLogger.systemConsole")
    formatters = systemDestination.formatters ?? []
    formatters.append(ApplicationLogLevelFormatter())
    systemDestination.formatters = formatters
    
    // Optionally set some configuration options
    systemDestination.outputLevel = systemDestination.defaultLogLevel
    systemDestination.showLogIdentifier = false
    systemDestination.showFunctionName = false
    systemDestination.showThreadName = false
    systemDestination.showLevel = true
    systemDestination.showFileName = true
    systemDestination.showLineNumber = true
    systemDestination.showDate = true
    
    // Add the destination to the logger
    log.add(destination: systemDestination)
    
    #if DEBUG
    DispatchQueue.main.async {
        addTextViewLogger(to: log)
    }
    #endif
    
    // Add basic app info, version info etc, to the start of the logs
    log.logAppDetails()
    
    return log
}()



// MARK: - Extensions for UITextView Logging on iOS

var loggingTextView: UITextView?

func addTextViewLogger(to log: XCGLogger) {
    
    let textView = UITextView()
    textView.font = UIFont(name: "Courier", size: 11)!
    textView.isEditable = false
    
    loggingTextView = textView
    
    log.add(destination: XCGLogger.XCGTextViewLogDestination(textView: textView, owner: log, identifier: "WatchCommunicatorLogger.textview"))
}

extension XCGLogger {
    
    public class XCGTextViewLogDestination: DestinationProtocol {
        
        public var owner: XCGLogger?
        public var identifier: String
        public var outputLevel: XCGLogger.Level = .debug
        
        public var showThreadName: Bool = false
        public var showFileName: Bool = true
        public var showLineNumber: Bool = true
        public var showLogLevel: Bool = true
        
        public var haveLoggedAppDetails: Bool = false
        public var formatters: [LogFormatterProtocol]? = []
        public var filters: [FilterProtocol]? = []
        
        public var textView: UITextView
        
        public init(textView: UITextView, owner: XCGLogger, identifier: String = "") {
            self.textView = textView
            self.owner = owner
            self.identifier = identifier
            self.outputLevel = self.defaultLogLevel
        }
        
        public func process(logDetails: LogDetails) {
            var extendedDetails: String = ""
            
            if showThreadName {
                extendedDetails += "[" + (Thread.isMainThread ? "main": (Thread.current.name! != "" ? Thread.current.name! : String(format: "%p", Thread.current))) + "] "
            }
            
            if showLogLevel {
                extendedDetails += "[" + logDetails.level.description + "] "
            }
            
            if showFileName {
                let filename = NSURL(fileURLWithPath: logDetails.fileName).lastPathComponent!
                extendedDetails += "[" + filename + (showLineNumber ? ":" + String(logDetails.lineNumber) : "") + "] "
            } else if showLineNumber {
                extendedDetails += "[" + String(logDetails.lineNumber) + "] "
            }
            
            var formattedDate: String = logDetails.date.description
            if let dateFormatter = owner!.dateFormatter {
                formattedDate = dateFormatter.string(from: logDetails.date)
            }
            
            let fullLogMessage: String =  "\(formattedDate) \(extendedDetails)\(logDetails.functionName): \(logDetails.message)\n"
            
            DispatchQueue.main.async { [weak self] in
                self?.textView.text += fullLogMessage
            }
        }
        
        public func processInternal(logDetails: LogDetails) {
            var extendedDetails: String = ""
            if showLogLevel {
                extendedDetails += "[" + logDetails.level.description + "] "
            }
            
            var formattedDate: String = logDetails.date.description
            if let dateFormatter = owner!.dateFormatter {
                formattedDate = dateFormatter.string(from: logDetails.date)
            }
            
            let fullLogMessage: String =  "\(formattedDate) \(extendedDetails): \(logDetails.message)\n"
            
            DispatchQueue.main.async { [weak self] in
                self?.textView.text += fullLogMessage
            }
        }
        
        // MARK: - Misc methods
        public func isEnabledFor(level: XCGLogger.Level) -> Bool {
            return level >= self.outputLevel
        }
        
        // MARK: - DebugPrintable
        public var debugDescription: String {
            return "XCGTextViewLogDestination: \(identifier) - LogLevel: \(outputLevel.description) showThreadName: \(showThreadName) showLogLevel: \(showLogLevel) showFileName: \(showFileName) showLineNumber: \(showLineNumber)"
        }
    }
}

extension XCGLogger.XCGTextViewLogDestination {
    var defaultLogLevel: XCGLogger.Level {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }
}

