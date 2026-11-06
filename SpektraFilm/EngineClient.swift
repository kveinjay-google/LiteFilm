import CoreGraphics
import Foundation
import UIKit

struct RenderParams: Equatable, Sendable {
    var film: String
    var paper: String
    var exposureEV: Double
    var previewLongEdge: Int

    func jsonString() throws -> String {
        let object: [String: Any] = [
            "film_stock": film,
            "print_stock": paper,
            "input_color_space": "Display P3",
            "input_cctf_decoding": true,
            "output_color_space": "Display P3",
            "output_cctf_encoding": true,
            "preview_long_edge": previewLongEdge,
            "exposure_compensation_ev": exposureEV,
            "auto_exposure": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw EngineError.message("参数序列化失败。")
        }
        return text
    }
}

struct Rendered: @unchecked Sendable {
    var image: CGImage
    var width: Int
    var height: Int
    var elapsedMS: Double
}

/// One SpektraLab engine, one open frame. Every C call stays on `queue`.
final class EngineClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "spektrafilm.engine")
    private var engine: OpaquePointer?
    private var session: OpaquePointer?
    private var previewFrame: FrameBuffer?
    private var previewParams: RenderParams?

    func start(resources: URL) throws {
        try sync {
            if self.engine != nil { return }
            let path = resources.path
            var created: OpaquePointer?
            path.withCString { created = spk_engine_create($0, nil) }
            guard let created else {
                throw EngineError.message(self.failure("引擎没有启动"))
            }
            self.engine = created
        }
    }

    func renderPreview(frame: FrameBuffer, params: RenderParams) throws -> Rendered {
        try sync {
            self.previewFrame = frame
            self.previewParams = params
            try self.openSession(frame: frame, params: params)
            return try self.render(tier: "live")
        }
    }

    func renderAgain(params: RenderParams) throws -> Rendered {
        try sync {
            guard let frame = self.previewFrame else {
                throw EngineError.message("还没有画面。")
            }
            self.previewParams = params
            if self.session == nil {
                try self.openSession(frame: frame, params: params)
            } else {
                try self.apply(params)
            }
            return try self.render(tier: "live")
        }
    }

    /// Renders `full` on a frame that is already the export resolution, then
    /// drops that session. The next preview call reopens the small frame.
    func export(frame: FrameBuffer, params: RenderParams) throws -> Rendered {
        try sync {
            self.closeSession()
            do {
                try self.openSession(frame: frame, params: params)
                let rendered = try self.render(tier: "full")
                self.closeSession()
                return rendered
            } catch {
                self.closeSession()
                throw error
            }
        }
    }

    private func openSession(frame: FrameBuffer, params: RenderParams) throws {
        guard let engine else { throw EngineError.message("引擎没有启动。") }
        closeSession()
        guard frame.width > 0, frame.height > 0, frame.pixels.count >= frame.width * frame.height * 3 else {
            throw EngineError.message("画面缓冲是空的。")
        }
        let json = try params.jsonString()
        var opened: OpaquePointer?
        try frame.pixels.withUnsafeBufferPointer { buffer in
            var image = spk_image(
                data: buffer.baseAddress,
                width: UInt32(frame.width),
                height: UInt32(frame.height),
                channels: 3
            )
            try json.withCString { cString in
                var outJSON: UnsafeMutablePointer<CChar>?
                opened = spk_open(engine, &image, cString, &outJSON)
                if let outJSON {
                    spk_string_free(outJSON)
                }
            }
        }
        guard let opened else {
            throw EngineError.message(failure("打开画面失败"))
        }
        session = opened
    }

    private func apply(_ params: RenderParams) throws {
        guard let session else { throw EngineError.message("没有打开的画面。") }
        let json = try params.jsonString()
        let status: Int32 = try json.withCString { cString in
            var outJSON: UnsafeMutablePointer<CChar>?
            let status = spk_set_params(session, cString, &outJSON)
            if let outJSON {
                spk_string_free(outJSON)
            }
            return status
        }
        guard status == SPK_OK else {
            throw EngineError.message(failure("参数没有写上"))
        }
    }

    private func render(tier: String) throws -> Rendered {
        guard let session else { throw EngineError.message("没有打开的画面。") }
        var result = spk_result()
        let status = tier.withCString { spk_render(session, $0, &result) }
        guard status == SPK_OK, let pixels = result.rgba16 else {
            let message = failure("渲染失败")
            spk_result_free(&result)
            throw EngineError.message(message)
        }
        let rendered: Rendered
        do {
            let image = try ImageCodec.cgImage(
                rgba16: pixels,
                width: Int(result.width),
                height: Int(result.height),
                rowStride: Int(result.row_stride_px)
            )
            rendered = Rendered(
                image: image,
                width: Int(result.width),
                height: Int(result.height),
                elapsedMS: result.elapsed_ms
            )
        } catch {
            spk_result_free(&result)
            throw error
        }
        spk_result_free(&result)
        return rendered
    }

    private func closeSession() {
        if let session {
            spk_session_release(session)
            self.session = nil
        }
    }

    private func failure(_ fallback: String) -> String {
        let text = String(cString: spk_last_error(engine))
        return text.isEmpty ? fallback : text
    }

    private func sync<T>(_ body: () throws -> T) throws -> T {
        try queue.sync {
            try autoreleasepool(invoking: body)
        }
    }
}

enum EngineError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
