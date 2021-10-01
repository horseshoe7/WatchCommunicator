//
//  ExtensionDelegate.swift
//  WatchCommunicator WatchKit Extension
//
//  Created by Stephen O'Connor (MHP) on 10.06.21.
//

import WatchKit
import XCGLogger

let UserInfoKeyMessage = "message"

extension Notification.Name {
    // userInfo will contain the message via the key UserInfoKeyMessage
    static let didReceiveWatchMessage = Notification.Name(rawValue: "WatchCommunicator_didReceiveWatchMessage")
}


class ExtensionDelegate: NSObject, WKExtensionDelegate {

    // MARK: - WCSession
    lazy var communicator: WatchCommunicator = {
        let communicator = WatchCommunicator()
        communicator.messageHandler = { [weak self] incomingMessage in
            return self?.handle(incomingMessage)
        }
        
        communicator.applicationContextAccessor = { [weak communicator] requestId in
            let json = ["DamnSon": "Is this working?"]
            let jsonData = try? communicator?.encoder.encode(json)
            return WatchCommunicatorMessage.response(toMessageId: requestId,
                                                  responseType: .applicationContext,
                                                  contentType: .watchContextData,
                                                  userInfo: [:],
                                                  jsonData: jsonData)
        }
        communicator.startSession()
        return communicator
    }()
    
    private func handle(_ incomingMessage: WatchCommunicatorMessage) -> WatchCommunicatorMessage? {
    
        DispatchQueue.main.async {
            logger.debug("Received message: \(incomingMessage)")
            NotificationCenter.default.post(name: .didReceiveWatchMessage, object: self.communicator, userInfo: [UserInfoKeyMessage: incomingMessage])
        }
        
        if incomingMessage.kind == .request {
            var response: WatchCommunicatorMessage
            
            switch incomingMessage.contentType {
                
            case .remoteLogFile, .imageFile:
                // it's a request, so it wants a response, ergo  you need to find the location of your log file and transfer that.
                // TODO: Implement me
                
                if let logFileURL = self.logFileURL() {
                    response = WatchCommunicatorMessage.response(
                        toMessageId: incomingMessage.id,
                        responseType: .fileTransfer,
                        contentType: incomingMessage.contentType,
                        userInfo: [:],
                        jsonData: nil
                    )
                    
                    response.fileURL = logFileURL
                    
                } else {
                    
                    response = WatchCommunicatorMessage.confirmationResponse(toMessageId: incomingMessage.id,
                                                                          responseType: incomingMessage.responseType)
                    
                }
            
            case .watchContextData:
                let payload = ["Testing": "This", "Application": "Context"]
                let data = try? self.communicator.encoder.encode(payload)
                response = WatchCommunicatorMessage.response(toMessageId: incomingMessage.id,
                                                          responseType: incomingMessage.responseType,
                                                          contentType: .watchContextData,
                                                          userInfo: [:],
                                                          jsonData: data)
                
            case .unspecified, .redirectToSomeAction, .remoteLogStatement, .confirmation:
                response = WatchCommunicatorMessage.confirmationResponse(toMessageId: incomingMessage.id,
                                                                      responseType: incomingMessage.responseType)
            }
            
            return response
            
            
        } else {
            
            return nil
        }
    }
    
    private func createRemoteLogger() {
        let remoteLogDestination = XCGLogger.WatchRemoteLogDestination(owner: logger, communicator: self.communicator)
        
        // Create a logger object with no destinations
        let logger: XCGLogger = {
            
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
            

            // TODO:  Add a RemoteLogger
            log.add(destination: remoteLogDestination)
         

            // Add basic app info, version info etc, to the start of the logs
            log.logAppDetails()
            
            return log
        }()
        
        remoteLogger = logger
    }
    
    private func logFileURL() -> URL? {
        
        if let logDestination = logger.destination(withIdentifier: fileLoggerIdentifier) as? AutoRotatingFileDestination {
            return logDestination.writeToFileURL
        }
        return nil
    }
    
    // MARK: - Extension Lifecycle
    func applicationDidFinishLaunching() {
        _ = communicator // initialize him
        
        // createRemoteLogger()  // disabled for now
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Be sure to complete the background task once you’re done.
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Be sure to complete the connectivity task once you’re done.
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                // Be sure to complete the relevant-shortcut task once you're done.
                relevantShortcutTask.setTaskCompletedWithSnapshot(false)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                // Be sure to complete the intent-did-run task once you're done.
                intentDidRunTask.setTaskCompletedWithSnapshot(false)
            default:
                // make sure to complete unhandled task types
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

}


