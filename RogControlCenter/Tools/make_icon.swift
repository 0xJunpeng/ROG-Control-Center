// 生成应用图标（1024px PNG），配合 iconutil 制作 .icns
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
let size: CGFloat = 1024

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 16, y: 16, width: size - 32, height: size - 32)

// 深色圆角底
let bg = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
bg.fill()

// 顶部红色渐变光带
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.18, alpha: 0.55),
    NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.18, alpha: 0.0)
])
glow?.draw(in: NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.maxY - 300, width: rect.width, height: 300),
                            xRadius: 210, yRadius: 210), angle: -90)

// 红色 R 字标
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 640, weight: .black),
    .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.18, alpha: 1),
    .paragraphStyle: para
]
let s = NSAttributedString(string: "R", attributes: attrs)
let b = s.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
s.draw(in: NSRect(x: 0, y: (size - b.height) / 2 - 60, width: size, height: b.height))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon written: \(outPath)")
