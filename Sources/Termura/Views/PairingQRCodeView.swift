import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders an arbitrary string as a QR code image. Used by
/// `RemoteControlSettingsView` so the pairing invitation can be scanned
/// directly with an iPhone camera instead of copy-pasting JSON.
///
/// The payload is the same JSON the controller already exposes via
/// `latestInvitationJSON` — this view is presentation-only and does not
/// alter the pairing protocol.
struct PairingQRCodeView: View {
    let payload: String
    let side: CGFloat

    var body: some View {
        Group {
            if let image = Self.render(payload: payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Pairing invitation QR code")
    }

    private static func render(payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage, raw.extent.width > 0 else { return nil }
        let upscale: CGFloat = 8
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: upscale, y: upscale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let size = NSSize(width: scaled.extent.width, height: scaled.extent.height)
        return NSImage(cgImage: cg, size: size)
    }
}
