import Foundation
import WebKit

/// On-device, one-shot evaluator. Never give it cookies, credentials, local URLs,
/// application objects, or a WebView used for browsing. iOS 15+.
@available(iOS 15.0, *)
@MainActor
@objc(VMWebKitChallengeProvider)
final class VMWebKitChallengeProvider: NSObject {
    static let maxScriptBytes = 4 * 1024 * 1024
    static let maxInputBytes = 1024 * 1024
    static let maxOutputBytes = 1024 * 1024
    private var active: Job?
    private var quarantined = false

    @objc(evaluateScript:inputJSON:completion:)
    func evaluateScript(_ script: String, inputJSON: String,
                        completion: @escaping (String?, NSError?) -> Void) {
        evaluateScript(script, inputJSON: inputJSON, requestID: UUID().uuidString, completion: completion)
    }

    @objc(evaluateScript:inputJSON:requestID:completion:)
    func evaluateScript(_ script: String, inputJSON: String, requestID: String,
                        completion: @escaping (String?, NSError?) -> Void) {
        guard !requestID.isEmpty, requestID.utf8.count <= 128 else {
            completion(nil, Self.error("Invalid request identifier")); return
        }
        guard !quarantined else { completion(nil, Self.error("Evaluator unavailable after timeout or process failure")); return }
        guard active == nil else { completion(nil, Self.error("Evaluator busy")); return }
        guard script.utf8.count <= Self.maxScriptBytes,
              inputJSON.utf8.count <= Self.maxInputBytes,
              let data = inputJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
        else { completion(nil, Self.error("Invalid or oversized JavaScript request")); return }
        // Intentional bounded ownership cycle until finish clears Job.completion.
        // Dropping the caller's reference must not drop its pending callback.
        let job = Job(script: script, inputJSON: inputJSON, requestID: requestID) { [self] result, error, quarantine in
            self.quarantined = self.quarantined || quarantine
            self.active = nil
            completion(result, error)
        }
        active = job
        job.start()
    }

    /// Invoke on backgrounding, user cancellation, or resolver cancellation.
    @objc func cancelAll() { active?.finish(nil, Self.error("Cancelled"), quarantine: true) }

    /// Late cancellation for an older request must not affect a newer job.
    @objc(cancelRequest:) func cancelRequest(_ requestID: String) {
        guard active?.requestID == requestID else { return }
        active?.finish(nil, Self.error("Cancelled"), quarantine: true)
    }

    fileprivate static func error(_ message: String) -> NSError {
        NSError(domain: "VoiceMatrix.WebKitChallenge", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    private final class Job: NSObject, WKNavigationDelegate, WKUIDelegate {
        let script: String
        let inputJSON: String
        let requestID: String
        var completion: ((String?, NSError?, Bool) -> Void)?
        var view: WKWebView?
        var deadline: DispatchWorkItem?
        var initialNavigation: WKNavigation?
        var didEvaluate = false
        var allowedInitialNavigation = false
        var expiresAt: UInt64 = 0
        init(script: String, inputJSON: String, requestID: String,
             completion: @escaping (String?, NSError?, Bool) -> Void) {
            self.script = script; self.inputJSON = inputJSON; self.requestID = requestID; self.completion = completion
        }
        func ensureActive() -> Bool {
            guard completion != nil else { return false }
            guard DispatchTime.now().uptimeNanoseconds < expiresAt else {
                finish(nil, VMWebKitChallengeProvider.error("JavaScript deadline exceeded"), quarantine: true)
                return false
            }
            return true
        }
        func start() {
            expiresAt = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
            let timer = DispatchWorkItem { [weak self] in
                self?.finish(nil, VMWebKitChallengeProvider.error("JavaScript deadline exceeded"), quarantine: true)
            }
            deadline = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timer)
            // Fail closed if the platform cannot compile its deny-all resource policy.
            let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "VoiceMatrix.NoNetwork.v1", encodedContentRuleList: rules
            ) { [weak self] rules, _ in
                guard let self, self.ensureActive() else { return }
                guard let rules else { self.finish(nil, VMWebKitChallengeProvider.error("Resource policy unavailable")); return }
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.processPool = WKProcessPool()
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                config.defaultWebpagePreferences.allowsContentJavaScript = false
                config.userContentController.add(rules)
                let view = WKWebView(frame: .zero, configuration: config)
                self.view = view
                view.navigationDelegate = self
                view.uiDelegate = self
                // No base URL, file-read entitlement, message handlers, remote HTML,
                // or remote scripts. Page JS disabled; only isolated-world API executes.
                let html = """
                <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; connect-src 'none'; img-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'none'; form-action 'none'"><title>Local calculation</title>
                """
                self.initialNavigation = view.loadHTMLString(html, baseURL: nil)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard ensureActive(), !didEvaluate, navigation === initialNavigation else { return }
            didEvaluate = true
            // Script is a function body, input is parsed JSON. No native object bridge.
            // Capture JSON.stringify before untrusted code can replace it.
            let body = """
            const serialize = JSON.stringify.bind(JSON);
            const finite = Number.isFinite.bind(Number);
            const InvalidResult = Error;
            const validate = (_, v) => {
                if ((typeof v === 'number' && !finite(v)) ||
                    ['undefined', 'function', 'symbol', 'bigint'].includes(typeof v)) {
                    throw new InvalidResult('Non-JSON result');
                }
                return v;
            };
            const parsedInput = JSON.parse(inputJSON);
            const value = await (async function(input) {
            \(script)
            })(parsedInput);
            const encoded = serialize(value, validate);
            if (typeof encoded !== 'string' || encoded.length > \(VMWebKitChallengeProvider.maxOutputBytes)) throw new Error('Invalid or oversized result');
            return encoded;
            """
            webView.callAsyncJavaScript(body, arguments: ["inputJSON": inputJSON],
                in: nil, in: WKContentWorld.world(name: "VoiceMatrix.Challenge")) { [weak self] result in
                guard let self, self.ensureActive() else { return }
                switch result {
                case .success(let value):
                    guard let string = value as? String,
                          string.utf8.count <= VMWebKitChallengeProvider.maxOutputBytes,
                          let data = string.data(using: .utf8),
                          (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
                    else { self.finish(nil, VMWebKitChallengeProvider.error("Invalid or oversized result")); return }
                    self.finish(string, nil)
                case .failure:
                    // Do not leak page script contents, tokens, or URLs through errors.
                    self.finish(nil, VMWebKitChallengeProvider.error("JavaScript evaluation failed"))
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only the controlled first blank main document may load.
            let initial = completion != nil && !allowedInitialNavigation && !didEvaluate && action.targetFrame?.isMainFrame == true && action.request.url?.absoluteString == "about:blank"
            if initial { allowedInitialNavigation = true }
            decisionHandler(initial ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(nil, VMWebKitChallengeProvider.error("Local document failed"))
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(nil, VMWebKitChallengeProvider.error("Local document failed"))
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(nil, VMWebKitChallengeProvider.error("JavaScript process stopped"), quarantine: true)
        }
        func finish(_ result: String?, _ error: NSError?, quarantine: Bool = false) {
            guard let callback = completion else { return }
            completion = nil
            deadline?.cancel(); deadline = nil
            view?.navigationDelegate = nil; view?.uiDelegate = nil
            view?.stopLoading()
            view = nil
            initialNavigation = nil
            callback(result, error, quarantine)
        }
    }
}
