import SwiftUI
import UIKit

/// Wraps UIActivityViewController so we can share text alongside multiple
/// images in one sheet — ShareLink can't mix a String and several UIImages
/// the way WhatsApp's share extension expects.
///
/// Photos are written to temporary, downscaled JPEG files and shared as file
/// URLs rather than raw UIImage instances. Handing some share extensions —
/// WhatsApp included — several full-resolution in-memory images is unreliable
/// and can make the extension bail out instead of opening; file URLs are the
/// standard, reliable way to hand off images.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    let images: [UIImage]
    var onComplete: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let imageURLs = Self.writeTemporaryJPEGs(images)
        let controller = UIActivityViewController(activityItems: [text] + imageURLs, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Self.cleanUp(imageURLs)
            onComplete(completed)
        }
        // No-op on iPhone; avoids a crash on iPad, which requires a popover anchor.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    private static func writeTemporaryJPEGs(_ images: [UIImage]) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "share-\(UUID().uuidString)", isDirectory: true
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return images.enumerated().compactMap { index, image in
            guard let data = image.resized(maxDimension: 1600).jpegData(compressionQuality: 0.85) else {
                return nil
            }
            let url = folder.appendingPathComponent("photo-\(index).jpg")
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }
    }

    private static func cleanUp(_ urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }

        let scaleFactor = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
