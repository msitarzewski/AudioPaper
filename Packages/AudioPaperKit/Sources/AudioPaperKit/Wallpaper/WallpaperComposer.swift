import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A display to render for, identified by its CGDirectDisplayID.
public struct ScreenDescriptor: Hashable, Sendable, Identifiable {
    public var id: UInt32
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: UInt32, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// How fan art is framed on a screen whose shape differs from the image.
public enum FanArtFraming: String, CaseIterable, Sendable, Identifiable {
    /// Fill when little would be cropped, otherwise fit.
    case automatic
    /// Always fill the screen, cropping from the centre (CSS "cover").
    case fill
    /// Always show the whole image at full height or width over a wash of itself (CSS "contain").
    case fit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .fill: "Fill screen"
        case .fit: "Fit whole image"
        }
    }

    /// Fraction of the image lost when filling `canvas`, above which `.automatic` fits instead.
    static let automaticCropLimit = 0.15

    /// Whether an image of `size` should be fitted (true) or filled (false) on `canvas`.
    public func fits(imageSize size: CGSize, canvas: CGSize) -> Bool {
        switch self {
        case .fill: return false
        case .fit: return true
        case .automatic: return Self.cropFraction(imageSize: size, canvas: canvas) > Self.automaticCropLimit
        }
    }

    /// 0 when aspect ratios match; 0.44 for a square image on a 16:9 screen.
    static func cropFraction(imageSize size: CGSize, canvas: CGSize) -> Double {
        let image = size.width / size.height, screen = canvas.width / canvas.height
        return 1 - min(image, screen) / max(image, screen)
    }
}

/// Renders artwork into screen-sized wallpaper images with Core Image.
///
/// Album covers are square, so they sit centered over a blurred, colour-matched wash of themselves.
/// Fan art fills the screen edge to edge, or — when filling would crop too much — is shown whole at full
/// height (or width) with its edges feathered into a blurred extension of its own edge colours.
public struct WallpaperComposer: Sendable {
    public let outputDirectory: URL
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init(outputDirectory: URL = WallpaperComposer.defaultOutputDirectory) {
        self.outputDirectory = outputDirectory
    }

    public static var defaultOutputDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "AudioPaper/Wallpapers", directoryHint: .isDirectory)
    }

    /// Renders one file per screen. Every call writes new file names; macOS ignores a repeated URL.
    public func render(_ artwork: Artwork, for screens: [ScreenDescriptor], framing: FanArtFraming = .automatic) throws -> [UInt32: URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        guard let source = CIImage(contentsOf: artwork.fileURL, options: [.applyOrientationProperty: true]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let stamp = UUID().uuidString.prefix(8)
        var files: [UInt32: URL] = [:]
        for screen in screens {
            let canvas = CGRect(x: 0, y: 0, width: screen.pixelWidth, height: screen.pixelHeight)
            let image = switch artwork.candidate.kind {
            case .albumCover: Self.albumScene(source, canvas: canvas)
            case .fanArt:
                framing.fits(imageSize: source.extent.size, canvas: canvas.size)
                    ? Self.fittedScene(source, canvas: canvas)
                    : Self.aspectFill(source, in: canvas)
            }
            let file = outputDirectory.appending(path: "\(stamp)-\(screen.id).heic")
            try context.writeHEIFRepresentation(
                of: image.cropped(to: canvas),
                to: file,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
            )
            files[screen.id] = file
        }
        return files
    }

    /// Deletes rendered wallpapers except those in `keep`.
    public func prune(keeping keep: Set<URL>) {
        let keepPaths = Set(keep.map { $0.standardizedFileURL.path(percentEncoded: false) })
        guard let files = try? FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keepPaths.contains(file.standardizedFileURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func aspectFill(_ image: CIImage, in canvas: CGRect) -> CIImage {
        let extent = image.extent
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(
            x: canvas.midX - scaled.extent.midX,
            y: canvas.midY - scaled.extent.midY
        )
        return scaled.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
    }

    static func aspectFit(_ image: CIImage, in canvas: CGRect) -> CIImage {
        let extent = image.extent
        let scale = min(canvas.width / extent.width, canvas.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(by: CGAffineTransform(
            translationX: canvas.midX - scaled.extent.midX, y: canvas.midY - scaled.extent.midY
        ))
    }

    /// The image blown up past the screen, blurred hard and slightly darkened: a colour-matched background.
    static func wash(_ image: CIImage, canvas: CGRect) -> CIImage {
        let blurRadius = canvas.height / 18
        return aspectFill(image, in: canvas.insetBy(dx: -blurRadius * 3, dy: -blurRadius * 3))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.25, kCIInputBrightnessKey: -0.12, kCIInputContrastKey: 0.95,
            ])
            .cropped(to: canvas)
    }

    /// The whole image at full height (or width), its open edges feathered into a blurred extension of itself.
    static func fittedScene(_ image: CIImage, canvas: CGRect) -> CIImage {
        let fitted = aspectFit(image, in: canvas)
        let frame = fitted.extent
        // Feather only the sides that meet the wash; edges touching the screen edge stay crisp.
        let feather = min(frame.width, frame.height) * 0.06
        let bandsLeftRight = frame.width < canvas.width - 1
        let inner = frame.insetBy(dx: bandsLeftRight ? feather : -feather * 4, dy: bandsLeftRight ? -feather * 4 : feather)
        let mask = CIImage(color: .white).cropped(to: inner)
            .applyingGaussianBlur(sigma: feather / 2)
            .cropped(to: frame)
        let feathered = fitted.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ])
        // Extend the picture's own edge pixels outward and blur them, so the open sides continue
        // the colours at its edges — a native stand-in for generative "expand".
        let extended = fitted.clampedToExtent()
            .applyingGaussianBlur(sigma: canvas.height / 12)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06, kCIInputSaturationKey: 1.1])
            .cropped(to: canvas)
        return feathered.composited(over: extended).cropped(to: canvas)
    }

    static func albumScene(_ cover: CIImage, canvas: CGRect) -> CIImage {
        let backdrop = wash(cover, canvas: canvas)

        // Cover: centred at 56% of the screen height with softly rounded corners and a drop shadow.
        let side = (canvas.height * 0.56).rounded()
        let coverRect = CGRect(x: canvas.midX - side / 2, y: canvas.midY - side / 2, width: side, height: side)
        let fitted = aspectFill(cover, in: coverRect).cropped(to: coverRect)
        let mask = roundedRectMask(coverRect, radius: side * 0.012)
        let rounded = fitted.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ])

        let shadowOffset = side * 0.02
        let shadow = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55))
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask.transformed(by: CGAffineTransform(translationX: 0, y: -shadowOffset)),
            ])
            .applyingGaussianBlur(sigma: side * 0.035)

        return rounded.composited(over: shadow.composited(over: backdrop)).cropped(to: canvas)
    }

    static func roundedRectMask(_ rect: CGRect, radius: CGFloat) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = .white
        return generator.outputImage ?? CIImage(color: .white).cropped(to: rect)
    }
}
