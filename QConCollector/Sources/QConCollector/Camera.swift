import AVFoundation
import SwiftUI
import UIKit

struct ZoomPreset: Identifiable, Equatable {
    let label: String
    let factor: CGFloat
    var id: String { label }
}

/// Embedded camera: AVCaptureSession + AVCapturePhotoOutput, one tap per photo, JPEG.
/// All session work runs on `queue`; published state changes on the main queue.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Status { case idle, running, denied, unavailable }

    @Published var status: Status = .idle
    @Published var presets: [ZoomPreset] = []
    @Published var zoom: CGFloat = 1
    private var zoomRange: ClosedRange<CGFloat> = 1...10

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private let queue = DispatchQueue(label: "collector.camera")
    private var configured = false
    private var pending: [Int64: (Data?) -> Void] = [:]   // main queue only

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.startSession() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func startSession() {
        queue.async {
            if !self.configured { self.configure() }
            guard self.configured else {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.status = running ? .running : .unavailable }
        }
    }

    /// Runs on `queue`.
    private func configure() {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera,
                                                    .builtInDualCamera, .builtInWideAngleCamera]
        var found: AVCaptureDevice? = nil
        for t in types {
            if let d = AVCaptureDevice.default(t, for: .video, position: .back) { found = d; break }
        }
        guard let dev = found, let input = try? AVCaptureDeviceInput(device: dev) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        device = dev

        // Zoom presets in "camera app" terms: 1x is the wide lens. On virtual devices with an
        // ultra-wide, zoom factor 1.0 is the ultra-wide, so 1x is the first switch-over factor.
        let switches = dev.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let hasUltraWide = dev.deviceType == .builtInTripleCamera || dev.deviceType == .builtInDualWideCamera
        let base: CGFloat = hasUltraWide ? (switches.first ?? 1) : 1
        var list = [ZoomPreset(label: "1×", factor: base), ZoomPreset(label: "2×", factor: base * 2)]
        let hasTele = dev.deviceType == .builtInTripleCamera || dev.deviceType == .builtInDualCamera
        if hasTele, let tele = switches.last, tele > base * 2.1 {
            list.append(ZoomPreset(label: "\(Int((tele / base).rounded()))×", factor: tele))
        }
        let maxZoom = dev.maxAvailableVideoZoomFactor
        list = list.filter { $0.factor <= maxZoom }
        applyZoom(base, on: dev)
        configured = true
        let upper = max(base, min(maxZoom, base * 15))
        DispatchQueue.main.async {
            self.presets = list
            self.zoom = base
            self.zoomRange = base...upper
        }
    }

    private func applyZoom(_ factor: CGFloat, on dev: AVCaptureDevice) {
        let f = min(max(factor, dev.minAvailableVideoZoomFactor), dev.maxAvailableVideoZoomFactor)
        do {
            try dev.lockForConfiguration()
            dev.videoZoomFactor = f
            dev.unlockForConfiguration()
        } catch {}
    }

    func setZoom(_ factor: CGFloat) {
        let f = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)
        zoom = f
        queue.async {
            if let dev = self.device { self.applyZoom(f, on: dev) }
        }
    }

    /// Display zoom relative to the wide lens, written to the photo event.
    var displayZoom: Double {
        let base = presets.first?.factor ?? 1
        return Double((zoom / base * 10).rounded() / 10)
    }

    /// Focus and expose on a point in device coordinates (0...1), so the bright slide is metered.
    func focus(at point: CGPoint) {
        queue.async {
            guard let dev = self.device, (try? dev.lockForConfiguration()) != nil else { return }
            if dev.isFocusPointOfInterestSupported && dev.isFocusModeSupported(.continuousAutoFocus) {
                dev.focusPointOfInterest = point
                dev.focusMode = .continuousAutoFocus
            }
            if dev.isExposurePointOfInterestSupported && dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposurePointOfInterest = point
                dev.exposureMode = .continuousAutoExposure
            }
            dev.unlockForConfiguration()
        }
    }

    /// Takes one JPEG. `orientation` is read by the caller on the main thread.
    func capture(orientation: UIDeviceOrientation, completion: @escaping (Data?) -> Void) {
        guard status == .running else { completion(nil); return }
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        pending[settings.uniqueID] = completion
        let angle = CameraController.rotationAngle(for: orientation)
        queue.async {
            if let conn = self.output.connection(with: .video), conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Back camera: device landscape-left (home side right) is the sensor's native orientation (0°).
    /// VERIFY ON DEVICE: photos taken in landscape and portrait should both be upright on the PC.
    static func rotationAngle(for o: UIDeviceOrientation) -> CGFloat {
        switch o {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let id = photo.resolvedSettings.uniqueID
        DispatchQueue.main.async {
            let done = self.pending.removeValue(forKey: id)
            done?(data)
        }
    }
}

/// UIView whose layer is the preview layer; tap to focus and expose.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspect
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = previewLayer.captureDevicePointConverted(fromLayerPoint: g.location(in: self))
        onTap?(p)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var angle: CGFloat = 90
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeRight: angle = 0
        case .landscapeLeft: angle = 180
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if let c = previewLayer.connection, c.isVideoRotationAngleSupported(angle) {
            c.videoRotationAngle = angle
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView(frame: .zero)
        v.previewLayer.session = camera.session
        let cam = camera
        v.onTap = { p in cam.focus(at: p) }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setNeedsLayout()
    }
}

/// Fallback camera (architecture §11: "use UIImagePickerController and move on").
/// Enabled with Export › "Use system camera". Two taps per photo, covers the screen.
struct SystemCameraPicker: UIViewControllerRepresentable {
    let onImage: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data?) -> Void
        init(onImage: @escaping (Data?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onImage(image?.jpegData(compressionQuality: 0.8))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}
