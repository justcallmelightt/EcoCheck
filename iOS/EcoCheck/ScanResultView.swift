import SwiftUI

struct ScanResultView: View {
    let imageData: Data
    @State private var classification: Classification?
    @State private var analysisError: String?
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var scanID = UUID().uuidString.lowercased()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
                }
                if let result = classification {
                    Text(result.guide.name).font(.title2.bold())
                    Text("\(result.guide.material) · 모델 신뢰도 \(Int(result.confidence * 100))%")
                        .foregroundStyle(.secondary)
                    GuideSteps(guide: result.guide)
                    Button(isSaved ? "기록 저장 완료" : "스캔 기록 저장") {
                        Task { await save(result) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isSaved)
                    if isSaving { ProgressView("저장 중…") }
                } else if let analysisError {
                    Label("분석을 완료하지 못했어요", systemImage: "info.circle").font(.headline)
                    Text(analysisError)
                    NavigationLink("기본 분리배출 안내 보기") { GuideListView() }
                } else {
                    ProgressView("아이폰에서 분석 중…")
                }
                if let saveMessage { Text(saveMessage).font(.callout).foregroundStyle(.secondary) }
                Text("사진 분석은 아이폰에서 진행돼요. 기록 저장 시 분류·신뢰도·모델 버전만 서버로 전송해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("스캔 결과")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { classification = try await OnDeviceClassifier.shared.classify(imageData) }
            catch is CancellationError { }
            catch { analysisError = error.localizedDescription }
        }
    }

    @MainActor private func save(_ result: Classification) async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Retry with the same UUID so a timeout cannot duplicate the record.
            let _ = try await EcoCheckAPI.shared.save(ScanSubmission(id: scanID, categoryId: result.guide.id,
                confidence: result.confidence, modelVersion: result.modelVersion))
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
