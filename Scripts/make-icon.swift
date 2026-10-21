#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func makeImage(pixels: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let scale = CGFloat(pixels) / 1024.0
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let body = canvas.insetBy(dx: 26, dy: 26)
    let radius: CGFloat = 224
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()

    let colors = [
        CGColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1.0),
        CGColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.49, green: 0.43, blue: 1.0, alpha: 1.0)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.minX, y: body.maxY),
            end: CGPoint(x: body.maxX, y: body.minY),
            options: []
        )
    }

    if let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.32),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 250, y: 830),
            startRadius: 0,
            endCenter: CGPoint(x: 250, y: 830),
            endRadius: 620,
            options: []
        )
    }

    context.restoreGState()

    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 292, y: 704))
    mark.addLine(to: CGPoint(x: 512, y: 318))
    mark.addLine(to: CGPoint(x: 732, y: 704))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 28,
        color: CGColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 0.22)
    )
    context.addPath(mark)
    context.setLineWidth(118)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(CGColor(red: 0.03, green: 0.07, blue: 0.11, alpha: 0.94))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.setLineWidth(4)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.26))
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in entries {
    guard let image = makeImage(pixels: pixels) else {
        fatalError("Impossibile generare l'icona \(name)")
    }
    let url = iconset.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Impossibile creare \(name)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fatalError("iconutil è terminato con errore")
}

print("Icona generata: Resources/AppIcon.icns")
