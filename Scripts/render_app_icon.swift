#!/usr/bin/env swift
/* Renders the bundled AppIcon PNGs from the design source.
 *
 * Source of truth: Design/simunow-app-icon.png (1024x1024, supplied artwork).
 * Outputs (into Apps/Shared/Assets.xcassets/AppIcon.appiconset/):
 *   - icon-1024.png       iOS: opaque full-square 1024. The system masks the
 *                         squircle; App Store validation rejects alpha, so the
 *                         artwork is composited onto the opaque navy background
 *                         (#0A2A3A from the artwork).
 *   - icon-{16..1024}-mac.png  macOS: actool has no single-size slot for macOS
 *                         (that format is iOS-only), so the full legacy size
 *                         set is rendered: the 1024 artwork clipped to the
 *                         824 pt squircle (corner radius ~186) on transparent
 *                         corners, downscaled to every legacy slot size.
 *
 * Run: swift Scripts/render_app_icon.swift   (Xcode toolchain required)
 */
import CoreGraphics
import Foundation
import ImageIO

// Canvas constants; the artwork itself is drawn 1:1 (source is already 1024).
let canvas = 1024
let macBody = CGRect(x: 100, y: 100, width: 824, height: 824) // macOS icon grid: 824 body on 1024 canvas
let macRadius: CGFloat = 186
// Legacy macOS AppIcon slot sizes (1x of each named size plus 2x variants).
let macSizes = [16, 32, 64, 128, 256, 512, 1024]
// Navy from the artwork background; used to fill the iOS full-square corners.
let navy = CGColor(srgbRed: 10.0 / 255.0, green: 42.0 / 255.0, blue: 58.0 / 255.0, alpha: 1.0)

let scriptURL = URL(fileURLWithPath: #filePath)
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Design/simunow-app-icon.png")
let setURL = root.appendingPathComponent("Apps/Shared/Assets.xcassets/AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

// Load the artwork at full resolution; no resampling is needed at 1024.
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("missing design source: \(sourceURL.path)")
}
guard artwork.width == canvas, artwork.height == canvas else {
    fail("design source must be 1024x1024, got \(artwork.width)x\(artwork.height)")
}
try? FileManager.default.createDirectory(at: setURL, withIntermediateDirectories: true)

/// Common: draw the artwork 1:1 over the prepared background (1024 space).
func drawArtwork(_ context: CGContext) {
    context.interpolationQuality = .none // 1:1 at full size; downscales set their own quality
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
}

// iOS variant: opaque full square. Alpha-free context so the written PNG
// carries no alpha channel (kCGImageAlphaNoneSkipLast).
func renderIOS() -> CGImage {
    guard let context = CGContext(
        data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fail("cannot create iOS bitmap context") }
    context.setFillColor(navy)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    drawArtwork(context)
    guard let image = context.makeImage() else { fail("cannot make iOS image") }
    return image
}

// macOS variant: clip the artwork to the 824 squircle, rendered at any legacy
// slot size. Drawing happens in the 1024 design space with a scaled CTM.
func renderMac(px: Int) -> CGImage {
    guard let context = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create macOS bitmap context") }
    context.scaleBy(x: CGFloat(px) / CGFloat(canvas), y: CGFloat(px) / CGFloat(canvas))
    context.saveGState()
    context.addPath(CGPath(roundedRect: macBody, cornerWidth: macRadius, cornerHeight: macRadius, transform: nil))
    context.clip()
    context.setFillColor(navy)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.interpolationQuality = .high // smooth downscale for small slots
    drawArtwork(context)
    context.restoreGState()
    guard let image = context.makeImage() else { fail("cannot make macOS image") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    // "public.png" as a plain CFString avoids the UniformTypeIdentifiers import.
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot create PNG destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write PNG: \(url.path)") }
}

do {
    // Render each platform once; the alpha info doubles as build evidence.
    let iosImage = renderIOS()
    let iosURL = setURL.appendingPathComponent("icon-1024.png")
    writePNG(iosImage, to: iosURL)
    print("wrote \(iosURL.path) alphaInfo=\(iosImage.alphaInfo.rawValue)")
    for px in macSizes {
        let image = renderMac(px: px)
        let url = setURL.appendingPathComponent("icon-\(px)-mac.png")
        writePNG(image, to: url)
        print("wrote \(url.path) \(px)x\(px) alphaInfo=\(image.alphaInfo.rawValue)")
    }
    print("done")
}
