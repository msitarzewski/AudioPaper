// apctl — developer harness for AudioPaperKit's artwork pipeline.
//
//   apctl cover  <artist> <album>              Look up the album cover through the provider chain.
//   apctl fanart <artist> <song> [outDir]      Run the fan-art pipeline, print every verdict, copy survivors.
//   apctl labels <imageFile>...                Print Vision classification, aesthetics, and text for images.
//   apctl render <image> <w> <h> [framing]     Render a wallpaper to the working directory to preview framing.
//
// Credentials come from the environment or the nearest `.env` walking up from the working directory.

import AudioPaperKit
import Foundation
import Vision

func findDotEnv() -> URL? {
    var dir = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
    for _ in 0..<6 {
        let candidate = dir.appending(path: ".env")
        if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        dir = dir.deletingLastPathComponent()
    }
    return nil
}

let args = Array(CommandLine.arguments.dropFirst())
let secrets = EnvironmentSecretStore(dotEnv: findDotEnv())
let cache = ArtworkCache()

func usage() -> Never {
    print("usage: apctl cover <artist> <album> | fanart <artist> <song> [outDir] | labels <file>... | render <image> <w> <h> [automatic|fill|fit] [album]")
    exit(64)
}

guard let command = args.first else { usage() }

switch command {
case "cover" where args.count == 3:
    let track = Track(title: "", artist: args[1], album: args[2], sourceID: "apctl")
    let providers: [any AlbumArtworkProvider] = [ITunesSearchProvider(), CoverArtArchiveProvider()]
    for provider in providers {
        do {
            if let candidate = try await provider.albumArtwork(for: track) {
                print(String(format: "%.2f  %@  %@", candidate.matchScore, provider.id, candidate.imageURL.absoluteString))
            } else {
                print("--    \(provider.id)  no match")
            }
        } catch {
            print("!!    \(provider.id)  \(error)")
        }
    }

case "fanart" where args.count >= 3:
    let track = Track(title: args[2], artist: args[1], album: "", sourceID: "apctl")
    let outDir = args.count > 3 ? URL(filePath: args[3], directoryHint: .isDirectory) : nil
    if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
    let pipeline = FanArtPipeline(
        sources: [
            FanartTVSource(secrets: secrets), TheAudioDBSource(secrets: secrets),
            DeviantArtSource(secrets: secrets), BraveImageSource(secrets: secrets),
        ],
        cache: cache
    )
    let configured = pipeline.sources.filter(\.isConfigured).map(\.id)
    print("sources: \(configured.joined(separator: ", "))")
    var accepted = 0, rejected = 0
    for await event in pipeline.run(for: track) {
        switch event {
        case let .accepted(artwork):
            accepted += 1
            let score = artwork.qualityScore.map { String(format: "%.2f", $0) } ?? "-"
            print("✅ \(artwork.pixelWidth)×\(artwork.pixelHeight) score \(score)  \(artwork.candidate.attribution.sourceName)  \(artwork.candidate.imageURL.absoluteString)")
            if let creator = artwork.candidate.attribution.creatorName { print("     by \(creator) \(artwork.candidate.attribution.creatorProfileURL?.absoluteString ?? "")") }
            if let outDir {
                let dest = outDir.appending(path: "\(accepted)-\(artwork.candidate.providerID).\(artwork.candidate.imageURL.pathExtension.isEmpty ? "jpg" : artwork.candidate.imageURL.pathExtension)")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: artwork.fileURL, to: dest)
            }
        case let .rejected(candidate, reason):
            rejected += 1
            print("❌ \(reason.padding(toLength: 34, withPad: " ", startingAt: 0)) \(candidate.imageURL.absoluteString.prefix(90))")
        }
    }
    print("accepted \(accepted), rejected \(rejected)")

case "labels" where args.count >= 2:
    for path in args.dropFirst() {
        let file = URL(filePath: path)
        guard let image = ImageLoading.image(at: file, maxPixelSize: 1024) else { print("\(path): undecodable"); continue }
        let aesthetics = try await CalculateImageAestheticsScoresRequest().perform(on: image)
        let labels = try await ClassifyImageRequest().perform(on: image)
            .filter { $0.confidence > 0.2 }
            .prefix(8)
            .map { String(format: "%@ %.2f", $0.identifier, $0.confidence) }
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        let text = try await textRequest.perform(on: image).compactMap { $0.topCandidates(1).first?.string }
        print("\(file.lastPathComponent): aes \(String(format: "%.2f", aesthetics.overallScore)) utility \(aesthetics.isUtility)")
        print("  labels: \(labels.joined(separator: ", "))")
        if !text.isEmpty { print("  text: \(text.joined(separator: " | ").prefix(120))") }
    }

case "render" where args.count >= 4:
    // apctl render <image> <width> <height> [automatic|fill|fit] [album]
    let file = URL(filePath: args[1])
    guard let width = Int(args[2]), let height = Int(args[3]), let size = ImageLoading.pixelSize(of: file) else { usage() }
    let framing = args.count > 4 ? FanArtFraming(rawValue: args[4]) ?? .automatic : .automatic
    let kind: ArtworkKind = args.count > 5 && args[5] == "album" ? .albumCover : .fanArt
    let artwork = Artwork(
        candidate: ArtworkCandidate(imageURL: file, kind: kind, providerID: "apctl", attribution: Attribution(sourceName: "apctl")),
        fileURL: file, pixelWidth: size.width, pixelHeight: size.height
    )
    let composer = WallpaperComposer(outputDirectory: URL(filePath: FileManager.default.currentDirectoryPath))
    let files = try composer.render(artwork, for: [ScreenDescriptor(id: 0, pixelWidth: width, pixelHeight: height)], framing: framing)
    print(files[0]?.path(percentEncoded: false) ?? "render failed")

default:
    usage()
}
