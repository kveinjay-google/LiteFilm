import Foundation

enum SelfTest {
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
