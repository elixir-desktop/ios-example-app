import Foundation
import Combine

import SwiftUI
import UIKit
import WebKit

final class WebViewController: NSObject, UIViewRepresentable, WKNavigationDelegate, WKScriptMessageHandler {
    var webview: WKWebView
    var lastURL: URL?
    var finish: (() -> ())?
    
    override init() {
        // Enable javascript in WKWebView to interact with the web app
        let preferences = WKPreferences()
        // preferences.javaScriptEnabled = true
        
        let page = WKWebpagePreferences()
        page.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.preferences = preferences
        configuration.defaultWebpagePreferences = page
        
        webview = WKWebView(frame: CGRect.zero, configuration: configuration)
        // webView.navigationDelegate = context.coordinator
        webview.allowsBackForwardNavigationGestures = true
        webview.scrollView.isScrollEnabled = true
        
        super.init()
        
        // fixing the zoom level
        addScript(configuration, "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" +
            "head.appendChild(meta);")
        
        // adding debug output
        addScript(configuration, "window.onerror = (msg, url, line, column, error) => { " +
          "const message = {" +
          "  message: msg," +
          "  url: url," +
          "  line: line," +
          "  column: column," +
          "  error: JSON.stringify(error)" +
          "}" +
          "if (window.webkit) {" +
          "  window.webkit.messageHandlers.error.postMessage(message);" +
          "}" +
          "};")
        configuration.userContentController.add(self, name: "error")
        
        // fixing the onlick event
        // https://stackoverflow.com/a/27525707
        addScript(configuration, """
            document.getElementsByTagName('a').forEach(node => {
                node.style.cursor = "pointer";
            })
        """)
        
        webview.navigationDelegate = self
    }
    
    func addScript(_ config: WKWebViewConfiguration, _ script: String) {
        let script: WKUserScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
    }
    
    func onFinish(finish: @escaping () -> ()) {
        self.finish = finish
    }
    
    func webView(_ webView: WKWebView,
                          didFinish navigation: WKNavigation!) {
        if let fun = self.finish {
            fun()
        }
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "error":
            // You should actually handle the error :)
            let error = (message.body as? [String: Any])?["message"] as? String ?? "unknown"
            assertionFailure("JavaScript error: \(error)")
        default:
            assertionFailure("Received invalid message: \(message.name)")
        }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        print("makeUIView")
        return webview
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        print("updateUIView")
        if lastURL != nil {
            webview.load(URLRequest(url: lastURL!))
        }
    }
    
    func loadURL(url: URL) {
        lastURL = url
        if lastURL != nil {
            webview.load(URLRequest(url: lastURL!))
        }
    }
}
