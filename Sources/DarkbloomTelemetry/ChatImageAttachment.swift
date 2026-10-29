import Foundation
import ImageIO

/// A selected image retained only in memory. No path, file URL, or remote URL
/// is accepted by this contract. Wire data is generated from validated bytes.
public struct ChatImageAttachment: Equatable, Sendable, CustomStringConvertible, CustomReflectable {
    public static let maximumBytes = 2 * 1_024 * 1_024
    public static let maximumImagesPerRequest = 4
    public static let maximumTotalBytes = 5 * 1_024 * 1_024
    public static let maximumPixels = 16_000_000
    public static let maximumTotalPixels = 24_000_000
    public static let supportedMIMETypes = ["image/png", "image/jpeg"]

    public let data: Data
    public let mimeType: String
    public let pixelCount: Int

    public init(data: Data, mimeType: String) throws {
        guard Self.supportedMIMETypes.contains(mimeType) else { throw ChatImageError.unsupportedMIMEType }
        guard data.count <= Self.maximumBytes else { throw ChatImageError.attachmentTooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == (mimeType == "image/png" ? "public.png" : "public.jpeg"),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= Self.maximumPixels,
              height <= Self.maximumPixels / width
        else { throw ChatImageError.invalidImage }
        self.data = data
        self.mimeType = mimeType
        self.pixelCount = width * height
    }

    public var description: String { "ChatImageAttachment(\(mimeType), \(data.count) bytes)" }
    public var customMirror: Mirror { Mirror(self, children: ["mimeType": mimeType, "byteCount": data.count]) }

    var dataURI: String { "data:\(mimeType);base64," + data.base64EncodedString() }

    /// Decoding never fetches a URL. Bound base64 before allocating decoded
    /// bytes and require its canonical encoding (no ignored garbage).
    static func decodeDataURI(_ uri: String) throws -> Self {
        let maximumEncodedBytes = ((maximumBytes + 2) / 3) * 4
        guard uri.utf8.count <= maximumEncodedBytes + 32 else { throw ChatImageError.attachmentTooLarge }
        guard let comma = uri.firstIndex(of: ",") else { throw ChatImageError.invalidImage }
        let header = String(uri[..<comma])
        guard let mimeType = supportedMIMETypes.first(where: { header == "data:\($0);base64" }) else {
            throw ChatImageError.unsupportedMIMEType
        }
        let encoded = String(uri[uri.index(after: comma)...])
        guard encoded.utf8.count <= maximumEncodedBytes,
              let data = Data(base64Encoded: encoded), data.base64EncodedString() == encoded
        else { throw ChatImageError.invalidImage }
        return try Self(data: data, mimeType: mimeType)
    }

    public static func validate(_ images: [Self]) throws {
        guard images.count <= maximumImagesPerRequest else { throw ChatImageError.tooManyImages }
        guard images.reduce(0, { $0 + $1.data.count }) <= maximumTotalBytes else {
            throw ChatImageError.totalAttachmentsTooLarge
        }
        guard images.reduce(0, { $0 + $1.pixelCount }) <= maximumTotalPixels else {
            throw ChatImageError.totalAttachmentsTooLarge
        }
    }
}

/// Fixed messages avoid reflecting image bytes, paths, or server text.
public enum ChatImageError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedMIMEType, invalidImage, attachmentTooLarge, tooManyImages
    case totalAttachmentsTooLarge, networkImagesUnsupported, imagesRequireUserRole
    case localImageEndpointChanged

    public var errorDescription: String? {
        switch self {
        case .unsupportedMIMEType: "Choose a PNG or JPEG image."
        case .invalidImage: "The image is invalid, animated, or larger than 16 megapixels."
        case .attachmentTooLarge: "Each image must be 2 MiB or smaller."
        case .tooManyImages: "A chat request can include at most four images, including history."
        case .totalAttachmentsTooLarge: "Images in this request exceed the 5 MiB or 24 megapixel total limit, including history."
        case .networkImagesUnsupported: "The selected network model has no fresh verified image support. Refresh network models or choose a model with image input."
        case .imagesRequireUserRole: "Images can only be attached to user messages."
        case .localImageEndpointChanged: "The local image destination changed or was not verified. Refresh local models before sending images."
        }
    }
}
