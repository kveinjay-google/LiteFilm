import SwiftUI
import UIKit

struct PhotoDetailView: View {
    let image: UIImage
    var original: UIImage? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var comparing = false
    @State private var showHighlights = false
    @State private var zoom = 1.0
    @State private var resetID = 0
    @State private var analysis: PhotoAnalysisResult?
    @State private var analyzedImageID: ObjectIdentifier?
    @State private var analysisError: String?

    private var displayedImage: UIImage { comparing ? (original ?? image) : image }
    private var currentAnalysis: PhotoAnalysisResult? {
        analyzedImageID == ObjectIdentifier(displayedImage) ? analysis : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("关闭照片详情").accessibilityIdentifier("photoDetail.close")
                Text(comparing ? "原图预览" : "照片详情").font(.headline)
                Spacer()
                Text(String(format: "%.1f×", zoom)).monospacedDigit().font(.subheadline)
                    .accessibilityLabel(String(format: "缩放 %.1f 倍，相对适合屏幕", zoom))
                Button("复位") { resetID += 1 }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("photoDetail.reset")
            }
            .foregroundStyle(Ink.ivory).padding(.horizontal, 12)
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height * 1.35 {
                    HStack(spacing: 0) {
                        photo
                        controls.frame(width: min(320, geometry.size.width * 0.38))
                    }
                } else {
                    VStack(spacing: 0) {
                        photo
                        controls.frame(height: min(290, geometry.size.height * 0.43))
                    }
                }
            }
        }
        .background(Ink.void).tint(Ink.amber).preferredColorScheme(.dark)
        .task(id: ObjectIdentifier(displayedImage)) {
            let source = displayedImage
            let identity = ObjectIdentifier(source)
            analysis = nil; analyzedImageID = nil; analysisError = nil
            do {
                let result = try await PhotoAnalysisWorker.shared.analyze(source)
                try Task.checkCancellation()
                analysis = result; analyzedImageID = identity
            } catch is CancellationError {
                // SwiftUI cancels the old task when comparison changes or this view closes.
            } catch {
                guard !Task.isCancelled else { return }
                analysisError = error.localizedDescription
            }
        }
    }

    private var photo: some View {
        PhotoZoomSurface(image: displayedImage,
            overlay: showHighlights ? currentAnalysis?.highlightOverlay : nil,
            resetID: resetID, zoom: $zoom)
            .clipped()
            .accessibilityIdentifier("photoDetail.image")
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Button {
                        comparing.toggle()
                    } label: {
                        Label(comparing ? "返回效果" : "查看原图", systemImage: "circle.lefthalf.filled")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Ink.hairline, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(original == nil)
                    .accessibilityValue(comparing ? "当前为原图" : "当前为处理效果")
                    .accessibilityIdentifier("photoDetail.compare")
                }
                Toggle("高光溢出提示", isOn: $showHighlights)
                    .font(.subheadline).accessibilityIdentifier("photoDetail.highlights")
                if let result = currentAnalysis {
                    PhotoAnalysisPanel(result: result)
                } else if let analysisError {
                    Text(analysisError).font(.caption).foregroundStyle(Ink.ember)
                } else {
                    ProgressView("正在分析预览…").font(.caption).frame(maxWidth: .infinity, minHeight: 70)
                }
                Text("预览 \(Int(displayedImage.size.width * displayedImage.scale)) × \(Int(displayedImage.size.height * displayedImage.scale)) · 双指缩放，双击放大/复位。1× 为适合屏幕；放大不会增加原片细节。")
                    .font(.caption).foregroundStyle(Ink.mute).fixedSize(horizontal: false, vertical: true)
            }.padding(16)
        }
        .background(Ink.surface)
    }
}

struct PhotoAnalysisPanel: View {
    let result: PhotoAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("亮度直方图").font(.subheadline.weight(.medium))
                Spacer()
                Text("0 — 255").font(.caption).foregroundStyle(Ink.mute)
            }
            Canvas { context, size in
                let peak = max(1, result.histogram.max() ?? 1)
                let step = size.width / 256
                var path = Path()
                for (index, count) in result.histogram.enumerated() where count > 0 {
                    let height = CGFloat(count) / CGFloat(peak) * size.height
                    path.addRect(CGRect(x: CGFloat(index) * step, y: size.height - height,
                        width: max(0.5, step), height: height))
                }
                context.fill(path, with: .color(Ink.amber))
            }
            .frame(height: 48)
            .background(Ink.void)
            .accessibilityLabel("预览亮度分布，左侧为黑，右侧为白")
            .accessibilityValue(String(format: "黑位 %.1f%%，高光通道接近上限 %.1f%%", result.shadowPercent, result.highlightPercent))
            HStack {
                Text(String(format: "黑位 %.1f%%", result.shadowPercent))
                Spacer()
                Text(String(format: "高光 %.1f%%", result.highlightPercent))
            }.font(.caption.monospacedDigit()).foregroundStyle(Ink.ivory)
            Text("按 \(result.width) × \(result.height) 预览采样；任一 RGB 通道 ≥254 标红，仅作提示，不写入导出。")
                .font(.caption2).foregroundStyle(Ink.mute).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Ink.ivory)
    }
}

private struct PhotoZoomSurface: UIViewRepresentable {
    let image: UIImage
    let overlay: CGImage?
    let resetID: Int
    @Binding var zoom: Double

    func makeUIView(context: Context) -> DetailZoomView {
        let view = DetailZoomView()
        view.onZoom = { value in
            DispatchQueue.main.async { zoom = value }
        }
        view.setImage(image, overlay: overlay)
        return view
    }

    func updateUIView(_ uiView: DetailZoomView, context: Context) {
        uiView.onZoom = { value in
            DispatchQueue.main.async { zoom = value }
        }
        uiView.setImage(image, overlay: overlay)
        if uiView.resetID != resetID {
            uiView.resetID = resetID
            uiView.resetZoom(animated: true)
        }
    }
}

/// The image and diagnostic mask share one zoomable canvas, so pan and zoom cannot
/// detach the clipping indication from the pixels it describes.
private final class DetailZoomView: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let canvas = UIView()
    let imageView = UIImageView()
    let overlayView = UIImageView()
    var onZoom: ((Double) -> Void)?
    var resetID = 0
    private var imageIdentity: ObjectIdentifier?
    private var overlayIdentity: ObjectIdentifier?
    private var previousSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Ink.void)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1; scrollView.maximumZoomScale = 8
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true
        addSubview(scrollView)
        scrollView.addSubview(canvas)
        canvas.addSubview(imageView); canvas.addSubview(overlayView)
        imageView.contentMode = .scaleToFill
        overlayView.contentMode = .scaleToFill
        overlayView.layer.magnificationFilter = .nearest
        overlayView.layer.minificationFilter = .nearest
        overlayView.isUserInteractionEnabled = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "照片预览"
        imageView.accessibilityHint = "双指缩放或双击放大；可使用复位按钮恢复全图"
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大", target: self, selector: #selector(detailAccessibilityZoomIn)),
            UIAccessibilityCustomAction(name: "复位", target: self, selector: #selector(detailAccessibilityReset))
        ]
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage, overlay: CGImage?) {
        let identity = ObjectIdentifier(image)
        if identity != imageIdentity {
            imageIdentity = identity
            imageView.image = image
            previousSize = .zero
            setNeedsLayout()
        }
        let maskIdentity = overlay.map { ObjectIdentifier($0) }
        if maskIdentity != overlayIdentity {
            overlayIdentity = maskIdentity
            overlayView.image = overlay.map { UIImage(cgImage: $0) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        scrollView.frame = bounds
        guard previousSize != bounds.size, let image = imageView.image else { return }
        previousSize = bounds.size
        // A geometry change (rotation / split view / original aspect) deliberately
        // returns to fit, avoiding inaccessible offsets from the previous layout.
        scrollView.setZoomScale(1, animated: false)
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        canvas.frame = CGRect(origin: .zero, size: size)
        imageView.frame = canvas.bounds; overlayView.frame = canvas.bounds
        scrollView.contentSize = size
        centerCanvas()
        scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        onZoom?(1)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerCanvas()
        onZoom?(Double(scrollView.zoomScale))
    }

    private func centerCanvas() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(1, animated: animated)
        if !animated || abs(scrollView.zoomScale - 1) < 0.001 {
            centerCanvas()
            scrollView.setContentOffset(CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top), animated: animated)
        }
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.05 { resetZoom(animated: true); return }
        let point = recognizer.location(in: canvas)
        let target: CGFloat = 3
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
            width: size.width, height: size.height), animated: true)
    }

    @objc private func detailAccessibilityZoomIn() -> Bool {
        scrollView.setZoomScale(min(8, scrollView.zoomScale * 2), animated: true)
        return true
    }

    @objc private func detailAccessibilityReset() -> Bool {
        resetZoom(animated: true)
        return true
    }
}
