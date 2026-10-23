import PhotosUI
import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingPreview = false
    @State private var showingSource = false
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingMap = false
    @State private var photoError: String?
    @State private var loadTask: Task<Void, Never>?

    private let background = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Image("EcoCheckLogo")
                        .resizable().scaledToFit()
                        .frame(width: 172, height: 57)
                        .accessibilityLabel("EcoCheck")
                    Spacer()
                }
                Text("HI, USER!")
                    .font(.custom("Pretendard-Medium", size: 20))
                    .tracking(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 15)
                    .padding(.top, 8)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 8) {
                            Capsule()
                                .fill(LinearGradient(colors: [lime, .clear], startPoint: .top, endPoint: .bottom))
                                .frame(width: 9, height: 56).padding(.top, 9)
                            Text("0g")
                                .font(.custom("Pretendard-ExtraBold", size: 73))
                                .tracking(-1.5)
                        }
                        Text("지금까지\n절약한 CO₂")
                            .font(.custom("Pretendard-SemiBold", size: 17))
                            .foregroundStyle(.gray)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.leading, 22)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .leading, spacing: 18) {
                        metric("leaf", "0", "리사이클")
                        metric("dollarsign.circle", "0", "포인트")
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 42)
                .padding(.horizontal, 9)

                Image("HomeBottle")
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Button { showingSource = true } label: {
                    HStack {
                        Text("지금 스캔하고\n분리배출을 확인해보세요!")
                            .font(.custom("Pretendard-SemiBold", size: 21))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 28))
                            .frame(width: 60, height: 60)
                            .background(.white.opacity(0.13), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color(red: 30/255, green: 32/255, blue: 31/255), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("촬영하거나 사진을 선택해 분리배출 확인하기")
                .padding(.horizontal, 4)

                HStack {
                    tab("house.fill", "홈", selected: true)
                    Button { showingHistory = true } label: { tab("clock.fill", "기록") }
                        .buttonStyle(.plain)
                    Button { showingSource = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 31))
                                .frame(width: 61, height: 61)
                                .background(lime, in: Circle())
                            Text("스캔").font(.custom("Pretendard-Medium", size: 12))
                        }
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("스캔할 사진 선택")
                    Button { showingMap = true } label: { tab("mappin", "지도") }
                        .buttonStyle(.plain)
                    Button { showingSettings = true } label: { tab("person", "설정") }
                        .buttonStyle(.plain)
                }
                .frame(height: 90)
                .background(.white, in: RoundedRectangle(cornerRadius: 25))
                .padding(.top, 15)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                Group {
                    if let photoData { ScanResultView(imageData: photoData) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showingPreview = false }
                            .font(.custom("Pretendard-Medium", size: 16))
                    }
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack { HistoryView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showingHistory = false } } } }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { ServerSettingsView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showingSettings = false } } } }
        }
        .sheet(isPresented: $showingMap) {
            NavigationStack { BinMapView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showingMap = false } } } }
        }
        .sheet(isPresented: $showingCamera, onDismiss: {
            if photoData != nil { showingPreview = true }
        }) {
            CameraCapture { photoData = $0 }.ignoresSafeArea()
        }
        .confirmationDialog("스캔할 사진 가져오기", isPresented: $showingSource, titleVisibility: .visible) {
            Button("카메라로 촬영") { Task { await openCamera() } }
            Button("앨범에서 선택") { showingPhotoLibrary = true }
            Button("취소", role: .cancel) { }
        }
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $selectedPhoto, matching: .images)
        .alert("사진을 가져오지 못했어요", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("확인") { photoError = nil }
        } message: { Text(photoError ?? "") }
        .onChange(of: selectedPhoto) { _, newPhoto in
            guard let newPhoto else { return }
            loadTask?.cancel()
            loadTask = Task {
                do {
                    guard let data = try await newPhoto.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                        photoError = "다른 사진을 선택해주세요."; return
                    }
                    try Task.checkCancellation()
                    photoData = data
                    showingPreview = true
                    selectedPhoto = nil
                } catch is CancellationError { }
                catch { photoError = "사진을 읽지 못했어요. 다시 선택해주세요." }
            }
        }
    }

    @MainActor private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            photoError = "이 기기에서는 카메라를 사용할 수 없어요. 앨범에서 선택해주세요."; return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { allowed = status == .authorized }
        guard allowed else {
            photoError = "아이폰 설정에서 EcoCheck의 카메라 접근을 허용해주세요."; return
        }
        photoData = nil
        showingCamera = true
    }

    private func metric(_ symbol: String, _ value: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 31, height: 31)
                .background(lime.opacity(0.35), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.custom("Pretendard-Bold", size: 30))
                Text(title).font(.custom("Pretendard-SemiBold", size: 15)).foregroundStyle(.gray)
            }
        }
    }

    private func tab(_ symbol: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 27)).frame(height: 39)
            Text(title).font(.custom("Pretendard-Medium", size: 12))
        }
        .foregroundStyle(selected ? Color.black : Color.gray)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
