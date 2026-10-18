import AppKit
import ImageIO
import UniformTypeIdentifiers

public struct ImageAttachment: Equatable {
    public let data: Data
    public let name: String
    public let pixelSize: CGSize

    public init?(data: Data, name: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        self.data = data
        self.name = URL(fileURLWithPath: name).lastPathComponent
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        pixelSize = orientation >= 5
            ? CGSize(width: height.doubleValue, height: width.doubleValue)
            : CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    var contentType: UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)
    }

    var cardSize: CGSize {
        let factor = min(1, 320 / max(pixelSize.width, pixelSize.height))
        return CGSize(width: pixelSize.width * factor, height: pixelSize.height * factor)
    }

    func thumbnail(maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

extension NoteRecord {
    @MainActor func fittedFrame(_ frame: CGRect) -> CGRect {
        image == nil ? NoteTextLayer.fittedFrame(frame, text: text) : frame
    }
}

@MainActor
enum ImageImport {
    static var clipboard: NSPasteboard { VerificationRuntime.imagePasteboard ?? .general }
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    static func read(_ pasteboard: NSPasteboard) -> [ImageAttachment] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            return urls.compactMap { url in
                guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                return ImageAttachment(data: bytes, name: url.lastPathComponent)
            }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let bytes = pasteboard.data(forType: type),
               let image = ImageAttachment(data: bytes, name: type == .png ? "Image.png" : "Image.tiff") {
                return [image]
            }
        }
        return []
    }
}

extension CanvasView {
    @discardableResult
    func importImages(from pasteboard: NSPasteboard, at point: CGPoint, centered: Bool = false) -> Bool {
        guard canInsertNotes, finishEditing() else { return false }
        let images = ImageImport.read(pasteboard).filter { $0.thumbnail(maxPixels: 32) != nil }
        guard !images.isEmpty else { return false }
        let origin = canvasPoint(from: point)
        let order = (notes.map(\.order).max() ?? -1) + 1
        let records = images.enumerated().map { index, image in
            let size = image.cardSize
            let offset = CGFloat(index) * 24
            return NoteRecord(id: UUID(), text: "", frame: CGRect(
                x: origin.x + offset - (centered ? size.width / 2 : 0),
                y: origin.y - offset - (centered ? size.height / 2 : size.height),
                width: size.width, height: size.height),
                order: order + index, spaceID: currentSpaceID, image: image)
        }
        guard applyChanges(records.map { .insert($0) }, actionName: "Import Images") else { return false }
        select(Set(records.map(\.id)))
        window?.makeFirstResponder(self)
        return true
    }

    @objc func paste(_ sender: Any?) {
        _ = importImages(from: ImageImport.clipboard, at: CGPoint(x: bounds.midX, y: bounds.midY), centered: true)
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canInsertNotes && ImageImport.canRead(sender.draggingPasteboard) ? .copy : []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        importImages(from: sender.draggingPasteboard, at: convert(sender.draggingLocation, from: nil))
    }
}

extension ResizeHandle {
    func resizeImage(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let left = [.left, .bottomLeft, .topLeft].contains(self)
        let right = [.right, .bottomRight, .topRight].contains(self)
        let bottom = [.bottom, .bottomLeft, .bottomRight].contains(self)
        let top = [.top, .topLeft, .topRight].contains(self)
        let dx = left ? -delta.width : right ? delta.width : 0
        let dy = bottom ? -delta.height : top ? delta.height : 0
        let factor: CGFloat
        if left || right, bottom || top {
            factor = 1 + (dx * rect.width + dy * rect.height) / (rect.width * rect.width + rect.height * rect.height)
        } else {
            factor = 1 + ((left || right) ? dx / rect.width : dy / rect.height)
        }
        let size = CGSize(width: rect.width * max(32 / min(rect.width, rect.height), factor),
                          height: rect.height * max(32 / min(rect.width, rect.height), factor))
        return CGRect(x: left ? rect.maxX - size.width : right ? rect.minX : rect.midX - size.width / 2,
                      y: bottom ? rect.maxY - size.height : top ? rect.minY : rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
