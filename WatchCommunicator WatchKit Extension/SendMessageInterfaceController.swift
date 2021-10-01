//
//  SendMessageInterfaceController.swift
//  WatchCommunicator WatchKit Extension
//
//  Created by Stephen O'Connor (MHP) on 17.09.21.
//

import WatchKit
import Foundation


class SendMessageInterfaceController: WKInterfaceController {

    fileprivate let timestampFormatter: DateFormatter = {
       let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    var application: ExtensionDelegate? {
        guard let application = WKExtension.shared().delegate as? ExtensionDelegate else {
            return nil
        }
        return application
    }
    
    @IBAction
    func didPressSendContext() {
        
        guard let application = self.application else { return }
        var contextMessage = application.communicator.applicationContextAccessor(nil)
        contextMessage.contentType = .watchContextData
        application.communicator.sendResponseMessage(contextMessage)
        
        self.pop()
    }
    
    @IBAction
    func didPressRequestContext() {
        
        guard let application = self.application else { return }
        let contextMessage = WatchCommunicatorMessage.request(responseType: .applicationContext, contentType: .watchContextData, userInfo: [:], jsonData: nil)
        application.communicator.sendRequestMessage(contextMessage) { [weak self] (_ result: WatchCommunicatorResult) in
            switch result {
            case .success(let responseMessage):
                if let response = responseMessage {
                    logger.debug("Received a Response! \(response)")
                } else {
                    logger.debug("Received a Response but with no message")
                }
                
            case .failure(let error):
                logger.error("Received an Error Response \(String(describing: error))")
            }
            
            self?.pop()
        }
        
        
    }
    
    @IBAction
    func didPressSendImage() {
        
        guard let imageURL = Bundle.main.url(forResource: "cute-puppy.jpeg", withExtension: nil) else {
            logger.error("No image available in the bundle to send.")
            return
        }
        
        var message = WatchCommunicatorMessage.response(toMessageId: nil, responseType: .fileTransfer, contentType: .imageFile, userInfo: [:], jsonData: nil)
        message.fileURL = imageURL
        
        guard let application = self.application else { return }
        
        application.communicator.sendResponseMessage(message)
        
        self.pop()
    }
    
    @IBAction
    func didPressSendLogFile() {
        logger.error("Not implemented!")
        
        self.pop()
    }
    
    @IBAction
    func didPressSendSimpleMessage() {
        
        let timestamp = timestampFormatter.string(from: Date())
        let fakeLogStatement = "\(timestamp): [⌚️] Testing Communication"
        
        guard let delegate = self.application else {
            logger.error("Couldn't get the extension delegate")
            return
        }
        
        let payload = try? delegate.communicator.encoder.encode(fakeLogStatement)
        let message = WatchCommunicatorMessage.response(toMessageId: nil,
                                                     responseType: .message,
                                                     contentType: .remoteLogStatement,
                                                     userInfo: [:],
                                                     jsonData: payload)
        
        
        delegate.communicator.sendResponseMessage(message)
        
        self.pop()
    }
}
