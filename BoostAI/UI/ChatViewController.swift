//
//  ChatViewController.swift
//  BoostAIUI
//
//  Copyright © 2021 boost.ai
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  Please contact us at contact@boost.ai if you have any questions.
//

import UIKit

public protocol ChatViewControllerDelegate {
    /// Return a fully custom response view (must be a subclass of ChatResponseView
    func chatResponseView(backend: ChatBackend) -> ChatResponseView?
    
    /// Return a custom subclass of a menu view controller if needed
    func menuViewController(backend: ChatBackend) -> MenuViewController?
    
    /// Return a custom subclass of the conversation feedback view controller if needed
    func conversationFeedbackViewController(backend: ChatBackend) -> ConversationFeedbackViewController?
}

open class ChatViewController: UIViewController {
    private let cellReuseIdentifier: String = "ChatDialogCell"
    private weak var bottomConstraint: NSLayoutConstraint!
    private weak var feedbackBottomConstraint: NSLayoutConstraint?
    private weak var bottomInnerConstraint: NSLayoutConstraint!
    private weak var inputWrapperView: UIView!
    private weak var inputWrapperInnerView: UIView!
    private weak var inputWrapperInnerBorderView: UIView!
    private weak var wrapperView: UIView!
    private weak var waitingForAgentResponseView: UIView?
    private var isKeyboardShown: Bool = false
    private var lastAvatarURL: String?
    private var inputInnerStackViewTopConstraint: NSLayoutConstraint!
    private var inputInnerStackViewBottomConstraint: NSLayoutConstraint!
    private var statusMessage: UIView?
    
    /// Chatbot backend instance
    public var backend: ChatBackend!
    
    /// Chat view controller backend for providing custom views
    public var delegate: ChatViewControllerDelegate?
    
    /// Data source for chat responses (for handling custom JSON responses or overriding the default implementations)
    public var chatResponseViewDataSource: ChatResponseViewDataSource?
    
    /// Font used for body text
    public var bodyFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    
    /// Font used for headlines
    public var headlineFont: UIFont = UIFont.preferredFont(forTextStyle: .headline)
    
    /// Font used for menu titles
    public var menuItemFont: UIFont = UIFont.preferredFont(forTextStyle: .title3)
    
    /// Font used for footnote sized strings (status messages, character count text etc.)
    public var footnoteFont: UIFont = UIFont.preferredFont(forTextStyle: .footnote)
    
    /// Primary color – setting this will override color from server config
    public var primaryColor: UIColor?
    
    /// Contrast color – setting this will override color from server config
    public var contrastColor: UIColor?
    
    /// Client message color – setting this will override color from server config (config name: `clientMessageColor`)
    public var userTextColor: UIColor?
    
    /// Client message background color – setting this will override color from server config (config name: `clientMessageBackground`)
    public var userBackgroundColor: UIColor?
    
    /// Server message color – setting this will override color from server config (config name: `serverMessageColor`)
    public var vaTextColor: UIColor?
    
    /// Server message background color – setting this will override color from server config (config name: `serverMessageBackground`)
    public var vaBackgroundColor: UIColor?
    
    /// Background color for action links – setting this will override color from server config (config name: `linkBelowBackground`)
    public var buttonBackgroundColor: UIColor?
    
    /// Text color for action links – setting this will override color from server config (config name: `linkBelowColor`)
    public var buttonTextColor: UIColor?
    
    public var feedbackSuccessMessage: String = NSLocalizedString("Thanks for the feedback.\nWe sincerely appreciate your insight, it helps us build a better customer experience.", comment: "")
    
    /// The scroll view containing chatStackView
    public weak var scrollView: UIScrollView!
    /// The stackView that contains all of the dialog (a list of `ChatResponseView`)
    public weak var chatStackView: UIStackView!
    
    /// Max character count allowed for user input
    public var maxCharacterCount: Int = 110
    /// Text view for user input
    public weak var inputTextView: UITextView!
    /// Placeholder label displayed when user input is empty
    public weak var inputTextViewPlaceholder: UILabel!
    /// Character count label that displayes characters typed/max characters allowe d(i.e. "14 / 110")
    public weak var characterCountLabel: UILabel!
    /// Button for submitting the user input text
    public weak var submitTextButton: UIButton!
    
    /// UIImage icon for button used to close the chat
    public var closeIconImage: UIImage? = UIImage(named: "close", in: Bundle(for: ChatViewController.self), compatibleWith: nil)
    /// UIImage icon for button used to minimize the chat
    public var minimizeIconImage: UIImage? = UIImage(named: "minimize", in: Bundle(for: ChatViewController.self), compatibleWith: nil)
    /// UIImage icon for button used to display the menu
    public var menuIconImage: UIImage? = UIImage(named: "question-mark-circle", in: Bundle(for: ChatViewController.self), compatibleWith: nil)
    
    /// Menu view controller
    public var menuViewController: MenuViewController?
    
    /// Conversation feedback view controller
    public var feedbackViewController: ConversationFeedbackViewController?
    
    /// Bar button item for closing the chat
    public weak var closeBarButtonItem: UIBarButtonItem?
    /// Bar button item for minimizing the chat
    public weak var minimizeBarButtonItem: UIBarButtonItem?
    /// Bar button item for displaying the menu
    public weak var menuBarButtonItem: UIBarButtonItem?
    /// Bar button item for di
    public weak var filterBarButtonItem: UIBarButtonItem?
    
    /// Should we hide the 1px line under the navigation bar?
    public var shouldHideNavigationBarLine: Bool = true
    
    /// "Chat is secure" banner
    public weak var secureChatBanner: UIView?
    
    /// Is chat secure?
    open var isSecureChat: Bool = false {
        didSet {
            if isSecureChat {
                showSecureChatBanner()
            } else {
                hideSecureChatBanner()
            }
        }
    }
    
    /// Is the user blocked from inputting text?
    open var isBlocked: Bool = true {
        didSet {
            inputTextView.isEditable = !isBlocked
            submitTextButton.isEnabled = !isBlocked && inputTextView.text.count > 0
            inputTextViewPlaceholder.isHidden = inputTextView.text.count > 0 || isBlocked
        }
    }
    
    /// Is the user waiting for agent response?
    /// (Human agent is typing or virtual agent has not responded to a message yet.)
    open var isWaitingForAgentResponse: Bool = false {
        didSet {
            if isWaitingForAgentResponse {
                waitingForAgentResponseView?.removeFromSuperview()
                
                let agentView = delegate?.chatResponseView(backend: backend) ?? ChatResponseView(backend: backend)
                agentView.vaTextColor = agentView.vaTextColor ?? vaTextColor
                agentView.configureAsWaitingForRemoteResponse()
                
                if let avatarURL = lastAvatarURL, let url = URL(string: avatarURL) {
                    let _ = ImageLoader.shared.loadImage(url) { (result) in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let image):
                                agentView.avatarImageView.image = image
                            case .failure(_):
                                break
                            }
                        }
                    }
                }
                
                chatStackView.addArrangedSubview(agentView)
                
                waitingForAgentResponseView = agentView
            } else {
                waitingForAgentResponseView?.layer.opacity = 0
            }
        }
    }
    
    /// The list of responses from the API
    open var responses: [Response] = []
    
    // MARK: - Initialization
    
    public init(backend: ChatBackend) {
        super.init(nibName: nil, bundle: nil)
        
        self.backend = backend
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.navigationBar.barTintColor = .black
        navigationController?.navigationBar.tintColor = .white
        
        setupView()
        removeNavigationBarBorder()
        
        // When the backend is ready (has received config data), start a new conversation
        backend.onReady { [weak self] (_, _) in
            DispatchQueue.main.async {
                if let config = self?.backend.config {
                    self?.updateStyle(config: config)
                }
                
                self?.startConversation()
            }
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setupNavigationItems()
        
        if let config = backend.config {
            updateStyle(config: config)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
            self.scrollToEnd(animated: false)
        })
        
        scrollToEnd(animated: false)
    }
    
    // MARK: - Conversation
    
    /// Start the conversation (add an observer for messages and start a new conversation throught the backend)
    open func startConversation() {
        self.isBlocked = backend.isBlocked
        
        let messages = backend.messages
        for message in messages {
            handleReceivedMessage(message, animateElements: false)
        }
        
        self.scrollToEnd(animated: false)
        
        backend.newMessageObserver(self) { [weak self] (message, error) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.isBlocked = self.backend.isBlocked
                
                if let error = error {
                    self.isWaitingForAgentResponse = false
                    self.addStatusMessage(message: error.localizedDescription, isError: true)
                } else if let message = message {
                    self.handleReceivedMessage(message)
                }
                
                // Scroll to the end if we have any responses
                if message?.response != nil || (message?.responses?.count ?? 0) > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.scrollToEnd(animated: true)
                    }
                }
            }
        }
        
        backend.newConfigObserver(self) { (config, error) in
            DispatchQueue.main.async {
                if let config = config {
                    self.updateStyle(config: config)
                }
            }
        }
        
        // Start new conversation if no messages exists
        if messages.count == 0 {
            isWaitingForAgentResponse = true
            backend.start()
        }
    }
    
    open func handleReceivedMessage(_ message: APIMessage, animateElements: Bool = true) {
        // Merge responses from the `response` and `responses` keys on the message
        var responses: [Response] = message.responses ?? []
        if let response = message.response {
            responses.append(response)
        }
        
        // Remove upload buttons after a new message has arrived
        for view in chatStackView.arrangedSubviews {
            if let responseView = view as? ChatResponseView {
                responseView.removeUploadButtons()
            }
        }
        
        // We only want to show feedback icons on messages received after the welcome message (and after consent messages <-- isBlocked == true)
        let welcomeMessageIndex = backend.messages.firstIndex(where: { !($0.conversation?.state.isBlocked ?? false) })
        let currentMessageIndex = backend.messages.firstIndex(where: { $0.response?.id == message.response?.id })
        let showFeedback = !self.isBlocked && (currentMessageIndex ?? 1) > (welcomeMessageIndex ?? 0)
        
        isWaitingForAgentResponse = message.conversation?.state.humanIsTyping ?? false
        isSecureChat = message.conversation?.state.authenticatedUserId != nil || (isSecureChat && responses.first?.source == .client)
        
        for response in responses {
            self.responses.append(response)
            
            // Create view for the response
            let responseView = delegate?.chatResponseView(backend: backend) ?? ChatResponseView(backend: backend)
            responseView.delegate = responseView.delegate ?? self
            responseView.dataSource = responseView.dataSource ?? chatResponseViewDataSource
            responseView.showFeedback = showFeedback
            responseView.headlineFont = headlineFont
            responseView.bodyFont = bodyFont
            responseView.footnoteFont = footnoteFont
            responseView.primaryColor = primaryColor
            responseView.userTextColor = responseView.userTextColor ?? userTextColor
            responseView.userBackgroundColor = responseView.userBackgroundColor ?? userBackgroundColor
            responseView.vaTextColor = responseView.vaTextColor ?? vaTextColor
            responseView.vaBackgroundColor = responseView.vaBackgroundColor ?? vaBackgroundColor
            responseView.buttonTextColor = responseView.buttonTextColor ?? buttonTextColor
            responseView.buttonBackgroundColor = responseView.buttonBackgroundColor ?? buttonBackgroundColor
            responseView.configureWith(response: response, conversation: message.conversation, animateElements: animateElements, sender: self)
            chatStackView.addArrangedSubview(responseView)
            
            waitingForAgentResponseView?.removeFromSuperview()
            waitingForAgentResponseView = nil
            
            // Store last avatar URL for use in "typing" indicator rows
            lastAvatarURL = message.response?.avatarUrl ?? message.responses?.last?.avatarUrl ?? self.lastAvatarURL
            
            // Show waiting for agent response view if we are in virtual agent mode
            let chatStatus = backend.lastResponse?.conversation?.state.chatStatus ?? .virtual_agent
            if response.source == .client && chatStatus == .virtual_agent {
                isWaitingForAgentResponse = true
            }
        }
        
        removeStatusMessage()
    }
    
    /// Send user input text
    @objc open func sendText() {
        guard inputTextView.text.count > 0 else { return }
        
        backend.message(value: inputTextView.text)
        inputTextView.text = ""
        inputTextViewPlaceholder.isHidden = false
        
        updateCharacterCount()
    }
    
    /// Update the character count for the user input message
    open func updateCharacterCount() {
        characterCountLabel.text = "\(inputTextView.text.count) / \(maxCharacterCount)"
        
        let isMultiline = inputTextView.intrinsicContentSize.height > 30
        let verticalMargin: CGFloat = isMultiline ? 15 : 10
        
        inputInnerStackViewTopConstraint.constant = verticalMargin
        inputInnerStackViewBottomConstraint.constant = verticalMargin
        characterCountLabel.isHidden = !isMultiline
    }
    
    /// Scroll to the end of the chat
    open func scrollToEnd(animated: Bool) {
        if scrollView.contentSize.height > scrollView.bounds.height {
            scrollView.setContentOffset(CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height), animated: animated)
        }
    }
    
    // MARK: - Secure chat
    
    private let bannerHeight: CGFloat = 38
    
    /// Show banner that indicates that the chat is secure
    open func showSecureChatBanner() {
        guard secureChatBanner == nil else {
            return
        }
        
        let banner = UIView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = UIColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1)
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowRadius = 5
        banner.layer.shadowOpacity = 0.3
        banner.layer.shadowOffset = .zero
        
        let iconImageView = UIImageView(image: UIImage(named: "secure", in: Bundle(for: ChatViewController.self), compatibleWith: nil))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 15).isActive = true
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = footnoteFont
        label.textColor = UIColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 1.0)
        label.text = backend.config?.language(languageCode: backend.languageCode).loggedIn
        
        let stackView = UIStackView(arrangedSubviews: [iconImageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.spacing = 5
        
        let padding: CGFloat = 10
        let constraints = [
            stackView.topAnchor.constraint(equalTo: banner.topAnchor, constant: padding),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: banner.leadingAnchor, constant: padding),
            banner.trailingAnchor.constraint(greaterThanOrEqualTo: stackView.trailingAnchor, constant: padding),
            banner.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: padding),
            stackView.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        
        banner.addSubview(stackView)
        view.addSubview(banner)
        
        var insets = scrollView.contentInset
        insets.top += bannerHeight
        scrollView.contentInset = insets
        
        NSLayoutConstraint.activate(constraints)
        
        secureChatBanner = banner
    }
    
    /// Hide the "secure chat" banner
    open func hideSecureChatBanner() {
        guard let secureChatBanner = secureChatBanner else { return }
        
        secureChatBanner.removeFromSuperview()
        self.secureChatBanner = nil
        
        var insets = scrollView.contentInset
        insets.top -= bannerHeight
        scrollView.contentInset = insets
    }
    
    open func addStatusMessage(message: String, isError: Bool = false) {
        removeStatusMessage()
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = footnoteFont
        label.textColor = isError ? .red : .darkGray
        label.text = message
        
        statusMessage = label
        
        chatStackView.addArrangedSubview(label)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
            self.scrollToEnd(animated: true)
        })
    }
    
    open func removeStatusMessage() {
        statusMessage?.removeFromSuperview()
    }
    
    // MARK: - Actions
    
    /// Dismiss the current view controller
    @objc func dismissSelf() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc public func _closeConversation() {
        // If we are already showing the feedback and the user tries to close the window, allow it
        if let _ = feedbackViewController {
            dismissSelf()
        }
        
        // Should we request conversation feedback? Show feedback dialogue
        let hasClientMessages = backend.messages.filter({ (apiMessage) -> Bool in
            return apiMessage.response?.source ?? apiMessage.responses?.first?.source ?? .bot == .client
        }).count > 0
        guard let config = backend.config, !config.requestConversationFeedback || !hasClientMessages else {
            showConversationFeedbackInput()
            return
        }
        
        // If all else fails, close the window
        dismissSelf()
    }
    
    /// Show the help menu
    @objc func toggleHelpMenu() {
        if let _ = menuViewController {
            hideMenu()
        } else {
            showMenu()
        }
    }
    
    @objc func showFilterMenu() {
        let filterPickerVC = FilterPickerViewController()
        filterPickerVC.title = backend.config?.language(languageCode: backend.languageCode).filterSelect
        filterPickerVC.currentFilter = backend.filter
        filterPickerVC.filters = backend.config?.filters
        filterPickerVC.didSelectFilterItem = { [weak self] (filterItem) in
            self?.backend.filter = filterItem
            self?.setupNavigationItems()
        }
        
        let navController = UINavigationController(rootViewController: filterPickerVC)
        navController.modalPresentationStyle = .popover
        navController.popoverPresentationController?.barButtonItem = filterBarButtonItem
        navController.popoverPresentationController?.delegate = self
        
        present(navController, animated: true)
        
        hideMenu()
    }
    
    // MARK: - View layout
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        bottomInnerConstraint.constant = isKeyboardShown ? 10 : view.safeAreaInsets.bottom + 10
    }
    
    private func setupNavigationItems() {
        let filter = backend.filter ?? backend.config?.filters?.first
        let menuBarButtonItem = createNavigationItem(image: menuIconImage, action: #selector(toggleHelpMenu), last: filter == nil)
        
        var items: [UIBarButtonItem] = []
        
        // Add "close" button if we are presented modally (user needs a way to close the conversation)
        if let _ = presentingViewController {
            let minimizeBarButtonItem = createNavigationItem(image: minimizeIconImage, action: #selector(dismissSelf))
            let closeBarButtonItem = createNavigationItem(image: closeIconImage, action: #selector(_closeConversation))
            items = [closeBarButtonItem, minimizeBarButtonItem, menuBarButtonItem]
            self.minimizeBarButtonItem = minimizeBarButtonItem
            self.closeBarButtonItem = closeBarButtonItem
            
        } else {
            items = [menuBarButtonItem]
        }
        
        if let filter = backend.filter ?? backend.config?.filters?.first {
            let button = createFilterNavigationItem(filter: filter)
            items.append(button)
            filterBarButtonItem = button
        }
        
        self.menuBarButtonItem = menuBarButtonItem
        
        navigationItem.rightBarButtonItems = items
    }
    
    private func createNavigationItem(image: UIImage?, action: Selector, last: Bool = false) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setImage(image, for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 32, height: 44)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: last ? 20 : 0, bottom: 0, right: 0)
        
        return UIBarButtonItem(customView: button)
    }
    
    private func createFilterNavigationItem(filter: ConfigFilter) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        let icon = UIImage(named: "chevron-down-light", in: Bundle(for: ChatViewController.self), compatibleWith: nil)
        button.setTitle(filter.title, for: .normal)
        button.setImage(icon, for: .normal)
        button.imageView?.tintColor = .white
        button.semanticContentAttribute = .forceRightToLeft
        button.addTarget(self, action: #selector(showFilterMenu), for: .touchUpInside)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 10)
        button.accessibilityLabel = backend.config?.language(languageCode: backend.languageCode).filterSelect
        
        return UIBarButtonItem(customView: button)
    }
    
    private func setupView() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        let shadowWidth: CGFloat = 4
        let cornerRadius: CGFloat = 3
        
        let wrapperView = UIView()
        wrapperView.backgroundColor = .white
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        
        let scrollContainerView = UIView()
        scrollContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollContainerView.backgroundColor = .white
        
        let scrollTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(resignInputFocus))
        scrollTapRecognizer.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(scrollTapRecognizer)
        
        let chatStackView = UIStackView()
        chatStackView.translatesAutoresizingMaskIntoConstraints = false
        chatStackView.axis = .vertical
        chatStackView.spacing = 20
        
        scrollContainerView.addSubview(chatStackView)
        scrollView.addSubview(scrollContainerView)
        wrapperView.addSubview(scrollView)
        
        let inputWrapperView = UIView()
        inputWrapperView.translatesAutoresizingMaskIntoConstraints = false
        inputWrapperView.backgroundColor = UIColor.BoostAI.lightGray
        inputWrapperView.setContentHuggingPriority(.required, for: .vertical)
        
        let inputWrapperTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusInput))
        inputWrapperTapRecognizer.numberOfTapsRequired = 1
        inputWrapperView.addGestureRecognizer(inputWrapperTapRecognizer)
        
        let topBorderView = UIView()
        topBorderView.translatesAutoresizingMaskIntoConstraints = false
        topBorderView.backgroundColor = UIColor.BoostAI.gray
        topBorderView.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        let inputWrapperInnerView = UIView()
        inputWrapperInnerView.translatesAutoresizingMaskIntoConstraints = false
        inputWrapperInnerView.backgroundColor = .white
        inputWrapperInnerView.layer.borderColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.2).cgColor
        inputWrapperInnerView.layer.borderWidth = 1
        inputWrapperInnerView.layer.cornerRadius = cornerRadius
        
        let inputWrapperInnerBorderView = UIView()
        inputWrapperInnerBorderView.translatesAutoresizingMaskIntoConstraints = false
        inputWrapperInnerBorderView.backgroundColor = inputWrapperView.backgroundColor
        inputWrapperInnerBorderView.layer.cornerRadius = cornerRadius
        
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .white
        textView.textColor = .darkText
        textView.textContainerInset = UIEdgeInsets.zero
        textView.font = bodyFont
        textView.delegate = self
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        let textViewPlaceholder = UILabel()
        textViewPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        textViewPlaceholder.text = NSLocalizedString("Ask your question here", comment: "")
        textViewPlaceholder.textColor = .darkText
        textViewPlaceholder.isHidden = true
        textView.addSubview(textViewPlaceholder)
        
        let characterCountLabel = UILabel()
        characterCountLabel.translatesAutoresizingMaskIntoConstraints = false
        characterCountLabel.textColor = UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        characterCountLabel.font = footnoteFont
        characterCountLabel.text = "0 / \(maxCharacterCount)"
        characterCountLabel.isHidden = true
        
        let submitTextButton = UIButton(type: .custom)
        submitTextButton.translatesAutoresizingMaskIntoConstraints = false
        submitTextButton.setImage(UIImage(named: "submit-text-icon", in: Bundle(for: ChatResponseView.self), compatibleWith: nil), for: .normal)
        submitTextButton.setImage(UIImage(named: "submit-text-icon-disabled", in: Bundle(for: ChatResponseView.self), compatibleWith: nil), for: .disabled)
        submitTextButton.isEnabled = false
        submitTextButton.addTarget(self, action: #selector(sendText), for: .touchUpInside)
        submitTextButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        submitTextButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        
        let rightInnerStackView = UIStackView(arrangedSubviews: [characterCountLabel, submitTextButton])
        rightInnerStackView.translatesAutoresizingMaskIntoConstraints = false
        rightInnerStackView.axis = .vertical
        rightInnerStackView.alignment = .trailing
        rightInnerStackView.distribution = .equalSpacing
        rightInnerStackView.spacing = 5
        
        inputWrapperInnerView.addSubview(textView)
        inputWrapperInnerView.addSubview(rightInnerStackView)
        inputWrapperView.addSubview(topBorderView)
        inputWrapperInnerBorderView.addSubview(inputWrapperInnerView)
        inputWrapperView.addSubview(inputWrapperInnerBorderView)
        wrapperView.addSubview(inputWrapperView)
        view.addSubview(wrapperView)
        
        let constraints = [
            topBorderView.topAnchor.constraint(equalTo: inputWrapperView.topAnchor),
            topBorderView.leadingAnchor.constraint(equalTo: inputWrapperView.leadingAnchor),
            topBorderView.trailingAnchor.constraint(equalTo: inputWrapperView.trailingAnchor),
            
            textView.centerYAnchor.constraint(equalTo: inputWrapperInnerView.centerYAnchor),
            textView.topAnchor.constraint(greaterThanOrEqualTo: inputWrapperInnerView.topAnchor, constant: 15 - shadowWidth),
            textView.leadingAnchor.constraint(equalTo: inputWrapperInnerView.leadingAnchor, constant: 10),
            inputWrapperInnerView.bottomAnchor.constraint(greaterThanOrEqualTo: textView.bottomAnchor, constant: 15 - shadowWidth),
            rightInnerStackView.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 10),
            
            inputWrapperInnerView.trailingAnchor.constraint(equalTo: rightInnerStackView.trailingAnchor, constant: 10),
            rightInnerStackView.widthAnchor.constraint(equalToConstant: 70),
            
            inputWrapperInnerView.topAnchor.constraint(equalTo: inputWrapperInnerBorderView.topAnchor, constant: shadowWidth),
            inputWrapperInnerView.leadingAnchor.constraint(equalTo: inputWrapperInnerBorderView.leadingAnchor, constant: shadowWidth),
            inputWrapperInnerBorderView.trailingAnchor.constraint(equalTo: inputWrapperInnerView.trailingAnchor, constant: shadowWidth),
            inputWrapperInnerBorderView.bottomAnchor.constraint(equalTo: inputWrapperInnerView.bottomAnchor, constant: shadowWidth),
            
            inputWrapperInnerBorderView.leadingAnchor.constraint(equalTo: inputWrapperView.leadingAnchor, constant: 10 - shadowWidth),
            inputWrapperInnerBorderView.topAnchor.constraint(equalTo: inputWrapperView.topAnchor, constant: 10 - shadowWidth),
            inputWrapperView.trailingAnchor.constraint(equalTo: inputWrapperInnerBorderView.trailingAnchor, constant: 10 - shadowWidth),
            
            inputWrapperView.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            inputWrapperView.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            inputWrapperView.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
            
            textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 0),
            textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            textViewPlaceholder.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            
            scrollView.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputWrapperView.topAnchor),
            
            scrollContainerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            scrollContainerView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollContainerView.widthAnchor.constraint(equalTo: wrapperView.widthAnchor),
            
            chatStackView.topAnchor.constraint(equalTo: scrollContainerView.topAnchor, constant: 20),
            chatStackView.leadingAnchor.constraint(equalTo: scrollContainerView.leadingAnchor),
            chatStackView.trailingAnchor.constraint(equalTo: scrollContainerView.trailingAnchor),
            scrollContainerView.bottomAnchor.constraint(equalTo: chatStackView.bottomAnchor, constant: 20),
            
            wrapperView.topAnchor.constraint(equalTo: view.topAnchor),
            wrapperView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wrapperView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wrapperView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        
        let inputInnerStackViewTopConstraint = rightInnerStackView.topAnchor.constraint(equalTo: inputWrapperInnerBorderView.topAnchor, constant: 10)
        let inputInnerStackViewBottomConstraint = inputWrapperInnerBorderView.bottomAnchor.constraint(equalTo: rightInnerStackView.bottomAnchor, constant: 10)
        
        inputInnerStackViewTopConstraint.isActive = true
        inputInnerStackViewBottomConstraint.isActive = true
        
        let bottomConstraint = wrapperView.bottomAnchor.constraint(equalTo: inputWrapperView.bottomAnchor)
        bottomConstraint.isActive = true
        
        let bottomInnerConstraint = inputWrapperView.bottomAnchor.constraint(equalTo: inputWrapperInnerBorderView.bottomAnchor, constant: wrapperView.safeAreaInsets.bottom + 10)
        bottomInnerConstraint.isActive = true
        
        NSLayoutConstraint.activate(constraints)
        
        self.inputWrapperView = inputWrapperView
        self.inputWrapperInnerView = inputWrapperInnerView
        self.inputWrapperInnerBorderView = inputWrapperInnerBorderView
        self.inputTextView = textView
        self.inputTextViewPlaceholder = textViewPlaceholder
        self.characterCountLabel = characterCountLabel
        self.submitTextButton = submitTextButton
        self.bottomConstraint = bottomConstraint
        self.bottomInnerConstraint = bottomInnerConstraint
        self.inputInnerStackViewTopConstraint = inputInnerStackViewTopConstraint
        self.inputInnerStackViewBottomConstraint = inputInnerStackViewBottomConstraint
        self.scrollView = scrollView
        self.chatStackView = chatStackView
        self.wrapperView = wrapperView
    }
    
    private func removeNavigationBarBorder() {
        guard shouldHideNavigationBarLine else { return }
        
        navigationController?.navigationBar.shadowImage = UIImage()
    }
    
    /// Update visual style based on a provided `ChatConfig`
    open func updateStyle(config: ChatConfig) {
        let primaryColor = self.primaryColor ?? UIColor(hex: config.primaryColor) ?? UIColor.BoostAI.purple
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.barTintColor = primaryColor
        submitTextButton.tintColor = primaryColor
        
        let contrastColor = self.contrastColor ?? UIColor(hex: config.contrastColor) ?? .white
        navigationController?.navigationBar.tintColor = contrastColor
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: contrastColor]
        
        if let messages = config.messages?.languages[backend.languageCode] {
            navigationItem.title = messages.headerText
            inputTextViewPlaceholder.text = messages.composePlaceholder
            submitTextButton.setTitle(messages.submitMessage, for: .normal)
            
            menuBarButtonItem?.accessibilityLabel = NSLocalizedString("Open menu", comment: "")
            closeBarButtonItem?.accessibilityLabel = messages.closeWindow
        }
    }
    
    open func layoutIfNeeded() {
        view.layoutIfNeeded()
    }
    
    // MARK: - Keyboard handling
    
    @objc open func keyboardWillShow(_ notification: NSNotification) {
        isKeyboardShown = true
        
        guard let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        let animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        
        UIView.animate(withDuration: animationDuration ?? 0.25, delay: 0, options: UIView.AnimationOptions(rawValue: animationCurve ?? 0), animations: {
            self.bottomConstraint.isActive = false
            
            let constraint = self.wrapperView.bottomAnchor.constraint(equalTo: self.inputWrapperView.bottomAnchor, constant: keyboardSize.height)
            constraint.isActive = true
            self.bottomConstraint = constraint
            
            self.feedbackBottomConstraint?.constant = keyboardSize.height
            
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
        
        self.scrollToEnd(animated: true)
    }
    
    @objc open func keyboardWillHide(_ notification: NSNotification) {        
        isKeyboardShown = false
        
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        let animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        
        UIView.animate(withDuration: animationDuration ?? 0.25, delay: 0, options: UIView.AnimationOptions(rawValue: animationCurve ?? 0), animations: {
            self.bottomConstraint.isActive = false
            
            let constraint = self.wrapperView.bottomAnchor.constraint(equalTo: self.inputWrapperView.bottomAnchor)
            constraint.isActive = true
            self.bottomConstraint = constraint
            
            self.feedbackBottomConstraint?.constant = 0
            
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }
    
    @objc open func focusInput() {
        inputTextView.becomeFirstResponder()
    }
    
    @objc open func resignInputFocus() {
        inputTextView.resignFirstResponder()
    }
}

extension ChatViewController: UITextViewDelegate {
    
    // MARK: - UITextViewDelegate
    
    public func textViewDidChange(_ textView: UITextView) {
        inputTextViewPlaceholder.isHidden = textView.text.count > 0
        submitTextButton.isEnabled = !isBlocked && textView.text.count > 0
        
        let value = backend.clientTyping(value: textView.text)
        maxCharacterCount = value.maxLength
        
        updateCharacterCount()
    }
    
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let isEnterKey = text == "\n"
        
        if isEnterKey {
            sendText()
            return false
        }
        
        let newString = (textView.text as NSString).replacingCharacters(in: range, with: text)
        
        return newString.count <= maxCharacterCount
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
        let primaryColor = self.primaryColor ?? UIColor(hex: backend.config?.primaryColor) ?? UIColor.BoostAI.purple
                
        UIView.animate(withDuration: 0.2) {
            self.inputWrapperInnerBorderView.backgroundColor = primaryColor.withAlphaComponent(0.25)
        }
        
        let borderAnimation = CABasicAnimation(keyPath: "borderColor");
        borderAnimation.fromValue = UIColor(red: 0, green: 0, blue: 0, alpha: 0.2).cgColor
        borderAnimation.toValue = primaryColor.cgColor
        borderAnimation.duration = 0.2
        
        self.inputWrapperInnerView.layer.add(borderAnimation, forKey: "border")
        self.inputWrapperInnerView.layer.borderColor = primaryColor.cgColor
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        let primaryColor = self.primaryColor ?? UIColor(hex: backend.config?.primaryColor) ?? UIColor.BoostAI.purple
        
        UIView.animate(withDuration: 0.2) {
            self.inputWrapperInnerBorderView.backgroundColor = self.inputWrapperView.backgroundColor
        }
        
        let borderAnimation = CABasicAnimation(keyPath: "borderColor");
        borderAnimation.fromValue = primaryColor.cgColor
        borderAnimation.toValue = UIColor(red: 0, green: 0, blue: 0, alpha: 0.2).cgColor
        borderAnimation.duration = 0.2
        
        self.inputWrapperInnerView.layer.add(borderAnimation, forKey: "border")
        self.inputWrapperInnerView.layer.borderColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.2).cgColor
    }
}

extension ChatViewController {
    public func showConversationFeedbackInput() {
        guard feedbackViewController == nil else {
            return
        }
        
        let feedbackVC = delegate?.conversationFeedbackViewController(backend: backend) ?? ConversationFeedbackViewController(backend: backend)
        feedbackVC.delegate = feedbackVC.delegate ?? self
        feedbackVC.feedbackSuccessMessage = self.feedbackSuccessMessage
        feedbackVC.primaryColor = feedbackVC.primaryColor ?? self.primaryColor
        feedbackVC.contrastColor = feedbackVC.contrastColor ?? self.contrastColor
        
        feedbackVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        feedbackVC.willMove(toParent: self)
        view.addSubview(feedbackVC.view)
        addChild(feedbackVC)
        feedbackVC.didMove(toParent: self)
        
        let constraints = [
            feedbackVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            feedbackVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: feedbackVC.view.trailingAnchor)
        ]
        
        let bottomConstraint: NSLayoutConstraint
        bottomConstraint = view.bottomAnchor.constraint(equalTo: feedbackVC.view.bottomAnchor)
        bottomConstraint.isActive = true
        
        NSLayoutConstraint.activate(constraints)
        
        feedbackViewController = feedbackVC
        feedbackBottomConstraint = bottomConstraint
        inputTextView.resignFirstResponder()
    }
}

extension ChatViewController: ChatResponseViewDelegate {
    public func setIsUploadingFile() {
        if let strings = backend.config?.language(languageCode: backend.languageCode), let fallbackStrings = backend.config?.language(languageCode: "en-US") {
            addStatusMessage(message: strings.uploadFileProgress.count > 0 ? strings.uploadFileProgress : fallbackStrings.uploadFileProgress)
        }
    }
}

extension ChatViewController: ChatDialogMenuDelegate {
    
    public func deleteConversation() {
        backend.delete(message: nil) { [weak self] (message, error) in
            DispatchQueue.main.async {
                guard error == nil else { return }
                
                // Remove responses
                self?.responses = []
                
                // Clear subviews
                for subview in (self?.chatStackView.arrangedSubviews ?? []) {
                    subview.removeFromSuperview()
                }
                
                // We are in a modal
                if let _ = self?.presentingViewController {
                    self?.dismissSelf()
                } else {
                    // We are in fullscreen mode -> Start a new conversation
                    self?.hideMenu()
                    self?.backend.start()
                }
            }
        }
    }
    
    public func showMenu() {
        let menuVC = delegate?.menuViewController(backend: backend) ?? MenuViewController(backend: backend)
        menuVC.menuDelegate = menuVC.menuDelegate ?? self
        menuVC.primaryColor = menuVC.primaryColor ?? self.primaryColor
        menuVC.contrastColor = menuVC.contrastColor ?? self.contrastColor
        
        menuVC.willMove(toParent: self)
        addChild(menuVC)
        view.addSubview(menuVC.view)
        menuVC.didMove(toParent: self)
        
        menuVC.view.translatesAutoresizingMaskIntoConstraints = false
        menuVC.view.layer.opacity = 0
        
        let constraints = [
            menuVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            menuVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: menuVC.view.trailingAnchor)
        ]
        
        if let _ = presentingViewController {
            view.bottomAnchor.constraint(equalTo: menuVC.view.bottomAnchor).isActive = true
        } else {
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: menuVC.view.bottomAnchor).isActive = true
        }
        
        NSLayoutConstraint.activate(constraints)
        
        UIView.animate(withDuration: 0.2) {
            menuVC.view.layer.opacity = 1
        }
        
        menuViewController = menuVC
        inputTextView.resignFirstResponder()
    }
    
    public func hideMenu() {
        guard let menuViewController = self.menuViewController else {
            return
        }
        
        UIView.animate(withDuration: 0.2, animations: {
            menuViewController.view.layer.opacity = 0
        }) { (_) in
            menuViewController.willMove(toParent: nil)
            menuViewController.view.removeFromSuperview()
            menuViewController.removeFromParent()
            menuViewController.didMove(toParent: nil)
            self.menuViewController = nil
        }
    }
    
    public func showFeedback() {
        showConversationFeedbackInput()
    }
    
}

extension ChatViewController: ConversationFeedbackDelegate {
    public func hideFeedback() {
        feedbackViewController?.willMove(toParent: nil)
        feedbackViewController?.view.removeFromSuperview()
        feedbackViewController?.removeFromParent()
        feedbackViewController?.didMove(toParent: nil)
        feedbackViewController = nil
    }
    
    public func closeConversation() {
        if let _ = presentingViewController {
            dismissSelf()
        } else {
            hideFeedback()
            hideMenu()
        }
    }
    
}

extension ChatViewController: UIPopoverPresentationControllerDelegate {
    public func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
}