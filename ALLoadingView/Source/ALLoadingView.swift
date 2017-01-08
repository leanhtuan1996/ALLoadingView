/*
 Copyright (c) 2015 Artem Loginov
 
 Permission is hereby granted,  free of charge,  to any person obtaining a
 copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation
 the rights to  use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.
 */

import UIKit

public typealias ALLVCompletionBlock = () -> Void
public typealias ALLVCancelBlock = () -> Void

public enum ALLVType {
    case basic
    case message
    case messageWithIndicator
    case messageWithIndicatorAndCancelButton
    case progress
}

public enum ALLVWindowMode {
    case fullscreen
    case windowed
}

private enum ALLVProgress {
    case hidden
    case initializing
    case viewReady
    case loaded
    case hiding
}

// building blocks
private enum ALLVViewType {
    case blankSpace
    case messageLabel
    case progressBar
    case cancelButton
    case activityIndicator
}

public class ALLoadingView: NSObject {
    //MARK: - Public variables
    public var animationDuration: TimeInterval = 0.5
    public var itemSpacing: CGFloat = 20.0
    public var cornerRadius: CGFloat = 0.0
    public var cancelCallback: ALLVCancelBlock?
    public var blurredBackground: Bool = false
    public lazy var backgroundColor: UIColor = UIColor(white: 0.0, alpha: 0.5)
    public lazy var textColor: UIColor = UIColor(white: 1.0, alpha: 1.0)
    public lazy var messageFont: UIFont = UIFont.systemFont(ofSize: 25.0)
    public lazy var messageText: String = "Loading"
    
    //MARK: Adjusment
    public var windowRatio: CGFloat = 0.4 {
        didSet {
            windowRatio = min(max(0.3, windowRatio), 1.0)
        }
    }
    
    //MARK: - Private variables
    private var loadingViewProgress: ALLVProgress
    private var loadingViewType: ALLVType
    private var operationQueue = OperationQueue()
    private var blankIntrinsicContentSize = CGSize(width: UIViewNoIntrinsicMetric, height: UIViewNoIntrinsicMetric)
    // Subviews
    private var loadingView: UIView?
    private var appearanceView: UIView?
    private var stackView: UIStackView?
    
    //MARK: Custom setters/getters
    private var loadingViewWindowMode: ALLVWindowMode {
        didSet {
            if loadingViewWindowMode == .fullscreen {
                cornerRadius = 0.0
            } else  {
                blurredBackground = false
                if cornerRadius == 0.0 {
                    cornerRadius = 10.0
                }
            }
        }
    }
    
    private var frameForView: CGRect {
        if loadingViewWindowMode == .fullscreen || windowRatio == 1.0 {
            return UIScreen.main.bounds
        } else {
            let bounds = UIScreen.main.bounds;
            let size = min(bounds.width, bounds.height)
            return CGRect(x: 0, y: 0, width: size * windowRatio, height: size * windowRatio)
        }
    }
    
    private var isUsingBlurEffect: Bool {
        return self.loadingViewWindowMode == .fullscreen && self.blurredBackground
    }
    
    //MARK: - Initialization
    public class var manager: ALLoadingView {
        struct Singleton {
            static let instance = ALLoadingView()
        }
        return Singleton.instance
    }
    
    override init() {
        loadingViewWindowMode = .fullscreen
        loadingViewProgress = .hidden
        loadingViewType = .basic
    }
    
    //MARK: - Public methods
    //MARK: Show loading view
    public func showLoadingView(ofType type: ALLVType, windowMode: ALLVWindowMode? = nil, completionBlock: ALLVCompletionBlock? = nil) {
        assert(loadingViewProgress == .hidden || loadingViewProgress == .hiding, "ALLoadingView Presentation Error. Trying to push loading view while there is one already presented")
        
        loadingViewProgress = .initializing
        loadingViewWindowMode = windowMode ?? .fullscreen
        loadingViewType = type
        
        let operationInit = BlockOperation { ()  -> Void in
            DispatchQueue.main.async {
                self.initializeLoadingView()
            }
        }
        
        let operationShow = BlockOperation { () -> Void in
            DispatchQueue.main.async {
                self.attachLoadingViewToContainer()
                self.updateSubviewsTitles()
                self.animateLoadingViewAppearance(withCompletion: completionBlock)
            }
        }
        
        operationShow.addDependency(operationInit)
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.addOperations([operationInit, operationShow], waitUntilFinished: false)
    }
    
    private func animateLoadingViewAppearance(withCompletion completionBlock: ALLVCompletionBlock? = nil) {
        self.updateContentViewAlphaValue(0.0)
        UIView.animate(withDuration: self.animationDuration, animations: { () -> Void in
            self.updateContentViewAlphaValue(1.0)
        }) { finished -> Void in
            if finished {
                self.loadingViewProgress = .loaded
                completionBlock?()
            }
        }
    }
    
    //MARK: Hiding loading view
    public func hideLoadingView(withDelay delay: TimeInterval? = nil, completionBlock: ALLVCompletionBlock? = nil) {
        let delayValue : TimeInterval = delay ?? 0.0
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(delayValue * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
            self.loadingViewProgress = .hiding
            self.animateLoadingViewDisappearance(withCompletion: completionBlock)
        }
    }
    
    private func animateLoadingViewDisappearance(withCompletion completionBlock: ALLVCompletionBlock? = nil) {
        if isUsingBlurEffect {
            self.loadingViewProgress = .hidden
            self.loadingView?.removeFromSuperview()
            completionBlock?()
            self.freeViewData()
        } else {
            UIView.animate(withDuration: self.animationDuration, animations: { () -> Void in
                self.appearanceView?.alpha = 0.0
            }) { finished -> Void in
                if finished {
                    self.loadingViewProgress = .hidden
                    self.loadingView?.removeFromSuperview()
                    completionBlock?()
                    self.freeViewData()
                }
            }
        }
    }
    
    private func freeViewData() {
        // View is hidden, now free memory
        for subview in loadingViewSubviews() {
            subview.removeFromSuperview()
        }
        self.stackView?.removeFromSuperview()
        self.appearanceView?.removeFromSuperview()
        self.stackView = nil
        self.appearanceView = nil
        self.loadingView = nil
    }
    
    //MARK: Reset to defaults
    public func resetToDefaults() {
        self.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        self.textColor = UIColor(white: 1.0, alpha: 1.0)
        self.messageFont = UIFont.systemFont(ofSize: 25.0)
        self.blurredBackground = false
        self.animationDuration = 0.5
        self.messageText = "Loading"
        self.cornerRadius = 0.0
        self.windowRatio = 0.4
        self.itemSpacing = 20.0
        //
        self.loadingViewWindowMode = .fullscreen
        self.loadingViewType = .basic
    }
    
    //MARK: Updating subviews data
    public func updateProgressLoadingView(withMessage message: String, forProgress progress: Float) {
        guard self.loadingViewProgress == .loaded else {
            return
        }
        assert(loadingViewType == .progress, "ALLoadingView Update Error. Set ALLVType to 'Progress' to access progress bar.")
        
        DispatchQueue.main.async {
            self.progress_updateProgressControls(withData: ["message": message, "progress" : progress])
            // Update stack view's height
            self.updateStackViewHeightConstraint()
        }
    }
    
    public func progress_updateProgressControls(withData data: NSDictionary) {
        let message = data["message"] as? String ?? ""
        let progress = data["progress"] as? Float ?? 0.0
        
        for view in self.loadingViewSubviews() {
            if view.responds(to: #selector(setter: UILabel.text)) {
                (view as! UILabel).text = message
            }
            if view.responds(to: #selector(setter: UIProgressView.progress)) {
                (view as! UIProgressView).progress = progress
            }
        }
    }
    
    public func updateMessageLabel(withText message: String) {
        assert(loadingViewType == .message ||
            loadingViewType == .messageWithIndicator ||
            loadingViewType == .messageWithIndicatorAndCancelButton, "ALLoadingView Update Error. Set .Message, .MessageWithIndicator and .MessageWithIndicatorAndCancelButton type to access message label.")
        
        DispatchQueue.main.async {
            self.progress_updateProgressControls(withData: ["message": message])
            // Update stack view's height
            self.updateStackViewHeightConstraint()
        }
    }
    
    private func updateSubviewsTitles() {
        let subviews: [UIView] = self.loadingViewSubviews()
        
        switch self.loadingViewType {
        case .message, .messageWithIndicator:
            for view in subviews {
                if view.responds(to: #selector(setter: UILabel.text)) {
                    (view as! UILabel).text = self.messageText
                }
            }
            break
        case .messageWithIndicatorAndCancelButton:
            for view in subviews {
                if view is UIButton {
                    (view as! UIButton).setTitle("Cancel", for: UIControlState())
                    (view as! UIButton).addTarget(self, action: #selector(ALLoadingView.cancelButtonTapped(_:)), for: .touchUpInside)
                }
                if view.responds(to: #selector(setter: UILabel.text)) {
                    (view as! UILabel).text = self.messageText
                }
            }
            break
        case .progress:
            for view in subviews {
                if view.responds(to: #selector(setter: UIProgressView.progress)) {
                    (view as! UIProgressView).progress = 0.0
                    
                }
                if view.responds(to: #selector(setter: UILabel.text)) {
                    (view as! UILabel).text = self.messageText
                }
            }
            break
        default:
            break
        }
        
        // Update stack view's height
        updateStackViewHeightConstraint()
    }
    
    //MARK: - Private methods
    //MARK: Initialize view
    private func initializeLoadingView() {
        loadingView = UIView(frame: CGRect.zero)
        loadingView?.backgroundColor = UIColor.clear
        loadingView?.clipsToBounds = true
        
        // Create blank stack view, will configure later
        stackView = UIStackView()
        
        // Set up appearance view (blur, color, such stuff)
        initializeAppearanceView()
    
        // View has been created. Add subviews according to selected type.
        configureStackView()
        createSubviewsForStackView()
    }
    
    private func initializeAppearanceView() {
        guard let loadingView = loadingView, let stackView = stackView else {
            return
        }
        
        if isUsingBlurEffect {
            let lightBlur = UIBlurEffect(style: .dark)
            let lightBlurView = UIVisualEffectView(effect: lightBlur)
            appearanceView = lightBlurView
            
            // Add stack view
            lightBlurView.contentView.addSubview(stackView)
        } else {
            appearanceView = UIView(frame: CGRect.zero)
            appearanceView?.backgroundColor = backgroundColor
            
            // Add stack view
            appearanceView?.addSubview(stackView)
        }
        appearanceView?.layer.cornerRadius = cornerRadius
        appearanceView?.layer.masksToBounds = true
        
        loadingView.addSubview(appearanceView!)
    }
    
    private func configureStackView() {
        guard let stackView = stackView else {
            return
        }
        
        stackView.axis = .vertical
        stackView.distribution = .equalCentering
        stackView.alignment = .center
        stackView.spacing = itemSpacing
    }
    
    private func attachLoadingViewToContainer() {
        guard let loadingView = loadingView, let appearanceView = appearanceView else {
            return
        }
        
        let container = UIApplication.shared.windows[0]
        container.addSubview(loadingView)
        
        // Set constraints for loading view (container)
        view_setWholeScreenConstraints(forView: loadingView, inContainer: container)
        
        // Set constraints for appearance view
        if loadingViewWindowMode == .fullscreen {
            view_setWholeScreenConstraints(forView: appearanceView, inContainer: loadingView)
        } else {
            view_setSizeConstraints(forView: appearanceView, inContainer: loadingView)
        }
    }

    private func view_setWholeScreenConstraints(forView subview: UIView, inContainer container: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        let topConstraint = NSLayoutConstraint(item: subview, attribute: .top,
                                               relatedBy: .equal, toItem: container,
                                               attribute: .top, multiplier: 1, constant: 0)
        let bottomContraint = NSLayoutConstraint(item: subview, attribute: .bottom,
                                                 relatedBy: .equal, toItem: container,
                                                 attribute: .bottom, multiplier: 1, constant: 0)
        let trallingConstaint = NSLayoutConstraint(item: subview, attribute: .trailing,
                                                   relatedBy: .equal, toItem: container,
                                                   attribute: .trailing, multiplier: 1, constant: 0)
        let leadingConstraint = NSLayoutConstraint(item: subview, attribute: .leading,
                                                   relatedBy: .equal, toItem: container,
                                                   attribute: .leading, multiplier: 1, constant: 0)
        container.addConstraints([topConstraint, bottomContraint, leadingConstraint, trallingConstaint])
    }
    
    private func view_setSizeConstraints(forView subview: UIView, inContainer container: UIView) {
        let frame = frameForView
        subview.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = NSLayoutConstraint(item: subview, attribute: .height,
                                               relatedBy: .equal, toItem: nil,
                                               attribute: .notAnAttribute, multiplier: 1, constant: frame.size.height)
        let widthContraint = NSLayoutConstraint(item: subview, attribute: .width,
                                                 relatedBy: .equal, toItem: nil,
                                                 attribute: .notAnAttribute, multiplier: 1, constant: frame.size.width)
        let centerXConstaint = NSLayoutConstraint(item: subview, attribute: .centerX,
                                                   relatedBy: .equal, toItem: container,
                                                   attribute: .centerX, multiplier: 1, constant: 0)
        let centerYConstraint = NSLayoutConstraint(item: subview, attribute: .centerY,
                                                   relatedBy: .equal, toItem: container,
                                                   attribute: .centerY, multiplier: 1, constant: 0)
        container.addConstraints([heightConstraint, widthContraint, centerYConstraint, centerXConstaint])
    }
    
    private func createSubviewsForStackView() {
        guard let stackView = stackView else {
            return
        }
        let viewTypes = getSubviewsTypes()
        
        // calculate frame for each view
        for viewType in viewTypes {
            let view = initializeView(withType: viewType, andFrame: CGRect(origin: CGPoint.zero, size: CGSize(width: 50.0, height: 50.0)))
            
            stackView.addArrangedSubview(view)
            if view.intrinsicContentSize.height == UIViewNoIntrinsicMetric {
                view.translatesAutoresizingMaskIntoConstraints = false
                view.heightAnchor.constraint(equalToConstant: view.frame.height).isActive = true
            }
            if view.intrinsicContentSize.width == UIViewNoIntrinsicMetric {
                view.translatesAutoresizingMaskIntoConstraints = false
                view.widthAnchor.constraint(equalToConstant: frameForView.width).isActive = true
            }
        }
        
        self.loadingViewProgress = .viewReady
        
        // Setting up constraints for stack view
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.widthAnchor.constraint(equalTo: (stackView.superview?.widthAnchor)!, multiplier: 1).isActive = true
        stackView.centerXAnchor.constraint(equalTo: (stackView.superview?.centerXAnchor)!).isActive = true
        stackView.centerYAnchor.constraint(equalTo: (stackView.superview?.centerYAnchor)!).isActive = true
    }
    
    private func updateStackViewHeightConstraint() {
        guard let stackView = stackView else {
            return
        }
        
        var summaryElementHeight : CGFloat = 0.0
        stackView.arrangedSubviews.forEach { summaryElementHeight += $0.elementHeightAtStackView() }
        summaryElementHeight += CGFloat(stackView.arrangedSubviews.count - 1) * stackView.spacing

        stackView.heightAnchor.constraint(equalToConstant: summaryElementHeight).isActive = true
    }
    
    private func getSubviewsTypes() -> [ALLVViewType] {
        switch self.loadingViewType {
        case .basic:
            return [.activityIndicator]
        case .message:
            return [.messageLabel]
        case .messageWithIndicator:
            return [.messageLabel, .activityIndicator]
        case .messageWithIndicatorAndCancelButton:
            if self.loadingViewWindowMode == ALLVWindowMode.windowed {
                return [.messageLabel, .activityIndicator, .cancelButton]
            } else {
                return [.messageLabel, .activityIndicator, .cancelButton]
            }
        case .progress:
            return [.messageLabel, .progressBar]
        }
    }
    
    //MARK: Loading view accessors & methods
    private func loadingViewSubviews() -> [UIView] {
        guard let stackView = stackView else {
            return []
        }
        return stackView.arrangedSubviews
    }
    
    private func updateContentViewAlphaValue(_ alpha: CGFloat) {
        if isUsingBlurEffect {
            if let asVisualEffectView = appearanceView as? UIVisualEffectView {
                asVisualEffectView.contentView.alpha = alpha
            }
        } else {
            appearanceView?.alpha = alpha
        }
    }
    
    //MARK: Initializing subviews
    private func initializeView(withType type: ALLVViewType, andFrame frame: CGRect) -> UIView {
        switch type {
        case .messageLabel:
            return view_messageLabel()
        case .activityIndicator:
            return view_activityIndicator()
        case .cancelButton:
            return view_cancelButton(frame)
        case .blankSpace:
            return UIView(frame: frame)
        case .progressBar:
            return view_standardProgressBar()
        }
    }
    
    private func view_activityIndicator() -> UIActivityIndicatorView {
        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: UIActivityIndicatorViewStyle.white)
        activityIndicator.startAnimating()
        return activityIndicator
    }
    
    private func view_messageLabel() -> UILabel {
        let label = UILabel(frame: CGRect.zero)
        label.textAlignment = .center
        label.textColor = textColor
        label.font = messageFont
        return label
    }
    
    private func view_cancelButton(_ frame: CGRect) -> UIButton {
        let button = UIButton(type: .custom)
        button.frame = frame
        button.setTitleColor(UIColor.white, for: UIControlState.normal)
        button.backgroundColor = UIColor.clear
        return button
    }
    
    private func view_standardProgressBar() -> UIProgressView {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0.0
        
        return progressView
    }
    
    //MARK: Subviews actions
    public func cancelButtonTapped(_ sender: AnyObject?) {
        if let _ = sender as? UIButton {
            cancelCallback?()
        }
    }
}

extension UIView {
    func elementHeightAtStackView() -> CGFloat {
        if self.intrinsicContentSize.height > 0 {
            return self.intrinsicContentSize.height
        }
        return self.frame.height
    }
}
