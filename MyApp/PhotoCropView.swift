import SwiftUI

/// A minimal square-crop tool: pinch to zoom, drag to position, within a fixed viewport.
struct PhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    private let cropSize: CGFloat = 300
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(image: UIImage, onCancel: @escaping () -> Void, onCrop: @escaping (UIImage) -> Void) {
        self.image = image.normalizedOrientation()
        self.onCancel = onCancel
        self.onCrop = onCrop
    }

    /// The scale at which the image exactly fills the crop square (like `.scaledToFill`).
    private var baseFillScale: CGFloat {
        max(cropSize / image.size.width, cropSize / image.size.height)
    }

    private var totalScale: CGFloat {
        baseFillScale * scale
    }

    private var scaledImageSize: CGSize {
        CGSize(width: image.size.width * totalScale, height: image.size.height * totalScale)
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                    .offset(offset)
                    .frame(width: cropSize, height: cropSize)
                    .clipped()
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(magnificationGesture)
                Spacer()
                Text("Pinch to zoom, drag to position")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        onCrop(croppedImage())
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                clampOffset()
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
                clampOffset()
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func clampOffset() {
        let maxOffsetX = max(0, (scaledImageSize.width - cropSize) / 2)
        let maxOffsetY = max(0, (scaledImageSize.height - cropSize) / 2)
        offset.width = min(max(offset.width, -maxOffsetX), maxOffsetX)
        offset.height = min(max(offset.height, -maxOffsetY), maxOffsetY)
    }

    /// Maps the on-screen crop viewport back to the original image's pixel coordinates.
    private func croppedImage() -> UIImage {
        let imageTopLeft = CGPoint(
            x: -scaledImageSize.width / 2 + offset.width,
            y: -scaledImageSize.height / 2 + offset.height
        )
        let originInScaledImage = CGPoint(
            x: -cropSize / 2 - imageTopLeft.x,
            y: -cropSize / 2 - imageTopLeft.y
        )
        let cropRectInPoints = CGRect(
            x: originInScaledImage.x / totalScale,
            y: originInScaledImage.y / totalScale,
            width: cropSize / totalScale,
            height: cropSize / totalScale
        ).intersection(CGRect(origin: .zero, size: image.size))

        let pixelScale = image.scale
        let cropRectInPixels = cropRectInPoints.applying(CGAffineTransform(scaleX: pixelScale, y: pixelScale))

        guard let cgImage = image.cgImage, let cropped = cgImage.cropping(to: cropRectInPixels) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: pixelScale, orientation: .up)
    }
}

private extension UIImage {
    /// Re-rasterizes the image so `imageOrientation` is always `.up`, which the crop
    /// math above assumes (raw `CGImage` cropping ignores `UIImage.imageOrientation`).
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
