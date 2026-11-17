import UIKit
import WebKit
import AVFoundation

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    var webView: WKWebView!
    let appURL = "https://chat.lingguangsh.com/h5/"
    var refreshControl: UIRefreshControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupGestures()
        loadApp()
        registerPush()
    }

    func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 允许网页自动播放音频（通话必需）
        if #available(iOS 15.0, *) {
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        }

        let userContent = WKUserContentController()
        userContent.add(self, name: "wuliaoBridge")
        config.userContentController = userContent

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)

        // 监听 token
        NotificationCenter.default.addObserver(self, selector: #selector(onToken(_:)),
                                               name: .apnsTokenReceived, object: nil)
    }

    func setupGestures() {
        let swipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(onSwipeBack(_:)))
        swipe.edges = .left
        view.addGestureRecognizer(swipe)
    }

    @objc func onSwipeBack(_ g: UIScreenEdgePanGestureRecognizer) {
        if g.state == .ended {
            if webView.canGoBack { webView.goBack() }
        }
    }

    @objc func onRefresh() {
        webView.reload()
    }

    func loadApp() {
        guard let url = URL(string: appURL) else { return }
        webView.load(URLRequest(url: url))
    }

    func registerPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    @objc func onToken(_ note: Notification) {
        guard let token = note.object as? String else { return }
        let js = "window.__apnsToken && window.__apnsToken('\(token)');"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // ===== 网页 -> 原生 =====
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "getToken":
            if let token = UserDefaults.standard.string(forKey: "apnsToken") {
                let js = "window.__apnsToken && window.__apnsToken('\(token)');"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        case "openExternal":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    // ===== 导航处理 =====
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        // 站内链接放行
        if url.host == "chat.lingguangsh.com" || scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow); return
        }
        // 外链用系统浏览器打开
        if scheme == "http" || scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // ===== 权限：网页请求麦克风/相机时自动授权（系统仍会弹窗） =====
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // ===== 支持 alert/confirm =====
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
}
