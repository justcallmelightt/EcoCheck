import SwiftUI

struct ScanResultView: View {
    let imageData: Data
    @State private var analysis: AnalysisResult?
    @State private var analysisError: String?
    @State private var saveMessage: String?
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var analysisTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
                }
                if let result = analysis {
                    Text(result.name).font(.title2.bold())
                    Text(result.material).foregroundStyle(.secondary)
                    Text(result.reason).font(.callout)
                    GuideSteps(guide: result.guide)
                    if result.saveAllowed {
                        Button(isSaved ? "기록 저장 완료" : "결과를 확인하고 기록 저장") {
                            Task { await save(result) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || isSaved)
                    } else {
                        Text("확실하지 않은 결과라 기록으로 저장할 수 없어요. 다시 촬영하거나 기본 안내를 확인해주세요.")
                            .font(.callout).foregroundStyle(.secondary)
                        NavigationLink("기본 분리배출 안내 보기") { GuideListView() }
                    }
                    if isSaving { ProgressView("저장 중…") }
                } else if let analysisError {
                    Label("분석을 완료하지 못했어요", systemImage: "info.circle").font(.headline)
                    Text(analysisError)
                    Button("다시 분석") { startAnalysis() }.disabled(isAnalyzing)
                    NavigationLink("기본 분리배출 안내 보기") { GuideListView() }
                } else if isAnalyzing {
                    ProgressView("사진을 분석 중…")
                } else {
                    Text("사진이 EcoCheck 서버를 거쳐 Google Gemini로 전송돼요. 무료 API에서는 Google이 입력을 제품 개선에 사용할 수 있으니 개인정보가 담긴 사진은 보내지 마세요. 분석 결과를 확인한 뒤에만 기록을 저장합니다.")
                        .font(.callout)
                    Button("동의하고 사진 분석") { startAnalysis() }
                        .buttonStyle(.borderedProminent)
                    NavigationLink("사진 전송 없이 기본 안내 보기") { GuideListView() }
                }
                if let saveMessage { Text(saveMessage).font(.callout).foregroundStyle(.secondary) }
                Text("서버에는 사진을 저장하지 않아요. AI 판단은 틀릴 수 있으니 실제 배출 전 안내를 확인해주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("스캔 결과")
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
        isSaving = true
        defer { isSaving = false }
        do {
            // Retry with the same server analysis ID so a timeout cannot duplicate the record.
            let _ = try await EcoCheckAPI.shared.save(ScanSubmission(analysisId: result.id, confirmed: true))
            isSaved = true
            saveMessage = "기록을 저장했어요."
        } catch { saveMessage = "저장하지 못했어요. \(error.localizedDescription) 다시 눌러 재시도할 수 있어요." }
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
