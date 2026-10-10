import SwiftUI
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Small shims so the same views build for iOS and macOS.
enum Platform {
    /// How the "capture an odometer photo" action is worded.
    static let scanWord = {
        #if os(iOS)
        "Scan"
        #else
        "Photo"
        #endif
    }()
}

extension PlatformImage {
    func jpegBytes(quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        jpegData(compressionQuality: quality)
        #else
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    var cgImageWithOrientation: (CGImage, CGImagePropertyOrientation)? {
        #if canImport(UIKit)
        guard let cgImage else { return nil }
        return (cgImage, CGImagePropertyOrientation(imageOrientation))
        #else
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (cgImage, .up)
        #endif
    }
}

#if canImport(UIKit)
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension Color {
    static var secondaryFill: Color {
        #if canImport(UIKit)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

extension View {
    @ViewBuilder func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func neverAutocapitalize() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Sheets on the Mac don't size themselves like iOS sheets do.
    @ViewBuilder func macSheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 440, minHeight: 480)
        #else
        self
        #endif
    }

    /// A row of buttons above the iOS keyboard (the Mac has no on-screen keyboard).
    @ViewBuilder func keyboardAccessory<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                content()
            }
        }
        #else
        self
        #endif
    }

    /// iOS: take a photo with the camera. macOS: pick an image file.
    func photoCapture(isPresented: Binding<Bool>, onImage: @escaping (PlatformImage) -> Void) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            CameraPicker(onImage: onImage).ignoresSafeArea()
        }
        #else
        fileImporter(isPresented: isPresented, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let image = NSImage(contentsOf: url) { onImage(image) }
        }
        #endif
    }
}
