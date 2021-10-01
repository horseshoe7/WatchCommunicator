//
//  LogInterfaceController.swift
//  WatchCommunicator WatchKit Extension
//
//  Created by Stephen O'Connor (MHP) on 17.09.21.
//

import WatchKit
import Foundation





class LogInterfaceController: WKInterfaceController {

    static let identifier = "LogInterfaceController"
    
    @IBOutlet var reachabilityButton: WKInterfaceButton!
    @IBOutlet var sendButton: WKInterfaceButton!
    @IBOutlet var table: WKInterfaceTable!
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }
    
    var application: ExtensionDelegate? {
        guard let application = WKExtension.shared().delegate as? ExtensionDelegate else {
            return nil
        }
        return application
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        addObservers()
    }
    
    override func didAppear() {
        super.didAppear()
        
        if let communicator = self.application?.communicator {
            self.reloadTableData(messages: communicator.messageHistory)
        }
    }
    
    override func willDisappear() {
        super.willDisappear()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
        cancelObservers()
    }
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotification(_:)), name: .didReceiveWatchMessage, object: nil)
        
        if let communicator = self.application?.communicator {
            communicator.isReachable.bindAndFire { [weak self] isReachable in
                let color: UIColor = isReachable ? .init(red: 0.0, green: 0.4, blue: 0.0, alpha: 1.0) : .init(red: 0.4, green: 0.0, blue: 0.0, alpha: 1.0)
                self?.reachabilityButton.setBackgroundColor(color)
                
                let text: String = isReachable ? "Reachable" : "Not Reachable"
                self?.reachabilityButton.setTitle(text)
            }
        }
    }
    
    private func cancelObservers() {
        NotificationCenter.default.removeObserver(self, name: .didReceiveWatchMessage, object: nil)
    }
    
    @objc
    private func handleNotification(_ note: Notification) {
        
        guard let communicator = note.object as? WatchCommunicator else {
            logger.error("Expected the notification's object to be a WatchCommunicator")
            return
        }
        self.reloadTableData(messages: communicator.messageHistory)
    }
    
    private func reloadTableData(messages: [WatchMessageHistoryItem]) {

        
        let rowControllers: [MessageRowController] = messages.map { historyItem in
            
            let viewModel = WatchHistoryItemViewModel(historyItem)
            
            switch historyItem.message.contentType {
            case .imageFile:
                let rowController = ImageRowController()
                rowController.viewModel = viewModel
                return rowController
            default:
                let rowController = TextRowController()
                rowController.viewModel = viewModel
                return rowController
            }
        }
        
        self.table.setRowTypes(rowControllers.map { $0.interfaceIdentifier })
        
        for (index, rowController) in rowControllers.enumerated() {
        
            // still have to assign the data to it
            if let row = table.rowController(at: index) as? MessageRowController {
                row.viewModel = rowController.viewModel
                row.refresh()
            }
        }
    }


    @IBAction
    func didPressSendButton() {
        
    }
}


protocol MessageRowController: NSObjectProtocol {
    var interfaceIdentifier: String { get }
    var viewModel: WatchHistoryItemViewModel? { get set }
    func refresh()
}

class TextRowController: NSObject, MessageRowController {
    /// this has to match in the Storyboard
    static let rowIdentifierOutgoing = "TextDisplayCell_Outgoing"
    static let rowIdentifierIncoming = "TextDisplayCell_Incoming"
    
    @IBOutlet weak var platformOriginLabel: WKInterfaceLabel!
    @IBOutlet weak var timestampLabel: WKInterfaceLabel!
    @IBOutlet weak var textLabel: WKInterfaceLabel!
    
    var interfaceIdentifier: String {
        
        if let historyItem = viewModel?.historyItem {
            return historyItem.isIncoming ? Self.rowIdentifierIncoming : Self.rowIdentifierOutgoing
        } else {
            return Self.rowIdentifierIncoming
        }
    }
    
    var viewModel: WatchHistoryItemViewModel?
    
    func refresh() {
        guard let viewModel = self.viewModel else {
            timestampLabel.setText(nil)
            textLabel.setText(nil)
            return
        }
        
        self.timestampLabel.setText(viewModel.timestampText)
        self.timestampLabel.setTextColor(viewModel.timestampColor)
        
        self.textLabel.setText(viewModel.messageText)
        self.textLabel.setTextColor(viewModel.messageColor)
        
        self.platformOriginLabel.setText(viewModel.plaformOriginIcon)
    }
}

class ImageRowController: NSObject, MessageRowController {
    
    /// this has to match in the Storyboard
    static let rowIdentifier = "ImageDisplayCell"
    
    @IBOutlet weak var platformOriginLabel: WKInterfaceLabel!
    @IBOutlet weak var timestampLabel: WKInterfaceLabel!
    @IBOutlet weak var image: WKInterfaceImage!
    @IBOutlet weak var captionLabel: WKInterfaceLabel!
    
    var interfaceIdentifier: String { return Self.rowIdentifier }
    var viewModel: WatchHistoryItemViewModel?
    
    func refresh() {
        guard let viewModel = self.viewModel else {
            timestampLabel.setText(nil)
            image.setImage(nil)
            return
        }
         
        self.timestampLabel.setText(viewModel.timestampText)
        self.timestampLabel.setTextColor(viewModel.timestampColor)
        
        self.captionLabel.setText(viewModel.messageText)
        self.captionLabel.setTextColor(viewModel.messageColor)
        
        self.platformOriginLabel.setText(viewModel.plaformOriginIcon)
        
        guard let fileURL = viewModel.historyItem.message.fileURL else {
            self.captionLabel.setText("(Image URL Missing)")
            self.image.setImage(nil)
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            self.captionLabel.setText("File Not found at imageURL path.")
            self.image.setImage(nil)
            return
        }
        
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            self.captionLabel.setText("Could not load image from URL")
            self.image.setImage(nil)
            return
        }
        
        self.image.setImage(image)
        self.captionLabel.setText(nil)
    }
}

