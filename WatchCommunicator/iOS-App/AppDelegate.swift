//
//  AppDelegate.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 10.06.21.
//

import UIKit

let UserInfoKeyMessage = "message"

extension Notification.Name {
    // userInfo will contain the message via the key UserInfoKeyMessage
    static let didReceiveWatchMessage = Notification.Name(rawValue: "WatchCommunicator_didReceiveWatchMessage")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    lazy var communicator: WatchCommunicator = {
        let communicator = WatchCommunicator()
        communicator.messageHandler = { [weak self] incomingMessage in
            // not currently called on main thread
            return self?.handle(incomingMessage)
        }
        
        communicator.applicationContextAccessor = { [weak self] requestId in
            // not currently called on main thread
            guard let response = self?.applicationContextResponse(requestId: requestId) else {
                return WatchCommunicatorMessage.confirmationResponse(toMessageId: requestId, responseType: .applicationContext)
            }
            return response
        }
        communicator.startSession()
        return communicator
    }()
    
    private func applicationContextResponse(requestId: String? = nil) -> WatchCommunicatorMessage {
        
        let payload = ["Testing": "This", "Application": "Context"]
        let data = try? self.communicator.encoder.encode(payload)
        return WatchCommunicatorMessage.response(toMessageId: requestId,
                                              responseType: .applicationContext,
                                              contentType: .watchContextData,
                                              userInfo: [:],
                                              jsonData: data)
    }
    
    private func handle(_ incomingMessage: WatchCommunicatorMessage) -> WatchCommunicatorMessage? {
    
        // This is to notify the UI that we received a message and if it wants to update anything, it can do so here.
        DispatchQueue.main.async {
            logger.debug("Received message: \(incomingMessage)")
            NotificationCenter.default.post(name: .didReceiveWatchMessage, object: self.communicator, userInfo: [UserInfoKeyMessage: incomingMessage])
        }
        
        // BELOW is the aspect of the message handler that will be application specific, but
        // generally, if you receive a request, you should provide a return value as the response.
        
        if incomingMessage.kind == .request {
            let response: WatchCommunicatorMessage
            
            switch incomingMessage.contentType {
                
            case .remoteLogFile, .imageFile:
                // it's a request, so it wants a response, ergo  you need to find the location of your log file and transfer that.
                // TODO: Implement me
                response = WatchCommunicatorMessage.confirmationResponse(toMessageId: incomingMessage.id,
                                                                      responseType: incomingMessage.responseType)
            
            case .watchContextData:
                let payload = ["Testing": "This", "Application": "Context"]
                
                do {
                    let data = try self.communicator.encoder.encode(payload)
                    response = WatchCommunicatorMessage.response(toMessageId: incomingMessage.id,
                                                              responseType: incomingMessage.responseType,
                                                              contentType: .watchContextData,
                                                              userInfo: [:],
                                                              jsonData: data)
                    return response
                } catch let e {
                    logger.error("Error serializing data: \(e.localizedDescription)")
                    return WatchCommunicatorMessage.confirmationResponse(toMessageId: incomingMessage.id, responseType: incomingMessage.responseType)
                }
                
            case .unspecified, .redirectToSomeAction, .remoteLogStatement, .confirmation:
                response = WatchCommunicatorMessage.confirmationResponse(toMessageId: incomingMessage.id,
                                                                      responseType: incomingMessage.responseType)
            }
            return response
            
            
        } else {
            
            switch incomingMessage.contentType {
            case .remoteLogStatement:
                if let statement = incomingMessage.decodedTypeFromJSONData(String.self) {
                    print(statement)
                }
            case .remoteLogFile:
                if let fileURL = incomingMessage.decodedTypeFromJSONData(URL.self) {
                    do {
                        let logContents = try String(contentsOf: fileURL)
                        print(logContents)
                    } catch {
                        logger.error("Failed opening file: \(error.localizedDescription)")
                    }
                }
            default:
                break
            }
            
            return nil
        }
    }

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = communicator // initialize him
        window = UIWindow()
        window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

