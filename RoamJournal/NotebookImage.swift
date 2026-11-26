import SwiftUI
import ImageIO
import UIKit

struct NotebookImage: View {
    @EnvironmentObject private var store: NotebookStore
    let data: Data?
    let reference: AttachmentReference?
    let tripID: UUID
    var pixels = 1600
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Label("Photo unavailable", systemImage: "photo.badge.exclamationmark").font(.caption) }
            else { ProgressView().frame(minHeight: 48) }
        }.task(id: reference?.blobID ?? String(data?.hashValue ?? 0)) {
            image = nil; failed = false
            do {
                guard let bytes = try await store.attachmentData(data, reference: reference, tripID: tripID) else { return }
                let jpeg = try await ThumbnailCache.shared.thumbnail(bytes, identifier: reference?.blobID, pixels: pixels)
                try Task.checkCancellation(); image = UIImage(data: jpeg)
            } catch is CancellationError {} catch { failed = true }
        }
    }
}
