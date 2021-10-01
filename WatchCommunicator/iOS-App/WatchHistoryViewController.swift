//
//  WatchHistoryViewController.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 20.09.21.
//

import UIKit



class WatchHistoryViewController: UIViewController {

    @IBOutlet weak var reachabilityLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var messageViewModels: [WatchHistoryItemViewModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addObservers()
    }
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotification(_:)), name: .didReceiveWatchMessage, object: nil)
        
        let communicator = (UIApplication.shared.delegate as! AppDelegate).communicator
        
        communicator.isReachable.bindAndFire { [weak self] isReachable in
            
            let color: UIColor = isReachable ? .init(red: 0.0, green: 0.4, blue: 0.0, alpha: 1.0) : .init(red: 0.4, green: 0.0, blue: 0.0, alpha: 1.0)
            self?.reachabilityLabel.backgroundColor = color
            
            let text: String = isReachable ? "Reachable" : "Not Reachable"
            self?.reachabilityLabel.text = text
        }
    }
    
    private func cancelObservers() {
        NotificationCenter.default.removeObserver(self, name: .didReceiveWatchMessage, object: nil)
    }
    
    @objc
    private func handleNotification(_ note: Notification) {
        
        // note, the incoming message gets generally handled by the WatchCommunicator's .messageHandler
        // but if you need to do something specific with it...
        
        guard let communicator = note.object as? WatchCommunicator else {
            logger.error("Expected the notification's object to be a WatchCommunicator")
            return
        }
        if let message = note.userInfo?[UserInfoKeyMessage] as? WatchCommunicatorMessage {
            // do something with the message
        }
        
        // in this case we are interested in showing the messageHistory
        self.reloadTableData(messages: communicator.messageHistory)
    }
    
    private func reloadTableData(messages: [WatchMessageHistoryItem]) {
        
        self.messageViewModels = messages.map({ return WatchHistoryItemViewModel($0) })
        self.tableView.reloadData()
        
    }
    

    @IBAction
    func pressedRequestLogs(_ button: UIButton?) {
        
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            
            let message = WatchCommunicatorMessage.request(responseType: .fileTransfer, contentType: .remoteLogFile, userInfo: [:], jsonData: nil)
            delegate.communicator.sendRequestMessage(message) { result in
                switch result {
                case .success(let responseMessage):
                    break // now you tap on the cell to view the log.

                case .failure(let error):
                    logger.error("Failed getting the logs: \(String(describing: error))")
                }
            }
        }
    }
    
    @IBAction
    func pressedSendSimpleMessage(_ button: UIButton?) {
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            
            let fakeLogStatement = "From iPhone"
            let payload = try? delegate.communicator.encoder.encode(fakeLogStatement)
            let message = WatchCommunicatorMessage.response(toMessageId: nil,
                                                         responseType: .message,
                                                         contentType: .remoteLogStatement,
                                                         userInfo: [:],
                                                         jsonData: payload)
            
            delegate.communicator.sendResponseMessage(message)
        }
    }
    
    @IBAction
    func pressedSendApplicationContext(_ button: UIButton?) {
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            let message = delegate.communicator.applicationContextAccessor(nil)
            delegate.communicator.sendResponseMessage(message)
        }
    }
    
    @IBAction
    func didPressSendImage(_ button: UIButton?) {
        
        guard let imageURL = Bundle.main.url(forResource: "cute-puppy.jpeg", withExtension: nil) else {
            logger.error("No image available in the bundle to send.")
            return
        }
        
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else {
            logger.error("Could not get the AppDelegate for some weird reason")
            return
        }
        
        var message = WatchCommunicatorMessage.response(toMessageId: nil, responseType: .fileTransfer, contentType: .imageFile, userInfo: [:], jsonData: nil)
        message.fileURL = imageURL
        
        // a 'response' with no reference messageId is considered a 'notification' message,
        // but under the hood it's just a response... i.e. it doesn't require a response
        // whereas a request requires a response.
        delegate.communicator.sendResponseMessage(message)
    }
}

extension WatchHistoryViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.messageViewModels.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let vm = self.messageViewModels[indexPath.row]
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: vm.cellIdentifier, for: indexPath) as? MessageHistoryCell else {
            fatalError("You hooked it up wrong.")
        }
        
        cell.applyViewModel(vm)
        
        return cell
    }
}

extension WatchHistoryItemViewModel {
    var cellIdentifier: String {
        return MessageHistoryCell.reuseIdentifier
    }
}

class MessageHistoryCell: UITableViewCell {
    
    static let reuseIdentifier = "MessageHistoryCell"
    
    @IBOutlet weak var platformOriginLabel: UILabel!
    @IBOutlet weak var timestampLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    
    // it's more a convenience to bind the view model to the cell
    var viewModel: WatchHistoryItemViewModel?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.platformOriginLabel.clipsToBounds = true
        self.platformOriginLabel.layer.cornerRadius = 4.0
    }
    
    func applyViewModel(_ viewModel: WatchHistoryItemViewModel) {
        self.viewModel = viewModel
        
        guard let viewModel = self.viewModel else {
            timestampLabel.text = nil
            messageLabel.text = nil
            return
        }
        
        self.platformOriginLabel.text = viewModel.plaformOriginIcon
        
        self.timestampLabel.text = viewModel.timestampText
        self.timestampLabel.textColor = viewModel.timestampColor
        
        self.messageLabel.text = viewModel.messageText
        self.messageLabel.textColor = viewModel.messageColor
        
        self.contentView.backgroundColor = viewModel.backgroundColor
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.platformOriginLabel.layer.cornerRadius = 4.0
        
    }
}
