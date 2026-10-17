import AppKit
import AVFoundation
import ImageIO

/// Thumbnails live only in RAM. Never QLThumbnailGenerator: it writes a system cache.
final class Thumbnails {
    static let shared = Thumbnails()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = Theme.thumbMemory
        return cache
    }()

    func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let cg = await Self.make(url) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        cache.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        return image
    }

    func clear() { cache.removeAllObjects() }

    private static func make(_ url: URL) async -> CGImage? {
        if url.type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Theme.thumbPixels,
            ] as CFDictionary)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Theme.thumbPixels, height: Theme.thumbPixels)
        return try? await generator.image(at: .zero).image
    }
}
