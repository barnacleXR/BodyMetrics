import SwiftUI
import UIKit

/// 系统分享面板(UIActivityViewController 包装)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        // iPad 上需要 popover 锚点,否则崩溃
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
