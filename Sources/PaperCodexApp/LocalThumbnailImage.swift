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

private enum LocalThumbnailDecodePolicy {
    static let appearanceDelayNanoseconds: UInt64 = 90_000_000
    static let decodePriority = TaskPriority.utility
}

private actor LocalThumbnailDecodeGate {
    static let shared = LocalThumbnailDecodeGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func wait() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

struct LocalThumbnailImage<Placeholder: View>: View {
    var url: URL
    var maxPixelSize: Int = 220
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?
    @State private var loadedURL: URL?

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
            loadedURL = url
            return
        }
        if loadedURL != url {
            image = nil
            loadedURL = url
        }
        try? await Task.sleep(nanoseconds: LocalThumbnailDecodePolicy.appearanceDelayNanoseconds)
        guard !Task.isCancelled else {
            return
        }
        if let cached = LocalThumbnailImageCache.shared.image(for: url) {
            image = cached
            loadedURL = url
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
    await LocalThumbnailDecodeGate.shared.wait()
    if Task.isCancelled {
        await LocalThumbnailDecodeGate.shared.signal()
        return nil
    }

    let result = await Task.detached(priority: LocalThumbnailDecodePolicy.decodePriority) { () -> DecodedLocalThumbnailImage? in
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
    await LocalThumbnailDecodeGate.shared.signal()
    return result
}
