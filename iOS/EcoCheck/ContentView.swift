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
    @State private var showingManual = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingMap = false
    @State private var selectedTab = "홈"
    @State private var photoError: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var recycleCount = 0

    private let background = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background.ignoresSafeArea()
                homeContent(in: geometry)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .preferredColorScheme(.light)
        .task { await loadHomeMetrics() }
        .onChange(of: showingManual) { _, shown in if !shown { Task { await loadHomeMetrics() } } }
        .onChange(of: showingPreview) { _, shown in if !shown { Task { await loadHomeMetrics() } } }
        .onChange(of: showingHistory) { _, shown in if !shown { Task { await loadHomeMetrics() } } }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                Group {
                    if let photoData { ScanResultView(imageData: photoData, onScanAnother: { showingPreview = false; showingSource = true }) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showingPreview = false }
                            .font(.custom("Pretendard-Medium", size: 16))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingHistory) {
            HistoryView { destination in
                showingHistory = false
                selectedTab = destination
                if destination == "지도" { showingMap = true }
                if destination == "스캔" { showingSource = true }
                if destination == "마이페이지" { showingSettings = true }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            ServerSettingsView()
        }
        .fullScreenCover(isPresented: $showingMap) {
            BinMapView { destination in
                showingMap = false
                switch destination {
                case "기록": showingHistory = true
                case "스캔": showingSource = true
                case "마이페이지": showingSettings = true
                default: selectedTab = "홈"
                }
            }
        }
        .sheet(isPresented: $showingCamera, onDismiss: {
            if photoData != nil { showingPreview = true }
        }) {
            CameraCapture { photoData = $0 }.ignoresSafeArea()
        }
        .sheet(isPresented: $showingManual) {
            NavigationStack {
                ManualMaterialSelectionView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showingManual = false }
                    } }
            }
        }
        .confirmationDialog("스캔할 사진 가져오기", isPresented: $showingSource, titleVisibility: .visible) {
            Button("카메라로 촬영") { Task { await openCamera() } }
            Button("앨범에서 선택") { showingPhotoLibrary = true }
            Button("재질 직접 선택") { showingManual = true }
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

    private func homeContent(in geometry: GeometryProxy) -> some View {
        let scale = min(geometry.size.width / 402, geometry.size.height / 874)
        let width = geometry.size.width
        let height = geometry.size.height
        // The Figma artboard omits the iPhone's Dynamic Island. Keep its header below it.
        let headerShift: CGFloat = 40
        let logoTop = 24 + headerShift
        let hiTop = 93 + headerShift

        return ZStack(alignment: .topLeading) {
            Image("EcoCheckLogo")
                .resizable().scaledToFit().frame(width: 172 * scale, height: 57 * scale)
                .position(x: 94 * scale, y: (logoTop + 28.5) * scale)
                .accessibilityLabel("EcoCheck")

            Button { showingSettings = true } label: {
                Image("EcoBell").resizable().scaledToFit().frame(width: 25 * scale, height: 25 * scale)
                    .frame(width: 44 * scale, height: 44 * scale).contentShape(Rectangle())
            }
            .buttonStyle(HomePressStyle(reduceMotion: reduceMotion))
                .position(x: 334.5 * scale, y: (52.5 + headerShift) * scale)
            .accessibilityLabel("알림")

            Button { showingSettings = true } label: {
                Image("EcoMenu").resizable().scaledToFit().frame(width: 19 * scale, height: 16 * scale)
                    .frame(width: 36 * scale, height: 44 * scale).contentShape(Rectangle())
            }
            .buttonStyle(HomePressStyle(reduceMotion: reduceMotion))
            .position(x: 369.5 * scale, y: (53 + headerShift) * scale)
            .accessibilityLabel("메뉴와 설정")

            Text("HI, USER!")
                .font(.custom("Pretendard-Medium", size: 20 * scale)).tracking(0.6 * scale)
                .foregroundStyle(Color(red: 23/255, green: 24/255, blue: 24/255))
                .position(x: 70 * scale, y: (hiTop + 12) * scale)

            Capsule()
                .fill(LinearGradient(colors: [Color(red: 215/255, green: 255/255, blue: 121/255).opacity(0.8), background.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 9.45 * scale, height: 55.85 * scale)
                .overlay(alignment: .top) {
                    Capsule().fill(Color(red: 189/255, green: 252/255, blue: 49/255)).frame(height: 10.3 * scale)
                }
                .position(x: 23.73 * scale, y: (190.4 + headerShift) * scale)
                .accessibilityHidden(true)

            Text("0g")
                .font(.custom("Pretendard-ExtraBold", size: 73.03 * scale)).tracking(-1.46 * scale)
                .foregroundStyle(.black)
                .frame(width: 187 * scale, height: 87 * scale, alignment: .leading)
                .position(x: (33.61 + 93.5) * scale, y: (190.5 + headerShift) * scale)
                .accessibilityLabel("지금까지 절약한 이산화탄소 0그램")

            Text("지금까지\n절약한 CO₂")
                .font(.custom("Pretendard-SemiBold", size: 17.18 * scale)).tracking(0.52 * scale)
                .lineSpacing(0).foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
                .frame(width: 110 * scale, height: 42 * scale, alignment: .leading)
                .position(x: (41.34 + 55) * scale, y: (227.76 + 21 + headerShift) * scale)

            Image("HomeBottleCrushed")
                .resizable().frame(width: 402 * scale, height: 534 * scale)
                .rotationEffect(.degrees(5.25), anchor: .center)
                .frame(width: 449.18 * scale, height: 568.54 * scale)
                .position(x: 209.59 * scale, y: (227 + 284.27) * scale)
                .accessibilityHidden(true)

            statIcon(isPoints: false, scale: scale)
                .position(x: 291.5 * scale, y: (182.5 + headerShift) * scale)
            Text("\(recycleCount)")
                .font(.custom("Pretendard-Bold", size: 30.64 * scale)).tracking(0.92 * scale)
                .frame(width: 61 * scale, height: 37 * scale, alignment: .leading)
                .position(x: (317.83 + 30.5) * scale, y: (161 + 18.5 + headerShift) * scale)
            Text("리사이클")
                .font(.custom("Pretendard-SemiBold", size: 15.91 * scale)).tracking(0.48 * scale)
                .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
                .frame(width: 62 * scale, height: 19 * scale, alignment: .leading)
                .position(x: (317.83 + 31) * scale, y: (196.43 + 9.5 + headerShift) * scale)

            Image("EcoStatsDivider").resizable().frame(width: 70.85 * scale, height: 1 * scale)
                .position(x: (314 + 35.43) * scale, y: (230.4 + headerShift) * scale)
                .accessibilityHidden(true)

            statIcon(isPoints: true, scale: scale)
                .position(x: 292 * scale, y: (256.5 + headerShift) * scale)
            Text("0")
                .font(.custom("Pretendard-Bold", size: 30.64 * scale)).tracking(0.92 * scale)
                .frame(width: 61 * scale, height: 37 * scale, alignment: .leading)
                .position(x: (317.83 + 30.5) * scale, y: (240.47 + 18.5 + headerShift) * scale)
            Text("포인트")
                .font(.custom("Pretendard-SemiBold", size: 15.91 * scale)).tracking(0.48 * scale)
                .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
                .frame(width: 62 * scale, height: 19 * scale, alignment: .leading)
                .position(x: (317.83 + 31) * scale, y: (276.85 + 9.5 + headerShift) * scale)

            Button { showingSource = true } label: {
                HStack(spacing: 0) {
                    Text("지금 스캔하고\n분리배출을 확인해보세요!")
                        .font(.custom("Pretendard-SemiBold", size: 22 * scale)).tracking(0.66 * scale)
                        .lineSpacing(0).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image("EcoArrowRight").resizable().scaledToFit().frame(width: 34 * scale, height: 34 * scale)
                        .frame(width: 60 * scale, height: 60 * scale)
                        .background(Color(red: 59/255, green: 59/255, blue: 59/255), in: Circle())
                }
                .foregroundStyle(.white).padding(.horizontal, 36 * scale)
                .frame(width: 380 * scale, height: 110 * scale)
                .background(Color(red: 34/255, green: 34/255, blue: 34/255), in: RoundedRectangle(cornerRadius: 22 * scale))
                .contentShape(RoundedRectangle(cornerRadius: 22 * scale))
            }
            .buttonStyle(HomePressStyle(reduceMotion: reduceMotion))
            .position(x: 204 * scale, y: 690 * scale)
            .accessibilityLabel("촬영하거나 사진을 선택해 분리배출 확인하기")

            bottomBar(scale: scale, width: width, height: height)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func statIcon(isPoints: Bool, scale: CGFloat) -> some View {
        GeometryReader { _ in
            Image("HomeStatIcons")
                .resizable()
                .frame(width: 52 * scale, height: 78 * scale)
                .offset(x: -10.6 * scale, y: (isPoints ? -39.8 : -5.3) * scale)
        }
        .frame(width: 31 * scale, height: 33 * scale)
        .clipped()
        .accessibilityHidden(true)
    }

    private func bottomBar(scale: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let barHeight = 104 * scale
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 15 * scale, topTrailingRadius: 15 * scale)
                .fill(.white)
                .overlay(alignment: .top) { Rectangle().fill(Color(red: 236/255, green: 238/255, blue: 237/255)).frame(height: 1 * scale) }
                .shadow(color: .black.opacity(0.04), radius: 8 * scale, y: -4 * scale)
            HStack(alignment: .bottom, spacing: 0) {
                tabButton("EcoTabHome", "홈", scale: scale, action: { selectedTab = "홈" })
                tabButton("EcoTabClock", "기록", scale: scale, action: { selectedTab = "기록"; showingHistory = true })
                scanTab(scale: scale)
                tabButton("EcoTabMap", "지도", scale: scale, action: { selectedTab = "지도"; showingMap = true })
                tabButton("EcoTabProfile", "마이페이지", scale: scale, action: { selectedTab = "마이페이지"; showingSettings = true })
            }
            .padding(.horizontal, 24 * scale)
            .padding(.bottom, 30 * scale)
            .frame(height: barHeight, alignment: .bottom)
        }
        .frame(width: width, height: barHeight)
        .position(x: width / 2, y: height - barHeight / 2)
    }

    private func tabButton(_ asset: String, _ title: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        let selected = selectedTab == title
        return Button(action: action) {
            VStack(spacing: 4 * scale) {
                Image(asset).resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 39 * scale, height: 39 * scale)
                Text(title).font(.custom("Pretendard-Medium", size: 11 * scale))
                    .foregroundStyle(selected ? Color.black : Color(red: 125/255, green: 125/255, blue: 125/255))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.black : Color(red: 125/255, green: 125/255, blue: 125/255))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func scanTab(scale: CGFloat) -> some View {
        Button { selectedTab = "스캔"; showingSource = true } label: {
            VStack(spacing: 4 * scale) {
                Image("EcoTabScan").resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 35 * scale, height: 35 * scale)
                    .frame(width: 61 * scale, height: 61 * scale)
                    .background(lime, in: Circle())
                Text("스캔").font(.custom("Pretendard-Medium", size: 11 * scale)).foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("스캔할 사진 선택")
    }

    private struct HomePressStyle: ButtonStyle {
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.84 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
        }
    }

    @MainActor private func loadHomeMetrics() async {
        do {
            recycleCount = try await LocalScanStore.shared.all().count
        } catch { }
    }
}

#Preview {
    ContentView()
}
