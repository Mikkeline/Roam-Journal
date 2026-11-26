import Foundation
import CryptoKit
import ImageIO
import UIKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [String: Data] = [:]
    private var cost = 0
    func clear() { images.removeAll(); cost = 0 }
    func thumbnail(_ bytes: Data, identifier: String?, pixels: Int) throws -> Data {
        let id = (identifier ?? SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()) + "/\(pixels)"
        if let cached = images[id] { return cached }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { throw NotebookError.invalidContent }
        if cost + jpeg.count > 12_000_000 { clear() }
        if jpeg.count <= 12_000_000 { images[id] = jpeg; cost += jpeg.count }
        return jpeg
    }
}
