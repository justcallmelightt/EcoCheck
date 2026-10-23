import SwiftUI

struct ScanResultView: View {
    let imageData: Data
    var onScanAnother: (() -> Void)? = nil
    @State private var analysis: AnalysisResult?
    @State private var analysisError: String?
    @State private var saveMessage: String?
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var analysisTask: Task<Void, Never>?
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 270)
                            .padding(.horizontal, 10)
                    }
                    if let result = analysis {
                        HStack(alignment: .center, spacing: 13) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold)).frame(width: 48, height: 48)
                                .background(lime.opacity(0.55), in: Circle())
                            Text("정확하게 인식했어요!").font(.custom("Pretendard-SemiBold", size: 17))
                            Spacer()
                        }
                        .padding(14).background(Color(red: 228/255, green: 249/255, blue: 210/255), in: Capsule())
                        .padding(.top, 10)

                        HStack { Text("배출 분류").foregroundStyle(.secondary); Spacer(); Text(result.name).fontWeight(.semibold) }
                            .padding(.vertical, 18).overlay(alignment: .bottom) { Rectangle().fill(Color(.separator).opacity(0.35)).frame(height: 1) }
                        HStack { Text("재질").foregroundStyle(.secondary); Spacer(); Text(result.material).fontWeight(.medium) }
                            .padding(.vertical, 18).overlay(alignment: .bottom) { Rectangle().fill(Color(.separator).opacity(0.35)).frame(height: 1) }
                        HStack(spacing: 13) {
                            Image(systemName: "lightbulb").font(.system(size: 20)).foregroundStyle(.secondary)
                            Text("라벨을 떼고, 내용물을 비워주세요").font(.custom("Pretendard-Medium", size: 14)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(18).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        .padding(.top, 22)
                        Text(result.reason).font(.custom("Pretendard-Regular", size: 14)).foregroundStyle(.secondary).padding(.top, 16)
                    } else if let analysisError {
                        ContentUnavailableView("인식하지 못했어요", systemImage: "questionmark.circle", description: Text(analysisError))
                        Button("다시 분석") { startAnalysis() }.disabled(isAnalyzing)
                        NavigationLink("하나씩 선택하기") { ManualMaterialSelectionView() }
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
                    if let saveMessage { Text(saveMessage).font(.footnote).foregroundStyle(.secondary).padding(.top, 12) }
                    Text("AI 결과는 틀릴 수 있어요. 배출 전에 지역별 안내를 확인해주세요.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 16)
                }
                .padding(.horizontal, 25).padding(.top, 18).padding(.bottom, 20)
            }
            if let result = analysis {
                VStack(spacing: 9) {
                    Button { Task { await save(result) } } label: {
                        Text(isSaved ? "기록 저장 완료" : "분리배출 기록 저장")
                            .font(.custom("Pretendard-SemiBold", size: 16))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .disabled(isSaved || isSaving || !result.saveAllowed)
                    .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
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
        .navigationTitle("인식결과")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { analysisTask?.cancel() }
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

    @MainActor private func save(_ result: AnalysisResult) async {
        guard !isSaved && !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LocalScanStore.shared.save(id: result.id, guide: result.guide,
                                                 source: result.source, modelVersion: result.modelVersion)
            isSaved = true
            saveMessage = "이 아이폰에 기록을 저장했어요."
        } catch { saveMessage = "저장하지 못했어요. \(error.localizedDescription)" }
    }
}

struct GuideSteps: View {
    let guide: RecyclingGuide
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.headline).frame(width: 28, height: 28)
                        .background(Color.green.opacity(0.15), in: Circle())
                    Text(step)
                }
            }
            Text(guide.note).font(.footnote).foregroundStyle(.secondary)
        }
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
    @State private var guides: [RecyclingGuide] = []
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section { Text("직접 선택하는 기본 안내예요. AI 판별 결과로 저장되지 않아요.").font(.footnote) }
            if let errorMessage { Text(errorMessage) }
            ForEach(guides) { guide in
                NavigationLink(guide.name) { ScrollView { GuideSteps(guide: guide).padding() }.navigationTitle(guide.name) }
            }
        }
        .navigationTitle("기본 분리배출 안내")
        .task {
            do { guides = try RecyclingGuide.load() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
