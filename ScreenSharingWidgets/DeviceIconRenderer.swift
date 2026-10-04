import AppKit
import UniformTypeIdentifiers

/// Renders the product image of a Mac model (as shown by Screen Sharing / Finder) to PNG.
@MainActor
enum DeviceIconRenderer {
    private static let modelTagClass = UTTagClass(rawValue: "com.apple.device-model-code")
    private static let pixelSize = 512

    /// Tries the coloured variant first (`Mac17,3@ECOLOR=7`), then the bare model code.
    static func pngData(forModel coloredModel: String) -> Data? {
        let candidates = [coloredModel, String(coloredModel.split(separator: "@").first ?? "")]
        for tag in candidates where !tag.isEmpty {
            guard let type = UTType(tag: tag, tagClass: modelTagClass, conformingTo: nil),
                  !type.isDynamic
            else { continue }
            return render(NSWorkspace.shared.icon(for: type))
        }
        return nil
    }

    static func fileName(forModel coloredModel: String) -> String {
        let safe = coloredModel.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(safe) + "-trim.png"
    }

    private static func render(_ image: NSImage) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixelSize, height: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        NSGraphicsContext.restoreGraphicsState()
        let trimmed = trimTransparentMargins(rep) ?? rep
        return trimmed.representation(using: .png, properties: [:])
    }

    /// Product images sit in a square canvas with large transparent margins
    /// (a Mac mini is a thin band in the middle); crop to the visible pixels.
    private static func trimTransparentMargins(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let cgImage = rep.cgImage else { return nil }
        var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = cgImage.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return nil }
        return NSBitmapImageRep(cgImage: cropped)
    }
}
