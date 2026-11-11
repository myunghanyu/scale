// swift icon.swift out.png → 1024×1024 1-bit pixel-art app icon (40×40 cells of 20px, Apple 100px margin)
import CoreGraphics
import Foundation
import ImageIO

let n = 40, cell = 20, off = (1024 - n * cell) / 2
var g = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)  // 0 clear, 1 paper, 2 ink

func inside(_ x: Int, _ y: Int, inset: Int, r: Int) -> Bool {
    let lo = inset, hi = n - 1 - inset
    guard x >= lo, x <= hi, y >= lo, y <= hi else { return false }
    let cx = min(max(x, lo + r), hi - r), cy = min(max(y, lo + r), hi - r)
    return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
}
for y in 0..<n { for x in 0..<n where inside(x, y, inset: 0, r: 8) { g[y][x] = inside(x, y, inset: 2, r: 6) ? 1 : 2 } }

func ink(_ x: Int, _ y: Int, _ v: Int = 2) { g[y + 4][x + 4] = v }  // scene is 32×32 at (4,4)
func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ v: Int = 2) { for j in 0..<h { for i in 0..<w { ink(x + i, y + j, v) } } }
func sprite(_ rows: [String], _ x: Int, _ y: Int) {
    for (j, r) in rows.enumerated() { for (i, c) in r.enumerated() { if c == "#" { ink(x + i, y + j) } else if c == "o" { ink(x + i, y + j, 1) } } }
}
func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    let steps = max(abs(x1 - x0), abs(y1 - y0))
    for s in 0...steps {
        let q = Double(s) / Double(steps)
        ink(x0 + Int((Double(x1 - x0) * q).rounded()), y0 + Int((Double(y1 - y0) * q).rounded()))
    }
}

rect(8, 28, 16, 2); rect(10, 26, 12, 2)          // base
rect(15, 9, 2, 17)                               // pillar
rect(3, 8, 26, 2)                                // beam
for ex in [5, 26] {                              // strings + pans
    line(ex, 10, ex - 5, 19); line(ex, 10, ex + 5, 19)
    rect(ex - 5, 20, 11, 1); rect(ex - 4, 21, 9, 1)
}
sprite([".###.", ".#o#.", "#####", "#####", "#####"], 3, 15)                       // goal weight
for (x, y) in [(23, 18), (27, 18), (25, 16)] { sprite(["o##", "###"], x, y) }      // ore pile
sprite([".####.", "######", "#o##o#", "######", "#o##o#", "##oo##", ".####."], 13, 5)  // face

let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for y in 0..<n { for x in 0..<n where g[y][x] != 0 {
    ctx.setFillColor(g[y][x] == 2 ? CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1) : CGColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1))
    ctx.fill(CGRect(x: off + x * cell, y: 1024 - off - (y + 1) * cell, width: cell, height: cell))
} }
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
