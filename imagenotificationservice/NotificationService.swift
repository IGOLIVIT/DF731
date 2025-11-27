//
//  NotificationService.swift
//  imagenotificationservice
//
//  Created by IGOR on 19/11/2025.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Ищем URL картинки в payload
        var imageUrlString: String?
        if let fcmOptions = bestAttemptContent.userInfo["fcm_options"] as? [String: Any],
           let image = fcmOptions["image"] as? String {
            imageUrlString = image
        } else if let image = bestAttemptContent.userInfo["image-url"] as? String {
            imageUrlString = image
        }

        // Если есть картинка, качаем и прикрепляем
        if let imageUrlString = imageUrlString, let imageUrl = URL(string: imageUrlString) {
            downloadImageFrom(url: imageUrl) { attachment in
                if let attachment = attachment {
                    bestAttemptContent.attachments = [attachment]
                }
                contentHandler(bestAttemptContent)
            }
        } else {
            // Нет картинки — просто показываем пуш
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func downloadImageFrom(url: URL, completionHandler: @escaping (UNNotificationAttachment?) -> Void) {
        // Скачиваем картинку во временную папку
        let task = URLSession.shared.downloadTask(with: url) { (downloadedUrl, response, error) in
            var attachment: UNNotificationAttachment? = nil
            if let downloadedUrl = downloadedUrl {
                let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                let uniqueName = UUID().uuidString + ".jpg"
                let tmpFile = tmpDir.appendingPathComponent(uniqueName)
                do {
                    try FileManager.default.moveItem(at: downloadedUrl, to: tmpFile)
                    attachment = try UNNotificationAttachment(identifier: "image", url: tmpFile, options: nil)
                } catch {
                    print("Failed to save image:", error)
                }
            }
            completionHandler(attachment)
        }
        task.resume()
    }
}
