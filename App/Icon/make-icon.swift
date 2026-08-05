#!/usr/bin/env swift
//
// Renders the app icon. Run from the repository root:
//
//     swift App/Icon/make-icon.swift
//
// The icon is generated rather than committed as an opaque PNG so it can be
// re-read, argued with and adjusted. It is the proximity scale itself: rings
// coloured by the same bands the app reports, green at the centre where the
// device is in your hand, red at the rim where it is a room away and fading,
// because that is what a weak signal is.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let centre = CGPoint(x: size / 2, y: size / 2)

/// The band colours the app draws with, innermost first. Full strength: fading
/// them with alpha over a near-black background turns red into brick and
/// orange into brown, so distance is carried by the ring getting thinner
/// instead.
let bands: [(rgb: (Double, Double, Double), width: Double)] = [
    ((0.19, 0.82, 0.35), 54),   // green  — arm's reach
    ((0.40, 0.83, 0.81), 44),   // mint   — same table
    ((1.00, 0.84, 0.04), 36),   // yellow — same room
    ((1.00, 0.62, 0.04), 28),   // orange — far
    ((1.00, 0.27, 0.23), 20),   // red    — very far or shielded
]

let firstRadius = 148.0
let ringPitch = 62.0

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create the drawing context")
}

func colour(_ rgb: (Double, Double, Double), _ alpha: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [rgb.0, rgb.1, rgb.2, alpha])!
}

// Background: near-black, lifted slightly at the centre so the rings sit in
// something with depth rather than on a flat rectangle. App Store icons carry
// no alpha, so this fills edge to edge.
ctx.setFillColor(colour((0.04, 0.05, 0.07)))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

if let glow = CGGradient(colorsSpace: space,
                         colors: [colour((0.09, 0.12, 0.17)), colour((0.04, 0.05, 0.07))] as CFArray,
                         locations: [0, 1]) {
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0,
                           endCenter: centre, endRadius: size * 0.62, options: [])
}

// The rings. Closed circles, evenly pitched: the scale is the subject, and an
// arc with a gap in it reads as a logo for wireless-something-or-other.
for (i, band) in bands.enumerated() {
    ctx.setStrokeColor(colour(band.rgb))
    ctx.setLineWidth(band.width)
    ctx.addArc(center: centre, radius: firstRadius + Double(i) * ringPitch,
               startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
}

// The device being walked towards: a white core over a green bloom, sitting
// inside the innermost ring so the eye lands there first.
// Tight and bright: a wide, dim bloom puts an olive well in the middle of the
// icon, which reads as a hole rather than as the thing you are looking for.
if let halo = CGGradient(colorsSpace: space,
                         colors: [colour((0.78, 1.00, 0.86)),
                                  colour((0.19, 0.82, 0.35)),
                                  colour((0.04, 0.05, 0.07))] as CFArray,
                         locations: [0, 0.42, 1]) {
    ctx.drawRadialGradient(halo, startCenter: centre, startRadius: 0,
                           endCenter: centre, endRadius: 86, options: [])
}
ctx.setFillColor(colour((1.0, 1.0, 1.0)))
ctx.fillEllipse(in: CGRect(x: centre.x - 46, y: centre.y - 46, width: 92, height: 92))

guard let image = ctx.makeImage() else { fatalError("could not render the icon") }

let out = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(
    out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not open \(out.path) for writing")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path)")
