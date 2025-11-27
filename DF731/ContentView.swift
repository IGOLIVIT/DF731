//
//  ContentView.swift
//  DF731
//
//  Main entry point for the app
//

import SwiftUI
import UserNotifications
import Combine

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var appsFlyerService = AppsFlyerService.shared
    @StateObject private var configService = ConfigService.shared
    
    @State private var showNotificationPermission = false
    @State private var showNoInternetScreen = false
    @State private var isInitializing = true
    @State private var initializationError: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            mainContent
            
            if showNotificationPermission {
                NotificationPermissionView(
                    onPermissionGranted: {
                        handleNotificationPermissionGranted()
                    },
                    onPermissionSkipped: {
                        handleNotificationPermissionSkipped()
                    }
                )
                .environmentObject(appState)
                .transition(.opacity)
                .zIndex(1)
            }
            
            if showNoInternetScreen {
                NoInternetConnectionView(
                    onRetry: {
                        handleNoInternetRetry()
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .background(Color.black) // Черный фон для всего приложения
        .preferredColorScheme(.dark) // Принудительная темная тема
        .environmentObject(appState)
        .onAppear {
            // Устанавливаем ссылку на AppState для PushNotificationService
            initializeApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handleAppDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // НЕ очищаем одноразовые URL при простом сворачивании
            // Пользователь может вернуться и должен остаться на той же странице
            print("📱 App backgrounded - keeping one-time notification URLs active")
            
            // Устанавливаем таймер для очистки URL через длительное время (30 минут)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { // 30 минут
                if UIApplication.shared.applicationState != .active {
                    print("🗑️ App inactive for 30 minutes - clearing one-time notification URLs")
                    self.appState.clearOneTimeNotificationURL()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            // Очищаем одноразовые URL только при полном закрытии приложения
            appState.clearOneTimeNotificationURL()
            print("🗑️ App terminating - cleared one-time notification URLs")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SendPushTokenToServer"))) { notification in
            if let token = notification.userInfo?["token"] as? String {
                handlePushTokenFromService(token)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SetNotificationURL"))) { notification in
            if let url = notification.userInfo?["url"] as? String {
                handleNotificationURL(url)
            }
        }
        .alert(isPresented: .constant(initializationError != nil)) {
            Alert(
                title: Text("Initialization Error"),
                message: Text(initializationError ?? ""),
                dismissButton: .default(Text("Retry")) {
                    initializeApp()
                }
            )
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        // Показываем загрузку если инициализируемся или есть ошибка инициализации
        if isInitializing {
            LoadingView()
        } else if initializationError != nil {
            ErrorView(
                title: "Connection Error",
                message: initializationError ?? "Unknown error",
                buttonTitle: "Retry"
            ) {
                initializeApp()
            }
        } else {
            // Показываем контент в зависимости от режима
            switch appState.appMode {
            case .undefined:
                ErrorView(
                    title: "Error",
                    message: "Error while getting app state",
                    buttonTitle: "Retry"
                ) {
                    initializeApp()
                }
                
            case .webView:
                WebViewScreen()
                    .environmentObject(appState)
                
            case .game:
                ZaglushkaView()
            }
        }
    }
    
    private func initializeApp() {
        print("🚀 ===== APP INITIALIZATION STARTED =====")
        print("⏰ Init Time: \(Date())")
        print("📱 Current App Mode: \(appState.appMode.rawValue)")
        print("🔄 Is First Launch: \(appState.isFirstLaunch)")
        
        // Сбрасываем состояние инициализации
        isInitializing = true
        initializationError = nil
        showNoInternetScreen = false
        
        // СРАЗУ ПРОВЕРЯЕМ ИНТЕРНЕТ ПЕРЕД ЛЮБЫМИ ОПЕРАЦИЯМИ
        print("🌐 Checking internet connection...")
        guard configService.isConnected else {
            print("❌ No internet connection detected at startup")
            isInitializing = false
            
            // При отсутствии интернета ВСЕГДА показываем кастомный экран
            // Игнорируем saved URL - пользователь должен знать что нет интернета
            print("📵 No internet - showing custom no internet screen (ignoring saved URLs)")
            showNoInternetScreen = true
            return
        }
        
        print("✅ Internet connection available")
        
        // Проверяем конфигурацию проекта и SDK
        DataManager.printFullStatus()
        
        print("🚀 Initializing AppsFlyer SDK...")
        appsFlyerService.initializeAppsFlyer()
        
        print("📊 Setting conversion data callback...")
        appsFlyerService.setConversionDataCallback { conversionData in
            print("📊 Conversion data callback triggered!")
            self.handleConversionData(conversionData)
        }
        print("==========================================")
    }
    
    private func handleConversionData(_ conversionData: [String: Any]) {
        appState.saveConversionData(conversionData)
        
        if let appsflyerID = appsFlyerService.getAppsFlyerUID() {
            appState.saveAppsFlyerID(appsflyerID)
        }
        
        // Отправляем отложенный push токен, если он есть
        PushNotificationService.shared.sendPendingTokenIfNeeded(
            conversionData: conversionData,
            appsflyerID: appState.appsflyerID
        )
        
        if configService.shouldRecheckConversion(conversionData: conversionData) {
            configService.recheckConversionData(appsflyerID: appState.appsflyerID ?? "") { result in
                switch result {
                case .success(let newData):
                    self.processConversionData(newData)
                case .failure:
                    self.processConversionData(conversionData)
                }
            }
        } else {
            processConversionData(conversionData)
        }
    }
    
    private func processConversionData(_ conversionData: [String: Any]) {
        
        // При повторном запуске проверяем срок действия URL
        if !appState.isFirstLaunch && appState.appMode != .undefined {
            // Если это одноразовый URL из уведомления - не обновляем его
            if appState.isOneTimeNotificationURL {
                print("📱 One-time notification URL active - skipping URL refresh")
                isInitializing = false
                handleAppModeSet()
                return
            }
            
            // Если URL истек - получаем новую ссылку
            if appState.isURLExpired() {
                print("🔄 URL expired - fetching new link")
                // Продолжаем выполнение для получения новой ссылки - показываем загрузку
            } else {
                // Используем последнюю открытую пользователем ссылку если expires еще валиден
                if let lastURL = UserDefaults.standard.string(forKey: "last_opened_url"), !lastURL.isEmpty {
                    print("✅ Using last opened URL by user: \(lastURL)")
                    appState.currentURL = lastURL
                } else {
                    print("✅ Using existing saved URL")
                }
                isInitializing = false
                handleAppModeSet()
                return
            }
        }
        
        // ПРИОРИТЕТ: Проверяем есть ли активный одноразовый URL от push уведомления
        if appState.isOneTimeNotificationURL {
            print("🚫 One-time notification URL active - skipping config request")
            print("📱 Using notification URL: \(appState.currentURL ?? "nil")")
            isInitializing = false
            appState.setAppMode(.webView)
            
            // Проверяем нужно ли показать экран уведомлений
            if appState.shouldShowNotificationPermission() {
                showNotificationPermission = true
                // Показываем запрос на отслеживание одновременно с экраном уведомлений
                requestTrackingPermissionForWebView {
                    print("🔐 Tracking permission handled alongside notification screen")
                }
            } else {
                requestTrackingPermissionForWebView {
                    // После запроса на отслеживание ничего дополнительного не делаем
                }
            }
            return
        }
        
        // Отправляем запрос конфига только если нет одноразового URL
        // (проверка интернета уже выполнена в initializeApp)
        sendConfigRequest(conversionData: conversionData)
    }
    
    
    private func sendConfigRequest(conversionData: [String: Any]) {
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
                        self.isInitializing = false
                        
                        // ПРИОРИТЕТ: НЕ перезаписываем одноразовый URL от push уведомления
                        if self.appState.isOneTimeNotificationURL {
                            print("🚫 One-time notification URL active - NOT overriding with config URL")
                            print("📱 Keeping notification URL: \(self.appState.currentURL ?? "nil")")
                            print("📝 Config URL ignored: \(url)")
                        } else {
                            print("💾 Saving config URL: \(url)")
                            self.appState.saveURL(url, expires: expires)
                        }
                        
                        // Устанавливаем режим webView сразу, чтобы избежать экрана ошибки
                        self.appState.setAppMode(.webView)
                        
                        // Сначала проверяем нужно ли показать экран уведомлений
                        if self.appState.shouldShowNotificationPermission() {
                            self.showNotificationPermission = true
                            // Показываем запрос на отслеживание одновременно с экраном уведомлений
                            self.requestTrackingPermissionForWebView {
                                print("🔐 Tracking permission handled alongside notification screen")
                            }
                        } else {
                            // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
                            self.requestTrackingPermissionForWebView {
                                // После запроса на отслеживание ничего дополнительного не делаем
                            }
                        }
                    } else {
                        self.isInitializing = false
                        self.handleConfigError(.invalidResponse)
                    }
                    
                case .failure(let error):
                    self.isInitializing = false
                    self.handleConfigError(error)
                }
            }
        }
    }
    
    private func handleConfigError(_ error: ConfigError) {
        switch error {
        case .serverError(let code, _) where code == 404 || code >= 400:
            // Проверяем сначала последнюю открытую ссылку, потом сохраненную
            if let lastURL = UserDefaults.standard.string(forKey: "last_opened_url"), !lastURL.isEmpty {
                print("🔄 Server error \(code), but using last opened URL: \(lastURL)")
                appState.currentURL = lastURL
                appState.setAppMode(.webView)
                
                // Сначала проверяем нужно ли показать экран уведомлений
                if appState.shouldShowNotificationPermission() {
                    showNotificationPermission = true
                    // Показываем запрос на отслеживание одновременно с экраном уведомлений
                    requestTrackingPermissionForWebView {
                        print("🔐 Tracking permission handled alongside notification screen")
                    }
                } else {
                    // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
                    requestTrackingPermissionForWebView {
                        // После запроса на отслеживание ничего дополнительного не делаем
                    }
                }
            } else if let savedURL = appState.currentURL, !savedURL.isEmpty {
                print("🔄 Server error \(code), but using saved URL: \(savedURL)")
                appState.setAppMode(.webView)
                
                // Сначала проверяем нужно ли показать экран уведомлений
                if appState.shouldShowNotificationPermission() {
                    showNotificationPermission = true
                    // Показываем запрос на отслеживание одновременно с экраном уведомлений
                    requestTrackingPermissionForWebView {
                        print("🔐 Tracking permission handled alongside notification screen")
                    }
                } else {
                    // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
                    requestTrackingPermissionForWebView {
                        // После запроса на отслеживание ничего дополнительного не делаем
                    }
                }
            } else {
                print("🎮 Server error \(code) and no saved URL - switching to game mode")
                appState.setAppMode(.game)
                handleAppModeSet()
            }
            
        case .noInternetConnection:
            handleNoInternetConnection()
            
        default:
            // Проверяем сначала последнюю открытую ссылку, потом сохраненную
            if let lastURL = UserDefaults.standard.string(forKey: "last_opened_url"), !lastURL.isEmpty {
                print("🔄 Config error, but using last opened URL: \(lastURL)")
                appState.currentURL = lastURL
                appState.setAppMode(.webView)
                
                // Сначала проверяем нужно ли показать экран уведомлений
                if appState.shouldShowNotificationPermission() {
                    showNotificationPermission = true
                    // Показываем запрос на отслеживание одновременно с экраном уведомлений
                    requestTrackingPermissionForWebView {
                        print("🔐 Tracking permission handled alongside notification screen")
                    }
                } else {
                    // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
                    requestTrackingPermissionForWebView {
                        // После запроса на отслеживание ничего дополнительного не делаем
                    }
                }
            } else if let savedURL = appState.currentURL, !savedURL.isEmpty {
                print("🔄 Config error, but using saved URL: \(savedURL)")
                appState.setAppMode(.webView)
                
                // Сначала проверяем нужно ли показать экран уведомлений
                if appState.shouldShowNotificationPermission() {
                    showNotificationPermission = true
                    // Показываем запрос на отслеживание одновременно с экраном уведомлений
                    requestTrackingPermissionForWebView {
                        print("🔐 Tracking permission handled alongside notification screen")
                    }
                } else {
                    // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
                    requestTrackingPermissionForWebView {
                        // После запроса на отслеживание ничего дополнительного не делаем
                    }
                }
            } else {
                print("❌ Config error and no saved URL - showing error")
                initializationError = "Configuration error: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleNoInternetConnection() {
        print("🌐 ===== HANDLING NO INTERNET CONNECTION =====")
        
        // Сначала проверяем отключены ли все сетевые интерфейсы
        let allInterfacesDisabled = configService.areAllNetworkInterfacesDisabled()
        
        if allInterfacesDisabled {
            // Если Wi-Fi и мобильный интернет отключены, сразу показываем кастомный экран
            print("📵 All network interfaces disabled - showing no internet screen immediately")
            showNoInternetScreen = true
            return
        }
        
        print("📶 Network interfaces available - performing real internet check")
        
        // Выполняем реальную проверку доступа в интернет
        configService.checkRealInternetConnectivity { hasRealInternet in
            
            if hasRealInternet {
                print("✅ Real internet access confirmed - retrying initialization")
                // Есть реальный интернет, пытаемся повторно инициализировать
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    initializeApp()
                }
                return
            }
            
            print("❌ No real internet access - showing custom no internet screen")
            print("📝 Note: Saved URLs ignored when no internet connection")
            
            // При отсутствии реального интернета ВСЕГДА показываем кастомный экран
            // Игнорируем saved URL - пользователь должен видеть что нет интернета
            showNoInternetScreen = true
        }
        
        print("===============================================")
    }
    
    private func handleAppModeSet() {
        print("📱 App mode set to: \(appState.appMode.rawValue)")
        
        // Проверяем нужно ли показать экран уведомлений
        if appState.shouldShowNotificationPermission() {
            print("📱 Showing notification permission screen")
            showNotificationPermission = true
            
            // Показываем запрос на отслеживание одновременно с экраном уведомлений
            print("🔐 Requesting tracking permission alongside notification screen...")
            requestTrackingPermissionForWebView {
                print("🔐 Tracking permission handled while notification screen is shown")
            }
        } else {
            // Если экран уведомлений не нужен, сразу запрашиваем разрешение на отслеживание
            print("📱 Skipping notification screen - requesting tracking permission")
            requestTrackingPermissionForWebView {
                // После запроса на отслеживание ничего дополнительного не делаем
            }
        }
    }
    
    private func handleNotificationPermissionGranted() {
        showNotificationPermission = false
        print("📱 ===== USER GRANTED NOTIFICATION PERMISSION =====")
        
        // При согласии НЕ сохраняем отказ - пользователь может еще отказаться в системном диалоге
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        print("✅ User agreed to notifications")
        
        // Если у нас уже есть push токен, отправляем его на сервер
        if let pushToken = appState.pushToken, !pushToken.isEmpty,
           let conversionData = appState.conversionData {
            print("✅ Push token available - sending to server immediately")
            sendPushTokenToServer(conversionData: conversionData, pushToken: pushToken)
        } else {
            print("⏳ Push token not available yet - will send when Firebase provides it")
            print("   Current token: \(appState.pushToken ?? "nil")")
            print("   Conversion data available: \(appState.conversionData != nil)")
        }
        
        // Запрос на отслеживание уже был показан при появлении экрана уведомлений
        print("📱 Notification permission handled - tracking permission already requested")
        
        print("================================================")
    }
    
    private func handleNotificationPermissionSkipped() {
        showNotificationPermission = false
        // При отказе на кастомном экране - сохраняем дату для повтора через 3 дня
        appState.saveNotificationPermissionDenied()
        
        // Запрос на отслеживание уже был показан при появлении экрана уведомлений
        print("📱 Notification permission skipped - tracking permission already requested")
    }
    
    private func sendPushTokenToServer(conversionData: [String: Any], pushToken: String) {
        print("📲 ===== SENDING PUSH TOKEN TO SERVER =====")
        print("🔗 Token: \(pushToken)")
        print("📊 Conversion data keys: \(conversionData.keys.sorted())")
        print("🆔 AppsFlyer ID: \(appState.appsflyerID ?? "nil")")
        
        configService.fetchConfig(
            conversionData: conversionData,
            appsflyerID: appState.appsflyerID,
            pushToken: pushToken
        ) { result in
            switch result {
            case .success:
                print("✅ Push token successfully sent to server")
            case .failure(let error):
                print("❌ Failed to send push token: \(error.localizedDescription)")
            }
            print("==========================================")
        }
    }
    
    private func handleAppDidBecomeActive() {
        // Не делаем автоматического обновления URL при возвращении в приложение
        // Пользователь сам может обновить если нужно
        print("📱 App became active - no automatic URL refresh")
    }
    
    private func refreshWebViewURL() {
        guard let conversionData = appState.conversionData else { return }
        
        configService.fetchConfig(
            conversionData: conversionData,
            appsflyerID: appState.appsflyerID,
            pushToken: appState.pushToken
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let url = response.url, let expires = response.expires {
                        print("✅ Got URL from refresh: \(url)")
                        self.appState.saveURL(url, expires: expires)
                    }
                case .failure:
                    break
                }
            }
        }
    }
    
    private func requestTrackingPermissionForWebView(completion: @escaping () -> Void) {
        print("🔐 Requesting tracking permission for WebView mode...")
        appsFlyerService.requestTrackingPermission { granted in
            print("🔐 Tracking permission result: \(granted ? "granted" : "denied")")
            completion()
        }
    }
    
    private func handleNoInternetRetry() {
        print("🔄 ===== USER TAPPED RETRY ON NO INTERNET SCREEN =====")
        
        // Сначала проверяем текущее состояние сетевых интерфейсов
        let allInterfacesDisabled = configService.areAllNetworkInterfacesDisabled()
        
        if allInterfacesDisabled {
            print("📵 Network interfaces still disabled - keeping no internet screen")
            return
        }
        
        print("📶 Network interfaces available - performing real internet check")
        
        // Выполняем реальную проверку интернета перед повтором
        configService.checkRealInternetConnectivity { hasRealInternet in
            if hasRealInternet {
                print("✅ Real internet confirmed - proceeding with retry")
                showNoInternetScreen = false
                
                // Сбрасываем состояние и пытаемся инициализировать приложение заново
                isInitializing = true
                initializationError = nil
                
                // Небольшая задержка для плавности анимации
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    initializeApp()
                }
            } else {
                print("❌ No real internet access - keeping no internet screen")
                print("📝 Note: Not using saved URLs when no internet connection")
                // Остаемся на экране отсутствия интернета, игнорируем saved URL
            }
        }
        
        print("========================================================")
    }
    
    private func handleNotificationURL(_ url: String) {
        print("📲 ===== HANDLING NOTIFICATION URL IN CONTENTVIEW =====")
        print("⏰ Handle Time: \(Date())")
        print("🔗 Notification URL: \(url)")
        print("📱 Current App Mode: \(appState.appMode.rawValue)")
        
        // Если уже есть активный одноразовый URL, очищаем его перед установкой нового
        if appState.isOneTimeNotificationURL {
            print("🗑️ Clearing previous one-time notification URL")
            appState.clearOneTimeNotificationURL()
        }
        
        // ВАЖНО: Устанавливаем одноразовый URL (НЕ сохраняется в UserDefaults)
        appState.setOneTimeNotificationURL(url)
        print("💾 One-time notification URL set in existing AppState")
        
        // Переключаемся в режим WebView если нужно
        if appState.appMode != .webView {
            print("🔄 Switching to WebView mode")
            appState.setAppMode(.webView)
        } else {
            print("✅ Already in WebView mode - URL will be loaded")
        }
        
        // Скрываем экраны уведомлений и ошибок если они показаны
        showNotificationPermission = false
        showNoInternetScreen = false
        isInitializing = false
        initializationError = nil
        
        print("🔄 UI state reset for notification URL")
        print("======================================================")
    }
    
    private func handlePushTokenFromService(_ token: String) {
        print("📱 ===== PUSH TOKEN FROM SERVICE =====")
        print("🔗 Token: \(token)")
        print("📊 Checking conversion data availability...")
        
        guard let conversionData = appState.conversionData else {
            print("⚠️ Conversion data not available yet - token will be sent later")
            return
        }
        
        print("✅ Conversion data available - sending token to server")
        
        configService.fetchConfig(
            conversionData: conversionData,
            appsflyerID: appState.appsflyerID,
            pushToken: token
        ) { result in
            switch result {
            case .success:
                print("✅ Push token successfully sent to server via ContentView")
            case .failure(let error):
                print("❌ Failed to send push token via ContentView: \(error.localizedDescription)")
            }
        }
        
        print("====================================")
    }
}

#Preview {
    ContentView()
}
