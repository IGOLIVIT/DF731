//
//  AppCore.swift
//  DF731
//
//  Created by IGOR on 18/11/2025.
//

import Foundation
import SwiftUI
import UIKit
import Network
import UserNotifications
import WebKit
import AppTrackingTransparency
import AppsFlyerLib // Раскомментируйте после добавления AppsFlyer SDK
import FirebaseCore // Раскомментируйте после добавления Firebase SDK
import FirebaseMessaging // Раскомментируйте после добавления Firebase SDK
import Combine

// MARK: - App Modes
enum AppMode: String, Codable {
    case webView = "webview"
    case game = "game"
    case undefined = "undefined"
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var appMode: AppMode = .undefined
    @Published var isFirstLaunch: Bool = true
    @Published var currentURL: String?
    @Published var urlExpires: TimeInterval?
    @Published var hasInternetConnection: Bool = true
    @Published var showNotificationPermissionScreen: Bool = false
    @Published var notificationPermissionDeniedDate: Date?
    @Published var isLoading: Bool = false
    @Published var pushToken: String?
    @Published var appsflyerID: String?
    @Published var conversionData: [String: Any]?
    @Published var isOneTimeNotificationURL: Bool = false // Флаг одноразового URL из уведомления
    
    private let userDefaults = UserDefaults.standard
    
    // Keys для UserDefaults
    private let appModeKey = "app_mode"
    private let isFirstLaunchKey = "is_first_launch"
    private let currentURLKey = "current_url"
    private let urlExpiresKey = "url_expires"
    private let notificationDeniedDateKey = "notification_denied_date"
    private let pushTokenKey = "push_token"
    private let appsflyerIDKey = "appsflyer_id"
    
    init() {
        loadState()
    }
    
    func loadState() {
        if let modeString = userDefaults.string(forKey: appModeKey),
           let mode = AppMode(rawValue: modeString) {
            self.appMode = mode
        }
        
        self.isFirstLaunch = userDefaults.bool(forKey: isFirstLaunchKey)
        self.currentURL = userDefaults.string(forKey: currentURLKey)
        self.urlExpires = userDefaults.object(forKey: urlExpiresKey) as? TimeInterval
        self.pushToken = userDefaults.string(forKey: pushTokenKey)
        self.appsflyerID = userDefaults.string(forKey: appsflyerIDKey)
        
        
        if let deniedDate = userDefaults.object(forKey: notificationDeniedDateKey) as? Date {
            self.notificationPermissionDeniedDate = deniedDate
        }
        
        if userDefaults.object(forKey: isFirstLaunchKey) == nil {
            self.isFirstLaunch = true
            saveState()
        }
    }
    
    func saveState() {
        userDefaults.set(appMode.rawValue, forKey: appModeKey)
        userDefaults.set(isFirstLaunch, forKey: isFirstLaunchKey)
        userDefaults.set(currentURL, forKey: currentURLKey)
        userDefaults.set(urlExpires, forKey: urlExpiresKey)
        userDefaults.set(pushToken, forKey: pushTokenKey)
        userDefaults.set(appsflyerID, forKey: appsflyerIDKey)
        
        if let deniedDate = notificationPermissionDeniedDate {
            userDefaults.set(deniedDate, forKey: notificationDeniedDateKey)
        }
    }
    
    func setAppMode(_ mode: AppMode) {
        self.appMode = mode
        self.isFirstLaunch = false
        saveState()
    }
    
    func saveURL(_ url: String, expires: TimeInterval) {
        self.currentURL = url
        self.urlExpires = expires
        self.isOneTimeNotificationURL = false // Обычный URL - не одноразовый
        saveState()
        print("✅ URL saved: \(url)")
    }
    
    func setOneTimeNotificationURL(_ url: String) {
        self.currentURL = url
        self.urlExpires = nil // Одноразовые URL не имеют срока истечения
        self.isOneTimeNotificationURL = true
        // НЕ вызываем saveState() - не сохраняем в UserDefaults!
        print("📱 One-time notification URL set (not persisted): \(url)")
    }
    
    func clearOneTimeNotificationURL() {
        if isOneTimeNotificationURL {
            print("🗑️ Clearing one-time notification URL")
            
            // Проверяем последний URL который открыл пользователь
            let lastUserURL = UserDefaults.standard.string(forKey: "last_opened_url")
            let savedConfigURL = userDefaults.string(forKey: currentURLKey)
            
            print("🔍 URL options for restoration:")
            print("   Current notification URL: \(self.currentURL ?? "nil")")
            print("   Last user-opened URL: \(lastUserURL ?? "nil")")
            print("   Saved config URL: \(savedConfigURL ?? "nil")")
            
            // Приоритет: используем последний URL пользователя, если он есть и отличается от config
            if let lastUserURL = lastUserURL,
               !lastUserURL.isEmpty,
               lastUserURL != savedConfigURL {
                print("✅ Restoring last user-opened URL instead of config URL")
                self.currentURL = lastUserURL
                self.urlExpires = nil // Пользовательские URL не имеют срока истечения
            } else {
                print("🔄 Restoring saved config URL from UserDefaults")
                // Восстанавливаем сохраненный config URL из UserDefaults
                self.currentURL = savedConfigURL
                self.urlExpires = userDefaults.object(forKey: urlExpiresKey) as? TimeInterval
            }
            
            self.isOneTimeNotificationURL = false
        }
    }
    
    func isURLExpired() -> Bool {
        guard let expires = urlExpires else { return true }
        return Date().timeIntervalSince1970 > expires
    }
    
    func savePushToken(_ token: String) {
        self.pushToken = token
        saveState()
        print("📱 Push token saved")
    }
    
    func saveAppsFlyerID(_ id: String) {
        self.appsflyerID = id
        saveState()
    }
    
    func saveConversionData(_ data: [String: Any]) {
        self.conversionData = data
    }
    
    func shouldShowNotificationPermission() -> Bool {
        guard appMode == .webView else { return false }
        
        // Проверяем системные разрешения синхронно
        var systemPermissionStatus: UNAuthorizationStatus = .notDetermined
        let semaphore = DispatchSemaphore(value: 0)
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            systemPermissionStatus = settings.authorizationStatus
            semaphore.signal()
        }
        semaphore.wait()
        
        print("📱 System notification permission status: \(systemPermissionStatus.rawValue)")
        
        // Если системное разрешение уже получено - не показываем кастомный экран
        if systemPermissionStatus == .authorized {
            print("✅ System permission already granted - skipping custom screen")
            return false
        }
        
        // Если системное разрешение окончательно отклонено - не показываем кастомный экран
        if systemPermissionStatus == .denied {
            print("❌ System permission permanently denied - skipping custom screen")
            return false
        }
        
        // Проверяем кастомный отказ (3 дня)
        if let deniedDate = notificationPermissionDeniedDate {
            let retryDate = Date().addingTimeInterval(-DataManager.notificationRetryInterval)
            if deniedDate > retryDate {
                print("⏰ Custom denial still active - \(Int(-retryDate.timeIntervalSinceNow / 86400)) days remaining")
                return false
            } else {
                print("⏰ Custom denial expired - can show screen again")
            }
        }
        
        print("✅ Should show custom notification permission screen")
        return true
    }
    
    func saveNotificationPermissionDenied() {
        self.notificationPermissionDeniedDate = Date()
        saveState()
        print("📅 Notification permission denied - next attempt in 3 days")
    }
    
}

// MARK: - Config Models
struct ConfigRequest: Encodable {
    let conversionData: [String: Any]
    let af_id: String?
    let bundle_id: String
    let os: String
    let store_id: String
    let locale: String
    let push_token: String?
    let firebase_project_id: String?
    
    init(conversionData: [String: Any], af_id: String?, bundle_id: String, store_id: String, locale: String, push_token: String?, firebase_project_id: String?) {
        self.conversionData = conversionData
        self.af_id = af_id
        self.bundle_id = bundle_id
        self.os = "iOS"
        self.store_id = store_id
        self.locale = locale
        self.push_token = push_token
        self.firebase_project_id = firebase_project_id
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        
        for (key, value) in conversionData {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            try container.encodeAny(value, forKey: codingKey)
        }
        
        if let af_id = af_id {
            try container.encode(af_id, forKey: DynamicCodingKeys(stringValue: "af_id")!)
        }
        try container.encode(bundle_id, forKey: DynamicCodingKeys(stringValue: "bundle_id")!)
        try container.encode(os, forKey: DynamicCodingKeys(stringValue: "os")!)
        try container.encode(store_id, forKey: DynamicCodingKeys(stringValue: "store_id")!)
        try container.encode(locale, forKey: DynamicCodingKeys(stringValue: "locale")!)
        
        if let push_token = push_token {
            try container.encode(push_token, forKey: DynamicCodingKeys(stringValue: "push_token")!)
        }
        
        if let firebase_project_id = firebase_project_id {
            try container.encode(firebase_project_id, forKey: DynamicCodingKeys(stringValue: "firebase_project_id")!)
        }
    }
}

struct ConfigResponse: Codable {
    let ok: Bool
    let url: String?
    let expires: TimeInterval?
    let message: String?
}


struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }
}

extension KeyedEncodingContainer where Key == DynamicCodingKeys {
    mutating func encodeAny(_ value: Any, forKey key: DynamicCodingKeys) throws {
        switch value {
        case let string as String:
            try encode(string, forKey: key)
        case let int as Int:
            try encode(int, forKey: key)
        case let double as Double:
            try encode(double, forKey: key)
        case let bool as Bool:
            try encode(bool, forKey: key)
        case is NSNull:
            try encodeNil(forKey: key)
        default:
            try encode(String(describing: value), forKey: key)
        }
    }
}

struct DeviceInfo {
    let bundleId: String
    let storeId: String
    let locale: String
    let osVersion: String
    let deviceModel: String
    
    static func current() -> DeviceInfo {
        let bundleId = Bundle.main.bundleIdentifier ?? "BundleID"
        
        // Согласно документации, для iOS Store ID должен быть с префиксом "id"
        let storeId = DataManager.appleAppID.isEmpty ? bundleId : DataManager.appleAppID
        
        let locale = Locale.current.languageCode ?? "en"
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        
        // Логирование убрано для уменьшения дублирования в консоли
        
        return DeviceInfo(
            bundleId: bundleId,
            storeId: storeId,
            locale: locale,
            osVersion: osVersion,
            deviceModel: deviceModel
        )
    }
}

// MARK: - Config Service
class ConfigService: ObservableObject {
    static let shared = ConfigService()
    
    private let configEndpoint = DataManager.configEndpoint
    
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var currentNetworkPath: NWPath?
    
    private init() {
        startNetworkMonitoring()
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.currentNetworkPath = path
                self?.logNetworkStatus(path)
            }
        }
        networkMonitor.start(queue: queue)
    }
    
    private func logNetworkStatus(_ path: NWPath) {
        print("🌐 ===== NETWORK STATUS =====")
        print("📶 Status: \(path.status)")
        print("💰 Is Expensive: \(path.isExpensive)")
        print("🔋 Is Constrained: \(path.isConstrained)")
        
        if path.usesInterfaceType(.wifi) {
            print("📡 Using Wi-Fi")
        }
        if path.usesInterfaceType(.cellular) {
            print("📱 Using Cellular")
        }
        if path.usesInterfaceType(.wiredEthernet) {
            print("🔌 Using Ethernet")
        }
        print("============================")
    }
    
    // Проверяем отключены ли все сетевые интерфейсы
    func areAllNetworkInterfacesDisabled() -> Bool {
        guard let path = currentNetworkPath else {
            print("⚠️ No network path available, assuming interfaces disabled")
            return true
        }
        
        let hasWiFi = path.usesInterfaceType(.wifi)
        let hasCellular = path.usesInterfaceType(.cellular)
        let hasEthernet = path.usesInterfaceType(.wiredEthernet)
        
        let allDisabled = !hasWiFi && !hasCellular && !hasEthernet
        
        print("🔍 Network interfaces check:")
        print("   Wi-Fi: \(hasWiFi ? "✅" : "❌")")
        print("   Cellular: \(hasCellular ? "✅" : "❌")")
        print("   Ethernet: \(hasEthernet ? "✅" : "❌")")
        print("   All disabled: \(allDisabled ? "✅" : "❌")")
        
        return allDisabled
    }
    
    // MARK: - Реальная проверка доступа в интернет
    
    /// Комплексная проверка реального доступа в интернет
    func checkRealInternetConnectivity(completion: @escaping (Bool) -> Void) {
        print("🌐 ===== STARTING REAL INTERNET CONNECTIVITY CHECK =====")
        
        // Сначала проверяем базовое соединение
        guard isConnected else {
            print("❌ Basic network check failed")
            completion(false)
            return
        }
        
        // Проверяем несколько методов параллельно
        let group = DispatchGroup()
        var results: [String: Bool] = [:]
        
        // Метод 1: Google DNS API
        group.enter()
        checkGoogleDNS { success in
            results["google_dns_api"] = success
            group.leave()
        }
        
        // Метод 2: HTTP запрос к Apple
        group.enter()
        checkAppleConnectivity { success in
            results["apple"] = success
            group.leave()
        }
        
        // Метод 3: HTTP запрос к Google
        group.enter()
        checkGoogleConnectivity { success in
            results["google"] = success
            group.leave()
        }
        
        // Метод 4: Cloudflare DNS API
        group.enter()
        checkCloudflareDNS { success in
            results["cloudflare_dns_api"] = success
            group.leave()
        }
        
        // Ждем завершения всех проверок
        group.notify(queue: .main) {
            let successCount = results.values.filter { $0 }.count
            let totalChecks = results.count
            let hasInternet = successCount >= 2 // Требуем минимум 2 успешные проверки
            
            print("🔍 Internet connectivity results:")
            for (method, success) in results {
                print("   \(method): \(success ? "✅" : "❌")")
            }
            print("📊 Success rate: \(successCount)/\(totalChecks)")
            print("🌐 Has real internet: \(hasInternet ? "✅" : "❌")")
            print("=====================================================")
            
            completion(hasInternet)
        }
    }
    
    /// Проверка доступности Google DNS через HTTP запрос к Google
    private func checkGoogleDNS(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://dns.google/resolve?name=google.com&type=A") else {
            completion(false)
            return
        }
        
        performHTTPCheck(url: url, timeout: 5.0) { success in
            print("🔍 Google DNS API: \(success ? "✅" : "❌")")
            completion(success)
        }
    }
    
    /// Проверка доступности Cloudflare DNS через HTTP запрос
    private func checkCloudflareDNS(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://1.1.1.1/dns-query?name=cloudflare.com&type=A") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let success = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
                print("🔍 Cloudflare DNS API: \(success ? "✅" : "❌")")
                completion(success)
            }
        }
        
        task.resume()
    }
    
    /// Проверка HTTP соединения с Apple
    private func checkAppleConnectivity(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
            completion(false)
            return
        }
        
        performHTTPCheck(url: url, expectedContent: "Success", timeout: 5.0) { success in
            print("🔍 Apple connectivity: \(success ? "✅" : "❌")")
            completion(success)
        }
    }
    
    /// Проверка HTTP соединения с Google
    private func checkGoogleConnectivity(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://www.google.com/generate_204") else {
            completion(false)
            return
        }
        
        performHTTPCheck(url: url, expectedStatusCode: 204, timeout: 5.0) { success in
            print("🔍 Google connectivity: \(success ? "✅" : "❌")")
            completion(success)
        }
    }
    
    /// Выполняет HTTP проверку
    private func performHTTPCheck(url: URL, expectedContent: String? = nil, expectedStatusCode: Int? = nil, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ HTTP check failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response")
                    completion(false)
                    return
                }
                
                // Проверяем статус код
                if let expectedCode = expectedStatusCode {
                    completion(httpResponse.statusCode == expectedCode)
                    return
                }
                
                // Проверяем содержимое
                if let expectedText = expectedContent, let data = data {
                    let content = String(data: data, encoding: .utf8) ?? ""
                    completion(content.contains(expectedText))
                    return
                }
                
                // По умолчанию проверяем что статус в диапазоне 200-299
                completion(200...299 ~= httpResponse.statusCode)
            }
        }
        
        task.resume()
    }
    
    func fetchConfig(conversionData: [String: Any], appsflyerID: String?, pushToken: String?, completion: @escaping (Result<ConfigResponse, ConfigError>) -> Void) {
        guard isConnected else {
            completion(.failure(.noInternetConnection))
            return
        }
        
        let deviceInfo = DeviceInfo.current()
        let configRequest = ConfigRequest(
            conversionData: conversionData,
            af_id: appsflyerID,
            bundle_id: deviceInfo.bundleId,
            store_id: deviceInfo.storeId,
            locale: deviceInfo.locale,
            push_token: pushToken,
            firebase_project_id: DataManager.firebaseProjectID.isEmpty ? nil : DataManager.firebaseProjectID
        )
        
        sendConfigRequest(configRequest, completion: completion)
    }
    
    private func sendConfigRequest(_ request: ConfigRequest, completion: @escaping (Result<ConfigResponse, ConfigError>) -> Void) {
        guard let url = URL(string: configEndpoint) else {
            print("❌ Invalid URL: \(configEndpoint)")
            completion(.failure(.invalidURL))
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(DataManager.createCustomUserAgent(), forHTTPHeaderField: "User-Agent")
        
        // ДЕТАЛЬНОЕ ЛОГИРОВАНИЕ ЗАПРОСА
        print("🌐 ===== CONFIG SERVER REQUEST DEBUG =====")
        print("📍 Endpoint URL: \(configEndpoint)")
        print("📍 Full URL: \(url.absoluteString)")
        print("🔧 HTTP Method: \(urlRequest.httpMethod ?? "N/A")")
        print("⏰ Request Time: \(Date())")
        print("📱 Device Info:")
        let deviceInfo = DeviceInfo.current()
        print("   Bundle ID: \(deviceInfo.bundleId)")
        print("   Store ID: \(deviceInfo.storeId)")
        print("   Locale: \(deviceInfo.locale)")
        print("   OS Version: \(deviceInfo.osVersion)")
        print("   Device Model: \(deviceInfo.deviceModel)")
        print("📋 Request Headers:")
        if let headers = urlRequest.allHTTPHeaderFields {
            for (key, value) in headers {
                print("   \(key): \(value)")
            }
        }
        
        do {
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📦 Request Body JSON:")
                print("\(jsonString)")
                print("📏 Request Body Size: \(jsonData.count) bytes")
            }
        } catch {
            print("❌ JSON Encoding Error: \(error)")
            completion(.failure(.encodingError(error)))
            return
        }
        print("==========================================")
        
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            DispatchQueue.main.async {
                // ДЕТАЛЬНОЕ ЛОГИРОВАНИЕ ОТВЕТА
                print("📥 ===== CONFIG SERVER RESPONSE DEBUG =====")
                print("⏰ Response Time: \(Date())")
                
                if let error = error {
                    print("❌ Network Error: \(error.localizedDescription)")
                    print("❌ Error Code: \((error as NSError).code)")
                    print("❌ Error Domain: \((error as NSError).domain)")
                    print("===========================================")
                    completion(.failure(.networkError(error)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP Response")
                    print("===========================================")
                    completion(.failure(.invalidResponse))
                    return
                }
                
                print("📊 HTTP Status Code: \(httpResponse.statusCode)")
                print("📄 Response Headers:")
                for (key, value) in httpResponse.allHeaderFields {
                    print("   \(key): \(value)")
                }
                
                guard let data = data else {
                    print("❌ No Data in Response")
                    print("===========================================")
                    completion(.failure(.noData))
                    return
                }
                
                print("📏 Response Size: \(data.count) bytes")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📝 Response Body:")
                    print("\(responseString)")
                } else {
                    print("❌ Unable to decode response as UTF-8 string")
                }
                
                do {
                    let configResponse = try JSONDecoder().decode(ConfigResponse.self, from: data)
                    print("✅ JSON Decoded Successfully:")
                    print("   ok: \(configResponse.ok)")
                    print("   url: \(configResponse.url ?? "nil")")
                    print("   expires: \(configResponse.expires ?? 0)")
                    print("   message: \(configResponse.message ?? "nil")")
                    
                    if httpResponse.statusCode == 200 && configResponse.ok {
                        print("✅ Config Request Successful!")
                        print("===========================================")
                        completion(.success(configResponse))
                    } else {
                        print("❌ Server Error - Status: \(httpResponse.statusCode), Message: \(configResponse.message ?? "No message")")
                        print("===========================================")
                        completion(.failure(.serverError(httpResponse.statusCode, configResponse.message)))
                    }
                } catch {
                    print("❌ JSON Decoding Error: \(error)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("   Missing key: \(key.stringValue)")
                            print("   Context: \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            print("   Type mismatch: expected \(type)")
                            print("   Context: \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            print("   Value not found: \(type)")
                            print("   Context: \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            print("   Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            print("   Unknown decoding error")
                        }
                    }
                    print("===========================================")
                    completion(.failure(.decodingError(error)))
                }
            }
        }.resume()
    }
    
    func shouldRecheckConversion(conversionData: [String: Any]) -> Bool {
        if let afStatus = conversionData["af_status"] as? String {
            return afStatus == "Organic"
        }
        return false
    }
    
    func recheckConversionData(appsflyerID: String, completion: @escaping (Result<[String: Any], ConfigError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + DataManager.conversionRecheckDelay) {
            completion(.failure(.appsflyerAPINotImplemented))
        }
    }
    
    
    
    deinit {
        networkMonitor.cancel()
    }
}

enum ConfigError: Error, LocalizedError {
    case noInternetConnection
    case invalidURL
    case encodingError(Error)
    case networkError(Error)
    case invalidResponse
    case noData
    case decodingError(Error)
    case serverError(Int, String?)
    case appsflyerAPINotImplemented
    
    var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            return "Нет интернет-соединения"
        case .invalidURL:
            return "Некорректный URL"
        case .encodingError(let error):
            return "Ошибка кодирования: \(error.localizedDescription)"
        case .networkError(let error):
            return "Сетевая ошибка: \(error.localizedDescription)"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .noData:
            return "Нет данных в ответе"
        case .decodingError(let error):
            return "Ошибка декодирования: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Ошибка сервера (\(code)): \(message ?? "Неизвестная ошибка")"
        case .appsflyerAPINotImplemented:
            return "AppsFlyer API не реализован"
        }
    }
}

// MARK: - AppsFlyer Service
class AppsFlyerService: NSObject, ObservableObject {
    static let shared = AppsFlyerService()
    
    private let appsFlyerDevKey = DataManager.appsFlyerDevKey
    private let appleAppID = DataManager.appleAppID
    
    @Published var conversionData: [String: Any]?
    @Published var appsflyerUID: String?
    @Published var isInitialized = false
    
    private var conversionDataCallback: (([String: Any]) -> Void)?
    
    private override init() {}
    
    func initializeAppsFlyer() {
        print("🚀 ===== APPSFLYER INITIALIZATION DEBUG =====")
        print("📱 AppsFlyer Dev Key: \(DataManager.appsFlyerDevKey.prefix(8))...")
        print("📱 Apple App ID: \(DataManager.appleAppID)")
        print("⏰ Initialization Time: \(Date())")
        print("🔧 Debug Mode: false (Production)")
        
        AppsFlyerLib.shared().appsFlyerDevKey = DataManager.appsFlyerDevKey
        AppsFlyerLib.shared().appleAppID = DataManager.appleAppID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().isDebug = false // Production mode
        
        // Запуск AppsFlyer
        AppsFlyerLib.shared().start { (dictionary, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ AppsFlyer initialization error: \(error)")
                    print("❌ Error domain: \((error as NSError).domain)")
                    print("❌ Error code: \((error as NSError).code)")
                    print("=============================================")
                } else {
                    print("✅ AppsFlyer initialized successfully")
                    self.isInitialized = true
                    self.appsflyerUID = AppsFlyerLib.shared().getAppsFlyerUID()
                    print("🆔 AppsFlyer UID: \(self.appsflyerUID ?? "N/A")")
                    if let dictionary = dictionary {
                        print("📊 Initialization Data: \(dictionary)")
                    }
                    print("=============================================")
                }
            }
        }
    }
    

    
    func getAppsFlyerUID() -> String? {
        return appsflyerUID
    }
    
    func setConversionDataCallback(_ callback: @escaping ([String: Any]) -> Void) {
        self.conversionDataCallback = callback
        
        if let data = conversionData {
            callback(data)
        }
    }
    
    func logEvent(eventName: String, eventValues: [String: Any]?) {
        AppsFlyerLib.shared().logEvent(eventName, withValues: eventValues)
        print("AppsFlyer Event logged: \(eventName)")
    }
    
    func requestTrackingPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14.5, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized:
                        print("✅ Tracking permission granted")
                        completion(true)
                    case .denied, .restricted, .notDetermined:
                        print("❌ Tracking permission denied or restricted")
                        completion(false)
                    @unknown default:
                        print("⚠️ Unknown tracking permission status")
                        completion(false)
                    }
                }
            }
        } else {
            // iOS < 14.5 - разрешение не требуется
            completion(true)
        }
    }
}

// MARK: - AppsFlyer Delegate
extension AppsFlyerService: AppsFlyerLibDelegate {
    
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        print("📊 ===== APPSFLYER CONVERSION SUCCESS =====")
        print("⏰ Conversion Time: \(Date())")
        print("📦 Raw Conversion Info: \(conversionInfo)")
        
        if let conversionData = conversionInfo as? [String: Any] {
            print("✅ Conversion Data Parsed Successfully:")
            for (key, value) in conversionData {
                print("   \(key): \(value)")
            }
            
            // Анализ ключевых параметров
            if let afStatus = conversionData["af_status"] as? String {
                print("🎯 Attribution Status: \(afStatus)")
            }
            if let mediaSource = conversionData["media_source"] as? String {
                print("📺 Media Source: \(mediaSource)")
            }
            if let campaign = conversionData["campaign"] as? String {
                print("📢 Campaign: \(campaign)")
            }
            if let isFirstLaunch = conversionData["is_first_launch"] as? Bool {
                print("🚀 First Launch: \(isFirstLaunch)")
            }
            
            DispatchQueue.main.async {
                self.conversionData = conversionData
                self.conversionDataCallback?(conversionData)
                print("✅ Conversion data callback executed")
            }
        } else {
            print("❌ Failed to parse conversion data as [String: Any]")
        }
        print("==========================================")
    }
    
    func onConversionDataFail(_ error: Error) {
        print("❌ ===== APPSFLYER CONVERSION FAILED =====")
        print("⏰ Error Time: \(Date())")
        print("❌ Error: \(error.localizedDescription)")
        print("❌ Error Domain: \((error as NSError).domain)")
        print("❌ Error Code: \((error as NSError).code)")
        
        // При ошибке AppsFlyer используем минимальные органические данные
        let fallbackData: [String: Any] = [
            "af_status": "Organic", // Органическая установка при ошибке AppsFlyer
            "is_first_launch": true,
            "error_fallback": true
        ]
        
        print("🔄 Using fallback organic data: \(fallbackData)")
        print("⚠️ AppsFlyer fallback triggered - will show Game mode")
        
        DispatchQueue.main.async {
            self.conversionData = fallbackData
            self.conversionDataCallback?(fallbackData)
            print("✅ Fallback data callback executed")
        }
        print("==========================================")
    }
    
    func onAppOpenAttribution(_ attributionData: [AnyHashable : Any]) {
        print("🔗 ===== APPSFLYER DEEP LINK SUCCESS =====")
        print("⏰ Attribution Time: \(Date())")
        print("📱 App Open Attribution Data: \(attributionData)")
        
        // Детальный анализ deep link данных
        if let link = attributionData["link"] as? String {
            print("🔗 Deep Link URL: \(link)")
        }
        if let scheme = attributionData["scheme"] as? String {
            print("📱 URL Scheme: \(scheme)")
        }
        if let host = attributionData["host"] as? String {
            print("🏠 Host: \(host)")
        }
        
        print("==========================================")
        // Обработка deep linking
    }
    
    func onAppOpenAttributionFailure(_ error: Error) {
        print("❌ ===== APPSFLYER DEEP LINK FAILED =====")
        print("⏰ Error Time: \(Date())")
        print("❌ Deep Link Error: \(error.localizedDescription)")
        print("❌ Error Domain: \((error as NSError).domain)")
        print("❌ Error Code: \((error as NSError).code)")
        print("==========================================")
    }
}

// MARK: - Push Notification Service
class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var pushToken: String?
    @Published var pendingNotificationURL: String?
    private var pendingTokenToSend: String? // Токен ожидающий отправки
    
    private override init() {
        super.init()
        setupNotificationCenter()
    }
    
    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self
    }
    
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        print("📱 ===== PUSH NOTIFICATION TOKEN DEBUG =====")
        print("⏰ Token Registration Time: \(Date())")
        
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let apnsToken = tokenParts.joined()
        
        print("📱 APNS Token Received: \(apnsToken)")
        print("📏 APNS Token Length: \(apnsToken.count) characters")
        print("📦 Raw Token Data Length: \(deviceToken.count) bytes")
        
        // Передаем APNS токен в Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        print("🔄 APNS token passed to Firebase Messaging")
        
        // Получаем FCM токен с повторными попытками
        requestFCMTokenWithRetry(attempt: 1, maxAttempts: 5)
    }
    
    private func requestFCMTokenWithRetry(attempt: Int, maxAttempts: Int) {
        print("🔄 ===== FCM TOKEN REQUEST ATTEMPT \(attempt)/\(maxAttempts) =====")
        print("⏰ Request Time: \(Date())")
        
        let messaging = Messaging.messaging()
        
        // Проверяем наличие APNS токена перед запросом FCM токена
        if messaging.apnsToken == nil {
            print("⚠️ APNS token not available for attempt \(attempt) - waiting...")
            
            if attempt < maxAttempts {
                let delay = Double(attempt) * 3.0 // Увеличиваем задержку для ожидания APNS токена
                print("⏳ Waiting \(delay) seconds for APNS token...")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.requestFCMTokenWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts)
                }
            } else {
                print("❌ APNS token never became available after \(maxAttempts) attempts")
                self.forceRefreshFCMToken()
            }
            return
        }
        
        print("✅ APNS token available - proceeding with FCM token request")
        
        messaging.token { [weak self] token, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error fetching FCM token (attempt \(attempt)): \(error)")
                print("❌ FCM Error Domain: \((error as NSError).domain)")
                print("❌ FCM Error Code: \((error as NSError).code)")
                
                // Если не последняя попытка, пытаемся еще раз
                if attempt < maxAttempts {
                    let delay = Double(attempt) * 2.0 // Увеличиваем задержку с каждой попыткой
                    print("⏳ Retrying FCM token request in \(delay) seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.requestFCMTokenWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts)
                    }
                } else {
                    print("❌ All FCM token attempts failed")
                    // Пытаемся принудительно удалить и получить новый токен
                    self.forceRefreshFCMToken()
                }
                print("========================================================")
                return
            }
            
            if let token = token, !token.isEmpty {
                print("✅ FCM Token Received (attempt \(attempt)): \(token)")
                print("📏 FCM Token Length: \(token.count) characters")
                DispatchQueue.main.async {
                    self.pushToken = token
                    AppState().savePushToken(token)
                    print("💾 FCM token saved to AppState")
                    self.updatePushTokenInConfig(token)
                    print("🔄 Updating FCM token in config...")
                }
                print("========================================================")
            } else {
                print("⚠️ FCM token is nil or empty (attempt \(attempt))")
                
                // Если не последняя попытка, пытаемся еще раз
                if attempt < maxAttempts {
                    let delay = Double(attempt) * 1.5
                    print("⏳ Retrying FCM token request in \(delay) seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.requestFCMTokenWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts)
                    }
                } else {
                    print("❌ All FCM token attempts returned nil")
                    self.forceRefreshFCMToken()
                }
                print("========================================================")
            }
        }
    }
    
    private func forceRefreshFCMToken() {
        print("🔄 ===== FORCE REFRESHING FCM TOKEN =====")
        print("⏰ Force Refresh Time: \(Date())")
        
        let messaging = Messaging.messaging()
        
        // Проверяем APNS токен перед удалением FCM токена
        if messaging.apnsToken == nil {
            print("⚠️ APNS token missing - re-registering for remote notifications first")
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            // Ждем APNS токен и повторяем
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.forceRefreshFCMToken()
            }
            return
        }
        
        print("✅ APNS token available - proceeding with FCM token refresh")
        
        // Удаляем текущий токен и запрашиваем новый
        messaging.deleteToken { [weak self] error in
            if let error = error {
                print("⚠️ Error deleting FCM token: \(error)")
            } else {
                print("✅ FCM token deleted successfully")
            }
            
            // Ждем немного и запрашиваем новый токен
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("🔄 Requesting new FCM token after deletion...")
                self?.requestFCMTokenWithRetry(attempt: 1, maxAttempts: 3)
            }
        }
        
        print("==========================================")
    }
    
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    private func updatePushTokenInConfig(_ token: String) {
        // Пытаемся найти AppState с conversionData через NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("SendPushTokenToServer"),
            object: nil,
            userInfo: ["token": token]
        )
        
        // Также сохраняем токен для отложенной отправки
        pendingTokenToSend = token
        print("💾 Push token saved for deferred sending when conversion data becomes available")
    }
    
    func sendPendingTokenIfNeeded(conversionData: [String: Any], appsflyerID: String?) {
        guard let token = pendingTokenToSend else {
            print("⚠️ No pending push token to send")
            return
        }
        
        print("📤 ===== SENDING PENDING PUSH TOKEN =====")
        print("🔗 Token: \(token)")
        print("📊 Conversion data available: true")
        
        // Отправляем токен на сервер через обычный config запрос
        ConfigService.shared.fetchConfig(
            conversionData: conversionData,
            appsflyerID: appsflyerID,
            pushToken: token
        ) { result in
            switch result {
            case .success:
                print("✅ Pending push token successfully sent to server")
                self.pendingTokenToSend = nil // Очищаем после успешной отправки
            case .failure(let error):
                print("❌ Failed to send pending push token: \(error.localizedDescription)")
                // Оставляем токен для повторной попытки
            }
        }
        
        print("==========================================")
    }
    
    func handlePushNotification(_ userInfo: [AnyHashable: Any]) {
        print("📲 ===== PUSH NOTIFICATION RECEIVED =====")
        print("⏰ Notification Time: \(Date())")
        print("📦 Full Notification Payload: \(userInfo)")
        
        // Анализ содержимого уведомления
        if let aps = userInfo["aps"] as? [String: Any] {
            print("📱 APS Data:")
            for (key, value) in aps {
                print("   \(key): \(value)")
            }
        }
        
        // Поиск URL в уведомлении согласно спецификации
        var foundURL: String?
        
        // Сначала ищем в data.url (основной способ согласно документации)
        if let data = userInfo["data"] as? [String: Any],
           let urlString = data["url"] as? String, !urlString.isEmpty {
            foundURL = urlString
            print("🔗 URL found in data.url: \(urlString)")
        }
        // Резервные варианты поиска URL
        else if let urlString = userInfo["url"] as? String, !urlString.isEmpty {
            foundURL = urlString
            print("🔗 URL found in root: \(urlString)")
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let urlString = aps["url"] as? String, !urlString.isEmpty {
            foundURL = urlString
            print("🔗 URL found in APS: \(urlString)")
        } else {
            print("❌ No URL found in notification payload")
            print("📋 Searching for URL in all payload keys...")
            // Поиск других возможных ключей с URL
            for (key, value) in userInfo {
                if let stringValue = value as? String, stringValue.hasPrefix("http") {
                    print("🔍 Possible URL found in key '\(key)': \(stringValue)")
                } else if let dict = value as? [String: Any] {
                    for (subKey, subValue) in dict {
                        if let stringValue = subValue as? String, stringValue.hasPrefix("http") {
                            print("🔍 Possible URL found in \(key).\(subKey): \(stringValue)")
                        }
                    }
                }
            }
        }
        
        if let urlString = foundURL {
            print("✅ Processing notification URL: \(urlString)")
            DispatchQueue.main.async {
                self.pendingNotificationURL = urlString
                self.openNotificationURL(urlString)
                print("📱 Notification URL opened")
            }
        } else {
            print("⚠️ No valid URL to process in notification")
        }
        print("==========================================")
    }
    
    private func openNotificationURL(_ url: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenNotificationURL"),
            object: nil,
            userInfo: ["url": url]
        )
    }
    
    func clearPendingNotificationURL() {
        pendingNotificationURL = nil
    }
    
    func updateFCMToken(_ token: String) {
        DispatchQueue.main.async {
            print("📱 ===== FCM TOKEN RECEIVED =====")
            print("🔗 Token: \(token)")
            
            self.pushToken = token
            AppState().savePushToken(token)
            self.updatePushTokenInConfig(token)
            
            print("==================================")
        }
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        handlePushNotification(userInfo)
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        handlePushNotification(userInfo)
        completionHandler()
    }
}
