import SwiftUI

struct HistoryView: View {
    @State private var records: [SavedScan] = []
    @State private var total = 0
    @State private var loading = false
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section("총 \(total)개 기록") {
                ForEach(records) { scan in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scan.name).font(.headline)
                        Text("\(scan.material) · 모델 신뢰도 \(Int(scan.confidence * 100))%")
                        Text(scan.createdAt).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("삭제", role: .destructive) { Task { await remove(scan) } }
                    }
                }
            }
            if records.isEmpty && !loading && errorMessage == nil { Text("저장된 스캔 기록이 없어요.") }
            if records.count < total {
                Button("더 보기") { Task { await load(more: true) } }.disabled(loading)
            }
            if loading { ProgressView("기록을 불러오는 중…") }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
                Button("다시 불러오기") { Task { await load() } }
            }
        }
        .navigationTitle("스캔 기록")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load(more: Bool = false) async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let page = try await EcoCheckAPI.shared.history(offset: more ? records.count : 0)
            if more {
                let known = Set(records.map(\.id))
                records.append(contentsOf: page.items.filter { !known.contains($0.id) })
            } else { records = page.items }
            total = page.total
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ scan: SavedScan) async {
        do {
            try await EcoCheckAPI.shared.delete(id: scan.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ServerSettingsView: View {
    @AppStorage("EcoCheckServerURL") private var serverURL = ""
    @State private var draft = ""
    @State private var message: String?
    var body: some View {
        Form {
            Section("기록 저장 서버") {
                TextField("https://your-server.example", text: $draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("주소 저장") {
                    if EcoCheckAPI.validBaseURL(draft) != nil {
                        serverURL = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        message = "서버 주소를 저장했어요."
                    } else { message = "올바른 HTTPS 서버 주소를 입력해주세요. 개발 빌드에서는 로컬 HTTP 주소도 사용할 수 있어요." }
                }
                if let message { Text(message).font(.footnote) }
            }
            Section {
                Text("AI 판별과 기본 안내는 서버 없이 이용할 수 있어요. 기록 저장·조회·삭제에는 서버 연결이 필요해요.")
                Text("기록은 이 기기의 보안 토큰으로 구분해요. 아직 회원가입·다른 기기 동기화 기능은 없어요.")
            }
        }
        .navigationTitle("설정")
        .onAppear { draft = serverURL }
    }
}
