#!/usr/bin/env swift
//
// make_icon.swift — generates the SudokuH app icon (Light, Dark, Tinted).
//
// Usage (from anywhere):
//     swift Design/make_icon.swift
//
// Writes three opaque 1024x1024 PNGs, square corners (iOS applies the mask),
// straight into SudokuH/Assets.xcassets/AppIcon.appiconset/.
//
// Tweak the `Palette` values and the `Layout` constants below, then re-run.

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tweakables

enum Layout {
    static let canvas: CGFloat = 1024
    static let cell: CGFloat = 188          // side of each rounded square
    static let gap: CGFloat = 26            // space between squares
    static let cornerRadius: CGFloat = 46   // roundness of each square
    static let highlight = (row: 2, col: 2) // 0-based from the top-left
    static let digit = "7"
    static let digitSize: CGFloat = 150     // point size of the digit
}

struct Palette {
    var backgroundTop: UInt32      // gradient start (top-left)
    var backgroundBottom: UInt32   // gradient end (bottom-right)
    var glow: UInt32               // soft light in the top-left corner
    var glowAlpha: CGFloat
    var cell: UInt32               // the 8 resting squares
    var cellAlpha: CGFloat
    var highlightTop: UInt32       // the "active" square (vertical gradient)
    var highlightBottom: UInt32
    var digit: UInt32
    var shadow: UInt32             // drop shadow under the active square
    var shadowAlpha: CGFloat
}

let variants: [(file: String, palette: Palette)] = [
    ("AppIcon.png", Palette(
        backgroundTop: 0xE07A5F, backgroundBottom: 0xF2A65A,
        glow: 0xFFE2B8, glowAlpha: 0.38,
        cell: 0xFFF4E6, cellAlpha: 0.36,
        highlightTop: 0xFFFAF2, highlightBottom: 0xFFF0DC,
        digit: 0xD96A4E,
        shadow: 0x8A3A22, shadowAlpha: 0.30)),

    ("AppIcon-Dark.png", Palette(
        backgroundTop: 0x3B2519, backgroundBottom: 0x22140D,
        glow: 0xF2A65A, glowAlpha: 0.14,
        cell: 0xF2A65A, cellAlpha: 0.24,
        highlightTop: 0xF7B86C, highlightBottom: 0xE8914E,
        digit: 0x2E1B11,
        shadow: 0x000000, shadowAlpha: 0.45)),

    // Grayscale: iOS multiplies this by the user's tint colour.
    ("AppIcon-Tinted.png", Palette(
        backgroundTop: 0x2A2A2A, backgroundBottom: 0x0E0E0E,
        glow: 0xFFFFFF, glowAlpha: 0.08,
        cell: 0xFFFFFF, cellAlpha: 0.30,
        highlightTop: 0xFFFFFF, highlightBottom: 0xE4E4E4,
        digit: 0x1A1A1A,
        shadow: 0x000000, shadowAlpha: 0.45)),
]

// MARK: - Drawing

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func render(_ p: Palette) -> CGImage {
    let s = Layout.canvas
    // noneSkipLast => opaque bitmap, so the PNG has no alpha channel.
    let ctx = CGContext(data: nil, width: Int(s), height: Int(s),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

    // Background: diagonal gradient, top-left -> bottom-right.
    ctx.drawLinearGradient(gradient([color(p.backgroundTop), color(p.backgroundBottom)]),
                           start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Gentle inner glow from the top-left.
    ctx.drawRadialGradient(gradient([color(p.glow, p.glowAlpha), color(p.glow, 0)]),
                           startCenter: CGPoint(x: s * 0.28, y: s * 0.80), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.28, y: s * 0.80), endRadius: s * 0.75,
                           options: [])

    // 3x3 grid of rounded squares, centred.
    let span = Layout.cell * 3 + Layout.gap * 2
    let origin = (s - span) / 2
    func cellRect(row: Int, col: Int) -> CGRect {
        let step = Layout.cell + Layout.gap
        return CGRect(x: origin + CGFloat(col) * step,
                      y: s - origin - CGFloat(row) * step - Layout.cell, // flip: row 0 is on top
                      width: Layout.cell, height: Layout.cell)
    }
    func roundedPath(_ r: CGRect) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: Layout.cornerRadius,
               cornerHeight: Layout.cornerRadius, transform: nil)
    }

    for row in 0..<3 {
        for col in 0..<3 where (row, col) != Layout.highlight {
            ctx.addPath(roundedPath(cellRect(row: row, col: col)))
            ctx.setFillColor(color(p.cell, p.cellAlpha))
            ctx.fillPath()
        }
    }

    // Highlighted square: soft shadow, then a subtle vertical gradient.
    let hi = cellRect(row: Layout.highlight.row, col: Layout.highlight.col)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                  color: color(p.shadow, p.shadowAlpha))
    ctx.addPath(roundedPath(hi))
    ctx.setFillColor(color(p.highlightBottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(roundedPath(hi))
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(p.highlightTop), color(p.highlightBottom)]),
                           start: CGPoint(x: hi.midX, y: hi.maxY),
                           end: CGPoint(x: hi.midX, y: hi.minY), options: [])
    ctx.restoreGState()

    // Digit: SF Rounded Heavy, optically centred on its glyph bounds.
    let base = NSFont.systemFont(ofSize: Layout.digitSize, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: Layout.digitSize) } ?? base
    let text = NSAttributedString(string: Layout.digit, attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: color(p.digit))!,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: hi.midX - glyphs.midX, y: hi.midY - glyphs.midY)
    CTLineDraw(line, ctx)

    return ctx.makeImage()!
}

// MARK: - Output

let scriptURL = URL(fileURLWithPath: #filePath)
let outDir = scriptURL
    .deletingLastPathComponent()   // Design/
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("SudokuH/Assets.xcassets/AppIcon.appiconset")

for (file, palette) in variants {
    let url = outDir.appendingPathComponent(file)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(dest, render(palette), nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Cannot write \(url.path)") }
    print(url.path)
}
