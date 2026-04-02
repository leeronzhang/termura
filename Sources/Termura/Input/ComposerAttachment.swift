import AppKit
import Foundation

/// Represents a single file attachment in the Composer input bar.
struct ComposerAttachment: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let kind: Kind
    /// True for clipboard/paste images saved to the tmp directory — must be deleted on removal
    /// or session close. False for user-selected files from the file system.
    let isTemporary: Bool
    /// Filename truncated to pill display length.
    /// Stored once at init — `url` is immutable so string operations are not repeated on each access.
    let displayName: String

    enum Kind: Sendable {
        case image
        case textFile
    }

    init(id: UUID, url: URL, kind: Kind, isTemporary: Bool) {
        self.id = id
        self.url = url
        self.kind = kind
        self.isTemporary = isTemporary
        let name = url.lastPathComponent
        displayName = name.count > AppConfig.Attachments.pillNameMaxLength
            ? String(name.prefix(AppConfig.Attachments.pillNameMaxLength)) + "..."
            : name
    }

    /// SF Symbol name for the attachment kind indicator.
    var symbolName: String {
        switch kind {
        case .image: "photo"
        case .textFile: "doc.text"
        }
    }
}

// MARK: - Temporary image save

enum AttachmentSaveError: Error {
    case imageConversionFailed
}

/// Saves an NSImage to the shared tmp directory and returns its URL.
/// Reuses AppConfig.DragDrop constants so all temp images land in the same directory.
func saveTemporaryAttachmentImage(_ image: NSImage) throws -> URL {
    let homeURL = FileManager.default.homeDirectoryForCurrentUser
    let tmpDir = homeURL.appendingPathComponent(AppConfig.DragDrop.tempImageSubdirectory)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let ts = Int(Date().timeIntervalSince1970)
    let name = "\(AppConfig.DragDrop.imagePastePrefix)-\(ts).\(AppConfig.DragDrop.imagePasteExtension)"
    let fileURL = tmpDir.appendingPathComponent(name)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw AttachmentSaveError.imageConversionFailed
    }
    try png.write(to: fileURL)
    return fileURL
}
