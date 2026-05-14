import ImageIO
import SwiftUI

@MainActor
private final class LocalThumbnailImageCache {
    static let shared = LocalThumbnailImageCache()

    private let cache = NSCache<NSURL, CachedLocalThumbnailImage>()

    private init() {
        cache.countLimit = 700
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(
            CachedLocalThumbnailImage(image),
            forKey: url as NSURL,
            cost: image.bytesPerRow * image.height
        )
    }
}

private final class CachedLocalThumbnailImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private struct DecodedLocalThumbnailImage: @unchecked Sendable {
    var image: CGImage
}

struct LocalThumbnailImage<Placeholder: View>: View {
    var url: URL
    var maxPixelSize: Int = 220
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        if let cached = LocalThumbnailImageCache.shared.image(for: url) {
            image = cached
            return
        }
        guard let decoded = await decodeLocalThumbnailImage(at: url, maxPixelSize: maxPixelSize) else {
            image = nil
            return
        }
        guard !Task.isCancelled else {
            return
        }
        LocalThumbnailImageCache.shared.insert(decoded.image, for: url)
        image = decoded.image
    }
}

private func decodeLocalThumbnailImage(at url: URL, maxPixelSize: Int) async -> DecodedLocalThumbnailImage? {
    await Task.detached(priority: .userInitiated) {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return DecodedLocalThumbnailImage(image: image)
    }.value
}
