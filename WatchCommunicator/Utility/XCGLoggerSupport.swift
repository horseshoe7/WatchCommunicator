//
//  XCGLoggerSupport.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 15.06.21.
//

import Foundation
import XCGLogger


extension ConsoleDestination {
    var defaultLogLevel: XCGLogger.Level {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }
}

extension FileDestination {
    var defaultLogLevel: XCGLogger.Level {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }
}

var logFileURL: URL? {
    if let baseFolderURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last {
        let logFolderURL = baseFolderURL.appendingPathComponent("logs/")
        if !FileManager.default.fileExists(atPath: logFolderURL.path) {
            try? FileManager.default.createDirectory(at: logFolderURL, withIntermediateDirectories: true, attributes: nil)
        }
        let logFileURL = logFolderURL.appendingPathComponent("applicationLog.txt")
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        
        return logFileURL
        
    } else {
        return nil
    }
}
