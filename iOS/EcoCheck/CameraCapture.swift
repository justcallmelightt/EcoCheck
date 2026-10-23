import AVFoundation
import SwiftUI

struct CameraPermissionIntroView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color(red: 20/255, green: 24/255, blue: 22/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onSkip) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("닫기")
                Spacer()
            }
            .foregroundStyle(ink).padding(.horizontal, 17).padding(.top, 44)
            Spacer()
            Image("HistoryMascot").resizable().scaledToFit().frame(width: 190, height: 155)
            Text("사진 한 장이면\n버리는 법을 알려드려요")
                .font(.custom("Pretendard-ExtraBold", size: 26)).multilineTextAlignment(.center)
                .lineSpacing(4).foregroundStyle(ink).padding(.top, 45)
            Text("카메라로 재질을 확인하고 분리배출 안내를 찾아볼 수 있어요.")
                .font(.custom("Pretendard-Regular", size: 15)).foregroundStyle(ink.opacity(0.75))
                .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 15)
            VStack(alignment: .leading, spacing: 13) {
                Label("촬영한 사진을 확인한 뒤 분석을 시작할 수 있어요", systemImage: "checkmark")
                Label("카메라 사용은 원할 때만 허용하면 돼요", systemImage: "checkmark")
            }
            .font(.custom("Pretendard-Medium", size: 14)).labelStyle(CameraCheckLabelStyle())
            .padding(.top, 35)
            Spacer(minLength: 20)
            Button(action: onAllow) {
                Text("카메라 켜기").font(.custom("Pretendard-SemiBold", size: 16))
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56)
                    .background(ink, in: Capsule())
            }
            .buttonStyle(CameraIntroButtonStyle(reduceMotion: reduceMotion)).padding(.horizontal, 29)
            Button("나중에 할게요", action: onSkip)
                .font(.custom("Pretendard-SemiBold", size: 15)).foregroundStyle(.secondary)
                .frame(height: 52).padding(.bottom, 20)
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private struct CameraCheckLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 10) { configuration.icon.foregroundStyle(Color.green); configuration.title }
        }
    }
    private struct CameraIntroButtonStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
        }
    }
}

struct CameraCapture: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = EcoCameraModel()
    let onPhoto: (Data) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                        Spacer()
                        Button { camera.flashEnabled.toggle() } label: {
                            Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(camera.flashEnabled ? "플래시 끄기" : "플래시 켜기")
                    }
                    .font(.system(size: 22, weight: .medium))
                    .padding(.horizontal, 17 * scale)
                    .padding(.top, max(48 * scale, geometry.safeAreaInsets.top + 10))
                    Text("쓰레기를 화면 안에 맞춰주세요")
                        .font(.custom("Pretendard-Medium", size: 18 * scale))
                        .padding(.top, 25 * scale)
                    Spacer()
                    ScanGuideCorners()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                        .frame(width: 280 * scale, height: 292 * scale)
                    Spacer()
                    Button { camera.capture() } label: {
                        Circle().fill(.white).frame(width: 90 * scale, height: 90 * scale)
                            .overlay {
                                Circle().stroke(Color(red: 164/255, green: 214/255, blue: 114/255), lineWidth: 3 * scale)
                                    .padding(9 * scale)
                            }
                    }
                    .buttonStyle(CameraPressStyle())
                    .disabled(camera.isCapturing)
                    .accessibilityLabel("사진 촬영")
                    Text("한번에 하나씩 촬영하면\n더 정확하게 분석할 수 있어요")
                        .font(.custom("Pretendard-Medium", size: 18 * scale))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * scale)
                        .padding(.top, 20 * scale)
                        .padding(.bottom, max(59 * scale, geometry.safeAreaInsets.bottom + 25))
                }
                .foregroundStyle(.white)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onAppear { camera.onPhoto = { onPhoto($0); dismiss() }; camera.start() }
        .onDisappear { camera.stop() }
        .alert("카메라를 시작하지 못했어요", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("닫기") { dismiss() }
        } message: { Text(camera.error ?? "") }
    }
}

private struct CameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}

private struct ScanGuideCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        let radius: CGFloat = 15
        var path = Path()
        path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero); path.addLine(to: CGPoint(x: length, y: 0))
        path.move(to: CGPoint(x: rect.maxX - length, y: 0)); path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: length, y: rect.maxY)); path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - length))
        return path
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
        view.previewLayer.videoGravity = .resizeAspectFill
        view.setNeedsLayout()
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        let preview = layer as! AVCaptureVideoPreviewLayer
        return preview
    }
}

@MainActor private final class EcoCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var flashEnabled = false
    @Published var isCapturing = false
    @Published var error: String?
    var onPhoto: ((Data) -> Void)?
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "kr.ecocheck.camera")

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                    Task { @MainActor in self.error = "카메라를 사용할 수 없어요." }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
    func stop() { queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } } }
    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashEnabled && output.supportedFlashModes.contains(.on) ? .on : .off
        output.capturePhoto(with: settings, delegate: self)
    }
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.isCapturing = false
            if let data { self.onPhoto?(data) }
            else { self.error = error?.localizedDescription ?? "사진을 저장하지 못했어요." }
        }
    }
}
