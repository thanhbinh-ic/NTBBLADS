import UIKit
import MobileCoreServices

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private static let groupID = "group.ic.thanhbinh.CustomBlocker"

    func beginRequest(with context: NSExtensionContext) {
        // Ưu tiên bộ lọc huynh tự nhập (app ghi vào App Group).
        // Chưa có thì dùng bộ lọc mặc định đi kèm extension.
        var jsonURL: URL?
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) {
            let custom = container.appendingPathComponent("blockerList.json")
            if FileManager.default.fileExists(atPath: custom.path) {
                jsonURL = custom
            }
        }
        if jsonURL == nil {
            jsonURL = Bundle.main.url(forResource: "blockerList", withExtension: "json")
        }

        guard let url = jsonURL, let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "CustomBlocker",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy blockerList.json"]
            ))
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
