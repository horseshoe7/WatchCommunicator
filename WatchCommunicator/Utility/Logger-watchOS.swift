//
//  Logger-watchOS.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 15.06.21.
//


import Foundation
import XCGLogger


let printFileLogBeforeInitializing: Bool = false

let fileLoggerIdentifier = "WatchCommunicatorLogger.file"

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
    

    // TODO:  Add a File Logger
    // Create a file log destination
    if let logFileURL = logFileURL {
        
        if printFileLogBeforeInitializing {
            if let contents = try? String(contentsOf: logFileURL) {
                print("\n\n\n======== EXISTING FILE LOG: ========\n\n")
                print(contents)
                print("\n\n\n======== END OF PRE-EXISTING LOG ========")
            }
        }
        
        let fileDestination = AutoRotatingFileDestination(owner: log,
                                                     writeToFile: logFileURL,
                                                     identifier: fileLoggerIdentifier,
                                                     shouldAppend: true,
                                                     appendMarker: "------- RELAUNCHED APP -------",
                                                     attributes: nil,
                                                     maxFileSize: AutoRotatingFileDestination.autoRotatingFileDefaultMaxFileSize,
                                                     maxTimeInterval: AutoRotatingFileDestination.autoRotatingFileDefaultMaxTimeInterval,
                                                     archiveSuffixDateFormatter: nil,
                                                     targetMaxLogFiles: 1)
        
        // Optionally set some configuration options
        fileDestination.outputLevel = fileDestination.defaultLogLevel
        fileDestination.showLogIdentifier = false
        fileDestination.showFunctionName = true
        fileDestination.showThreadName = true
        fileDestination.showLevel = true
        fileDestination.showFileName = true
        fileDestination.showLineNumber = true
        fileDestination.showDate = true
        
        // Process this destination in the background
        fileDestination.logQueue = XCGLogger.logQueue
        
        // Add the destination to the logger
        log.add(destination: fileDestination)
    }
 

    // Add basic app info, version info etc, to the start of the logs
    log.logAppDetails()
    
    return log
}()

var remoteLogger = logger
