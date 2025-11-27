//
//  AppViews.swift
//  DF731
//
//  Created by IGOR on 18/11/2025.
//

import SwiftUI
@preconcurrency import WebKit
import UserNotifications
import UniformTypeIdentifiers
import PhotosUI

// MARK: - WebView Component
struct WebView: UIViewRepresentable {
    let url: String
    @Binding var isLoading: Bool
    @State private var hideLoaderTimer: Timer?
    @State private var orientationObserver: NSObjectProtocol?
    
    var onNavigationAction: ((URL) -> Bool)?
    var onLoadFinished: (() -> Void)?
    var onLoadError: ((Error) -> Void)?
    var onRedirectLimitReached: ((String) -> Void)? // Callback при достижении лимита редиректов
    var onRedirectDetected: (() -> Void)? // Callback при обнаружении любого редиректа
    var onUserNavigation: ((String, Date) -> Void)? // Callback при пользовательской навигации
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true
        
        let preferences = WKPreferences()
        
        // ✅ ПОЛНАЯ ПОДДЕРЖКА JAVASCRIPT
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            preferences.javaScriptEnabled = true
        }
        preferences.javaScriptCanOpenWindowsAutomatically = true
        
        
        // Поддержка текстового взаимодействия и современных веб-функций
        if #available(iOS 15.0, *) {
            configuration.preferences.isTextInteractionEnabled = true
            configuration.preferences.isElementFullscreenEnabled = true
        }
        
        // Специальные настройки для улучшения работы с input полями
        if #available(iOS 16.4, *) {
            configuration.preferences.shouldPrintBackgrounds = true
        }
        
        configuration.preferences = preferences
        
        configuration.allowsAirPlayForMediaPlayback = true
        
        // Стандартные настройки
        configuration.processPool = WKProcessPool()
        configuration.suppressesIncrementalRendering = true // Предотвращаем мелькание при загрузке
        
        // ✅ ПОЛНАЯ ПОДДЕРЖКА COOKIE И СЕССИЙ
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Настройка HTTP Cookie политики через системное хранилище
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        
        // Оптимизации для предотвращения проблем с навигацией
        if #available(iOS 14.0, *) {
            // Улучшенная обработка редиректов
            configuration.limitsNavigationsToAppBoundDomains = false
        }
        
        // Дополнительные настройки для стабильности
        if #available(iOS 15.0, *) {
            configuration.upgradeKnownHostsToHTTPS = false
        }
        
        // ✅ ДОПОЛНИТЕЛЬНЫЕ ВЕБ-ВОЗМОЖНОСТИ
        if #available(iOS 14.0, *) {
            // Разрешаем все типы контента
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        
        // Поддержка современных веб-стандартов
        if #available(iOS 14.5, *) {
            // Улучшенная поддержка веб-приложений
            configuration.limitsNavigationsToAppBoundDomains = false
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        webView.customUserAgent = DataManager.createCustomUserAgent()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        
        // ✅ ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ WEBVIEW
        webView.isOpaque = true
        webView.backgroundColor = UIColor.black
        
        // Предотвращение мелькания при загрузке
        webView.scrollView.backgroundColor = UIColor.black
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        
        // ✅ АГРЕССИВНОЕ ОТКЛЮЧЕНИЕ ЗУМА НА НАТИВНОМ УРОВНЕ
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.zoomScale = 1.0
        webView.scrollView.bouncesZoom = false
        webView.scrollView.isScrollEnabled = true // Оставляем прокрутку, убираем только зум
        
        // Дополнительные настройки для предотвращения зума
        // Используем .never для полного контроля через JavaScript
        // Это предотвращает автоматическое изменение contentInset при появлении клавиатуры
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        
        // Клавиатура остается открытой при скролле
        webView.scrollView.keyboardDismissMode = .none
        
        // Отключаем ВСЕ жесты зума
        if let scrollView = webView.scrollView as UIScrollView? {
            // Отключаем все tap жесты (включая двойное нажатие)
            for gesture in scrollView.gestureRecognizers ?? [] {
                if let tapGesture = gesture as? UITapGestureRecognizer {
                    if tapGesture.numberOfTapsRequired == 2 {
                        tapGesture.isEnabled = false
                        print("🚫 Disabled double-tap zoom gesture")
                    }
                }
                
                // Отключаем pinch жесты
                if let pinchGesture = gesture as? UIPinchGestureRecognizer {
                    pinchGesture.isEnabled = false
                    print("🚫 Disabled pinch zoom gesture")
                }
            }
            
            // Устанавливаем делегат для дополнительного контроля
            scrollView.delegate = context.coordinator
        }
        
        // Отключаем белый фон при загрузке
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = UIColor.black
        }
        
        // Поддержка современных веб-функций
        if #available(iOS 16.4, *) {
            webView.isInspectable = true // Для отладки в Safari Web Inspector
        }
        
        // Добавляем наблюдатель за поворотами экрана для сброса зума
        context.coordinator.setupOrientationObserver(for: webView)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let targetURL = URL(string: url) else {
            print("❌ WebView: Invalid URL - \(url)")
            return
        }
        
        // НЕ вмешиваемся если WebView уже загружается или в процессе навигации
        if webView.isLoading {
            print("🔄 WebView: Currently loading - not interfering with navigation")
            return
        }
        
        // Получаем текущий URL в WebView
        let currentURLString = webView.url?.absoluteString ?? ""
        let targetURLString = targetURL.absoluteString
        
        // ВАЖНО: НЕ перезагружаем если пользователь уже находится на финальной странице
        // Это предотвращает принудительный возврат к config URL или редиректам
        if !currentURLString.isEmpty && currentURLString != targetURLString {
            // Проверяем признаки пользовательской навигации
            let hasNavigationHistory = webView.canGoBack || webView.canGoForward
            let isDifferentDomain = URL(string: currentURLString)?.host != URL(string: targetURLString)?.host
            
            // Проверяем последний пользовательский URL из UserDefaults
            let lastUserURL = UserDefaults.standard.string(forKey: "last_opened_url") ?? ""
            let isCurrentURLUserOpened = currentURLString == lastUserURL
            
            // НЕ блокируем если это редиректы на том же домене (например /redirect/1 -> /redirect/2)
            let isRedirectSequence = currentURLString.contains("/redirect/") && targetURLString.contains("/redirect/")
            
            // НОВОЕ: НЕ перезагружаем если пользователь уже на финальной странице, а target - редирект
            let isCurrentFinal = currentURLString.contains("/final") || !currentURLString.contains("/redirect/")
            let isTargetRedirect = targetURLString.contains("/redirect/")
            let shouldPreserveFinalPage = isCurrentFinal && isTargetRedirect
            
            if ((hasNavigationHistory || (isDifferentDomain && isCurrentURLUserOpened)) && !isRedirectSequence) || shouldPreserveFinalPage {
                print("🚫 WebView: NOT forcing reload")
                print("   Current URL: \(currentURLString)")
                print("   Target URL: \(targetURLString)")
                print("   Has history: \(hasNavigationHistory)")
                print("   Different domain: \(isDifferentDomain)")
                print("   Is user-opened URL: \(isCurrentURLUserOpened)")
                print("   Is redirect sequence: \(isRedirectSequence)")
                print("   Should preserve final page: \(shouldPreserveFinalPage)")
                print("   Allowing user to stay on current page")
                return
            }
        }
        
        // Загружаем только если URL действительно изменился и WebView не в процессе загрузки
        if currentURLString != targetURLString && !webView.isLoading {
            print("🌐 WebView: Loading new URL - \(targetURLString)")
            print("   Previous URL: \(currentURLString)")
            
            // Показываем лоадер
            DispatchQueue.main.async {
                self.isLoading = true
                self.hideLoaderTimer?.invalidate()
            }
            
            // Создаем запрос с оптимизированными настройками
            var request = URLRequest(url: targetURL)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30.0
            
            webView.load(request)
        } else if webView.isLoading {
            print("🔄 WebView: Already loading, skipping new request")
        } else {
            print("🔄 WebView: URL unchanged, skipping reload")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createCustomUserAgent() -> String {
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        
        return "Mozilla/5.0 (\(deviceModel); CPU OS \(systemVersion.replacingOccurrences(of: ".", with: "_")) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(systemVersion) Mobile/15E148 Safari/604.1"
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
        let parent: WebView
        private var redirectCount = 0
        private let maxRedirects = 15
        private var isHandlingRedirectLimit = false
        private var orientationObserver: NSObjectProtocol?
        private weak var webView: WKWebView?
        private var lastRedirectTime: TimeInterval = 0
        private var redirectChainStartURL: String?
        private var isGamblingDomain = false
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        deinit {
            removeOrientationObserver()
        }
        
        func setupOrientationObserver(for webView: WKWebView) {
            self.webView = webView
            removeOrientationObserver() // Удаляем предыдущий наблюдатель если есть
            
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleOrientationChange()
            }
        }
        
        private func removeOrientationObserver() {
            if let observer = orientationObserver {
                NotificationCenter.default.removeObserver(observer)
                orientationObserver = nil
            }
        }
        
        private func handleOrientationChange() {
            guard let webView = webView else { return }
            
            // Небольшая задержка для завершения анимации поворота
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Только сбрасываем зум, НЕ перезагружаем страницу
                if webView.scrollView.zoomScale != 1.0 {
                    webView.scrollView.setZoomScale(1.0, animated: false)
                    print("🔄 WebView zoom reset to 100% after orientation change")
                }
                
                // Переустанавливаем настройки зума без агрессивных действий
                webView.scrollView.minimumZoomScale = 1.0
                webView.scrollView.maximumZoomScale = 1.0
                webView.scrollView.bouncesZoom = false
                
                print("🔧 Zoom settings reapplied after orientation change (no page reload)")
            }
        }
        
        private func handleDeepLink(url: URL, webView: WKWebView) {
            print("🔗 ===== DEEP LINK HANDLING =====")
            print("📱 URL: \(url.absoluteString)")
            print("🔍 Scheme: \(url.scheme ?? "nil")")
            print("🏠 Host: \(url.host ?? "nil")")
            
            // Сохраняем текущий URL для возврата
            let currentURL = webView.url
            print("💾 Current URL saved for return: \(currentURL?.absoluteString ?? "nil")")
            
            // Улучшенная логика открытия deep links
            // Сначала пытаемся открыть напрямую, не полагаясь на canOpenURL
            print("🚀 Attempting to open deep link directly...")
            UIApplication.shared.open(url, options: [:]) { success in
                print("📱 Deep link opened: \(success ? "✅ success" : "❌ failed")")
                
                if success {
                    print("✅ Successfully opened external app")
                    // Ждем немного дольше для полного открытия внешнего приложения
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.returnToPreviousPage(webView: webView, fallbackURL: currentURL)
                    }
                } else {
                    print("❌ Failed to open deep link directly")
                    // Только если прямое открытие не удалось, пытаемся найти альтернативы
                    DispatchQueue.main.async {
                        self.handleUnsupportedDeepLink(url: url, webView: webView, fallbackURL: currentURL)
                    }
                }
            }
            
            print("================================")
        }
        
        private func handleUPILink(url: URL, webView: WKWebView) {
            print("💳 ===== UPI LINK HANDLING =====")
            print("📱 UPI URL: \(url.absoluteString)")
            
            // Сохраняем текущий URL для возврата
            let currentURL = webView.url
            print("💾 Current URL saved for return: \(currentURL?.absoluteString ?? "nil")")
            
            // Список популярных UPI приложений в порядке приоритета
            let upiApps = [
                ("phonepe", "PhonePe"),
                ("paytmmp", "Paytm"),
                ("gpay", "Google Pay"),
                ("bhimupi", "BHIM"),
                ("phonepe-switch", "PhonePe Switch"),
                ("paytm", "Paytm Alt"),
                ("phonepe-merchant", "PhonePe Merchant")
            ]
            
            // Пытаемся открыть UPI ссылку в каждом приложении
            tryUPIApps(url: url, apps: upiApps, currentIndex: 0, webView: webView, fallbackURL: currentURL)
            
            print("===============================")
        }
        
        private func tryUPIApps(url: URL, apps: [(String, String)], currentIndex: Int, webView: WKWebView, fallbackURL: URL?) {
            guard currentIndex < apps.count else {
                print("❌ All UPI apps failed, returning to previous page")
                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            let (scheme, appName) = apps[currentIndex]
            let upiURLString = url.absoluteString.replacingOccurrences(of: "upi://", with: "\(scheme)://")
            
            guard let upiURL = URL(string: upiURLString) else {
                print("❌ Invalid UPI URL for \(appName)")
                tryUPIApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            print("🔄 Trying UPI with \(appName): \(upiURLString)")
            
            UIApplication.shared.open(upiURL, options: [:]) { success in
                if success {
                    print("✅ Successfully opened UPI with \(appName)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                    }
                } else {
                    print("❌ Failed to open UPI with \(appName), trying next app")
                    DispatchQueue.main.async {
                        self.tryUPIApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                    }
                }
            }
        }
        
        private func handleBankIDLink(url: URL, webView: WKWebView) {
            print("🏦 ===== BANKID LINK HANDLING =====")
            print("📱 BankID URL: \(url.absoluteString)")
            
            // Сохраняем текущий URL для возврата
            let currentURL = webView.url
            print("💾 Current URL saved for return: \(currentURL?.absoluteString ?? "nil")")
            
            // Список BankID схем в порядке приоритета
            let bankidApps = [
                ("bankid", "BankID"),
                ("bankid-app", "BankID App"),
                ("mobilebankid", "Mobile BankID")
            ]
            
            // Пытаемся открыть BankID ссылку в каждом приложении
            tryBankIDApps(url: url, apps: bankidApps, currentIndex: 0, webView: webView, fallbackURL: currentURL)
            
            print("===============================")
        }
        
        private func tryBankIDApps(url: URL, apps: [(String, String)], currentIndex: Int, webView: WKWebView, fallbackURL: URL?) {
            guard currentIndex < apps.count else {
                print("❌ All BankID apps failed, returning to previous page")
                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            let (scheme, appName) = apps[currentIndex]
            let originalScheme = url.scheme?.lowercased() ?? ""
            let bankidURLString = url.absoluteString.replacingOccurrences(of: "\(originalScheme)://", with: "\(scheme)://")
            
            guard let bankidURL = URL(string: bankidURLString) else {
                print("❌ Invalid BankID URL for \(appName)")
                tryBankIDApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            print("🔄 Trying BankID with \(appName): \(bankidURLString)")
            
            UIApplication.shared.open(bankidURL, options: [:]) { success in
                if success {
                    print("✅ Successfully opened BankID with \(appName)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // BankID может требовать больше времени
                        self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                    }
                } else {
                    print("❌ Failed to open BankID with \(appName), trying next app")
                    DispatchQueue.main.async {
                        self.tryBankIDApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                    }
                }
            }
        }
        
        private func handlePhonePeLink(url: URL, webView: WKWebView) {
            print("💳 ===== PHONEPE LINK HANDLING =====")
            print("📱 PhonePe URL: \(url.absoluteString)")
            
            // Сохраняем текущий URL для возврата
            let currentURL = webView.url
            print("💾 Current URL saved for return: \(currentURL?.absoluteString ?? "nil")")
            
            // Список PhonePe схем в порядке приоритета
            let phonepeApps = [
                ("phonepe", "PhonePe"),
                ("phonepe-switch", "PhonePe Switch"),
                ("phonepe-merchant", "PhonePe Merchant")
            ]
            
            // Пытаемся открыть PhonePe ссылку в каждом приложении
            tryPhonePeApps(url: url, apps: phonepeApps, currentIndex: 0, webView: webView, fallbackURL: currentURL)
            
            print("===============================")
        }
        
        private func tryPhonePeApps(url: URL, apps: [(String, String)], currentIndex: Int, webView: WKWebView, fallbackURL: URL?) {
            guard currentIndex < apps.count else {
                print("❌ All PhonePe apps failed, returning to previous page")
                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            let (scheme, appName) = apps[currentIndex]
            let originalScheme = url.scheme?.lowercased() ?? ""
            let phonepeURLString = url.absoluteString.replacingOccurrences(of: "\(originalScheme)://", with: "\(scheme)://")
            
            guard let phonepeURL = URL(string: phonepeURLString) else {
                print("❌ Invalid PhonePe URL for \(appName)")
                tryPhonePeApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                return
            }
            
            print("🔄 Trying PhonePe with \(appName): \(phonepeURLString)")
            
            UIApplication.shared.open(phonepeURL, options: [:]) { success in
                if success {
                    print("✅ Successfully opened PhonePe with \(appName)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                    }
                } else {
                    print("❌ Failed to open PhonePe with \(appName), trying next app")
                    DispatchQueue.main.async {
                        self.tryPhonePeApps(url: url, apps: apps, currentIndex: currentIndex + 1, webView: webView, fallbackURL: fallbackURL)
                    }
                }
            }
        }
        
        private func returnToPreviousPage(webView: WKWebView, fallbackURL: URL?) {
            print("⬅️ ===== RETURNING TO PREVIOUS PAGE =====")
            
            if webView.canGoBack {
                print("✅ Going back to previous page")
                webView.goBack()
                
                // Проверяем через некоторое время, что страница загрузилась корректно
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.checkPageLoadStatus(webView: webView, fallbackURL: fallbackURL)
                }
            } else if let fallbackURL = fallbackURL {
                print("🔄 No back history, reloading fallback URL")
                webView.load(URLRequest(url: fallbackURL))
            } else {
                print("⚠️ No back history and no fallback URL")
            }
            
            print("========================================")
        }
        
        private func checkPageLoadStatus(webView: WKWebView, fallbackURL: URL?) {
            // Проверяем, не показывается ли страница ошибки
            webView.evaluateJavaScript("document.title") { result, error in
                if let title = result as? String {
                    print("📄 Current page title: \(title)")
                    
                    // Проверяем на типичные заголовки страниц ошибок
                    let errorTitles = ["error", "not found", "404", "500", "unavailable", "problem"]
                    let isErrorPage = errorTitles.contains { title.lowercased().contains($0) }
                    
                    if isErrorPage {
                        print("❌ Error page detected, attempting to reload fallback URL")
                        if let fallbackURL = fallbackURL {
                            DispatchQueue.main.async {
                                webView.load(URLRequest(url: fallbackURL))
                            }
                        }
                    } else {
                        print("✅ Page appears to be loaded correctly")
                    }
                } else {
                    print("⚠️ Could not get page title: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
        
        private func handleUnsupportedDeepLink(url: URL, webView: WKWebView, fallbackURL: URL?) {
            print("🔍 ===== HANDLING UNSUPPORTED DEEP LINK =====")
            
            // Пытаемся найти альтернативные способы открытия
            if let scheme = url.scheme?.lowercased() {
                var alternativeURL: URL?
                var shouldTryAlternativeSchemes = false
                
                switch scheme {
                // Социальные сети
                case "instagram":
                    if let path = url.path.isEmpty ? nil : url.path {
                        alternativeURL = URL(string: "https://instagram.com\(path)")
                    }
                case "twitter", "x":
                    if let path = url.path.isEmpty ? nil : url.path {
                        alternativeURL = URL(string: "https://twitter.com\(path)")
                    }
                case "facebook", "fb":
                    if let path = url.path.isEmpty ? nil : url.path {
                        alternativeURL = URL(string: "https://facebook.com\(path)")
                    }
                case "youtube":
                    if let path = url.path.isEmpty ? nil : url.path {
                        alternativeURL = URL(string: "https://youtube.com\(path)")
                    }
                case "tiktok":
                    if let path = url.path.isEmpty ? nil : url.path {
                        alternativeURL = URL(string: "https://tiktok.com\(path)")
                    }
                
                // Платежные приложения
                case "paytmmp", "paytm":
                    print("💳 Detected Paytm payment link")
                    shouldTryAlternativeSchemes = true
                    // Пытаемся альтернативные схемы для Paytm
                    let paytmSchemes = ["paytm://", "paytmmp://"]
                    for altScheme in paytmSchemes {
                        if altScheme != "\(scheme)://" {
                            let altURLString = url.absoluteString.replacingOccurrences(of: "\(scheme)://", with: altScheme)
                            if let altURL = URL(string: altURLString) {
                                print("🔄 Trying alternative Paytm scheme: \(altURLString)")
                                UIApplication.shared.open(altURL, options: [:]) { success in
                                    if success {
                                        print("✅ Successfully opened Paytm with alternative scheme")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                    
                case "phonepe", "phonepe-merchant", "phonepe-switch":
                    print("💳 Detected PhonePe payment link")
                    shouldTryAlternativeSchemes = true
                    // Пытаемся альтернативные схемы для PhonePe
                    let phonepeSchemes = ["phonepe://", "phonepe-merchant://", "phonepe-switch://"]
                    for altScheme in phonepeSchemes {
                        if altScheme != "\(scheme)://" {
                            let altURLString = url.absoluteString.replacingOccurrences(of: "\(scheme)://", with: altScheme)
                            if let altURL = URL(string: altURLString) {
                                print("🔄 Trying alternative PhonePe scheme: \(altURLString)")
                                UIApplication.shared.open(altURL, options: [:]) { success in
                                    if success {
                                        print("✅ Successfully opened PhonePe with alternative scheme")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                    
                case "bankid", "bankid-app", "mobilebankid":
                    print("🏦 Detected BankID authentication link")
                    shouldTryAlternativeSchemes = true
                    // Пытаемся альтернативные схемы для BankID
                    let bankidSchemes = ["bankid://", "bankid-app://", "mobilebankid://"]
                    for altScheme in bankidSchemes {
                        if altScheme != "\(scheme)://" {
                            let altURLString = url.absoluteString.replacingOccurrences(of: "\(scheme)://", with: altScheme)
                            if let altURL = URL(string: altURLString) {
                                print("🔄 Trying alternative BankID scheme: \(altURLString)")
                                UIApplication.shared.open(altURL, options: [:]) { success in
                                    if success {
                                        print("✅ Successfully opened BankID with alternative scheme")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                    
                case "gpay", "googlepay", "tez":
                    print("💳 Detected Google Pay payment link")
                    shouldTryAlternativeSchemes = true
                    
                case "upi":
                    print("💳 Detected UPI payment link")
                    shouldTryAlternativeSchemes = true
                    
                case "bhim", "bhimupi":
                    print("💳 Detected BHIM payment link")
                    shouldTryAlternativeSchemes = true
                    
                case "whatsapp":
                    print("💬 Detected WhatsApp link")
                    shouldTryAlternativeSchemes = true
                    
                case "telegram", "tg":
                    print("💬 Detected Telegram link")
                    shouldTryAlternativeSchemes = true
                    
                default:
                    print("🤷‍♂️ Unknown scheme: \(scheme)")
                    shouldTryAlternativeSchemes = true
                }
                
                // Если есть веб-альтернатива, пытаемся ее
                if let altURL = alternativeURL {
                    print("🔄 Trying web alternative URL: \(altURL.absoluteString)")
                    webView.load(URLRequest(url: altURL))
                    return
                }
                
                // Для платежных и других приложений пытаемся подождать и повторить
                if shouldTryAlternativeSchemes {
                    print("⏳ Waiting and retrying deep link for \(scheme)...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        UIApplication.shared.open(url, options: [:]) { success in
                            if success {
                                print("✅ Successfully opened \(scheme) on retry")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                                }
                            } else {
                                print("❌ Failed to open \(scheme) on retry")
                                // Показываем пользователю информативное сообщение
                                DispatchQueue.main.async {
                                    self.showDeepLinkFailureMessage(scheme: scheme, webView: webView, fallbackURL: fallbackURL)
                                }
                            }
                        }
                    }
                    return
                }
            }
            
            // Если нет альтернативы, возвращаемся на предыдущую страницу
            print("⬅️ No alternative found, returning to previous page")
            self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
            
            print("===============================================")
        }
        
        private func showDeepLinkFailureMessage(scheme: String, webView: WKWebView, fallbackURL: URL?) {
            print("💬 ===== SHOWING DEEP LINK FAILURE MESSAGE =====")
            
            let appName = getAppNameForScheme(scheme)
            let message = "The \(appName) app is required to complete this action. Please install \(appName) from the App Store or try again."
            
            // Создаем alert
            let alert = UIAlertController(
                title: "App Required",
                message: message,
                preferredStyle: .alert
            )
            
            // Кнопка "Try Again"
            alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
                print("🔄 User chose to try again")
                // Пытаемся открыть еще раз
                if let originalURL = URL(string: "\(scheme)://\(fallbackURL?.path ?? "")") {
                    UIApplication.shared.open(originalURL, options: [:]) { success in
                        if !success {
                            // Если все еще не работает, возвращаемся на предыдущую страницу
                            DispatchQueue.main.async {
                                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                            }
                        }
                    }
                } else {
                    self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
                }
            })
            
            // Кнопка "Cancel"
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                print("❌ User cancelled deep link")
                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
            })
            
            // Показываем alert
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                DispatchQueue.main.async {
                    rootViewController.present(alert, animated: true)
                }
            } else {
                // Если не можем показать alert, просто возвращаемся
                self.returnToPreviousPage(webView: webView, fallbackURL: fallbackURL)
            }
            
            print("================================================")
        }
        
        private func getAppNameForScheme(_ scheme: String) -> String {
            switch scheme.lowercased() {
            case "paytmmp", "paytm":
                return "Paytm"
            case "phonepe", "phonepe-merchant", "phonepe-switch":
                return "PhonePe"
            case "bankid", "bankid-app", "mobilebankid":
                return "BankID"
            case "gpay", "googlepay", "tez":
                return "Google Pay"
            case "upi":
                return "UPI"
            case "bhim", "bhimupi":
                return "BHIM"
            case "whatsapp":
                return "WhatsApp"
            case "telegram", "tg":
                return "Telegram"
            case "instagram":
                return "Instagram"
            case "twitter", "x":
                return "Twitter"
            case "facebook", "fb":
                return "Facebook"
            case "youtube":
                return "YouTube"
            case "tiktok":
                return "TikTok"
            default:
                return "required"
            }
        }
        
        private func shouldOpenURLExternally(url: URL, urlString: String, scheme: String, host: String) -> Bool {
            // Список доменов, которые лучше открывать в внешних приложениях
            let externalAppDomains = [
                // Социальные сети
                "instagram.com", "www.instagram.com",
                "facebook.com", "www.facebook.com", "m.facebook.com",
                "twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com",
                "tiktok.com", "www.tiktok.com", "m.tiktok.com",
                "linkedin.com", "www.linkedin.com",
                "snapchat.com", "www.snapchat.com",
                
                // Мессенджеры
                "telegram.org", "t.me", "web.telegram.org",
                "whatsapp.com", "www.whatsapp.com", "web.whatsapp.com",
                "discord.com", "www.discord.com",
                
                // Видео и музыка
                "youtube.com", "www.youtube.com", "m.youtube.com",
                "youtu.be",
                "spotify.com", "www.spotify.com", "open.spotify.com",
                "soundcloud.com", "www.soundcloud.com",
                
                // Магазины приложений
                "apps.apple.com", "itunes.apple.com",
                "play.google.com",
                
                // Карты
                "maps.google.com", "www.google.com/maps",
                "maps.apple.com"
            ]
            
            // Проверяем, содержит ли URL домен из списка
            let shouldOpen = externalAppDomains.contains { domain in
                host == domain || host.hasSuffix("." + domain)
            }
            
            if shouldOpen {
                print("🎯 Domain \(host) should be opened externally")
            }
            
            return shouldOpen
        }
        
        private func isGamblingDomain(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            
            let gamblingDomains = [
                // Casino domains
                "ninecasino", "betonliga", "invofy", "casino", "bet", "poker", "slots",
                "gambling", "game", "play", "win", "jackpot", "roulette", "blackjack",
                // Gaming providers
                "bgaming", "jacks", "pragmatic", "netent", "microgaming", "playtech",
                "evolution", "ezugi", "playson", "quickspin", "yggdrasil", "nolimit",
                // Specific domains from logs
                "ninecasinogo.com", "02ninecasino61.com", "auth.betonliga.com", "invofy5.com"
            ]
            
            return gamblingDomains.contains { domain in
                host.contains(domain)
            }
        }
        
        private func isGamingProviderDomain(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            
            let gamingProviders = [
                // Major gaming providers that use about:blank and special schemes
                "bgaming", "jacks", "pragmaticplay", "netent", "microgaming", "playtech",
                "evolution", "ezugi", "playson", "quickspin", "yggdrasil", "nolimitcity",
                "redtiger", "bigtime", "relax", "hacksaw", "push", "thunderkick",
                "kalamba", "fantasma", "booming", "spinomenal", "wazdan", "evoplay"
            ]
            
            return gamingProviders.contains { provider in
                host.contains(provider)
            }
        }
        
        private func isTrackingDomain(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            
            let trackingDomains = [
                // Google tracking
                "doubleclick.net", "googleadservices.com", "googlesyndication.com",
                "google-analytics.com", "googletagmanager.com", "googletagservices.com",
                // Facebook tracking
                "facebook.com", "connect.facebook.net",
                // Other tracking
                "hotjar.com", "mixpanel.com", "segment.com", "amplitude.com",
                "yandex.ru", "mc.yandex.ru"
            ]
            
            return trackingDomains.contains { domain in
                host.contains(domain)
            }
        }
        
        private func resetRedirectCounterSafely() {
            let now = Date().timeIntervalSince1970
            
            // Для казино сайтов используем более длительный интервал
            let resetInterval: TimeInterval = isGamblingDomain ? 10.0 : 3.0
            
            if now - lastRedirectTime > resetInterval {
                redirectCount = 0
                isHandlingRedirectLimit = false
                redirectChainStartURL = nil
                print("🔄 Redirect counter reset after \(resetInterval)s interval")
            }
        }
        
        private func disableZoomWithJavaScript(_ webView: WKWebView) {
            let jsCode = """
                // ПОЛНОЕ ОТКЛЮЧЕНИЕ ЗУМА С ОПТИМИЗИРОВАННОЙ ОБРАБОТКОЙ КЛАВИАТУРЫ
                
                // ============================================
                // ГЛОБАЛЬНЫЙ STATE (Single Source of Truth)
                // ============================================
                var GLOBAL_STATE = {
                    activeInputElement: null,
                    keyboardVisible: false,
                    keyboardAnimating: false,
                    scrollDebounceTimer: null,
                    lastViewportHeight: window.visualViewport ? window.visualViewport.height : window.innerHeight
                };
                
                // Экспортируем для совместимости с существующим кодом
                window.getActiveInputElement = function() {
                    return GLOBAL_STATE.activeInputElement;
                };
                
                // 1. Усиленный viewport meta tag
                function enforceViewportSettings() {
                    var viewport = document.querySelector('meta[name="viewport"]');
                    var viewportContent = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no, shrink-to-fit=no, viewport-fit=cover';
                    
                    if (viewport) {
                        viewport.setAttribute('content', viewportContent);
                    } else {
                        var meta = document.createElement('meta');
                        meta.name = 'viewport';
                        meta.content = viewportContent;
                        document.getElementsByTagName('head')[0].appendChild(meta);
                    }
                    
                    // Принудительно переопределяем все существующие viewport теги
                    var allViewports = document.querySelectorAll('meta[name="viewport"]');
                    for (var i = 0; i < allViewports.length; i++) {
                        allViewports[i].setAttribute('content', viewportContent);
                    }
                }
                
                // 2. CSS стили для предотвращения зума (улучшенные для input полей)
                function addZoomPreventionCSS() {
                    var style = document.createElement('style');
                    style.textContent = `
                        * {
                            -webkit-user-select: none;
                            -webkit-touch-callout: none;
                            -webkit-tap-highlight-color: transparent;
                        }
                        
                        html, body {
                            -ms-touch-action: manipulation;
                            touch-action: manipulation;
                            -webkit-text-size-adjust: 100%;
                            -ms-text-size-adjust: 100%;
                            -webkit-overflow-scrolling: touch;
                        }
                        
                        /* Специальные настройки для input элементов */
                        input, textarea, select, button, a, [contenteditable], [role="textbox"] {
                            -webkit-user-select: auto !important;
                            -webkit-touch-callout: default !important;
                            touch-action: manipulation !important;
                            -webkit-tap-highlight-color: rgba(0,0,0,0.1) !important;
                        }
                        
                        /* Дополнительная защита для форм */
                        form, .form-control, .input, .form-group {
                            -webkit-user-select: auto !important;
                            touch-action: manipulation !important;
                        }
                        
                        /* Предотвращаем случайное масштабирование и "прыжки" при фокусе */
                        input:focus, textarea:focus, select:focus, [contenteditable]:focus {
                            -webkit-transform: translateZ(0);
                            transform: translateZ(0);
                        }
                    `;
                    document.head.appendChild(style);
                }
                
                // 3. Блокировка всех жестов зума
                function blockZoomGestures() {
                    // Блокируем жесты пинча
                    document.addEventListener('gesturestart', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                    }, { passive: false, capture: true });
                    
                    document.addEventListener('gesturechange', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                    }, { passive: false, capture: true });
                    
                    document.addEventListener('gestureend', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                    }, { passive: false, capture: true });
                    
                    // Блокируем wheel события (зум колесиком мыши)
                    document.addEventListener('wheel', function(e) {
                        if (e.ctrlKey) {
                            e.preventDefault();
                            e.stopPropagation();
                        }
                    }, { passive: false, capture: true });
                    
                    // Блокируем keydown события для зума (Ctrl +/-)
                    document.addEventListener('keydown', function(e) {
                        if ((e.ctrlKey || e.metaKey) && (e.key === '+' || e.key === '-' || e.key === '=' || e.key === '0')) {
                            e.preventDefault();
                            e.stopPropagation();
                        }
                    }, { passive: false, capture: true });
                }
                
                // 4. Умная блокировка двойного нажатия с защитой input полей
                function blockDoubleTapZoom() {
                    var lastTouchEnd = 0;
                    var touchCount = 0;
                    var lastTouchTarget = null;
                    var isNavigating = false;
                    var touchStartTime = 0;
                    var touchStartCount = 0;
                    
                    // Отслеживаем навигацию
                    window.addEventListener('beforeunload', function() {
                        isNavigating = true;
                        setTimeout(function() { isNavigating = false; }, 1000);
                    });
                    
                    window.addEventListener('popstate', function() {
                        isNavigating = true;
                        setTimeout(function() { isNavigating = false; }, 1000);
                    });
                    
                    // Отслеживаем фокус на input элементах → ИСПОЛЬЗУЕМ ГЛОБАЛЬНЫЙ STATE
                    document.addEventListener('focusin', function(event) {
                        var target = event.target;
                        if (isInputElement(target)) {
                            GLOBAL_STATE.activeInputElement = target;
                            console.log('📝 Input element focused, disabling zoom protection temporarily');
                        }
                    }, true);
                    
                    document.addEventListener('focusout', function(event) {
                        var target = event.target;
                        if (isInputElement(target)) {
                            // Задержка перед сбросом, чтобы избежать конфликтов
                            setTimeout(function() {
                                GLOBAL_STATE.activeInputElement = null;
                                console.log('📝 Input element unfocused, re-enabling zoom protection');
                            }, 300);
                        }
                    }, true);
                    
                    // Более осторожная блокировка touchstart
                    document.addEventListener('touchstart', function(event) {
                        if (isNavigating) return;
                        
                        var target = event.target;
                        
                        // НЕ блокируем события на input элементах или когда input активен
                        if (isInputElement(target) || GLOBAL_STATE.activeInputElement) {
                            return;
                        }
                        
                        var now = Date.now();
                        if (now - touchStartTime <= 350) { // Увеличили время для более точного определения
                            touchStartCount++;
                            if (touchStartCount >= 2) {
                                if (!isInteractiveElement(target)) {
                                    event.preventDefault();
                                    console.log('🚫 Blocked fast double touchstart');
                                    return false;
                                }
                            }
                        } else {
                            touchStartCount = 1;
                        }
                        touchStartTime = now;
                    }, { passive: false });
                    
                    // Более осторожная блокировка touchend
                    document.addEventListener('touchend', function(event) {
                        if (isNavigating) return;
                        
                        var target = event.target;
                        
                        // НЕ блокируем события на input элементах или когда input активен
                        if (isInputElement(target) || GLOBAL_STATE.activeInputElement) {
                            return;
                        }
                        
                        var now = Date.now();
                        
                        if (now - lastTouchEnd > 500 || target !== lastTouchTarget) {
                            touchCount = 1;
                        } else {
                            touchCount++;
                        }
                        
                        // Блокируем только двойные нажатия на неинтерактивных элементах
                        if (now - lastTouchEnd <= 450 && touchCount >= 2) { // Увеличили время
                            if (!isInteractiveElement(target)) {
                                event.preventDefault();
                                console.log('🚫 Blocked double-tap zoom');
                                touchCount = 0;
                                return false;
                            }
                        }
                        
                        lastTouchEnd = now;
                        lastTouchTarget = target;
                    }, { passive: false });
                    
                    // Более осторожная блокировка click событий
                    document.addEventListener('click', function(event) {
                        if (isNavigating) return;
                        
                        var target = event.target;
                        
                        // НЕ блокируем click на input элементах или когда input активен
                        if (isInputElement(target) || GLOBAL_STATE.activeInputElement) {
                            return;
                        }
                        
                        var now = Date.now();
                        if (now - lastClickTime <= 450) { // Увеличили время
                            clickCount++;
                            if (clickCount >= 2 && !isInteractiveElement(target)) {
                                event.preventDefault();
                                console.log('🚫 Blocked double-click zoom');
                                return false;
                            }
                        } else {
                            clickCount = 1;
                        }
                        lastClickTime = now;
                    }, { passive: false });
                }
                
                // 5. Проверка input элементов
                function isInputElement(target) {
                    if (!target) return false;
                    
                    var tagName = target.tagName ? target.tagName.toLowerCase() : '';
                    var inputTypes = ['input', 'textarea', 'select'];
                    
                    if (inputTypes.includes(tagName)) {
                        return true;
                    }
                    
                    // Проверяем contenteditable элементы
                    if (target.contentEditable === 'true' || target.contentEditable === '') {
                        return true;
                    }
                    
                    // Проверяем role="textbox"
                    if (target.getAttribute('role') === 'textbox') {
                        return true;
                    }
                    
                    return false;
                }
                
                // 6. Улучшенная проверка интерактивных элементов
                function isInteractiveElement(target) {
                    if (!target) return false;
                    
                    // Сначала проверяем input элементы
                    if (isInputElement(target)) {
                        return true;
                    }
                    
                    var currentElement = target;
                    var maxDepth = 7;
                    var depth = 0;
                    
                    while (currentElement && depth < maxDepth) {
                        var tagName = currentElement.tagName ? currentElement.tagName.toLowerCase() : '';
                        
                        // Проверяем интерактивные теги
                        if (['button', 'a', 'input', 'select', 'textarea', 'label', 'option', 'form'].includes(tagName)) {
                            return true;
                        }
                        
                        // Проверяем атрибуты и классы
                        if (currentElement.onclick || 
                            currentElement.getAttribute('onclick') ||
                            currentElement.getAttribute('role') === 'button' ||
                            currentElement.getAttribute('role') === 'textbox' ||
                            currentElement.getAttribute('tabindex') ||
                            currentElement.hasAttribute('data-click') ||
                            currentElement.hasAttribute('data-action') ||
                            currentElement.hasAttribute('data-toggle') ||
                            currentElement.classList.contains('btn') ||
                            currentElement.classList.contains('button') ||
                            currentElement.classList.contains('clickable') ||
                            currentElement.classList.contains('link') ||
                            currentElement.classList.contains('interactive') ||
                            currentElement.classList.contains('form-control') ||
                            currentElement.classList.contains('input')) {
                            return true;
                        }
                        
                        // Проверяем стили
                        try {
                            var styles = window.getComputedStyle(currentElement);
                            if (styles.cursor === 'pointer') {
                                return true;
                            }
                        } catch (e) {}
                        
                        currentElement = currentElement.parentElement;
                        depth++;
                    }
                    
                    return false;
                }
                
                // 6. ОПТИМИЗИРОВАННАЯ обработка клавиатуры (БЕЗ ПОДЕРГИВАНИЙ)
                function setupKeyboardProtection() {
                    if (!window.visualViewport) {
                        console.warn('⚠️ visualViewport not supported');
                        return;
                    }
                    
                    // ============================================
                    // ЕДИНСТВЕННЫЙ обработчик visualViewport resize
                    // ============================================
                    window.visualViewport.addEventListener('resize', function() {
                        var currentHeight = window.visualViewport.height;
                        var heightDiff = GLOBAL_STATE.lastViewportHeight - currentHeight;
                        var wasVisible = GLOBAL_STATE.keyboardVisible;
                        
                        // Определяем видимость клавиатуры
                        GLOBAL_STATE.keyboardVisible = (window.innerHeight - currentHeight) > 150;
                        
                        // Логирование изменения состояния
                        if (GLOBAL_STATE.keyboardVisible && !wasVisible) {
                            console.log('⌨️ Keyboard appeared');
                            GLOBAL_STATE.keyboardAnimating = true;
                        } else if (!GLOBAL_STATE.keyboardVisible && wasVisible) {
                            console.log('⌨️ Keyboard disappeared');
                            GLOBAL_STATE.keyboardAnimating = false;
                        }
                        
                        // Если клавиатура появляется И есть активный input
                        if (GLOBAL_STATE.keyboardVisible && heightDiff > 100 && GLOBAL_STATE.activeInputElement) {
                            // Отменяем предыдущие запланированные скроллы (debouncing)
                            if (GLOBAL_STATE.scrollDebounceTimer) {
                                clearTimeout(GLOBAL_STATE.scrollDebounceTimer);
                            }
                            
                            // Планируем ОДИН финальный скролл после стабилизации viewport
                            GLOBAL_STATE.scrollDebounceTimer = setTimeout(function() {
                                if (GLOBAL_STATE.activeInputElement) {
                                    scrollToInputInstant(GLOBAL_STATE.activeInputElement);
                                }
                                GLOBAL_STATE.keyboardAnimating = false;
                            }, 100); // Минимальный debounce для стабилизации
                        }
                        
                        // Если клавиатура скрывается
                        if (!GLOBAL_STATE.keyboardVisible && wasVisible) {
                            // Отменяем все pending скроллы
                            if (GLOBAL_STATE.scrollDebounceTimer) {
                                clearTimeout(GLOBAL_STATE.scrollDebounceTimer);
                                GLOBAL_STATE.scrollDebounceTimer = null;
                            }
                        }
                        
                        GLOBAL_STATE.lastViewportHeight = currentHeight;
                    });
                    
                    // ============================================
                    // БЛОКИРОВКА браузерного автоскролла
                    // ============================================
                    document.addEventListener('touchend', function(event) {
                        var target = event.target;
                        if (isInputElement(target)) {
                            // Предотвращаем браузерный автоскролл
                            event.preventDefault();
                            
                            // Программно даем фокус (контролируемый процесс)
                            target.focus();
                            
                            console.log('🔒 Browser autoscroll blocked, focus applied programmatically');
                        }
                    }, { capture: true, passive: false });
                    
                    console.log('✅ Optimized keyboard protection enabled');
                }
                
                // ============================================
                // МГНОВЕННЫЙ скролл к input (БЕЗ smooth анимации)
                // ============================================
                function scrollToInputInstant(element) {
                    if (!element) return;
                    
                    try {
                        var rect = element.getBoundingClientRect();
                        var elementTop = rect.top + (window.pageYOffset || document.documentElement.scrollTop);
                        var viewportHeight = window.visualViewport ? window.visualViewport.height : window.innerHeight;
                        
                        // Позиционируем поле ввода в верхней трети экрана (30% от верха)
                        var targetScroll = elementTop - (viewportHeight * 0.3);
                        targetScroll = Math.max(0, targetScroll);
                        
                        // Проверяем нужен ли скролл
                        var currentScroll = window.pageYOffset || document.documentElement.scrollTop;
                        var scrollDiff = Math.abs(targetScroll - currentScroll);
                        
                        if (scrollDiff > 20) {
                            // INSTANT скролл (НЕ smooth!) для синхронизации с клавиатурой
                            window.scrollTo({
                                top: targetScroll,
                                behavior: 'auto'  // 'auto' = instant/immediate
                            });
                            console.log('📍 Input positioned instantly (distance: ' + Math.round(scrollDiff) + 'px)');
                        } else {
                            console.log('📍 Input already in optimal position');
                        }
                    } catch (e) {
                        console.warn('⚠️ Error in scrollToInputInstant:', e);
                    }
                }
                
                // 7. Постоянный мониторинг (более осторожный)
                function startZoomMonitoring() {
                    setInterval(function() {
                        // Не переопределяем viewport если активен input
                        if (!GLOBAL_STATE.activeInputElement) {
                            enforceViewportSettings();
                        }
                        
                        // Проверяем и сбрасываем зум если он появился (но не во время ввода)
                        if (window.visualViewport && window.visualViewport.scale > 1.01 && !GLOBAL_STATE.activeInputElement) {
                            console.log('🔧 Detected zoom, attempting to reset');
                            window.scrollTo(0, 0);
                        }
                    }, 2000); // Увеличили интервал чтобы меньше мешать
                }
                
                // Инициализация всех защит
                enforceViewportSettings();
                addZoomPreventionCSS();
                blockZoomGestures();
                blockDoubleTapZoom();
                setupKeyboardProtection();
                startZoomMonitoring();
                
                console.log('🚫 COMPLETE ZOOM PROTECTION WITH OPTIMIZED KEYBOARD SUPPORT ENABLED');
                console.log('✅ Improvements: Single viewport handler, instant scroll, debouncing, prevented browser autoscroll');
            """
            
            webView.evaluateJavaScript(jsCode) { result, error in
                if let error = error {
                    print("❌ Error executing complete zoom disable JavaScript: \(error.localizedDescription)")
                } else {
                    print("✅ Complete zoom protection enabled via JavaScript")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Простое начало навигации
            print("🌐 WebView: Started loading")
        }
        
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            print("🔄 Server redirect detected")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                print("✅ WebView: Successfully loaded URL - \(webView.url?.absoluteString ?? "N/A")")
                
                // Сохраняем последний URL который посетил пользователь
                if let currentUrl = webView.url?.absoluteString,
                   currentUrl.hasPrefix("http://") || currentUrl.hasPrefix("https://") {
                    UserDefaults.standard.set(currentUrl, forKey: "last_opened_url")
                    print("💾 Updated last opened URL: \(currentUrl)")
                }
                
                // Сбрасываем счетчик редиректов при успешной загрузке с учетом типа домена
                if let currentUrl = webView.url {
                    self.isGamblingDomain = self.isGamblingDomain(currentUrl)
                }
                
                // Для казино сайтов ждем дольше перед сбросом счетчика
                let resetDelay: TimeInterval = self.isGamblingDomain ? 5.0 : 1.0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay) {
                    self.resetRedirectCounterSafely()
                    print("🔄 Redirect counter reset after \(resetDelay)s - page loaded successfully")
                }
                
                // Отключаем зум через JavaScript только при первой загрузке или смене домена
                if let currentUrl = webView.url?.host {
                    let lastHost = UserDefaults.standard.string(forKey: "last_zoom_protection_host")
                    if lastHost != currentUrl {
                        UserDefaults.standard.set(currentUrl, forKey: "last_zoom_protection_host")
                        self.disableZoomWithJavaScript(webView)
                        print("🔧 Applied zoom protection for new host: \(currentUrl)")
                    } else {
                        print("🔧 Zoom protection already applied for host: \(currentUrl)")
                    }
                } else {
                    // Если нет хоста, применяем защиту
                    self.disableZoomWithJavaScript(webView)
                }
                
                // Скрываем лоадер
                self.parent.hideLoaderTimer?.invalidate()
                self.parent.hideLoaderTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                    }
                }
                
                self.parent.onLoadFinished?()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                let nsError = error as NSError
                print("❌ Navigation failed: \(nsError.localizedDescription) (code: \(nsError.code))")
                
                // Не сбрасываем счетчик для отмененных запросов или временных ошибок
                if nsError.code != NSURLErrorCancelled && nsError.code != 102 {
                    // Сбрасываем счетчик редиректов только для серьезных ошибок
                    self.resetRedirectCounterSafely()
                    print("🔄 Redirect counter reset due to navigation failure")
                } else {
                    print("⚠️ Navigation cancelled/interrupted - keeping redirect counter")
                }
                
                self.parent.onLoadError?(error)
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                let nsError = error as NSError
                print("🔴 WebView Failed Provisional Navigation:")
                print("   Error Code: \(nsError.code)")
                print("   Error Domain: \(nsError.domain)")
                print("   Error Description: \(error.localizedDescription)")
                print("   URL: \(webView.url?.absoluteString ?? "N/A")")
                
                // Игнорируем только отмену запросов (-999) и прерывание загрузки (102)
                if nsError.code == NSURLErrorCancelled || nsError.code == 102 {
                    print("   Ignored error - cancelled or frame load interrupted")
                    return
                }
                
                // Для казино сайтов более терпимо относимся к ошибкам
                let shouldResetCounter = !self.isGamblingDomain ||
                                       (nsError.code != NSURLErrorTimedOut &&
                                        nsError.code != NSURLErrorNetworkConnectionLost &&
                                        nsError.code != NSURLErrorNotConnectedToInternet)
                
                if shouldResetCounter {
                    // Сбрасываем счетчик редиректов только для серьезных ошибок
                    self.resetRedirectCounterSafely()
                    print("🔄 Redirect counter reset due to provisional navigation failure")
                } else {
                    print("⚠️ Temporary error on gambling domain - keeping redirect counter")
                }
                
                // Для всех остальных ошибок просто передаем их дальше
                self.parent.onLoadError?(error)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            print("🔗 Navigation request: \(url.absoluteString)")
            
            // Обработка deep links и внешних приложений
            if !url.absoluteString.hasPrefix("http") && !url.absoluteString.hasPrefix("https") {
                let scheme = url.scheme?.lowercased() ?? ""
                let urlString = url.absoluteString.lowercased()
                
                // Специальная обработка для схем, используемых игровыми провайдерами
                if scheme == "about" {
                    // Разрешенные about: схемы для игровых провайдеров
                    let allowedAboutSchemes = ["about:blank", "about:srcdoc"]
                    let isAllowedAboutScheme = allowedAboutSchemes.contains { allowedScheme in
                        urlString.hasPrefix(allowedScheme)
                    }
                    
                    if isAllowedAboutScheme {
                        // Проверяем текущий домен для дополнительной безопасности
                        if let currentURL = webView.url {
                            let isCurrentGambling = self.isGamblingDomain(currentURL)
                            let isCurrentGamingProvider = self.isGamingProviderDomain(currentURL)
                            
                            if isCurrentGambling || isCurrentGamingProvider {
                                print("🎮 Allowing \(urlString.components(separatedBy: "?").first ?? urlString) for gaming site: \(currentURL.host ?? "unknown")")
                                decisionHandler(.allow)
                                return
                            }
                        }
                        
                        // Для всех остальных сайтов тоже разрешаем (часто используется для popup окон и iframe)
                        print("🎮 Allowing \(urlString.components(separatedBy: "?").first ?? urlString) (commonly used for popups and gaming)")
                        decisionHandler(.allow)
                        return
                    } else {
                        print("🚫 Blocking unsupported about scheme: \(url.absoluteString)")
                        decisionHandler(.cancel)
                        return
                    }
                }
                
                // Разрешаем data: схемы для игровых провайдеров (могут использоваться для загрузки игр)
                if scheme == "data" {
                    print("🎮 Allowing data scheme for gaming content")
                    decisionHandler(.allow)
                    return
                }
                
                // Разрешаем blob: схемы для игровых провайдеров (используются для медиа контента)
                if scheme == "blob" {
                    print("🎮 Allowing blob scheme for gaming media content")
                    decisionHandler(.allow)
                    return
                }
                
                // Игнорируем только действительно проблемные системные схемы
                let blockedSchemes = ["javascript", "file"]
                
                if blockedSchemes.contains(scheme) {
                    print("🚫 Blocking dangerous system scheme: \(scheme):// (URL: \(url.absoluteString))")
                    decisionHandler(.cancel)
                    return
                }
                
                print("📱 Deep link detected: \(scheme)://")
                
                // Специальная обработка для различных типов ссылок
                if scheme == "upi" {
                    print("💳 UPI payment link detected - attempting multiple payment apps")
                    self.handleUPILink(url: url, webView: webView)
                } else if ["bankid", "bankid-app", "mobilebankid"].contains(scheme) {
                    print("🏦 BankID authentication link detected")
                    self.handleBankIDLink(url: url, webView: webView)
                } else if ["phonepe", "phonepe-merchant", "phonepe-switch"].contains(scheme) {
                    print("💳 PhonePe payment link detected")
                    self.handlePhonePeLink(url: url, webView: webView)
                } else {
                    self.handleDeepLink(url: url, webView: webView)
                }
                
                decisionHandler(.cancel)
                return
            }
            
            // Обработка специальных HTTP/HTTPS ссылок, которые должны открываться в внешних приложениях
            if let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() {
                let urlString = url.absoluteString.lowercased()
                
                // Проверяем популярные приложения, которые имеют веб-версии но лучше открываются в приложениях
                let shouldOpenExternally = self.shouldOpenURLExternally(url: url, urlString: urlString, scheme: scheme, host: host)
                
                if shouldOpenExternally {
                    print("📱 External app link detected: \(url.absoluteString)")
                    self.handleDeepLink(url: url, webView: webView)
                    decisionHandler(.cancel)
                    return
                }
            }
            
            // Определяем тип домена для специальной обработки
            isGamblingDomain = isGamblingDomain(url)
            let isTracking = isTrackingDomain(url)
            
            // Игнорируем трекинговые домены в подсчете редиректов
            if isTracking {
                print("📊 Tracking domain detected, ignoring for redirect count: \(url.host ?? "unknown")")
                decisionHandler(.allow)
                return
            }
            
            // Обработка редиректов для предотвращения ошибки "too many redirects"
            if navigationAction.navigationType == .other {
                let now = Date().timeIntervalSince1970
                
                // Начинаем новую цепочку редиректов если прошло много времени
                if redirectChainStartURL == nil || now - lastRedirectTime > 5.0 {
                    redirectChainStartURL = url.absoluteString
                    redirectCount = 1
                    print("🔄 Starting new redirect chain from: \(url.absoluteString)")
                } else {
                    redirectCount += 1
                }
                
                lastRedirectTime = now
                print("🔄 Redirect #\(redirectCount): \(url.absoluteString)")
                
                // Для казино сайтов используем более высокий лимит редиректов
                let effectiveMaxRedirects = isGamblingDomain ? 25 : maxRedirects
                
                // Уведомляем о каждом редиректе
                parent.onRedirectDetected?()
                
                // Если достигли лимита редиректов
                if redirectCount >= effectiveMaxRedirects && !isHandlingRedirectLimit {
                    print("⚠️ Redirect limit reached (\(effectiveMaxRedirects)) for \(isGamblingDomain ? "gambling" : "regular") domain")
                    print("🔗 Chain started from: \(redirectChainStartURL ?? "unknown")")
                    print("🔗 Current URL: \(url.absoluteString)")
                    
                    isHandlingRedirectLimit = true
                    redirectCount = 0 // Сбрасываем счетчик для новой цепочки
                    redirectChainStartURL = nil
                    
                    // Уведомляем родительский компонент о достижении лимита
                    parent.onRedirectLimitReached?(url.absoluteString)
                    
                    decisionHandler(.cancel)
                    return
                }
            } else {
                // Сбрасываем счетчик для новых навигаций (не редиректов) с учетом времени
                if navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted {
                    resetRedirectCounterSafely()
                    print("🔄 Reset redirect counter - new user navigation")
                    
                    // Сохраняем информацию о том, что пользователь перешел на другую страницу
                    if let currentURL = webView.url?.absoluteString, currentURL != url.absoluteString {
                        print("👤 User manually navigated from \(currentURL) to \(url.absoluteString)")
                        // Обновляем последний URL который посетил пользователь
                        UserDefaults.standard.set(url.absoluteString, forKey: "last_opened_url")
                        
                        // Уведомляем родительский компонент о пользовательской навигации
                        parent.onUserNavigation?(url.absoluteString, Date())
                    }
                }
            }
            
            // Проверяем кастомный обработчик навигации
            if let shouldAllow = parent.onNavigationAction?(url), !shouldAllow {
                decisionHandler(.cancel)
                return
            }
            
            // Разрешаем все HTTP/HTTPS навигации
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler()
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(false)
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(alert, animated: true)
            } else {
                completionHandler(false)
            }
        }
        
        // Автоматическое разрешение для Protected Media Content (iOS 15+)
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            print("📹 Auto-granting media capture permission for: \(origin.host)")
            decisionHandler(.grant)
        }
        
        // Автоматическое разрешение для других типов контента убрано - API недоступен
        
        // MARK: - UIScrollViewDelegate для полного контроля зума
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            // Возвращаем nil чтобы полностью запретить зум
            return nil
        }
        
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            // Предотвращаем начало зума
            print("🚫 Prevented zoom attempt")
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Принудительно сбрасываем зум если он каким-то образом произошел
            if scrollView.zoomScale != 1.0 {
                print("🔧 Force resetting zoom scale from \(scrollView.zoomScale) to 1.0")
                scrollView.setZoomScale(1.0, animated: false)
            }
        }
        
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Дополнительная проверка и сброс зума
            if scale != 1.0 {
                print("🔧 Force resetting zoom scale after zoom end from \(scale) to 1.0")
                scrollView.setZoomScale(1.0, animated: false)
            }
        }
        
        // Поддержка загрузки файлов - упрощенная версия без WKOpenPanelParameters
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: Any, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            print("📁 File upload request - opening file picker")
            
            // Показываем action sheet для выбора источника
            presentFilePickerOptions(webView: webView, completionHandler: completionHandler)
        }
        
        // Показываем опции выбора файлов (камера или файлы)
        private func presentFilePickerOptions(webView: WKWebView, completionHandler: @escaping ([URL]?) -> Void) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController else {
                completionHandler(nil)
                return
            }
            
            let actionSheet = UIAlertController(title: "Select File", message: nil, preferredStyle: .actionSheet)
            
            // Опция камеры
            actionSheet.addAction(UIAlertAction(title: "Camera", style: .default) { _ in
                self.presentImagePicker(webView: webView, sourceType: .camera, completionHandler: completionHandler)
            })
            
            // Опция фотогалереи
            actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                self.presentImagePicker(webView: webView, sourceType: .photoLibrary, completionHandler: completionHandler)
            })
            
            // Опция файлов
            actionSheet.addAction(UIAlertAction(title: "Files", style: .default) { _ in
                self.presentDocumentPicker(webView: webView, completionHandler: completionHandler)
            })
            
            // Отмена
            actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(nil)
            })
            
            // Настройки для iPad
            if let popover = actionSheet.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(actionSheet, animated: true)
        }
        
        // Показываем UIImagePickerController для камеры/галереи
        private func presentImagePicker(webView: WKWebView, sourceType: UIImagePickerController.SourceType, completionHandler: @escaping ([URL]?) -> Void) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController else {
                completionHandler(nil)
                return
            }
            
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = sourceType
            imagePicker.mediaTypes = ["public.image"]
            
            let coordinator = ImagePickerCoordinator(completionHandler: completionHandler)
            imagePicker.delegate = coordinator
            
            // Сохраняем coordinator чтобы он не освободился
            objc_setAssociatedObject(imagePicker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            rootViewController.present(imagePicker, animated: true)
        }
        
        // Показываем UIDocumentPickerViewController для файлов
        private func presentDocumentPicker(webView: WKWebView, completionHandler: @escaping ([URL]?) -> Void) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController else {
                completionHandler(nil)
                return
            }
            
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .image, .movie, .audio, .text, .pdf])
            documentPicker.allowsMultipleSelection = false // По умолчанию одиночный выбор
            
            let coordinator = DocumentPickerCoordinator(completionHandler: completionHandler)
            documentPicker.delegate = coordinator
            
            // Сохраняем coordinator чтобы он не освободился
            objc_setAssociatedObject(documentPicker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            rootViewController.present(documentPicker, animated: true)
        }
    }
}

// MARK: - File Upload Coordinators
class ImagePickerCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let completionHandler: ([URL]?) -> Void
    
    init(completionHandler: @escaping ([URL]?) -> Void) {
        self.completionHandler = completionHandler
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let image = info[.originalImage] as? UIImage {
            // Сохраняем изображение во временную папку
            let tempURL = saveImageToTempDirectory(image)
            if let url = tempURL {
                print("📸 Image saved to temp directory: \(url.absoluteString)")
                completionHandler([url])
            } else {
                completionHandler(nil)
            }
        } else {
            completionHandler(nil)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        completionHandler(nil)
    }
    
    private func saveImageToTempDirectory(_ image: UIImage) -> URL? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "upload_image_\(Date().timeIntervalSince1970).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ Error saving image: \(error)")
            return nil
        }
    }
}

class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let completionHandler: ([URL]?) -> Void
    
    init(completionHandler: @escaping ([URL]?) -> Void) {
        self.completionHandler = completionHandler
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("📄 Documents selected: \(urls.map { $0.lastPathComponent })")
        completionHandler(urls)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("📄 Document picker cancelled")
        completionHandler(nil)
    }
}

// MARK: - WebView Screen
struct WebViewScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var configService = ConfigService.shared
    @State private var isLoading = false // Для тестирования начинаем с false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var webViewOpacity: Double = 1.0
    @State private var pendingRedirectURL: String? // URL ожидающий применения после завершения редиректов
    @State private var redirectCompletionTimer: Timer? // Таймер для определения завершения цепочки
    @State private var userHasNavigated = false // Флаг что пользователь перешел на другую страницу
    @State private var lastUserNavigationTime: Date? // Время последней пользовательской навигации
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                if let url = appState.currentURL, !url.isEmpty {
                    WebView(
                        url: url,
                        isLoading: $isLoading,
                        onNavigationAction: { navigationURL in
                            return true
                        },
                        onLoadFinished: {
                            // WebView загружен
                        },
                        onLoadError: { error in
                            handleWebViewError(error)
                        },
                        onRedirectLimitReached: { intermediateURL in
                            handleRedirectLimitReached(intermediateURL)
                        },
                        onRedirectDetected: {
                            handleRedirectDetected()
                        },
                        onUserNavigation: { navigationURL, navigationTime in
                            // Отслеживаем пользовательскую навигацию
                            if navigationURL != url {
                                userHasNavigated = true
                                lastUserNavigationTime = navigationTime
                                print("👤 User navigation detected to: \(navigationURL)")
                            }
                        }
                    )
                    .background(Color.black) // Черный фон для предотвращения мелькания
                    .opacity(webViewOpacity)
                    .animation(.easeInOut(duration: 0.2), value: webViewOpacity)
                    .id(url) // ID по полному URL для корректной работы редиректов
                    .ignoresSafeArea(edges: isLandscape ? .top : .horizontal) // Portrait: без отступов слева/справа, Landscape: без отступа сверху
                    .ignoresSafeArea(.keyboard) // Предотвращает движение WebView при появлении клавиатуры (iOS 15.6+)
                } else {
                    LoadingOrErrorView(
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        onRetry: {
                            loadWebViewURL()
                        }
                    )
                }
                
            }
        }
        .background(Color.black) // Черный фон для Safe Area
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                // Загружаем URL если его нет или он истек
                if appState.currentURL?.isEmpty != false || appState.isURLExpired() {
                    loadWebViewURL()
                }
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                primaryButton: .default(Text("Повторить")) {
                    loadWebViewURL()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func loadWebViewURL() {
        guard !isLoading else { return }
        
        // ПРИОРИТЕТ: Если это одноразовый URL от push уведомления - НЕ перезаписываем его
        if appState.isOneTimeNotificationURL {
            print("🚫 One-time notification URL active - skipping config URL loading")
            print("📱 Current notification URL: \(appState.currentURL ?? "nil")")
            return
        }
        
        // Если есть валидный URL, не делаем ничего
        if let savedURL = appState.currentURL, !savedURL.isEmpty, !appState.isURLExpired() {
            return
        }
        
        isLoading = true
        showError = false
        
        guard let conversionData = appState.conversionData else {
            handleConfigError(.noData)
            return
        }
        
        configService.fetchConfig(
            conversionData: conversionData,
            appsflyerID: appState.appsflyerID,
            pushToken: appState.pushToken
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let url = response.url, let expires = response.expires {
                        print("✅ Got URL from server: \(url)")
                        self.isLoading = false
                        self.appState.saveURL(url, expires: expires)
                    } else {
                        self.isLoading = false
                        self.handleConfigError(.invalidResponse)
                    }
                    
                case .failure(let error):
                    self.isLoading = false
                    self.handleConfigError(error)
                }
            }
        }
    }
    
    private func handleConfigError(_ error: ConfigError) {
        switch error {
        case .noInternetConnection:
            if let savedURL = appState.currentURL, !savedURL.isEmpty {
                return
            } else {
                errorMessage = "No ethernet connection"
                showError = true
            }
            
        case .serverError(let code, _):
            if code == 404 || code >= 400 {
                appState.setAppMode(.game)
                return
            }
            fallthrough
            
        default:
            if let savedURL = appState.currentURL, !savedURL.isEmpty {
                return
            }
            
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func handleWebViewError(_ error: Error) {
        let nsError = error as NSError
        
        if nsError.code == NSURLErrorCancelled {
            return
        }
        
        errorMessage = "Error while loading: \(error.localizedDescription)"
        showError = true
    }
    
    private func handleRedirectLimitReached(_ intermediateURL: String) {
        print("🔄 ===== REDIRECT LIMIT HANDLER =====")
        print("🔗 Intermediate URL: \(intermediateURL)")
        print("⏰ Time: \(Date())")
        
        // Сохраняем промежуточный URL, но НЕ обновляем WebView сразу
        pendingRedirectURL = intermediateURL
        
        print("💾 Saved intermediate URL for later application")
        print("⏳ Waiting for redirect chain to complete...")
        
        // Устанавливаем таймер для определения завершения цепочки редиректов
        redirectCompletionTimer?.invalidate()
        redirectCompletionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.applyPendingRedirectURL()
            }
        }
        
        print("====================================")
    }
    
    private func applyPendingRedirectURL() {
        guard let pendingURL = pendingRedirectURL else { return }
        
        print("🔄 ===== APPLYING PENDING REDIRECT URL =====")
        print("🔗 Final URL: \(pendingURL)")
        print("⏰ Time: \(Date())")
        
        // Плавно скрываем WebView
        withAnimation(.easeInOut(duration: 0.2)) {
            webViewOpacity = 0.0
        }
        
        // После скрытия обновляем URL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.appState.currentURL = pendingURL
            self.pendingRedirectURL = nil
            
            print("✅ Applied final redirect URL")
            
            // Плавно показываем WebView с финальным URL
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.webViewOpacity = 1.0
                }
            }
        }
        
        print("==========================================")
    }
    
    private func handleRedirectDetected() {
        // Сбрасываем таймер завершения при каждом новом редиректе
        redirectCompletionTimer?.invalidate()
        
        // Если есть отложенный URL, продлеваем ожидание
        if pendingRedirectURL != nil {
            redirectCompletionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.applyPendingRedirectURL()
                }
            }
            print("⏳ Redirect detected - extending completion timer")
        }
    }
}

// MARK: - Loading/Error View
struct LoadingOrErrorView: View {
    let isLoading: Bool
    let errorMessage: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    
                                            Text("Loading")
                            .font(.headline)
                            .foregroundColor(.primary)
                }
            } else if !errorMessage.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("No ethernet connection")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Check your connection and try again")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        onRetry()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct GameButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(color)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Notification Permission View
struct NotificationPermissionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    
    var onPermissionGranted: () -> Void
    var onPermissionSkipped: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let horizontalPadding: CGFloat = isLandscape ? max(60, geometry.size.width * 0.15) : 20
            let maxContentWidth: CGFloat = isLandscape ? min(600, geometry.size.width * 0.7) : geometry.size.width
            
            // Определяем размер устройства для корректных отступов
            let isSmallDevice = geometry.size.height < 700 // iPhone SE, iPhone 12 mini и подобные
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let bottomPadding: CGFloat = {
                if isLandscape {
                    // В горизонтальной ориентации учитываем home indicator и размер устройства
                    if isSmallDevice {
                        return max(50, safeAreaBottom + 20) // Минимум 50, но не меньше safe area + 20
                    } else {
                        return max(40, safeAreaBottom + 15) // Для больших устройств
                    }
                } else {
                    return max(40, safeAreaBottom + 10) // Вертикальная ориентация
                }
            }()
            
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.4),
                        Color(red: 0.2, green: 0.1, blue: 0.3),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // Иконка
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.yellow, .orange]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: isLandscape ? 100 : 120, height: isLandscape ? 100 : 120)
                            
                            Image(systemName: "bell.fill")
                                .font(.system(size: isLandscape ? 40 : 50, weight: .medium))
                                .foregroundColor(.white)
                            
                            Circle()
                                .fill(Color.red)
                                .frame(width: isLandscape ? 20 : 24, height: isLandscape ? 20 : 24)
                                .offset(x: isLandscape ? 30 : 35, y: isLandscape ? -30 : -35)
                        }
                        .padding(.bottom, isLandscape ? 30 : 40)
                        
                        // Заголовок и описание
                        VStack(spacing: isLandscape ? 15 : 20) {
                            Text("Get Notifications")
                                .font(.system(size: isLandscape ? 24 : 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: isLandscape ? 8 : 12) {
                                
                                Text("Be among the first to receive gifts and bonuses")
                                    .font(isLandscape ? .callout : .body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, isLandscape ? 30 : 50)
                        
                        Spacer()
                        
                        // Кнопки
                        VStack(spacing: isLandscape ? 12 : 16) {
                            Button(action: {
                                requestNotificationPermission()
                            }) {
                                HStack {
                                    Image(systemName: "gift.fill")
                                        .font(isLandscape ? .body : .title3)
                                    
                                    Text("Enable Notifications")
                                        .font(isLandscape ? .body : .headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: isLandscape ? 48 : 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.green, .blue]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(isLandscape ? 24 : 28)
                                .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                            
                            Button(action: {
                                skipNotificationPermission()
                            }) {
                                Text("Skip")
                                    .font(isLandscape ? .callout : .body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: isLandscape ? 40 : 44)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(isLandscape ? 20 : 22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: isLandscape ? 20 : 22)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, bottomPadding)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, horizontalPadding)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.onPermissionGranted()
                } else {
                    self.appState.saveNotificationPermissionDenied()
                    self.onPermissionSkipped()
                }
            }
        }
    }
    
    private func skipNotificationPermission() {
        appState.saveNotificationPermissionDenied()
        onPermissionSkipped()
    }
}

// MARK: - No Internet Connection View
struct NoInternetConnectionView: View {
    @State private var isAnimating = false
    
    var onRetry: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let horizontalPadding: CGFloat = isLandscape ? max(60, geometry.size.width * 0.15) : 20
            let maxContentWidth: CGFloat = isLandscape ? min(600, geometry.size.width * 0.7) : geometry.size.width
            
            // Определяем размер устройства для корректных отступов
            let isSmallDevice = geometry.size.height < 700 // iPhone SE, iPhone 12 mini и подобные
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let bottomPadding: CGFloat = {
                if isLandscape {
                    // В горизонтальной ориентации учитываем home indicator и размер устройства
                    if isSmallDevice {
                        return max(50, safeAreaBottom + 20) // Минимум 50, но не меньше safe area + 20
                    } else {
                        return max(40, safeAreaBottom + 15) // Для больших устройств
                    }
                } else {
                    return max(40, safeAreaBottom + 10) // Вертикальная ориентация
                }
            }()
            
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.15, blue: 0.25),
                        Color(red: 0.15, green: 0.1, blue: 0.2),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // Иконка
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.red, .orange]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: isLandscape ? 100 : 120, height: isLandscape ? 100 : 120)
                            
                            Image(systemName: "wifi.slash")
                                .font(.system(size: isLandscape ? 40 : 50, weight: .medium))
                                .foregroundColor(.white)
                            
                            Circle()
                                .fill(Color.red)
                                .frame(width: isLandscape ? 20 : 24, height: isLandscape ? 20 : 24)
                                .offset(x: isLandscape ? 30 : 35, y: isLandscape ? -30 : -35)
                        }
                        .padding(.bottom, isLandscape ? 30 : 40)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 0.6), value: isAnimating)
                        
                        // Заголовок и описание
                        VStack(spacing: isLandscape ? 15 : 20) {
                            Text("No Internet Connection")
                                .font(.system(size: isLandscape ? 24 : 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: isLandscape ? 8 : 12) {
                                Text("Please check your internet connection")
                                    .font(isLandscape ? .callout : .body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                
                                Text("Make sure Wi-Fi or cellular data is enabled")
                                    .font(isLandscape ? .callout : .body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, isLandscape ? 30 : 50)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: isAnimating)
                        
                        Spacer()
                        
                        // Кнопка повтора
                        VStack(spacing: isLandscape ? 12 : 16) {
                            Button(action: {
                                onRetry()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                        .font(isLandscape ? .body : .title3)
                                    
                                    Text("Try Again")
                                        .font(isLandscape ? .body : .headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: isLandscape ? 48 : 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .cyan]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(isLandscape ? 24 : 28)
                                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, bottomPadding)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.8).delay(0.4), value: isAnimating)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, horizontalPadding)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @State private var isAnimating = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.1, blue: 0.2),
                        Color(red: 0.1, green: 0.05, blue: 0.15),
                        Color(red: 0.05, green: 0.05, blue: 0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Индикатор загрузки
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .cyan, .blue]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(rotationAngle))
                    }
                    
                    // Текст
                    VStack(spacing: 8) {
                        Text(DataManager.currentAppName)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                    
                    Text("Loading")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
            
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Error View
struct ErrorView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(buttonTitle) {
                action()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}
