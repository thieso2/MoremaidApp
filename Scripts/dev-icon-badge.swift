import AppKit

// Usage: swift dev-icon-badge.swift <icon-src-dir> <iconset-dst-dir>
// Creates badged icon PNGs in an .iconset directory for iconutil conversion.

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: dev-icon-badge.swift <icon-src-dir> <iconset-dst-dir>\n", stderr)
    exit(1)
}

let srcDir = args[1]
let dstDir = args[2]

// Icon sizes: (source filename, iconset filename, pixel size)
let icons: [(src: String, dst: String, size: Int)] = [
    ("icon_16x16.png",    "icon_16x16.png",      16),
    ("icon_32x32.png",    "icon_16x16@2x.png",   32),
    ("icon_32x32.png",    "icon_32x32.png",       32),
    ("icon_64x64.png",    "icon_32x32@2x.png",    64),
    ("icon_128x128.png",  "icon_128x128.png",     128),
    ("icon_256x256.png",  "icon_128x128@2x.png",  256),
    ("icon_256x256.png",  "icon_256x256.png",      256),
    ("icon_512x512.png",  "icon_256x256@2x.png",  512),
    ("icon_512x512.png",  "icon_512x512.png",      512),
    ("icon_1024x1024.png","icon_512x512@2x.png",  1024),
]

try? FileManager.default.createDirectory(atPath: dstDir, withIntermediateDirectories: true)

for icon in icons {
    let srcPath = "\(srcDir)/\(icon.src)"
    let dstPath = "\(dstDir)/\(icon.dst)"
    let size = icon.size

    guard let srcImage = NSImage(contentsOfFile: srcPath) else {
        fputs("warning: Cannot load \(srcPath), skipping\n", stderr)
        continue
    }

    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    srcImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

    // Badge background
    let badgeH = CGFloat(size) * 0.2
    let badgeRect = NSRect(x: 0, y: 0, width: CGFloat(size), height: badgeH)
    NSColor(red: 0.86, green: 0.24, blue: 0.24, alpha: 0.85).setFill()
    badgeRect.fill()

    // "dev" text (skip for tiny sizes where it would be illegible)
    if size >= 32 {
        let fontSize = badgeH * 0.65
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let text = "dev" as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (CGFloat(size) - textSize.width) / 2,
            y: (badgeH - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("warning: Failed to create PNG for \(icon.dst)\n", stderr)
        continue
    }
    try! png.write(to: URL(fileURLWithPath: dstPath))
}
