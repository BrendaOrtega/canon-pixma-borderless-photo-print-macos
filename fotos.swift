// fotos — imprime fotos a tamaño estándar (4x6, 5x7...) sin bordes en la Canon G500.
// Recorta con detección de caras/personas para no cortar cabezas, genera PDF de
// tamaño exacto y lo manda con lp (sin fit-to-page: AirPrint sacaba hojas en blanco).
import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers

let sizes: [String: (Double, Double)] = [
    "4x6": (4, 6), "5x7": (5, 7), "3.5x5": (3.5, 5), "5x5": (5, 5), "8x10": (8, 10),
]
let papers: [String: String] = [
    "glossy2": "com.canon.mtgr", "glossy": "com.canon.mtglossy",
    "matte": "com.canon.mtmat", "plain": "stationery",
]

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    print("""
    uso: fotos [opciones] foto1.jpg foto2.jpg ...
      --size 4x6|5x7|3.5x5|5x5|8x10   tamaño del papel (default 4x6)
      --paper glossy2|glossy|matte|plain  tipo de papel (default glossy2)
      --preview        genera PDF y hoja de contacto y los abre, no imprime
      --printer NOMBRE impresora (default: la predeterminada)
      --out DIR        dónde guardar el PDF (default: carpeta temporal)
    """)
    exit(0)
}

// MARK: argumentos

var sizeName = "4x6", paperName = "glossy2", preview = false
var printer: String?, outDir: String?
var files: [String] = []
var args = CommandLine.arguments.dropFirst().makeIterator()
func value() -> String { if let v = args.next() { return v }; usage() }
while let a = args.next() {
    switch a {
    case "--size": sizeName = value()
    case "--paper": paperName = value()
    case "--printer": printer = value()
    case "--out": outDir = value()
    case "--preview": preview = true
    case "-h", "--help": usage()
    default: files.append(a)
    }
}
if files.isEmpty { usage() }
guard let (pw, ph) = sizes[sizeName] else { die("tamaño no válido: \(sizeName)") }
guard let mediaType = papers[paperName] else { die("papel no válido: \(paperName)") }

// MARK: imagen

func load(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int else { die("no pude leer \(path)") }
    // La miniatura a tamaño completo aplica la orientación EXIF.
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(w, h),
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { die("no pude leer \(path)") }
    return img
}

func rotate90(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: CGFloat(h), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

// Cajas de caras y personas en píxeles, origen arriba-izquierda.
func detect(_ img: CGImage) -> (faces: [CGRect], people: [CGRect]) {
    let faceReq = VNDetectFaceRectanglesRequest()
    let humanReq = VNDetectHumanRectanglesRequest()
    humanReq.upperBodyOnly = false
    try? VNImageRequestHandler(cgImage: img).perform([faceReq, humanReq])
    let W = CGFloat(img.width), H = CGFloat(img.height)
    func px(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * W, y: (1 - r.maxY) * H, width: r.width * W, height: r.height * H)
    }
    return ((faceReq.results ?? []).map { px($0.boundingBox) },
            (humanReq.results ?? []).map { px($0.boundingBox) })
}

// Posición de una ventana de largo `len` sobre un eje de largo `total`.
// keep: rango que debe quedar dentro si cabe; must: rango prioritario (cabezas).
func place(len: CGFloat, total: CGFloat, keep: ClosedRange<CGFloat>?, must: ClosedRange<CGFloat>?, headsFirst: Bool) -> CGFloat {
    func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), total - len) }
    guard let keep else { return clamp((total - len) / 2) }
    if keep.upperBound - keep.lowerBound <= len {
        return clamp((keep.lowerBound + keep.upperBound - len) / 2)
    }
    guard let must else { return clamp(headsFirst ? keep.lowerBound : (keep.lowerBound + keep.upperBound - len) / 2) }
    // No cabe todo: cabezas completas arriba, se sacrifican los pies.
    return clamp(headsFirst ? must.lowerBound : (must.lowerBound + must.upperBound - len) / 2)
}

func smartCrop(_ img: CGImage, ratio: CGFloat) -> CGImage {
    let W = CGFloat(img.width), H = CGFloat(img.height)
    let (faces, people) = detect(img)
    // Margen sobre la cara para incluir el pelo.
    let heads = faces.map { $0.insetBy(dx: -$0.width * 0.3, dy: 0).offsetBy(dx: 0, dy: -$0.height * 0.5)
        .union($0) }
    let all = heads + people
    let crop: CGRect
    if W / H > ratio {
        let cw = (H * ratio).rounded(.down)
        let keep = all.isEmpty ? nil : all.map(\.minX).min()!...all.map(\.maxX).max()!
        let must = heads.isEmpty ? nil : heads.map(\.minX).min()!...heads.map(\.maxX).max()!
        crop = CGRect(x: place(len: cw, total: W, keep: keep, must: must, headsFirst: false), y: 0, width: cw, height: H)
    } else {
        let ch = (W / ratio).rounded(.down)
        let keep = all.isEmpty ? nil : all.map(\.minY).min()!...all.map(\.maxY).max()!
        let must = heads.isEmpty ? nil : heads.map(\.minY).min()!...heads.map(\.maxY).max()!
        crop = CGRect(x: 0, y: place(len: ch, total: H, keep: keep, must: must, headsFirst: true), width: W, height: ch)
    }
    return img.cropping(to: crop.integral.intersection(CGRect(x: 0, y: 0, width: W, height: H)))!
}

// MARK: proceso

let pageW = pw * 72, pageH = ph * 72
let ratio = CGFloat(pw / ph)
let dir = URL(fileURLWithPath: outDir ?? NSTemporaryDirectory() + "fotos-\(Int(Date().timeIntervalSince1970))")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let pdfURL = dir.appendingPathComponent("fotos-\(sizeName).pdf")
var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
guard let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else { die("no pude crear el PDF") }

var crops: [CGImage] = []
for f in files {
    var img = load(f)
    if pw != ph && img.width > img.height { img = rotate90(img) }
    let c = smartCrop(img, ratio: ratio)
    crops.append(c)
    pdf.beginPDFPage(nil)
    pdf.interpolationQuality = .high
    pdf.draw(c, in: mediaBox)
    pdf.endPDFPage()
    print("✓ \((f as NSString).lastPathComponent)")
}
pdf.closePDF()

// Hoja de contacto para revisar los recortes.
let tw = 240, th = Int(Double(tw) * ph / pw), cols = min(5, crops.count), gap = 10
let rows = (crops.count + cols - 1) / cols
let sheetW = cols * (tw + gap) + gap, sheetH = rows * (th + gap) + gap
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(gray: 1, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
sheet.interpolationQuality = .high
for (i, c) in crops.enumerated() {
    let x = gap + (i % cols) * (tw + gap)
    let y = sheetH - (gap + (i / cols + 1) * (th + gap)) + gap
    sheet.draw(c, in: CGRect(x: x, y: y, width: tw, height: th))
}
let sheetURL = dir.appendingPathComponent("vista-previa.png")
if let dest = CGImageDestinationCreateWithURL(sheetURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, sheet.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
print("PDF: \(pdfURL.path)")
print("Vista previa: \(sheetURL.path)")

func run(_ cmd: String, _ argv: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmd)
    p.arguments = argv
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

if preview {
    _ = run("/usr/bin/open", [sheetURL.path])
} else {
    var argv = ["-o", "PageSize=\(sizeName).Fullbleed", "-o", "MediaType=\(mediaType)", pdfURL.path]
    if let printer { argv = ["-d", printer] + argv }
    exit(run("/usr/bin/lp", argv))
}
