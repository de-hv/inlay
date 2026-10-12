// Cuts a sprite sheet into the frames of an animated GIF.
//
//   gif <meta.json> <out.gif> <sprite-0.png> [<sprite-1.png> ...]
//
// meta.json: { "w": 800, "h": 540, "cols": 8, "per": 16, "delays": [ms, ...] }. A sprite is a grid of `cols` columns
// with `per` frames (the last sprite may have fewer), each of w x h points, drawn at any scale: every frame is scaled
// down to w x h pixels. Several sprites rather than a big one: a headless Chrome cuts a very tall screenshot.
//
// A small GIF89a encoder of its own rather than ImageIO: one palette for the whole animation, and every frame only
// carries the rectangle that changed, with the pixels that didn't change as transparent. For flat pictures like
// these, that is several times smaller than a GIF of full frames.
//
// Built by scripts/make-docs-images.sh with the Command Line Tools: swiftc -O gif.swift -o gif

import CoreGraphics
import Foundation
import ImageIO

struct Meta: Decodable {
    var w: Int
    var h: Int
    var cols: Int
    var per: Int
    var delays: [Int]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 4 else { fail("usage: gif <meta.json> <out.gif> <sprite-0.png> [<sprite-1.png> ...]") }
guard let metaData = FileManager.default.contents(atPath: args[1]), let meta = try? JSONDecoder().decode(Meta.self, from: metaData) else {
    fail("can't read \(args[1])")
}
let output = args[2]
let sprites: [CGImage] = args.dropFirst(3).map { path in
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("can't read \(path)") }
    return image
}
guard sprites.count == (meta.delays.count + meta.per - 1) / meta.per else { fail("\(meta.delays.count) frames don't fit in \(sprites.count) sprite(s)") }

let width = meta.w
let height = meta.h
let cellWidth = sprites[0].width / meta.cols
let cellHeight = cellWidth * height / width

/// The frame as RGB bytes (4 per pixel, the last one unused), scaled down to width x height
func pixels(ofFrame index: Int) -> [UInt8] {
    let inSprite = index % meta.per
    let cell = CGRect(x: (inSprite % meta.cols) * cellWidth, y: (inSprite / meta.cols) * cellHeight, width: cellWidth, height: cellHeight)
    guard cell.maxY <= CGFloat(sprites[index / meta.per].height), let image = sprites[index / meta.per].cropping(to: cell) else {
        fail("frame \(index) is out of its sprite")
    }
    var data = [UInt8](repeating: 0, count: width * height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

let frames = meta.delays.indices.map(pixels(ofFrame:))

// MARK: - Palette: 255 colors, counted in 5 bits per channel. The last entry is the transparent one.
// The most used colors come first (the flat surfaces and the edges of the text). The rest of the palette goes, one
// by one, to the color that is the farthest from the ones already chosen, so that a small detail in a color of
// its own (a red dot, an app icon) keeps its color

@inline(__always) func bin(_ p: [UInt8], _ i: Int) -> Int { (Int(p[i]) >> 3) << 10 | (Int(p[i + 1]) >> 3) << 5 | Int(p[i + 2]) >> 3 }

var count = [Int](repeating: 0, count: 32768)
var sum = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 32768)
for frame in frames {
    for i in stride(from: 0, to: frame.count, by: 4) {
        let b = bin(frame, i)
        count[b] += 1
        sum[b].r += Int(frame[i])
        sum[b].g += Int(frame[i + 1])
        sum[b].b += Int(frame[i + 2])
    }
}
let used = (0 ..< 32768).filter { count[$0] > 0 }.sorted { count[$0] > count[$1] }
func color(_ b: Int) -> (r: Int, g: Int, b: Int) { (sum[b].r / count[b], sum[b].g / count[b], sum[b].b / count[b]) }
func distance(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Int {
    (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
}
var chosen = Array(used.prefix(128))
var farthest = [Int: Int](uniqueKeysWithValues: used.dropFirst(128).map { b in (b, chosen.map { distance(color(b), color($0)) }.min() ?? 0) })
while chosen.count < 255, let next = farthest.max(by: { $0.value < $1.value })?.key {
    chosen.append(next)
    farthest[next] = nil
    for b in farthest.keys { farthest[b] = min(farthest[b]!, distance(color(b), color(next))) }
}
let palette: [(r: Int, g: Int, b: Int)] = chosen.map(color)
var indexOfBin = [UInt8](repeating: 0, count: 32768)
for (index, b) in chosen.enumerated() { indexOfBin[b] = UInt8(index) }
for b in used where !chosen.contains(b) { // The rest of the colors: the nearest one of the palette
    let c = color(b)
    var best = 0
    var bestDistance = Int.max
    for (index, p) in palette.enumerated() {
        let d = distance(p, c)
        if d < bestDistance { (best, bestDistance) = (index, d) }
    }
    indexOfBin[b] = UInt8(best)
}
let transparent: UInt8 = 255

// MARK: - LZW

func lzw(_ indices: [UInt8]) -> [UInt8] {
    let minCodeSize = 8
    let clear = 1 << minCodeSize
    let end = clear + 1
    var out: [UInt8] = []
    var bits: UInt32 = 0
    var bitCount = 0
    var codeSize = minCodeSize + 1
    var next = end + 1
    var table: [UInt32: Int] = [:]
    table.reserveCapacity(4096)
    func emit(_ code: Int) {
        bits |= UInt32(code) << UInt32(bitCount)
        bitCount += codeSize
        while bitCount >= 8 {
            out.append(UInt8(bits & 0xFF))
            bits >>= 8
            bitCount -= 8
        }
    }
    emit(clear)
    var prefix = Int(indices[0])
    for byte in indices.dropFirst() {
        let key = UInt32(prefix) << 8 | UInt32(byte)
        if let code = table[key] {
            prefix = code
            continue
        }
        emit(prefix)
        if next < 4096 {
            table[key] = next
            if next == 1 << codeSize { codeSize += 1 }
            next += 1
        } else {
            emit(clear)
            table.removeAll(keepingCapacity: true)
            codeSize = minCodeSize + 1
            next = end + 1
        }
        prefix = Int(byte)
    }
    emit(prefix)
    emit(end)
    if bitCount > 0 { out.append(UInt8(bits & 0xFF)) }
    return out
}

// MARK: - The file

var gif: [UInt8] = Array("GIF89a".utf8)
func word(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
gif += word(width) + word(height) + [0xF7, 0, 0] // A global palette of 256 colors
for index in 0 ..< 256 {
    let c: (r: Int, g: Int, b: Int) = index < palette.count ? palette[index] : (0, 0, 0)
    gif += [UInt8(c.r), UInt8(c.g), UInt8(c.b)]
}
gif += [0x21, 0xFF, 11] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0] // Loops forever

/// What is on the screen, as palette indices
var screen: [UInt8] = []
/// The frames to write. A frame that changes nothing only adds its delay to the previous one
var images: [(x: Int, y: Int, w: Int, h: Int, indices: [UInt8], delay: Int)] = []
for (frameIndex, frame) in frames.enumerated() {
    var indices = [UInt8](repeating: 0, count: width * height)
    for i in 0 ..< width * height { indices[i] = indexOfBin[bin(frame, i * 4)] }
    if screen.isEmpty {
        images.append((0, 0, width, height, indices, meta.delays[frameIndex]))
        screen = indices
        continue
    }
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0 ..< height {
        for x in 0 ..< width where indices[y * width + x] != screen[y * width + x] {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    if maxX < 0 {
        images[images.count - 1].delay += meta.delays[frameIndex]
        continue
    }
    let w = maxX - minX + 1
    let h = maxY - minY + 1
    var part = [UInt8](repeating: transparent, count: w * h)
    for y in 0 ..< h {
        for x in 0 ..< w {
            let i = (minY + y) * width + minX + x
            if indices[i] != screen[i] { part[y * w + x] = indices[i] }
        }
    }
    images.append((minX, minY, w, h, part, meta.delays[frameIndex]))
    screen = indices
}
for (index, image) in images.enumerated() {
    // Graphic control: keep the frame in place when the next one comes, the delay in 1/100 s, and the transparent color.
    // The first frame is a full one and has no transparent pixels
    gif += [0x21, 0xF9, 4, index == 0 ? 0x04 : 0x05] + word(max(image.delay / 10, 2)) + [transparent, 0]
    gif += [0x2C] + word(image.x) + word(image.y) + word(image.w) + word(image.h) + [0]
    gif.append(8)
    let data = lzw(image.indices)
    var offset = 0
    while offset < data.count {
        let size = min(255, data.count - offset)
        gif.append(UInt8(size))
        gif += data[offset ..< offset + size]
        offset += size
    }
    gif.append(0)
}
gif.append(0x3B)
do {
    try Data(gif).write(to: URL(fileURLWithPath: output))
} catch {
    fail("can't write \(output): \(error.localizedDescription)")
}
print("\(output): \(images.count) frames, \(width)x\(height), \(gif.count / 1024) KB")
