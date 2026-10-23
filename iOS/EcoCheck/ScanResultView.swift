import SwiftUI

struct ScanResultView: View {
    let imageData: Data
    var onScanAnother: (() -> Void)? = nil
    @State private var analysis: AnalysisResult?
    @State private var analysisError: String?
    @State private var isAnalyzing = false
    @State private var analysisTask: Task<Void, Never>?
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let result = analysis {
                        ZStack(alignment: .bottomTrailing) {
                            if let image = UIImage(data: imageData) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(maxWidth: .infinity).frame(height: 230).clipped()
                            }
                            VStack(alignment: .trailing, spacing: 7) {
                                Text(result.material.uppercased()).font(.custom("Pretendard-SemiBold", size: 13))
                                    .foregroundStyle(.blue).padding(.horizontal, 15).padding(.vertical, 7)
                                    .background(Color.blue.opacity(0.17), in: Capsule())
                                Text(result.name).font(.custom("Pretendard-Bold", size: 24))
                                Text(result.material).font(.custom("Pretendard-SemiBold", size: 15)).foregroundStyle(.secondary)
                            }
                            .padding(18)
                        }
                        .frame(height: 230).frame(maxWidth: .infinity)
                        .background(Color(red: 244/255, green: 248/255, blue: 247/255), in: RoundedRectangle(cornerRadius: 22))
                        .clipShape(RoundedRectangle(cornerRadius: 22))

                        HStack(spacing: 12) {
                            Image("HistoryMascot").resizable().scaledToFit().frame(width: 82, height: 62)
                            Text("정확하게 인식했어요!").font(.custom("Pretendard-Bold", size: 17))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 68)
                        .background(Color(red: 228/255, green: 249/255, blue: 210/255), in: Capsule())
                        .padding(.top, 10)

                        HStack { Text("배출 분류").foregroundStyle(.secondary); Spacer(); Text(result.name).font(.custom("Pretendard-SemiBold", size: 15)) }
                            .padding(.vertical, 18).overlay(alignment: .bottom) { Rectangle().fill(Color(.separator).opacity(0.35)).frame(height: 1) }
                        HStack { Text("재질").foregroundStyle(.secondary); Spacer(); Text(result.material).font(.custom("Pretendard-SemiBold", size: 15)) }
                            .padding(.vertical, 18).overlay(alignment: .bottom) { Rectangle().fill(Color(.separator).opacity(0.35)).frame(height: 1) }
                        HStack(spacing: 13) {
                            Image(systemName: "lightbulb").font(.system(size: 20)).foregroundStyle(.secondary)
                            Text(result.reason.isEmpty ? "재질별 안내를 확인해주세요" : result.reason).font(.custom("Pretendard-Medium", size: 14)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(16).background(Color(red: 243/255, green: 243/255, blue: 245/255), in: Capsule())
                        .padding(.top, 22)
                    } else if let analysisError {
                        let multipleItems = analysisError.localizedCaseInsensitiveContains("여러") ||
                            analysisError.localizedCaseInsensitiveContains("multiple") ||
                            analysisError.localizedCaseInsensitiveContains("하나씩")
                        VStack(spacing: 0) {
                            Spacer(minLength: 52)
                            Image("HistoryMascot").resizable().scaledToFit().frame(width: 122, height: 96)
                            Text("?").font(.system(size: 34, weight: .bold)).foregroundStyle(.secondary).offset(x: 55, y: -73)
                                .frame(height: 0)
                            Text(multipleItems ? "한 번에 하나씩 찍어주세요" : "인식하지 못했어요")
                                .font(.custom("Pretendard-Bold", size: 24)).padding(.top, 28)
                            Text(multipleItems ? "여러 개가 한 화면에 있으면 정확하게 분석하기 어려워요." : analysisError)
                                .font(.custom("Pretendard-Regular", size: 14)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.top, 8)
                            VStack(spacing: 0) {
                                tipRow("1", "밝은 곳에서 찍어주세요")
                                Divider()
                                tipRow("2", "물체를 화면 가운데에 두세요")
                                Divider()
                                tipRow("3", multipleItems ? "한 개만 화면 안에 맞춰주세요" : "한 번에 하나씩 촬영해주세요")
                            }
                            .padding(.horizontal, 16).padding(.top, 42)
                            Spacer(minLength: 38)
                            Button("다시 찍기") { onScanAnother?() }
                                .font(.custom("Pretendard-SemiBold", size: 16)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Color(red: 34/255, green: 34/255, blue: 34/255), in: Capsule())
                            NavigationLink { ManualMaterialSelectionView() } label: {
                                Text("목록에서 직접 고르기")
                                    .font(.custom("Pretendard-SemiBold", size: 16)).foregroundStyle(.black)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .overlay(Capsule().stroke(Color(.separator).opacity(0.5), lineWidth: 1))
                            }
                            .padding(.top, 10)
                        }
                        .frame(minHeight: 590)
                    } else if isAnalyzing {
                        VStack(spacing: 18) {
                            ProgressView().controlSize(.large).tint(lime)
                            Text("사진을 분석하고 있어요").font(.custom("Pretendard-SemiBold", size: 18))
                            Text("잠시만 기다려주세요").font(.custom("Pretendard-Regular", size: 14)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("사진을 분석해볼까요?").font(.custom("Pretendard-Bold", size: 22))
                            Text("사진은 EcoCheck 서버를 거쳐 Google Gemini로 전송됩니다. 무료 API는 입력을 제품 개선에 사용할 수 있으니 개인정보가 담긴 사진은 보내지 마세요.")
                                .font(.custom("Pretendard-Regular", size: 14)).foregroundStyle(.secondary)
                            Button("동의하고 사진 분석") { startAnalysis() }
                                .buttonStyle(.borderedProminent).tint(Color(red: 31/255, green: 39/255, blue: 36/255))
                            NavigationLink("사진 전송 없이 안내 찾기") { ManualMaterialSelectionView() }
                        }
                        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(.top, 18)
                    }
                    Text("AI 결과는 틀릴 수 있어요. 배출 전에 지역별 안내를 확인해주세요.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 16)
                }
                .padding(.horizontal, 25).padding(.top, 18).padding(.bottom, 20)
            }
            if let result = analysis {
                VStack(spacing: 9) {
                    NavigationLink("분리배출 방법 보기") { GuideSteps(guide: result.guide) }
                        .font(.custom("Pretendard-SemiBold", size: 16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(red: 31/255, green: 39/255, blue: 36/255), in: Capsule())
                    Button { onScanAnother?() } label: {
                        Label("다른 쓰레기 스캔하기", systemImage: "viewfinder")
                            .font(.custom("Pretendard-Medium", size: 16)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 25).padding(.top, 10).padding(.bottom, 12)
                .background(.white)
            }
        }
        .background(.white, ignoresSafeAreaEdges: .all)
        .overlay {
            if isAnalyzing {
                AnalysisLoadingOverlay(imageData: imageData) {
                    analysisTask?.cancel()
                    onScanAnother?()
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .toolbar(isAnalyzing ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(isAnalyzing ? "" : "인식결과")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { analysisTask?.cancel() }
    }

    private func tipRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text(number).font(.custom("Pretendard-Bold", size: 16)).foregroundStyle(Color.gray.opacity(0.55))
            Text(text).font(.custom("Pretendard-SemiBold", size: 15))
            Spacer()
        }
        .frame(height: 52)
    }

    private func startAnalysis() {
        guard !isAnalyzing else { return }
        analysisError = nil
        isAnalyzing = true
        analysisTask = Task {
            do {
                let jpeg = try Self.makeJPEG(from: imageData)
                let result = try await EcoCheckAPI.shared.analyze(jpegData: jpeg)
                try Task.checkCancellation()
                analysis = result
            } catch is CancellationError { }
            catch { analysisError = error.localizedDescription }
            isAnalyzing = false
        }
    }

    @MainActor private static func makeJPEG(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw ClassificationError.invalidImage }
        let ratio = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [CGFloat(0.82), 0.65, 0.45] {
            if let jpeg = normalized.jpegData(compressionQuality: quality), jpeg.count <= 4 * 1024 * 1024 {
                return jpeg
            }
        }
        throw APIError.server("사진 크기를 줄이지 못했어요. 다른 사진을 선택해주세요.")
    }

}

private struct AnalysisLoadingOverlay: View {
    let imageData: Data
    let onCancel: () -> Void

    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let photo = UIImage(data: imageData) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }

                Color.black.opacity(0.66)

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onCancel) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 23, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, max(geometry.safeAreaInsets.top, 54) + 8)

                    Text("쓰레기를 화면 안에 맞춰주세요")
                        .font(.custom("Pretendard-Medium", size: 14))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 34)

                    Spacer(minLength: 18)

                    ZStack {
                        ScanCornerMarks()
                            .stroke(lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: min(geometry.size.width - 104, 286), height: 300)

                        Image("HistoryMascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 104, height: 76)
                            .shadow(color: lime.opacity(0.35), radius: 18)
                    }

                    Text("분석하는 중")
                        .font(.custom("Pretendard-Bold", size: 20))
                        .foregroundStyle(.white)
                        .padding(.top, 12)
                    Text("재질과 오염 여부를 보고 있어요")
                        .font(.custom("Pretendard-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.top, 6)

                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.24))
                            Capsule().fill(lime).frame(width: bar.size.width * 0.68)
                        }
                    }
                    .frame(width: 174, height: 5)
                    .padding(.top, 15)
                    Text("68%")
                        .font(.custom("Pretendard-Medium", size: 10))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 5)

                    Spacer(minLength: 22)

                    Text("한번에 하나씩 촬영하면\n더 정확하게 분석할 수 있어요")
                        .font(.custom("Pretendard-Medium", size: 14))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 28) + 12)
                }
                .padding(.horizontal, 28)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.black)
        }
        .background(.black)
        .accessibilityElement(children: .contain)
    }
}

private struct ScanCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 34
        let radius: CGFloat = 14
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        return path
    }
}

struct GuideSteps: View {
    let guide: RecyclingGuide
    @Environment(\.dismiss) private var dismiss
    @State private var showingCompletion = false
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    Spacer()
                    Text("분리배출 방법").font(.custom("Pretendard-Bold", size: 21))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 2)

                Image(guideImageName(guide.id))
                    .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 210)
                    .background(Color(red: 245/255, green: 247/255, blue: 249/255), in: RoundedRectangle(cornerRadius: 22))
                Text(guide.name).font(.custom("Pretendard-Bold", size: 27)).tracking(-0.5)
                Text("재질: \(guide.material)").font(.custom("Pretendard-Medium", size: 15)).foregroundStyle(.secondary)
                Text("분리배출 방법").font(.custom("Pretendard-Bold", size: 20)).padding(.top, 17)
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 15) {
                        Text(String(format: "%02d", index + 1))
                            .font(.custom("Pretendard-Bold", size: 17)).frame(width: 32)
                        Text(step).font(.custom("Pretendard-Medium", size: 15)).lineSpacing(4)
                        Spacer(minLength: 0)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 245/255, green: 247/255, blue: 249/255), in: RoundedRectangle(cornerRadius: 17))
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                    Text(guide.note).font(.custom("Pretendard-Regular", size: 14)).lineSpacing(4)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(lime.opacity(0.35), in: RoundedRectangle(cornerRadius: 17))
                Button { showingCompletion = true } label: {
                    Text("분리배출 완료")
                        .font(.custom("Pretendard-SemiBold", size: 17))
                        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(red: 34/255, green: 34/255, blue: 34/255), in: Capsule())
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 29).padding(.top, 20).padding(.bottom, 40)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(.white)
        .navigationDestination(isPresented: $showingCompletion) {
            RecyclingCompleteView(guide: guide)
        }
    }
}

private struct RecyclingCompleteView: View {
    let guide: RecyclingGuide
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var requestId = UUID().uuidString.lowercased()
    private let lime = Color(red: 199/255, green: 248/255, blue: 37/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("뒤로")
                Spacer()
                Text("분리배출 방법").font(.custom("Pretendard-Bold", size: 21))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .foregroundStyle(.black).padding(.horizontal, 17).padding(.top, 20)
            Spacer(minLength: 30)
            VStack(spacing: 0) {
                HStack {
                    Text(guide.name).font(.custom("Pretendard-Bold", size: 25))
                    Spacer()
                    Text(guide.material).font(.custom("Pretendard-SemiBold", size: 16))
                        .padding(.horizontal, 18).padding(.vertical, 8).background(lime, in: Capsule())
                }
                .padding(.horizontal, 27).frame(height: 112)
                Text("올바른 분리배출이에요")
                    .font(.custom("Pretendard-Bold", size: 18)).padding(.top, 20).padding(.bottom, 10)
                VStack(spacing: 0) {
                    metricRow("절약한 CO₂", value: "미산정", symbol: "leaf")
                    Divider().padding(.horizontal, 18)
                    metricRow("지급 포인트", value: "미제공", symbol: "plus.circle")
                    Divider().padding(.horizontal, 18)
                    HStack {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("분리배출 방법").font(.custom("Pretendard-Medium", size: 15)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 19).frame(height: 70)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                Text("실제 배출을 확인하거나 CO₂·포인트를 산정하는 기능은 아직 연결되지 않았어요.")
                    .font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 16)
                if let errorMessage {
                    Text(errorMessage).font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.red).padding(.top, 10)
                }
            }
            .padding(.horizontal, 17)
            Spacer(minLength: 30)
            Button { Task { await saveCompletion() } } label: {
                Text(saved ? "기록했어요" : "확인")
                    .font(.custom("Pretendard-SemiBold", size: 17)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color(red: 34/255, green: 34/255, blue: 34/255), in: Capsule())
            }
            .disabled(isSaving || saved).padding(.horizontal, 29).padding(.bottom, 32)
        }
        .background(Color(red: 243/255, green: 243/255, blue: 245/255).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func metricRow(_ label: String, value: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).font(.system(size: 19)).frame(width: 27).foregroundStyle(.secondary)
            Text(label).font(.custom("Pretendard-Medium", size: 16)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.custom("Pretendard-SemiBold", size: 16))
        }
        .padding(.horizontal, 19).frame(height: 74)
    }

    @MainActor private func saveCompletion() async {
        guard !isSaving && !saved else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LocalScanStore.shared.save(id: requestId, guide: guide, source: "manual-complete", modelVersion: "local")
            saved = true
            try? await Task.sleep(for: .milliseconds(550))
            dismiss()
        } catch {
            errorMessage = "이 기기에 완료 기록을 저장하지 못했어요. 다시 시도해주세요."
        }
    }
}

private func guideImageName(_ id: String) -> String {
    switch id {
    case "pet_bottle": "ManualPetBottle"
    case "aluminum_can", "steel_can": "ManualCan"
    case "glass_bottle": "ManualGlass"
    case "cardboard", "paper": "ManualPaper"
    default: "ManualPlastic"
    }
}

private enum ManualMaterial: String, CaseIterable, Identifiable {
    case petBottle, can, paper, plastic, glass, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .petBottle: "페트병"
        case .can: "캔"
        case .paper: "종이"
        case .plastic: "플라스틱"
        case .glass: "유리"
        case .other: "기타"
        }
    }
    var imageName: String? {
        switch self {
        case .petBottle: "ManualPetBottle"
        case .can: "ManualCan"
        case .paper: "ManualPaper"
        case .plastic: "ManualPlastic"
        case .glass: "ManualGlass"
        case .other: nil
        }
    }
    var route: ManualRoute {
        switch self {
        case .petBottle: .guide("pet_bottle")
        case .can: .can
        case .paper: .guide("paper")
        case .plastic: .guide("plastic_container")
        case .glass: .guide("glass_bottle")
        case .other: .other
        }
    }
}

private enum ManualRoute: Hashable {
    case guide(String)
    case can
    case other
}

struct ManualMaterialSelectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var guides = (try? RecyclingGuide.load()) ?? []
    @State private var selected: ManualMaterial?
    @State private var showingNext = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let background = Color(red: 245/255, green: 247/255, blue: 249/255)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("어떤 재질인가요?")
                        .font(.custom("Pretendard-Bold", size: 26))
                    Text("AI가 판단하기 어려웠어요.\n가장 가까운 재질을 골라주세요.")
                        .font(.custom("Pretendard-Regular", size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(Color(red: 103/255, green: 103/255, blue: 103/255))

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ManualMaterial.allCases) { material in
                            materialCard(material)
                        }
                    }
                    .padding(.top, 20)

                    Text("찾는 품목이 없거나 재질을 모르겠다면 지역 안내를 확인해주세요.")
                        .font(.custom("Pretendard-Medium", size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 29)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            Button {
                guard selected != nil else { return }
                showingNext = true
            } label: {
                HStack {
                    Spacer()
                    Text("다음")
                        .font(.custom("Pretendard-SemiBold", size: 18))
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.16), in: Circle())
                        .padding(.trailing, 15)
                }
                .foregroundStyle(.white)
                .frame(height: 59)
                .background(Color(red: 31/255, green: 39/255, blue: 36/255), in: RoundedRectangle(cornerRadius: 25))
            }
            .buttonStyle(.plain)
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.45 : 1)
            .padding(.horizontal, 29)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(background, ignoresSafeAreaEdges: .all)
        .navigationTitle("재질 선택")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingNext) {
            if let selected {
                switch selected.route {
                case .guide(let id):
                    if let guide = guides.first(where: { $0.id == id }) {
                        ManualGuideReviewView(guide: guide)
                    } else {
                        MissingGuideView()
                    }
                case .can:
                    ManualCanSelectionView(guides: guides)
                case .other:
                    ManualOtherView()
                }
            }
        }
        .task {
            if let remote = try? await EcoCheckAPI.shared.categories(), !remote.isEmpty {
                guides = remote
            }
        }
    }

    private func materialCard(_ material: ManualMaterial) -> some View {
        let isSelected = selected == material
        return Button {
            withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 1)) {
                selected = material
            }
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let imageName = material.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .accessibilityHidden(true)
                    } else {
                        Text("?")
                            .font(.custom("Pretendard-Bold", size: 36))
                            .foregroundStyle(Color(red: 176/255, green: 176/255, blue: 176/255))
                            .frame(width: 80, height: 80)
                            .background(Color(red: 244/255, green: 244/255, blue: 244/255), in: Circle())
                    }
                }
                Text(material.title)
                    .font(.custom("Pretendard-Bold", size: 16))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 144)
            .background(isSelected ? Color(red: 228/255, green: 253/255, blue: 212/255) : .white,
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(red: 207/255, green: 207/255, blue: 207/255) : Color(red: 235/255, green: 235/255, blue: 235/255),
                            lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color(red: 109/255, green: 133/255, blue: 124/255), in: Circle())
                        .padding(8)
                }
            }
        }
        .buttonStyle(ManualChoiceButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ManualChoiceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
    }
}

private struct ManualCanSelectionView: View {
    let guides: [RecyclingGuide]

    var body: some View {
        List {
            Section("캔의 종류를 골라주세요") {
                guideLink("aluminum_can")
                guideLink("steel_can")
            }
        }
        .navigationTitle("캔 종류 선택")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func guideLink(_ id: String) -> some View {
        if let guide = guides.first(where: { $0.id == id }) {
            NavigationLink(guide.name) { ManualGuideReviewView(guide: guide) }
        } else {
            Text("안내를 불러오지 못했어요.").foregroundStyle(.secondary)
        }
    }
}

private struct ManualGuideReviewView: View {
    let guide: RecyclingGuide
    @State private var requestId = UUID().uuidString.lowercased()
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guide.name).font(.custom("Pretendard-Bold", size: 28))
                    Text(guide.material).font(.custom("Pretendard-SemiBold", size: 18)).foregroundStyle(.secondary)
                }
                GuideSteps(guide: guide)
                Button(isSaved ? "기록 저장 완료" : "안내 확인 후 기록 저장") {
                    Task { await saveManualRecord() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 31/255, green: 39/255, blue: 36/255))
                .disabled(isSaving || isSaved)
                if isSaving { ProgressView("저장 중…") }
                if let saveMessage { Text(saveMessage).font(.callout).foregroundStyle(.secondary) }
                Text("기록은 재질을 선택한 내용이며, 실제 배출 완료를 뜻하지 않아요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("분리배출 방법")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor private func saveManualRecord() async {
        guard !isSaving && !isSaved else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LocalScanStore.shared.save(id: requestId, guide: guide,
                                                 source: "manual", modelVersion: "local")
            isSaved = true
            saveMessage = "직접 선택한 분류를 이 아이폰에 기록했어요."
        } catch {
            saveMessage = "저장하지 못했어요. \(error.localizedDescription)"
        }
    }
}

private struct ManualOtherView: View {
    var body: some View {
        ContentUnavailableView(
            "정확한 분류 안내가 없어요",
            systemImage: "questionmark.circle",
            description: Text("재질을 추측해 기록하지 않아요. 지역의 분리배출 안내를 확인한 뒤 배출해주세요."))
            .navigationTitle("기타 품목")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MissingGuideView: View {
    var body: some View {
        ContentUnavailableView("안내를 찾지 못했어요", systemImage: "info.circle")
            .navigationTitle("분리배출 방법")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var guides: [RecyclingGuide] = []
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var category = "전체"
    private let categories = ["전체", "페트병", "캔", "종이", "유리", "플라스틱"]
    private var filtered: [RecyclingGuide] {
        guides.filter { guide in
            let matchesCategory = category == "전체" ||
                (category == "페트병" && guide.id == "pet_bottle") ||
                (category == "캔" && guide.id.contains("can")) ||
                (category == "종이" && ["paper", "cardboard"].contains(guide.id)) ||
                (category == "유리" && guide.id == "glass_bottle") ||
                (category == "플라스틱" && guide.id == "plastic_container")
            return matchesCategory && (search.isEmpty || guide.name.localizedCaseInsensitiveContains(search) || guide.material.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("분리배출 가이드")
                    .font(.custom("Pretendard-SemiBold", size: 17))
                    .foregroundStyle(.black)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(Color(red: 225/255, green: 227/255, blue: 230/255), lineWidth: 0.8))
                            .shadow(color: .black.opacity(0.035), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("뒤로")
                    Spacer()
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 14)
            .background(.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text("무엇을 버리시나요?")
                    .font(.custom("Pretendard-Bold", size: 27)).tracking(-0.5).padding(.bottom, 23)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20))
                    TextField("분리배출 품목 검색", text: $search)
                        .font(.custom("Pretendard-Regular", size: 16))
                }
                .padding(.horizontal, 18).frame(height: 56)
                .background(Color(red: 245/255, green: 247/255, blue: 249/255), in: Capsule())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(categories, id: \.self) { option in
                            Button { category = option } label: {
                                Text(option).font(.custom("Pretendard-SemiBold", size: 14))
                                    .foregroundStyle(category == option ? .white : .black)
                                    .padding(.horizontal, 18).frame(height: 38)
                                    .background(category == option ? Color.black : Color(red: 245/255, green: 247/255, blue: 249/255), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 23)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                ForEach(filtered) { guide in
                    NavigationLink { GuideSteps(guide: guide) } label: {
                        HStack(spacing: 16) {
                            Image(guideImageName(guide.id)).resizable().scaledToFit()
                                .frame(width: 58, height: 58)
                                .background(Color(red: 245/255, green: 247/255, blue: 249/255), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(guide.name).font(.custom("Pretendard-SemiBold", size: 17))
                                Text(guide.material).font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
                        }
                        .foregroundStyle(.black).frame(height: 77)
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty && errorMessage == nil {
                    Text("일치하는 품목이 없어요.").font(.custom("Pretendard-Medium", size: 15))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
                Text("품목별 기준은 지역마다 다를 수 있어요. 배출 전 수거함 안내를 확인해주세요.")
                    .font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.secondary)
                    .padding(.top, 28)
                }
                .padding(.horizontal, 29).padding(.top, 30).padding(.bottom, 50)
            }
        }
        .background(Color.white, ignoresSafeAreaEdges: .all)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do { guides = try RecyclingGuide.load() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
