//
//  ConnectivityDelegate.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 31.08.21.
//

import Foundation
import WatchConnectivity

#if os(watchOS)
import ClockKit
#endif


// Custom notifications.
// Posted when Watch Connectivity activation or reachibility status is changed,
// or when data is received or sent. Clients observe these notifications to update the UI.
//
extension Notification.Name {
    
    static let activationDidComplete = Notification.Name("ActivationDidComplete")
    static let activationStateDidChange = Notification.Name("ActivationStateDidChange")
    static let reachabilityDidChange = Notification.Name("ReachabilityDidChange")
}

public typealias WatchCommunicatorResult = Result<WatchCommunicatorMessage?, WatchCommunicatorError>

public typealias WatchMessageHistoryItem = (message: WatchCommunicatorMessage, isIncoming: Bool)

public class WatchCommunicator: NSObject {
    
    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1 // serial queue
        queue.underlyingQueue = self.workerQueue
        return queue
    }()
    
    private var userInfoTransfers: [WCSessionUserInfoTransfer] = []
    private var fileTransfers: [WCSessionFileTransfer] = []
    
    /// For any decoding needs
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// For any JSON decoding needs
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    public let deviceName: String = {
        let device: String
        #if os(iOS)
        device = "iPhone"
        #else
        device = "Watch"
        #endif
        return device
    }()
    
    public let otherDeviceName: String = {
        let device: String
        #if os(iOS)
        device = "Watch"
        #else
        device = "iPhone"
        #endif
        return device
    }()
    
    /// Depending on the method of data transmission, you can send a Data payload, or you can send a .plist style dictionary (`[String: Any]`)
    /// Since we always convert our `WatchCommunicatorMessage` types to data (which is a valid .plist type, but not JSON), whenever we have to send our messages via plist dictionary, we serialize to JSON data, then put it in a dictionary using the keys below.  `messageId` is added as a convenience, so you don't have
    /// to deserialize the JSON data into a Message in order to know if you want to do anything with it.  (Used usually in terms of filtering out duplicate messages that have arrived)
    fileprivate struct DictionaryKeys {
        static let messageData = "messageData"  // a WatchCommunicatorMessage as Data.  Needs to be JSON decoded
        static let messageId = "messageId"  // for quick access without having to deserialize messageData
    }
    
    /// The queue that the requests / updates / isReachable changes should complete on.  Default is `.main`
    fileprivate let completionQueue: DispatchQueue
    
    /// this is the underlying queue that the OperationQueue will work on.
    fileprivate let workerQueue = DispatchQueue(label: "watchcommunicator.operationQueue")
    
    internal let session: WCSession?
    
    /// you use this to keep track of recent messages, so that if the same message comes in twice, you can filter it out.
    /// it's a FIFO buffer, i.e. new messages get inserted at 0, so that you can crop the array if messages are older than X...
    private(set) var messageHistory = [WatchMessageHistoryItem]()
    
    /// You can bind this variable to notify your UI (on the main thread) if the reachability changes.
    let isReachable: WatchCommunicator.DynamicChangeOnNotifyingThread<Bool>

    /// tracks whether the user started the session before trying to use the `WatchCommunicator` instance.
    private var didStartSession = false
    
    public init(session: WCSession = .default, completionQueue: DispatchQueue = .main) {
        
        self.session = WCSession.isSupported() ? session : nil
        if self.session == nil {
            logger.error("WCSession is not supported on this device.")
        }
        self.isReachable = WatchCommunicator.DynamicChangeOnNotifyingThread(false, notifyQueue: completionQueue)
        self.completionQueue = completionQueue
        super.init()
    }
    
    /// call this once after you've set up your communicator
    func startSession() {
        
        if session != nil {
            didStartSession = true
        }
        
        session?.delegate = self
        session?.activate()
    }
    
    /// Whether the basics requirements exist to be able to exchange data between Watch and Phone
    var validSession: WCSession? {
        // paired - the user has to have their device paired to the watch
        // watchAppInstalled - the user must have your watch app installed
        
        // Note: if the device is paired, but your watch app is not installed
        // consider prompting the user to install it for a better experience
        
        guard let session = session else { return nil }
        
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled, session.activationState == .activated else {
            return nil
        }
        return session
        #else
        guard session.activationState == .activated else { return nil }
        return session
        #endif
    }
    
    /// basically, if this is defined, you have the state you need to be able to use the `sendMessage(...)` API on `WCSession`
    fileprivate var validReachableSession: WCSession? {
        
        guard let validSession = self.validSession else { return nil }
        guard validSession.isReachable else {
            self.isReachable.value = false
            return nil
        }
        self.isReachable.value = true
        return validSession
    }
    
    /// any outgoing message that is of applicationContext type.
    private var _applicationContextMessage: WatchCommunicatorMessage?
    private func setApplicationContextMessage(_ message: WatchCommunicatorMessage) {
        guard let existing = _applicationContextMessage else {
            _applicationContextMessage = message
            return
        }
        
        guard message.timestamp > existing.timestamp else {
            return // incoming isn't newer, so ignore it.
        }
        _applicationContextMessage = message
    }
    
    /// the last applicationContextMessage sent by the communicator.  Analogous to the applicationContext property on WCSession.
    var applicationContextMessage: WatchCommunicatorMessage? {
        if let contextMessage = _applicationContextMessage {
            return contextMessage
        }
        if let context = session?.applicationContext, let messageData = context[DictionaryKeys.messageData] as? Data {
            
            // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
            guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
                return nil
            }
            
            _applicationContextMessage = message
            return message
            
        } else {
            logger.error("Could not find any message data in the current appplication context, meaning you likely haven't exchanged one yet.")
            
            let context = self.applicationContextAccessor(nil)
            _applicationContextMessage = context
        }
        return nil
    }
    
    /// any incoming message that is of applicaitonContext type.
    private var _receivedApplicationContextMessage: WatchCommunicatorMessage? = nil
    private func setReceivedApplicationContextMessage(_ message: WatchCommunicatorMessage) {
        guard let existing = _receivedApplicationContextMessage else {
            _receivedApplicationContextMessage = message
            return
        }
        
        guard message.timestamp > existing.timestamp else {
            return // incoming isn't newer, so ignore it.
        }
        _receivedApplicationContextMessage = message
    }
    /// the last applicationContextMessage received by the communicator.  Analogous to the receivedApplicationContext property on WCSession.
    var receivedApplicationContextMessage: WatchCommunicatorMessage? {
        if let contextMessage = _receivedApplicationContextMessage {
            return contextMessage
        }
        if let context = session?.receivedApplicationContext {
            guard let messageData = context[DictionaryKeys.messageData] as? Data else {
                logger.error("Could not find any message data in the current appplication context, meaning you likely haven't exchanged one yet.")
                return nil
            }
            
            // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
            guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
                return nil
            }
            _receivedApplicationContextMessage = message
            return message
        }
        return nil
    }
    
    // MARK: - Public Methods and Properties
    
    /// If you reachability changes from false to true, whether the applicationContext should be sent automatically
    var sendsApplicationContextAfterActivation: Bool = true
    
    /// will be invoked on `completionQueue`.  This is the main property you will have to customize.
    var messageHandler: ((_ incoming: WatchCommunicatorMessage) -> WatchCommunicatorMessage?) = {
        _ in
        logger.error("You haven't set a messageHandler value yet!")
        return nil
    }
    
    /// basically the data that gets set to the property .jsonData on a WatchCommunicatorMessage, also the userInfo
    var applicationContextAccessor: ((_ requestId: String?) -> WatchCommunicatorMessage) = { requestId in
        logger.error("You haven't set an applicationContextResponse value yet!")
        return WatchCommunicatorMessage.confirmationResponse(toMessageId: requestId, responseType: .applicationContext)
    }
    
    /// According to the documentation, for a WCSessionFile:
    /// `The system places downloaded files inside a temporary directory. If you intend to keep the file, it is your responsibility to move the file to a more permanent location inside your extension’s container directory. You must move the file before your session delegate’s session(_:didReceive:) method returns.`
    /// So by default, this will move the file to the caches folder
    var fileLocationMapper: ((_ temporaryDownloadURL: URL) -> URL) = { tempURL in
        
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cachesFolderURL = paths[0]
        let fileName = tempURL.lastPathComponent
        
        let saveURL = cachesFolderURL.appendingPathComponent(fileName)
        return saveURL
    }
    
    /// for any method that requires a reply
    public func sendRequestMessage(_ message: WatchCommunicatorMessage, responseHandler: @escaping (_ result: WatchCommunicatorResult) -> Void) {
        
        guard didStartSession else {
            logger.error("Before you start to do anything with a WatchCommunicator, you need to call `startSession()` on it, and the only way that is possible is if WCSession.isSupported() returns true")
            return
        }
        
        if self.validSession == nil {
            suspendQueue()
        } else {
            resumeQueue()
        }
        
        if case WatchCommunicatorMessage.Kind.request = message.kind {
            // message gets added to history in the transmit method!
            let operation = MessageRequestOperation(message: message, communicator: self)
            operation.responseHandler = responseHandler
            self.operationQueue.addOperation(operation)
        } else {
            logger.warning("You used a message request sending method to send a message that doesn't expect a response. Behaviour is undefined.")
            // message gets added to history in the transmit method!
            let operation = MessageOperation(message: message, communicator: self)
            self.operationQueue.addOperation(operation)
        }
    }
    
    /// When you want to send a message and do not expect a reply.
    public func sendResponseMessage(_ message: WatchCommunicatorMessage) {
        
        guard didStartSession else {
            logger.error("Before you start to do anything with a WatchCommunicator, you need to call `startSession()` on it, and the only way that is possible is if WCSession.isSupported() returns true")
            return
        }
        
        if self.validSession == nil {
            suspendQueue()
        } else {
            resumeQueue()
        }
        
        // create an operation, attach this message, attach this instance
        if case WatchCommunicatorMessage.Kind.request = message.kind {
            logger.warning("You used a message response sending method to send a request that expects a response. Behaviour is undefined.")
            // message gets added to history in the transmit method!
            let operation = MessageRequestOperation(message: message, communicator: self)
            operation.responseHandler = nil
            self.operationQueue.addOperation(operation)
        } else {
            // message gets added to history in the transmit method!
            let operation = MessageOperation(message: message, communicator: self)
            self.operationQueue.addOperation(operation)
        }
    }
}
    
    
extension WatchCommunicator: WCSessionDelegate {
    
    // MARK: - Session State
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("[\(deviceName)] Activation did complete: \(String(describing:activationState)) (\(activationState.rawValue))")
        if let error = error {
            logger.error("[\(deviceName)] Error Occurred: \(error.localizedDescription)")
        }
        postNotificationOnMainQueueAsync(name: .activationDidComplete)
  
        // we don't send anything until the reachability changes.
        
        self.isReachable.value = session.isReachable
        
        if activationState == .activated {
            if self.sendsApplicationContextAfterActivation {
                sendApplicationContext()
            }
            resumeQueue()
        } else {
            suspendQueue()
        }
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        postNotificationOnMainQueueAsync(name: .activationStateDidChange)
        suspendQueue()
    }
    #endif
    
    #if os(iOS)
    public func sessionDidDeactivate(_ session: WCSession) {
        postNotificationOnMainQueueAsync(name: .activationStateDidChange)
    }
    #endif
    
    // MARK: - State Changes
    
    #if os(iOS)
    /**
     The session object calls this method when the value in the isPaired, isWatchAppInstalled, isComplicationEnabled, or watchDirectoryURL properties of the WCSession object changes.
     */
    public func sessionWatchStateDidChange(_ session: WCSession) {
        logger.info("[\(deviceName)] - Watch State Changed:")
        logger.info("activationState: \(session.activationState.rawValue)")
        logger.info("watchDirURL: \(String(describing: session.watchDirectoryURL))")
        logger.info("isPaired: \(session.isPaired.truthyString)")
        logger.info("isWatchAppInstalled: \(session.isWatchAppInstalled.truthyString)")
        logger.info("isComplicationEnabled: \(session.isComplicationEnabled.truthyString)")
        postNotificationOnMainQueueAsync(name: .activationStateDidChange)
        
        self.isReachable.value = session.isReachable
        
    }
    #endif
    
    #if os(iOS)
    public func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("[\(deviceName)] - Reachability Changed.  isReachable: \(session.isReachable.truthyString)")
        postNotificationOnMainQueueAsync(name: .reachabilityDidChange)
        
        self.isReachable.value = session.isReachable
    }
    #endif
}

// MARK: - Receiving Messages or Data
extension WatchCommunicator {
    
    func sendApplicationContext(refresh: Bool = false) {

        if !refresh, let lastSent = self.applicationContextMessage {
            self.transmit(lastSent)
        } else {
            let message = self.applicationContextAccessor(nil)
            guard message.responseType == .applicationContext else {
                fatalError("You need to return a responseType of .applicationContext in your applicationContextResponse accessor block!")
            }
            self.transmit(message)
        }
    }
    
    /// will invoke your messageHandler which is used purely for your own business logic purposes.
    private func handleIncomingMessage(_ message: WatchCommunicatorMessage) -> WatchCommunicatorMessage? {
        
        guard self.shouldProcess(message) else {
            logger.warning("Already received this message, or it's outdated.  Doing nothing.")
            return nil
        }
        
        self.addToHistory(message: message, isIncoming: true)
        
        logger.debug("Incoming Message:\n\(message)")
        
        // handles the message and generates the response, if message.kind == .request
        // otherwise it still handles it.
        
        var responseMessage: WatchCommunicatorMessage?
        
        if !message.isConfirmationOnly {
            responseMessage = self.messageHandler(message)
        }
        
        // if we were expecting a response, do some housekeeping
        if case WatchCommunicatorMessage.Kind.response(let requestId) = message.kind {
            
            // if it's a read receipt for a file transfer request, then we don't finish the operation,
            // as we will wait for the file transfer to complete
            if message.kind.isResponse, message.responseType == .fileTransfer, message.isConfirmationOnly {
                // do nothing
            } else {
                finishOperation(with: requestId, successMessage: message)
            }
        }
        
        return responseMessage
    }
    
    private func shouldProcess(_ message: WatchCommunicatorMessage) -> Bool {
        
        if self.messageHistory.contains(where: { (existing: WatchCommunicatorMessage, isIncoming: Bool) in
            return existing.id == message.id
        }) {
            logger.debug("shouldProcess already processed: \(message)")
            return false
        }
        
        guard message.responseType == .applicationContext else {
            return true  // if we haven't received the message yet because it's not in the history, and it's not an application context, good to go.
        }
        
        // now filter by all application context messages, sort by newest first, and if the timestamp on the incoming is older than the first, reject it.
        let appContextHistory = self.messageHistory.filter ({ entry in
            // filter for messages that are for *providing* app context, which means not a request
            return entry.message.responseType == .applicationContext && entry.isIncoming && !entry.message.kind.isRequest
        }).sorted { $0.message.timestamp > $1.message.timestamp }
        
        guard let latestContext = appContextHistory.first else {
            return true  // there is no latest context, so process this message
        }
        // if an already received context message is newer than the incoming, ignore the incoming.
        if latestContext.message.timestamp > message.timestamp {
            return false
        }
        return true
    }
    
    /// Note: does not check if it should be added.  You call shouldProcess(...) for that.
    private func addToHistory(message: WatchCommunicatorMessage, isIncoming: Bool) {
        let logItem: WatchMessageHistoryItem = (message: message, isIncoming: isIncoming)
        self.messageHistory.insert(logItem, at: 0) // FIFO
        self.trimHistory(messagesOlderThan: 60 * 60) // one hour
    }
    
    private func trimHistory(messagesOlderThan ageInSeconds: TimeInterval) {
        messageHistory = messageHistory.filter({ entry in
            return abs(entry.message.timestamp.timeIntervalSinceNow) < ageInSeconds
        })
    }
    
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // handle receiving application context
        
        // the context should have one key, value is data, which you convert to a WatchCommunicatorMessage
        guard let messageData = applicationContext[DictionaryKeys.messageData] as? Data else {
            logger.error("You didn't do this properly.  You should always be passing WatchCommunicatorMessages when using this component / WCSession.  (Or it's possible it's an earlier revision of this code.) Received this: \(applicationContext)")
            _receivedApplicationContextMessage = nil
            return
        }
        
        // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
        guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
            logger.error("Bad WatchCommunicatorMessage data.  Probablybecause you're in development and you changed the spec.  Ignoring...")
            return
        }
        
        if message.responseType == .applicationContext {
            setReceivedApplicationContextMessage(message)
        }
        
        if let response = self.handleIncomingMessage(message) {
            let operation = MessageOperation(message: response, communicator: self)
            self.operationQueue.addOperation(operation)
        }
    }
    
    // when you receive a message but it expects no reply
    public func session(_ session: WCSession,
                 didReceiveMessageData messageData: Data) {
        
        // convert to WatchCommunicatorMessage
        // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
        guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
            logger.error("Could not deserialize WatchCommunicatorMessage.  It's possible it's spec changed.")
            return
        }
        
        if case WatchCommunicatorMessage.Kind.response = message.kind, message.responseType == .applicationContext {
            setReceivedApplicationContextMessage(message)
        }
        
        if let response = self.handleIncomingMessage(message) {
            let operation = MessageOperation(message: response, communicator: self)
            self.operationQueue.addOperation(operation)
        }
    }
    
    // when you received a message and it expects a reply
    public func session(_ session: WCSession,
                 didReceiveMessageData messageData: Data,
                 replyHandler: @escaping (Data) -> Void) {
        
        // convert to WatchCommunicatorMessage
        // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
        guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
            logger.error("Could not deserialize WatchCommunicatorMessage.  Most likely because you're still in development.")
            replyHandler(Data())
            return
        }
        
        if case WatchCommunicatorMessage.Kind.response = message.kind, message.responseType == .applicationContext {
            setReceivedApplicationContextMessage(message)
        }
        
        // ask your message Handler to process that message, then verify there's a responseMessage
        if let response = self.handleIncomingMessage(message) {
            
            // check whether it was requesting a file, if so, send a receipt, then initiate a file transfer
            if response.kind.isResponse, message.kind.isRequest, message.responseType == .fileTransfer {
                
                let fileTransfer = response
                let receivedMessage = WatchCommunicatorMessage.confirmationResponse(toMessageId: message.id, responseType: message.responseType)
                let messageData = try! self.encoder.encode(receivedMessage)
                
                self.addToHistory(message: receivedMessage, isIncoming: false)
                replyHandler(messageData)
                
                // ADD HERE
                let operation = MessageOperation(message: fileTransfer, communicator: self)
                operation.queuePriority = .veryHigh
                self.operationQueue.addOperation(operation)
                
            } else {
                // not a file request
                // convert that to Data
                let messageData = try! self.encoder.encode(response)
                self.addToHistory(message: response, isIncoming: false)
                replyHandler(messageData)
            }
            
        } else {
            // this method might still expect a response, so just send back a confirmation message so the operation won't time out.
            let response = WatchCommunicatorMessage.confirmationResponse(toMessageId: message.id, responseType: message.responseType)
            let messageData = try! self.encoder.encode(response)
            
            self.addToHistory(message: response, isIncoming: false)
            replyHandler(messageData)
        }
    }
    
    public func session(_ session: WCSession,
                 didReceive file: WCSessionFile) {
        
        // get the message from the metadata
        guard let metadata = file.metadata, let messageData = metadata[DictionaryKeys.messageData] as? Data else {
            fatalError("You should have transferred the file while including the message in the metadata")
        }
        
        // convert
        // convert to WatchCommunicatorMessage
        // we force try because WatchCommunicatorMessage should never fail decoding (if you are running unit tests...)
        guard var message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
            logger.error("Received unexpected bad WatchCommunicatorMessage data.  Most likely only to happen during development.")
            return
        }
        
        // check the message is a response.  requestId doesn't need to be set.
        guard case WatchCommunicatorMessage.Kind.response = message.kind else {
            fatalError("The message you responded with did not have a requestMessageId set, and/or you didn't set its kind to .response")
        }
        
        // According to the documentation, you have to move the file before this method returns

        let destinationURL = self.fileLocationMapper(file.fileURL)
        
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: file.fileURL, to: destinationURL)
            
        } catch let error {
            logger.error("Couldn't move transferred file: \(error.localizedDescription)")
        }
        
        // set the file's url to the response message
        message.userInfo[WatchCommunicatorMessage.UserInfoKey.fileURLPath] = destinationURL.path
        
        let urlData = try? self.encoder.encode(destinationURL)
        if urlData == nil {
            logger.error("Could not convert fileURL to Data after receiving the file.")
        }
        message.jsonData = urlData
        
        // message will be a response, meaning you don't need the result. Will also do any necessary cleanup
        _ = self.handleIncomingMessage(message)
        
    }

    public func session(_ session: WCSession,
                        didReceiveUserInfo userInfo: [String : Any]) {
        
        // treat this like you would the application context.
        // the context should have one key, value is data, which you convert to a WatchCommunicatorMessage
        guard let messageData = userInfo[DictionaryKeys.messageData] as? Data else {
            logger.error("You didn't do this properly.  You should always be passing WatchCommunicatorMessages when using this component / WCSession.  (Or it's possible a previous version is passing old data). Received this:  \(userInfo)")
            return
        }
        
        guard let message = try? self.decoder.decode(WatchCommunicatorMessage.self, from: messageData) else {
            logger.error("Received unexpected bad WatchCommunicatorMessage data.  Most likely only to happen during development.")
            return
        }
        
        if let response = self.handleIncomingMessage(message) {
            // the response message will get added to the history in the `transmit(...)` method.
            let operation = MessageOperation(message: response, communicator: self)
            self.operationQueue.addOperation(operation)
        }
    }
}

// MARK: - Operation Helpers
extension WatchCommunicator {
    
    private func findOperation(requestId: String?) -> MessageOperation? {
        
        guard let id = requestId else { return nil }
        
        let op = self.operationQueue.operations.first { operation in
            guard let messageOp = operation as? MessageOperation else {
                return false
            }
            return messageOp.message.id == id
        }
        
        return op as? MessageOperation
    }
    
    private func finishOperation(with requestId: String?, successMessage: WatchCommunicatorMessage?) {
        
        guard let requestId = requestId else {
            logger.debug("We received a finishOperation call without a requestId provided, which suggests this message was not a response to a request, but simply a 'fire and forget' message.")
            return
        }
        
        if let operation = self.findOperation(requestId: requestId) {
            operation.finish(with: .success(successMessage))
        } else {
            logger.warning("Could not find an Operation in the queue corresponding to message with Id: \(requestId).  It might have already been processed via another route, OR the one device sent a response to no request, which is valid/permitted.")
        }
    }
    
    private func finishOperation(with messageId: String?, error: Error) {
        
        guard let requestId = messageId else {
            logger.debug("We received a finishOperation call without a requestId provided, which suggests this message was not a response to a request, but simply a 'fire and forget' message.  Anyway, an error occurred: \(String(describing: error))")
            return
        }
        
        if let operation = self.findOperation(requestId: requestId) {
            let watchError = WatchCommunicatorError.sessionError(details: String(describing: error))
            operation.finish(with: .failure(watchError))
        } else {
            logger.error("Could not find an Operation in the queue corresponding to message with Id: \(requestId).  It could be because that operation already finished because it never expected a response.\n\nAnyway, this error occurred: \(String(describing: error))")
        }
    }
    
    // MARK: - Utility / Private Methods
    fileprivate func suspendQueue() {
        // consider also cancelling the current operation, or consider how to restart it, or set some state in it.
        self.operationQueue.isSuspended = true
    }
    
    fileprivate func resumeQueue() {
        self.operationQueue.isSuspended = false
    }
}

// MARK: - Sending Messages Related

extension WatchCommunicator {
    
    /// You will have to cast the return value to the type you are expecting.  This is generally invoked by one of the Operation subclasses
    @discardableResult
    fileprivate func transmit(_ message: WatchCommunicatorMessage) -> Any? {
        
        guard let validSession = self.validSession else {
            logger.error("You tried transmitting a message when the session was not active.")
            return nil
        }
        
        logger.info("Outgoing Message:\n\(message)")
        self.addToHistory(message: message, isIncoming: false)
        
        switch message.responseType {
        case .applicationContext:
            let messageData = try! self.encoder.encode(message)
            
            guard let validReachableSession = self.validReachableSession else {
                
                let payload: [String: Any] = [
                    DictionaryKeys.messageData: messageData,
                    DictionaryKeys.messageId: message.id
                ]
                
                try? validSession.updateApplicationContext(payload)
                setApplicationContextMessage(message)  // update the last sent message
                // need to clean up the operation here, in case he was expecting someting
                self.finishOperation(with: message.id, successMessage: nil)
                
                return nil
            }
            
            
            validReachableSession.sendMessageData(messageData) { [weak self] responseMessageData in
                guard let self = self else { return }
                self.setApplicationContextMessage(message)
                
                // force try because we know this won't be old data that the watch is sending.
                let responseMessage = try! self.decoder.decode(WatchCommunicatorMessage.self, from: responseMessageData)
                _ = self.handleIncomingMessage(responseMessage)  // there shouldn't be a returned value on a response
                                
            } errorHandler: { [weak self] error in
                guard let self = self else { return }
                self.finishOperation(with: message.id, error: error)
            }
            
            
        case .message, .complicationUserInfo:
            
            let messageData = try! self.encoder.encode(message)
            
            guard let validReachableSession = self.validReachableSession else {
                
                let payload: [String: Any] = [
                    DictionaryKeys.messageData: messageData,
                    DictionaryKeys.messageId: message.id
                ]
                
                #if targetEnvironment(simulator)
                  // your simulator code
                logger.error("You wanted to call transferUserInfo(...) or transferCurrentComplicationUserInfo(...) from the simulator.  This is not supported.  Check the API docs of either of those methods on WCSession")

                #endif
                
                let transfer: WCSessionUserInfoTransfer
                
                #if os(iOS)
                
                if message.responseType == .complicationUserInfo, validSession.remainingComplicationUserInfoTransfers > 0 {
                    transfer = validSession.transferCurrentComplicationUserInfo(payload)
                } else {
                    if validSession.remainingComplicationUserInfoTransfers == 0 {
                        logger.debug("You wanted to send complicationUserInfo but your remainingComplicationUserInfoTransfers is zero.  Sending via transferUserInfo(...) instead.")
                    }
                    transfer = validSession.transferUserInfo(payload)
                }
                
                #else
                
                if message.responseType == .complicationUserInfo {
                    logger.warning("You are trying to send a complicationUserInfo from the watch, which doesn't actually make sense, so it will be sent via transferUserInfo instead.")
                }
                
                transfer = validSession.transferUserInfo(payload)
                
                #endif
                
                
                
                self.userInfoTransfers.append(transfer)
                return transfer
            }
            
            validReachableSession.sendMessageData(messageData) { [weak self] responseMessageData in
                guard let self = self else { return }
                
                // force try because we know this won't be old data that the watch is sending.
                let responseMessage = try! self.decoder.decode(WatchCommunicatorMessage.self, from: responseMessageData)
                _ = self.handleIncomingMessage(responseMessage)  // there shouldn't be a returned value on a response
                
            } errorHandler: { [weak self] error in
                guard let self = self else { return }
                self.finishOperation(with: message.id, error: error)
            }
 
        case .fileTransfer:
            
            let messageData = try! self.encoder.encode(message)
            
            if case WatchCommunicatorMessage.Kind.response = message.kind {
                // this is where you create file transfers
                
                // it's responding to a file request.  So in  your messageHandler, you'll have created
                // a response message with the userInfo fileURLPath set, that's where the file is locally,
                // and will be transferred
                if let urlPath = message.userInfo[WatchCommunicatorMessage.UserInfoKey.fileURLPath] {
                    if FileManager.default.fileExists(atPath: urlPath) {
                        let url = URL(fileURLWithPath: urlPath)
                        let metadata: [String: Any] = [DictionaryKeys.messageData: messageData, DictionaryKeys.messageId: message.id]
                        let transfer = validSession.transferFile(url, metadata: metadata)
                        self.fileTransfers.append(transfer)
                        return transfer
                        // delegate callbacks will handle the rest in terms of finishOperation(...)
                        
                    } else {
                        self.finishOperation(with: message.id, error: WatchCommunicatorError.fileNotFound)
                    }
                } else {
                    self.finishOperation(with: message.id, error: WatchCommunicatorError.noURLPathProvided)
                }
                
            } else {
                // it's a request, so you send it as a normal message, asking for a file, and the UserInfo should give more details as to which file / content
      
                if let validReachableSession = self.validReachableSession {
                    
                    // for files we don't expect a reply because we're asking it to send us a file.
                    validReachableSession.sendMessageData(messageData, replyHandler: nil) { [weak self] error in
                        guard let self = self else { return }
                        self.finishOperation(with: message.id, error: error)
                    }
                } else {
                    let payload: [String: Any] = [
                        DictionaryKeys.messageData: messageData,
                        DictionaryKeys.messageId: message.id
                    ]
                    
                    #if targetEnvironment(simulator)
                      // your simulator code
                    logger.error("You wanted to call transferUserInfo(...) or transferCurrentComplicationUserInfo(...) from the simulator.  This is not supported.  Check the API docs of either of those methods on WCSession")

                    #endif
                    
                    let transfer = validSession.transferUserInfo(payload)
                    self.userInfoTransfers.append(transfer)
                    return transfer
                    
                    // once the userInfo transfer completes, check if the message it sent was a request, if not, you can finishOperation
                }
                
                // you don't call finishOperation here, because we expect a reply
            }
        }
        
        return nil
    }

    
    // sender's side...
    public func session(_ session: WCSession,
                 didFinish fileTransfer: WCSessionFileTransfer,
                 error: Error?) {
        
        // remove the file transfer from list
        let messageId = fileTransfer.file.metadata?[DictionaryKeys.messageId] as? String
        self.fileTransfers.removeAll { transfer in
            let otherMessageId = transfer.file.metadata?[DictionaryKeys.messageId] as? String
            return messageId == otherMessageId
        }
        
        if let error = error {
            self.finishOperation(with: messageId, error: error)
        } else {
            if let messageData = fileTransfer.file.metadata?[DictionaryKeys.messageData] as? Data,
               let message = try? decoder.decode(WatchCommunicatorMessage.self, from: messageData) {
                self.finishOperation(with: messageId, successMessage: message)
            } else {
                logger.error("Could not get message from file transfer's metadata.  It should be there...")
            }
        }
    }
    
    // still all on the sender's side...
    public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        
        let messageId = userInfoTransfer.userInfo[DictionaryKeys.messageId] as? String
        self.userInfoTransfers.removeAll { transfer in
            let otherMessageId = transfer.userInfo[DictionaryKeys.messageId] as? String
            return messageId == otherMessageId
        }
        
        if let error = error {
            self.finishOperation(with: messageId, error: error)
        } else {
            if let messageData = userInfoTransfer.userInfo[DictionaryKeys.messageData] as? Data,
               let message = try? decoder.decode(WatchCommunicatorMessage.self, from: messageData) {
                
                if !message.kind.isRequest {
                    self.finishOperation(with: messageId, successMessage: message)
                }
                
            } else {
                logger.error("Could not get message from userInfoTransfer's userInfo.  It should be there...")
            }
        }
    }
}

// MARK: - Helpers

extension WatchCommunicator {

    fileprivate func postNotificationOnMainQueueAsync(name: NSNotification.Name, object: WatchCommunicatorMessage? = nil) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: object)
        }
    }
}

fileprivate extension Bool {
    var truthyString: String {
        return (self == true) ? "true" : "false"
    }
}


fileprivate class MessageOperation: Operation {
    
    let message: WatchCommunicatorMessage
    let communicator: WatchCommunicator
    
    // is it a fire and forget kind of transmission?
    let expectsResponse: Bool
    
    // for file transfer requests.   You'll never be setting it to nil, otherwise you'll need more elaborate handling
    weak var fileTransfer: WCSessionFileTransfer?
    var transferProgressToken: NSKeyValueObservation?
    
    
    static let timeoutDefault: TimeInterval = 5.0
    static let timeoutForFileTransfers: TimeInterval = 40.0
    static let timeoutDefaultNotReachable: TimeInterval = 2400.0 // 40 minutes
    
    var timeout: TimeInterval {
        if self.communicator.isReachable.value {
            if self.message.responseType == .fileTransfer {
                return MessageOperation.timeoutForFileTransfers
            }
            return MessageOperation.timeoutDefault
        } else {
            return MessageOperation.timeoutDefaultNotReachable
        }
    }

    private var timeoutItem: DispatchWorkItem?
    
    init(message: WatchCommunicatorMessage, communicator: WatchCommunicator) {
        self.message = message
        self.communicator = communicator
        
        if case WatchCommunicatorMessage.Kind.request = message.kind {
            self.expectsResponse = true
        } else {
            self.expectsResponse = false
        }
    }
    
    override var isAsynchronous: Bool {
        return true
    }

    private var _isExecuting: Bool = false {
        willSet {
            willChangeValue(forKey: "isExecuting")
        }
        didSet {
            didChangeValue(forKey: "isExecuting")
        }
    }

    override var isExecuting: Bool {
        return _isExecuting
    }

    private var _isFinished = false {
        willSet {
            willChangeValue(forKey: "isFinished")
        }
        didSet {
            didChangeValue(forKey: "isFinished")
        }
    }

    override var isFinished: Bool {
        return _isFinished
    }
    
    override func start() {
        
        if isCancelled {
            finish(with: .failure(.messageTransmissionWasCancelled))
            return
        }
     
        setTimeout(self.timeout)
        
        _isExecuting = true
     
        sendMessage()
    }
    
    private func setTimeout(_ duration: TimeInterval) {
        self.timeoutItem?.cancel()
        if duration > 0.0 {
            self.timeoutItem = DispatchWorkItem { [weak self] in
                self?.timeOut()
            }
            
            self.communicator.workerQueue.asyncAfter(deadline: .now() + .milliseconds(Int(duration * 1000)), execute: self.timeoutItem!)
        }
    }
    
    private func timeOut() {
        self.timeoutItem = nil
        
        if self.expectsResponse {
            finish(with: .failure(.tookTooLongToRespond))
        } else {
            finish(with: .success(nil))
        }
    }
    
    func sendMessage() {
        // here you deal with the various types of messages, and figure out if you send applicationContext, as a message, or a file.
        if let fileTransfer = self.communicator.transmit(self.message) as? WCSessionFileTransfer {
            self.fileTransfer = fileTransfer
            setTimeout(self.timeout)
            observeProgress(of: fileTransfer)
        }
        
        if self.expectsResponse == false {
            setTimeout(0.5)
        }
    }
    
    override func cancel() {
        stopObservingFileTransferProgress()
        self.timeoutItem?.cancel()
        self.fileTransfer?.cancel()
        super.cancel()
    }
    
    func finish(with result: WatchCommunicatorResult) {
        
        stopObservingFileTransferProgress()
        self.timeoutItem?.cancel()
        
        guard !_isFinished, _isExecuting else {
            return  // already happened
        }
        
        switch result {
        case .success:
            break
        case .failure(let error):
            logger.error("Operation failed:  \(String(describing: error))")
        }

        _isFinished = true
        _isExecuting = false
    }
    
    private func observeProgress(of fileTransfer: WCSessionFileTransfer?) {
        guard let transfer = fileTransfer else { return }
        
        transferProgressToken = transfer.progress.observe(\.fractionCompleted, options: .new) { progress, change in
            print("File transfer progress: \(String(format: "%.1f", progress.fractionCompleted * 100))")
        }
    }
    
    private func stopObservingFileTransferProgress() {
        transferProgressToken?.invalidate()
    }
}

// same as a message operation but has a response handler
fileprivate class MessageRequestOperation: MessageOperation {
    
    // only relevant for request type operations
    var responseHandler: ((_ result: WatchCommunicatorResult) -> Void)?
    
    override func finish(with result: WatchCommunicatorResult) {
        
        guard let completion = self.responseHandler else {
            let errorMessage = "You had a MessageRequestOperation without a responseHandler provided.  There is no functional reason to do this, so this is an error"
            logger.error(errorMessage)
            finish(with: .failure(.invalidConfiguration(details: errorMessage)))
            return
        }
        
        communicator.completionQueue.async {
            completion(result)
        }
        
        super.finish(with: result)
    }
}

//MARK: - Helpers

/// A way to track changes to a given parameter.  You initialize these with a value, then when they change, they will notify their single (if any) listener
extension WatchCommunicator {
    
    class DynamicChangeOnNotifyingThread<Value: Equatable> {
        
        typealias Listener = (Value) -> ()
        var listener: Listener?
        
        let notifyQueue: DispatchQueue
        
        init(_ value: Value, notifyQueue: DispatchQueue = .main) {
            self.notifyQueue = notifyQueue
            self.value = value
        }
        
        /// Explicitly get the current value being managed by this instance.
        var value: Value {
            didSet {
                if oldValue != self.value {
                    self.notifyQueue.async { [unowned self] in
                        self.listener?(self.value)
                    }
                }
            }
        }
        
        /// register a new listener for to receive updates whenever the value changes.
        func bind(_ listener: Listener?) {
            self.listener = listener
        }
        
        /// Register for changes in the Dynamic property, and also update the listener with the value right now.
        func bindAndFire(_ listener: Listener?) {
            self.listener = listener
            
            self.notifyQueue.async { [unowned self] in
                self.listener?(self.value)
            }
        }
        
        /// Send the current value to the listener right now.
        func fire() {
            self.notifyQueue.async { [unowned self] in
                self.listener?(self.value)
            }
        }
    }
}
