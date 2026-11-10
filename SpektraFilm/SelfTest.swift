import Foundation
import CoreGraphics

enum SelfTest {
    static func meanLuma(_ image: CGImage) -> Double {
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return stride(from: 0, to: pixels.count, by: 4).reduce(0.0) {
            $0 + 0.2126 * Double(pixels[$1]) + 0.7152 * Double(pixels[$1 + 1]) + 0.0722 * Double(pixels[$1 + 2])
        } / 4096
    }

    static func run() -> Int32 {
        logLine("SPEKTRAFILM_SELFTEST_START")
        do {
            guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil) else {
                logLine("SPEKTRAFILM_SELFTEST_FAIL missing engine resources")
                return 1
            }
            let metallib = resources.appendingPathComponent("spektrafilm.metallib")
            let constants = resources.appendingPathComponent("spektrafilm_constants.bin")
            let portra = resources.appendingPathComponent("profiles/kodak_portra_400.json")
            guard FileManager.default.fileExists(atPath: metallib.path),
                  FileManager.default.fileExists(atPath: constants.path),
                  FileManager.default.fileExists(atPath: portra.path)
            else {
                logLine("SPEKTRAFILM_SELFTEST_FAIL engine bundle is incomplete")
                return 1
            }
            guard let sampleURL = Bundle.main.url(forResource: "SampleBars", withExtension: "png") else {
                logLine("SPEKTRAFILM_SELFTEST_FAIL missing sample")
                return 1
            }
            let data = try Data(contentsOf: sampleURL)
            let frame = try ImageCodec.decode(data, maxLongEdge: 480)
            logLine("SPEKTRAFILM_SELFTEST_FRAME \(frame.width)x\(frame.height)")
            let engine = EngineClient()
            try engine.start(resources: resources)
            let params = RenderParams(
                film: "kodak_portra_400",
                paper: "kodak_portra_endura",
                exposureEV: 0,
                previewLongEdge: 800
            )
            let rendered = try engine.renderPreview(frame: frame, params: params)
            let spread = ImageCodec.lumaSpread(rendered.image)
            logLine(String(format: "SPEKTRAFILM_SELFTEST_RENDER %dx%d elapsed_ms=%.1f luma_stddev=%.2f",
                           rendered.width, rendered.height, rendered.elapsedMS, spread))
            guard rendered.width > 0, rendered.height > 0, spread > 2 else {
                logLine("SPEKTRAFILM_SELFTEST_FAIL render has no tonal variation")
                return 1
            }
            var brightParams = params
            brightParams.exposureEV = 1
            let bright = try engine.renderAgain(params: brightParams)
            brightParams.exposureEV = -1
            let dark = try engine.renderAgain(params: brightParams)
            let levels = [meanLuma(dark.image), meanLuma(rendered.image), meanLuma(bright.image)]
            logLine("LITEFILM_EXPOSURE_LEVELS \(levels)")
            guard levels[0] < levels[1] * 0.88, levels[2] > levels[1] * 1.12 else {
                throw EngineError.message("Exposure +/-1 EV must visibly change final photo brightness")
            }
            try AdjustmentSelfTest.run()
            let jpeg = try ImageCodec.write(rendered.image, format: .jpeg)
            let png = try ImageCodec.write(rendered.image, format: .png)
            let heic = try ImageCodec.write(rendered.image, format: .heic)
            for url in [jpeg, png, heic] {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size > 500 else {
                    logLine("SPEKTRAFILM_SELFTEST_FAIL empty file \(url.lastPathComponent)")
                    return 1
                }
                logLine("SPEKTRAFILM_SELFTEST_FILE \(url.pathExtension) \(size)")
            }
            logLine("SPEKTRAFILM_SELFTEST_OK")
            return 0
        } catch {
            logLine("SPEKTRAFILM_SELFTEST_FAIL \(error.localizedDescription)")
            return 1
        }
    }
}
