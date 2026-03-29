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

    enum Kind: Sendable {
        case image
        case textFile
    }

    /// Filename truncated to pill display length.
    var displayName: String {
        let name = url.lastPathComponent
        guard name.count > AppConfig.Attachments.pillNameMaxLength else { return name }
        return String(name.prefix(AppConfig.Attachments.pillNameMaxLength)) + "..."
    }

    /// SF Symbol name for the attachment kind indicator.
    var symbolName: String {
        switch kind {
        case .image: return "photo"
        case .textFile: return "doc.text"
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
