import SwiftUI

struct HistoryView: View {
    var onNavigate: (String) -> Void = { _ in }
    @State private var records: [SavedScan] = []
    @State private var total = 0
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var period = "주간"
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)
    private let canvas = Color(red: 243/255, green: 243/255, blue: 245/255)
    private let muted = Color(red: 125/255, green: 125/255, blue: 125/255)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let top = max(58 * scale, geometry.safeAreaInsets.top + 8)
            ZStack(alignment: .top) {
                (records.isEmpty && !loading ? Color.white : canvas).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button { onNavigate("홈") } label: {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("홈으로 돌아가기")
                        Spacer()
                        Text("기록").font(.custom("Pretendard-Bold", size: 22 * scale))
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 17 * scale)
                    .frame(height: 52 * scale)
                    .background(.white)

                    HStack(spacing: 20 * scale) {
                        ForEach(["주간", "월간", "전체"], id: \.self) { item in
                            Button { period = item } label: {
                                if records.isEmpty {
                                    VStack(spacing: 8 * scale) {
                                        Text(item).font(.custom(period == item ? "Pretendard-Bold" : "Pretendard-SemiBold", size: 16 * scale))
                                            .foregroundStyle(period == item ? Color.black : muted)
                                        Capsule().fill(period == item ? lime : .clear).frame(width: 28 * scale, height: 3 * scale)
                                    }
                                } else {
                                    Text(item).font(.custom("Pretendard-Medium", size: 16 * scale))
                                        .foregroundStyle(period == item ? .white : muted)
                                        .frame(width: 102 * scale, height: 40 * scale)
                                        .background(period == item ? Color.black : Color(red: 232/255, green: 232/255, blue: 232/255), in: Capsule())
                                }
                            }
                            .buttonStyle(HistoryPressStyle(reduceMotion: reduceMotion))
                        }
                        Spacer()
                    }
                    .padding(.leading, 27 * scale)
                    .frame(height: 60 * scale, alignment: .center)
                    .background(.white)

                    if loading && records.isEmpty {
                        Spacer()
                        ProgressView("기록을 불러오는 중…")
                        Spacer()
                    } else if let errorMessage, records.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("기록을 불러오지 못했어요").font(.custom("Pretendard-Bold", size: 23))
                            Text(errorMessage).font(.custom("Pretendard-Regular", size: 14)).multilineTextAlignment(.center).foregroundStyle(muted)
                            Button("다시 불러오기") { Task { await load() } }
                                .font(.custom("Pretendard-SemiBold", size: 16)).foregroundStyle(.white)
                                .frame(width: 200, height: 56).background(Color(red: 20/255, green: 24/255, blue: 22/255), in: Capsule())
                        }
                        .padding(.horizontal, 30)
                        Spacer()
                    } else if visibleRecords.isEmpty {
                        Spacer()
                        VStack(spacing: 0) {
                            Image("HistoryMascot").resizable().scaledToFit()
                                .frame(width: 210 * scale, height: 140 * scale)
                            Text(records.isEmpty ? "아직 버린 게 없어요" : "\(period) 기록이 없어요")
                                .font(.custom("Pretendard-ExtraBold", size: 26 * scale))
                                .tracking(-0.5).padding(.top, 22 * scale)
                            Text(records.isEmpty ? "첫 번째 쓰레기를 확인하고\n나의 분리배출 기록을 쌓아보세요!" : "다른 기간을 선택하거나\n새로운 쓰레기를 스캔해보세요!")
                                .font(.custom("Pretendard-Regular", size: 14 * scale))
                                .foregroundStyle(Color(red: 103/255, green: 103/255, blue: 103/255))
                                .multilineTextAlignment(.center).lineSpacing(4 * scale)
                                .padding(.top, 10 * scale)
                            Button { onNavigate("스캔") } label: {
                                Text("첫 스캔 하러 가기")
                                    .font(.custom("Pretendard-SemiBold", size: 16 * scale))
                                    .foregroundStyle(.white)
                                    .frame(width: 200 * scale, height: 56 * scale)
                                    .background(Color(red: 20/255, green: 24/255, blue: 22/255), in: Capsule())
                            }
                            .buttonStyle(HistoryPressStyle(reduceMotion: reduceMotion))
                            .padding(.top, 42 * scale)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 13 * scale) {
                                summaryCard(scale: scale)
                                Text("최근 기록")
                                    .font(.custom("Pretendard-Bold", size: 20 * scale))
                                    .padding(.leading, 20 * scale).padding(.top, 4 * scale)
                                ForEach(visibleRecords) { scan in
                                    recordRow(scan, scale: scale)
                                }
                            }
                            .padding(.horizontal, 10 * scale)
                            .padding(.top, 23 * scale)
                            .padding(.bottom, 30 * scale)
                        }
                        .refreshable { await load() }
                    }
                    tabBar(scale: scale)
                }
                .padding(.top, top)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task { await load() }
    }

    private var visibleRecords: [SavedScan] {
        let calendar = Calendar.current
        let now = Date()
        return records.filter { scan in
            guard let date = scanDate(scan.createdAt) else { return period == "전체" }
            switch period {
            case "주간": return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case "월간": return calendar.isDate(date, equalTo: now, toGranularity: .month)
            default: return true
            }
        }
    }

    private func scanDate(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func summaryCard(scale: CGFloat) -> some View {
        let daily = (0..<7).map { day in
            visibleRecords.filter { scan in
                guard let date = scanDate(scan.createdAt) else { return false }
                let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7
                return weekday == day
            }.count
        }
        return VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(visibleRecords.count)").font(.custom("Pretendard-Bold", size: 58 * scale))
                    Text("회").font(.custom("Pretendard-Bold", size: 40 * scale))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(period) 기록").font(.custom("Pretendard-Bold", size: 23 * scale))
                    Text("스캔·저장 기준").font(.custom("Pretendard-Medium", size: 14 * scale)).foregroundStyle(muted)
                }.padding(.top, 5 * scale)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 6 * scale) {
                        Spacer(minLength: 0)
                        Text(daily[index] == 0 ? "" : "\(daily[index])")
                            .font(.custom("Pretendard-Regular", size: 11 * scale))
                            .foregroundStyle(Color(red: 120/255, green: 162/255, blue: 36/255))
                        RoundedRectangle(cornerRadius: 10 * scale)
                            .fill([Color(red: 244/255, green: 255/255, blue: 207/255), Color(red: 204/255, green: 219/255, blue: 156/255), Color(red: 238/255, green: 248/255, blue: 205/255), Color(red: 189/255, green: 212/255, blue: 114/255)][index % 4])
                            .frame(width: 26 * scale, height: daily[index] == 0 ? 4 * scale : CGFloat(daily[index]) * 16 * scale)
                            .frame(maxHeight: 132 * scale, alignment: .bottom)
                        Text(["월", "화", "수", "목", "금", "토", "일"][index])
                            .font(.custom("Pretendard-Regular", size: 11 * scale)).foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150 * scale)
        }
        .padding(.horizontal, 23 * scale).padding(.vertical, 20 * scale)
        .frame(height: 265 * scale)
        .background(.white, in: RoundedRectangle(cornerRadius: 30 * scale))
    }

    private func recordRow(_ scan: SavedScan, scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            Image(imageName(for: scan)).resizable().scaledToFit()
                .frame(width: 56 * scale, height: 56 * scale)
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text("\(scan.name) (\(scan.material))")
                    .font(.custom("Pretendard-Bold", size: 17.5 * scale)).lineLimit(1)
                Text(recordDate(scan.createdAt))
                    .font(.custom("Pretendard-Medium", size: 14.5 * scale)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { Task { await remove(scan) } } label: {
                Image(systemName: "trash").font(.system(size: 17))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("\(scan.name) 기록 삭제")
        }
        .padding(.horizontal, 12 * scale)
        .frame(height: 72 * scale)
        .background(.white, in: RoundedRectangle(cornerRadius: 10 * scale))
    }

    private func imageName(for scan: SavedScan) -> String {
        let value = "\(scan.name) \(scan.material)".lowercased()
        if value.contains("페트") || value.contains("pet") { return "ManualPetBottle" }
        if value.contains("캔") || value.contains("al") { return "ManualCan" }
        if value.contains("유리") { return "ManualGlass" }
        if value.contains("종이") || value.contains("팩") { return "ManualPaper" }
        return "ManualPlastic"
    }

    private func recordDate(_ text: String) -> String {
        guard let date = scanDate(text) else { return text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "오늘 HH:mm" : "M월 d일 HH:mm"
        return formatter.string(from: date)
    }

    private func tabBar(scale: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            tab("EcoTabHome", "홈", scale: scale)
            tab("EcoTabClock", "기록", scale: scale)
            tab("EcoTabScan", "스캔", scale: scale)
            tab("EcoTabMap", "지도", scale: scale)
            tab("EcoTabProfile", "마이페이지", scale: scale)
        }
        .padding(.horizontal, 24 * scale).padding(.bottom, 30 * scale)
        .frame(height: 104 * scale, alignment: .bottom)
        .frame(maxWidth: .infinity).background(.white)
    }

    private func tab(_ icon: String, _ title: String, scale: CGFloat) -> some View {
        Button { if title != "기록" { onNavigate(title) } } label: {
            VStack(spacing: 4 * scale) {
                Image(icon).resizable().renderingMode(.template).scaledToFit()
                    .frame(width: (title == "스캔" ? 35 : 39) * scale, height: (title == "스캔" ? 35 : 39) * scale)
                    .frame(width: (title == "스캔" ? 61 : 39) * scale, height: (title == "스캔" ? 61 : 39) * scale)
                    .background(title == "스캔" ? lime : .clear, in: Circle())
                Text(title).font(.custom("Pretendard-Medium", size: 11 * scale)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(title == "기록" || title == "스캔" ? .black : muted)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(HistoryPressStyle(reduceMotion: reduceMotion))
    }

    private struct HistoryPressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
        }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            records = try await LocalScanStore.shared.all()
            total = records.count
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ scan: SavedScan) async {
        do {
            try await LocalScanStore.shared.delete(id: scan.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ServerSettingsView: View {
    @AppStorage("EcoCheckServerURL") private var serverURL = ""
    @State private var draft = ""
    @State private var message: String?
    @AppStorage("ecoCheckNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("ecoCheckMissionNotificationsEnabled") private var missionNotificationsEnabled = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let background = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let ink = Color(red: 20/255, green: 24/255, blue: 22/255)
    private let secondary = Color(red: 107/255, green: 114/255, blue: 111/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("뒤로")
                        Spacer()
                        Text("설정").font(.custom("Pretendard-Bold", size: 22 * scale))
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 16 * scale)
                    .frame(height: 48 * scale)

                    sectionLabel("알림", scale: scale)
                    settingToggle("푸시 알림", value: $notificationsEnabled, scale: scale)
                    settingToggle("적립·미션 알림", value: $missionNotificationsEnabled, scale: scale)
                    row("마케팅 정보 수신", detail: "준비 중", scale: scale)
                    Text("알림 기능은 아직 연결되지 않았어요. 선택한 설정만 이 기기에 저장됩니다.")
                        .font(.custom("Pretendard-Regular", size: 12 * scale))
                        .foregroundStyle(secondary).padding(.top, 8 * scale)

                    sectionLabel("계정", scale: scale)
                    row("로그인 없이 이용 중", detail: "게스트", scale: scale)
                    Text("분리배출 안내와 지도는 로그인 없이 이용할 수 있어요. 포인트 적립과 계정 동기화는 준비 중이에요.")
                        .font(.custom("Pretendard-Regular", size: 13 * scale))
                        .foregroundStyle(secondary).lineSpacing(4 * scale)
                        .padding(.top, 10 * scale)

                    sectionLabel("분석 서버", scale: scale)
                    VStack(alignment: .leading, spacing: 10 * scale) {
                        TextField("https://your-server.example", text: $draft)
                            .font(.custom("Pretendard-Regular", size: 16 * scale))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).textContentType(.URL)
                            .padding(.vertical, 13 * scale)
                            .overlay(alignment: .bottom) { line }
                        Button {
                            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                serverURL = ""
                                message = "서버 주소를 지웠어요. 수동 선택과 기기 기록은 계속 사용할 수 있어요."
                            } else if EcoCheckAPI.validBaseURL(draft) != nil {
                                serverURL = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                message = "서버 주소를 저장했어요."
                            } else {
                                message = "HTTPS 주소를 입력해주세요. 개발 빌드에서는 로컬 HTTP 주소도 가능해요."
                            }
                        } label: {
                            Text("주소 저장")
                                .font(.custom("Pretendard-SemiBold", size: 16 * scale))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, minHeight: 48 * scale)
                                .background(lime, in: Capsule())
                        }
                        .buttonStyle(SettingsPressStyle(reduceMotion: reduceMotion))
                        if let message {
                            Text(message).font(.custom("Pretendard-Regular", size: 12 * scale))
                                .foregroundStyle(secondary)
                        }
                        Text("사진 AI 분석에는 서버 연결이 필요해요. 수동 분류와 기록은 이 아이폰에서 저장·조회·삭제할 수 있어요.")
                            .font(.custom("Pretendard-Regular", size: 13 * scale))
                            .foregroundStyle(secondary).lineSpacing(4 * scale)
                    }

                    sectionLabel("기타", scale: scale)
                    row("앱 버전", detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "개발 빌드", scale: scale)
                    Text("사진 분석을 선택하면 사진이 EcoCheck 서버를 거쳐 Google Gemini로 전송됩니다.")
                        .font(.custom("Pretendard-Regular", size: 12 * scale))
                        .foregroundStyle(secondary).lineSpacing(3 * scale)
                        .padding(.top, 22 * scale)
                }
                .padding(.horizontal, 29 * scale)
                .padding(.top, max(58 * scale, geometry.safeAreaInsets.top + 8))
                .padding(.bottom, 45 * scale)
            }
            .background(background.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear { draft = serverURL }
    }

    private var line: some View {
        Rectangle().fill(Color(red: 226/255, green: 230/255, blue: 228/255)).frame(height: 1)
    }

    private func sectionLabel(_ title: String, scale: CGFloat) -> some View {
        Text(title)
            .font(.custom("Pretendard-SemiBold", size: 13 * scale))
            .foregroundStyle(secondary)
            .padding(.top, 30 * scale).padding(.bottom, 8 * scale)
    }

    private func row(_ title: String, detail: String, scale: CGFloat) -> some View {
        HStack {
            Text(title).foregroundStyle(ink)
            Spacer()
            Text(detail).foregroundStyle(secondary)
        }
        .font(.custom("Pretendard-SemiBold", size: 16 * scale))
        .frame(height: 50 * scale)
        .overlay(alignment: .bottom) { line }
    }

    private func settingToggle(_ title: String, value: Binding<Bool>, scale: CGFloat) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack {
                Text(title).font(.custom("Pretendard-SemiBold", size: 16 * scale))
                    .foregroundStyle(ink)
                Spacer()
                Capsule().fill(value.wrappedValue ? lime : Color(red: 217/255, green: 217/255, blue: 217/255))
                    .frame(width: 48 * scale, height: 28 * scale)
                    .overlay(alignment: value.wrappedValue ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 24 * scale, height: 24 * scale)
                            .padding(2 * scale)
                    }
            }
            .frame(height: 59 * scale)
            .overlay(alignment: .bottom) { line }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(title)
        .accessibilityValue(value.wrappedValue ? "켬" : "끔")
    }

    private struct SettingsPressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
        }
    }
}

struct ProfileView: View {
    var onNavigate: (String) -> Void
    @State private var recordCount = 0
    @State private var notice: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let canvas = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("마이").font(.custom("Pretendard-Bold", size: 28))
                            Spacer()
                            Button("설정") { onNavigate("설정") }
                                .font(.custom("Pretendard-SemiBold", size: 15))
                        }
                        .foregroundStyle(.black)

                        HStack(spacing: 15) {
                            Image("HistoryMascot").resizable().scaledToFit()
                                .frame(width: 66, height: 66).background(.white, in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text("USER 님").font(.custom("Pretendard-Bold", size: 21))
                                Text("새싹 분리러 · 게스트").font(.custom("Pretendard-Medium", size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.top, 28)

                        HStack(alignment: .top, spacing: 0) {
                            metric("절약 CO₂", value: "—", unit: "g")
                            metric("분리배출", value: "\(recordCount)", unit: "회")
                            metric("포인트", value: "—", unit: "P")
                        }
                        .padding(.top, 30).padding(.bottom, 20)
                        .overlay(alignment: .top) { divider }
                        .overlay(alignment: .bottom) { divider }

                        profileButton("내 기록") { onNavigate("기록") }
                        profileButton("포인트 교환") { notice = "로그인과 포인트 적립 기능이 연결되면 이용할 수 있어요." }
                        NavigationLink { GuideListView() } label: { profileRow("분리배출 가이드") }
                            .buttonStyle(ProfilePressStyle(reduceMotion: reduceMotion))
                        profileButton("알림 설정") { onNavigate("설정") }
                        profileButton("고객센터") { notice = "고객센터 연결을 준비하고 있어요." }

                        Button("로그인·회원가입") { onNavigate("계정") }
                            .font(.custom("Pretendard-Medium", size: 13)).foregroundStyle(.secondary)
                            .padding(.top, 27)
                        Text("CO₂ 절감량과 포인트는 아직 산정되지 않아요.")
                            .font(.custom("Pretendard-Regular", size: 12)).foregroundStyle(.secondary).padding(.top, 9)
                    }
                    .padding(.horizontal, 29).padding(.top, 64).padding(.bottom, 150)
                }
                .background(canvas.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
            profileTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.light)
        .alert("안내", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인") { notice = nil }
        } message: { Text(notice ?? "") }
        .task { recordCount = (try? await LocalScanStore.shared.all().count) ?? 0 }
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.18)).frame(height: 1)
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.custom("Pretendard-Bold", size: 23))
                Text(unit).font(.custom("Pretendard-Bold", size: 13))
            }
            Text(title).font(.custom("Pretendard-Medium", size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { profileRow(title) }
            .buttonStyle(ProfilePressStyle(reduceMotion: reduceMotion))
    }

    private func profileRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.custom("Pretendard-SemiBold", size: 16))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.gray.opacity(0.55))
        }
        .foregroundStyle(.black).frame(height: 50).contentShape(Rectangle())
    }

    private var profileTabBar: some View {
        HStack(spacing: 0) {
            profileTab("EcoTabHome", "홈")
            profileTab("EcoTabClock", "기록")
            Button { onNavigate("스캔") } label: {
                Image("EcoTabScan").resizable().renderingMode(.template).scaledToFit().frame(width: 31, height: 31)
                    .foregroundStyle(.black).frame(width: 61, height: 61).background(lime, in: Circle())
                    .frame(maxWidth: .infinity)
            }
            profileTab("EcoTabMap", "지도")
            profileTab("EcoTabProfile", "마이페이지", selected: true)
        }
        .padding(.horizontal, 24).padding(.top, 9).padding(.bottom, 26)
        .background(.white.shadow(.drop(color: .black.opacity(0.04), radius: 8, y: -4)))
        .overlay(alignment: .top) { divider }
    }

    private func profileTab(_ asset: String, _ title: String, selected: Bool = false) -> some View {
        Button { onNavigate(title) } label: {
            VStack(spacing: 4) {
                Image(asset).resizable().renderingMode(.template).scaledToFit().frame(width: 32, height: 32)
                Text(title).font(.custom("Pretendard-Medium", size: 11))
            }
            .foregroundStyle(selected ? Color.black : Color.gray).frame(maxWidth: .infinity)
        }
        .buttonStyle(ProfilePressStyle(reduceMotion: reduceMotion))
    }

    private struct ProfilePressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
        }
    }
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = "전체"
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("닫기")
                Spacer()
                Text("알림").font(.custom("Pretendard-Bold", size: 22))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16).padding(.top, 60)
            HStack(spacing: 10) {
                ForEach(["전체", "포인트", "배출", "공지"], id: \.self) { option in
                    Button { category = option } label: {
                        Text(option).font(.custom("Pretendard-SemiBold", size: 14))
                            .foregroundStyle(category == option ? .black : .gray)
                            .padding(.horizontal, 17).frame(height: 38)
                            .background(category == option ? lime : Color(red: 241/255, green: 242/255, blue: 243/255), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 25)
            Spacer()
            Image(systemName: "bell.slash").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.gray)
            Text("아직 알림이 없어요").font(.custom("Pretendard-Bold", size: 22)).padding(.top, 22)
            Text("알림 서비스가 연결되면 이곳에서 확인할 수 있어요.")
                .font(.custom("Pretendard-Regular", size: 14)).foregroundStyle(.gray).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity).background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

struct AccountFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = "로그인"
    @State private var email = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var keepLogin = true
    @State private var nickname = ""
    @State private var confirmedPassword = ""
    @State private var allTerms = true
    @State private var alertMessage: String?
    private let ink = Color(red: 20/255, green: 24/255, blue: 22/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        NavigationStack {
            Group {
                if page == "로그인" {
                    loginScreen
                } else if page == "비밀번호 찾기" {
                    recoveryScreen
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Button { page = "로그인" } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                                Spacer()
                                Text(page).font(.custom("Pretendard-Bold", size: 21))
                                Spacer()
                                Color.clear.frame(width: 40, height: 40)
                            }
                            .foregroundStyle(ink).padding(.top, 46)
                            if page == "회원가입" { signupContent } else { termsContent }
                        }
                        .padding(.horizontal, 27).padding(.bottom, 40)
                    }
                    .background(Color(red: 245/255, green: 247/255, blue: 249/255).ignoresSafeArea())
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("계정 기능 준비 중", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("확인") { alertMessage = nil }
            } message: { Text(alertMessage ?? "") }
        }
        .preferredColorScheme(.light)
    }

    private var loginScreen: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / 402
            let sy = proxy.size.height / 874
            ZStack(alignment: .topLeading) {
                Color(red: 243/255, green: 243/255, blue: 245/255)
                Button { dismiss() } label: {
                    Image("LoginBackArrow").resizable().scaledToFit()
                        .frame(width: 24*sx, height: 24*sy)
                        .contentShape(Rectangle()).frame(width: 44*sx, height: 44*sy)
                }
                .position(x: 39*sx, y: 76*sy)

                Image("LoginHeroBottle").resizable().scaledToFill()
                    .frame(width: 319.9*sx, height: 373.4*sy)
                    .scaleEffect(y: -1).rotationEffect(.degrees(-149.1))
                    .frame(width: 466.25*sx, height: 484.67*sy)
                    .position(x: 297.12*sx, y: 262.33*sy)
                    .allowsHitTesting(false)

                Image("EcoCheckLogo").resizable().scaledToFit()
                    .frame(width: 215.4*sx, height: 71.8*sy)
                    .position(x: 122.7*sx, y: 162.2*sy)
                    .allowsHitTesting(false)

                Text("지금 스캔하고,\n작은 변화를 만들어보세요.")
                    .font(.custom("Pretendard-Medium", size: 16.5*sx)).lineSpacing(1)
                    .foregroundStyle(Color(red: 105/255, green: 105/255, blue: 105/255))
                    .frame(width: 180*sx, height: 42*sy, alignment: .leading)
                    .position(x: 122*sx, y: 218*sy)

                loginCard(scaleX: sx, scaleY: sy)
                    .frame(width: 344*sx, height: 400*sy)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20*sx))
                    .position(x: 201*sx, y: 540*sy)

                Button("로그인 하지 않고 분리배출 방법만 알고싶어요!") { dismiss() }
                    .font(.custom("Pretendard-Medium", size: 13*sx))
                    .foregroundStyle(Color(red: 107/255, green: 114/255, blue: 111/255))
                    .frame(width: 300*sx, height: 22*sy)
                    .position(x: 201*sx, y: 781*sy)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func loginCard(scaleX sx: CGFloat, scaleY sy: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Button { page = "로그인" } label: {
                    Text("로그인").font(.custom("Pretendard-Medium", size: 13.35*sx)).foregroundStyle(.black)
                        .frame(width: 150*sx, height: 32*sy).background(Color(red: 233/255, green: 247/255, blue: 207/255), in: Capsule())
                }
                Button { page = "회원가입" } label: {
                    Text("회원가입").font(.custom("Pretendard-Medium", size: 13.35*sx)).foregroundStyle(Color(red: 105/255, green: 105/255, blue: 105/255))
                        .frame(width: 148*sx, height: 32*sy)
                }
            }
            .background(Color(red: 244/255, green: 244/255, blue: 246/255), in: Capsule())
            .overlay(Capsule().stroke(Color.white, lineWidth: 1))
            .frame(width: 298*sx, height: 32*sy).offset(x: 24*sx, y: 14*sy)

            HStack(spacing: 10*sx) {
                Image("LoginMailIcon").resizable().scaledToFit().frame(width: 20*sx, height: 20*sy)
                ZStack(alignment: .leading) {
                    if email.isEmpty { Text("이메일을 입력해주세요").font(.custom("Pretendard-Regular", size: 11*sx)).foregroundStyle(Color(red: 149/255, green: 149/255, blue: 149/255)) }
                    TextField("", text: $email).font(.custom("Pretendard-Regular", size: 12*sx))
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                }
            }
            .padding(.horizontal, 13*sx).frame(width: 298*sx, height: 42*sy, alignment: .leading)
            .background(Color(red: 244/255, green: 244/255, blue: 246/255), in: RoundedRectangle(cornerRadius: 10*sx))
            .offset(x: 24*sx, y: 70*sy)

            HStack(spacing: 10*sx) {
                Image("LoginLockIcon").resizable().scaledToFit().frame(width: 22*sx, height: 22*sy)
                ZStack(alignment: .leading) {
                    if password.isEmpty { Text("비밀번호를 입력해주세요").font(.custom("Pretendard-Regular", size: 11*sx)).foregroundStyle(Color(red: 149/255, green: 149/255, blue: 149/255)) }
                    Group {
                        if passwordVisible { TextField("", text: $password) }
                        else { SecureField("", text: $password) }
                    }
                    .font(.custom("Pretendard-Regular", size: 12*sx))
                }
                Button { passwordVisible.toggle() } label: {
                    Image("LoginEyeOffIcon").resizable().scaledToFit().frame(width: 20*sx, height: 20*sy)
                }
            }
            .padding(.horizontal, 13*sx).frame(width: 299*sx, height: 42*sy, alignment: .leading)
            .background(Color(red: 244/255, green: 244/255, blue: 246/255), in: RoundedRectangle(cornerRadius: 10*sx))
            .offset(x: 23*sx, y: 119*sy)

            Button { keepLogin.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8*sx).fill(keepLogin ? Color(red: 206/255, green: 252/255, blue: 90/255) : Color.white)
                    if keepLogin { Image("LoginCheckIcon").resizable().scaledToFit().frame(width: 13.34*sx, height: 9.85*sy) }
                }
                .frame(width: 24*sx, height: 24*sy)
            }
            .offset(x: 26*sx, y: 172*sy)
            Text("로그인 상태 유지").font(.custom("Pretendard-Regular", size: 10*sx)).foregroundStyle(.black)
                .frame(width: 90*sx, height: 20*sy, alignment: .leading).offset(x: 55*sx, y: 174*sy)
            Button("비밀번호 찾기") { page = "비밀번호 찾기" }
                .font(.custom("Pretendard-Regular", size: 10*sx)).foregroundStyle(.black)
                .frame(width: 70*sx, height: 20*sy).offset(x: 256*sx, y: 174*sy)

            Button {
                alertMessage = "로그인 서버가 아직 연결되지 않았어요. 분리배출 안내와 기기 기록은 게스트로 이용할 수 있어요."
            } label: {
                ZStack {
                    Text("로그인").font(.custom("Pretendard-Medium", size: 15.5*sx)).foregroundStyle(.white)
                    Circle().fill(ink).frame(width: 31.2*sx, height: 31.2*sy)
                        .overlay(Image("LoginRightArrow").resizable().scaledToFit().frame(width: 17.67*sx, height: 17.67*sy))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8*sx)
                }
                .frame(width: 300*sx, height: 45*sy).background(ink, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8.7*sx, x: 1.7*sx, y: 1.7*sy)
            }
            .offset(x: 22*sx, y: 217*sy)

            HStack(spacing: 8*sx) {
                Rectangle().fill(Color(red: 206/255, green: 206/255, blue: 206/255)).frame(height: 1)
                Text("다른 방법으로 시작하기").font(.custom("Pretendard-Regular", size: 11*sx)).foregroundStyle(Color(red: 149/255, green: 149/255, blue: 149/255)).fixedSize()
                Rectangle().fill(Color(red: 206/255, green: 206/255, blue: 206/255)).frame(height: 1)
            }
            .frame(width: 309*sx, height: 20*sy).offset(x: 18*sx, y: 283*sy)

            Button { alertMessage = "Google 로그인이 아직 연결되지 않았어요." } label: {
                HStack(spacing: 9*sx) {
                    GeometryReader { geo in
                        Image("GoogleLoginSource").resizable()
                            .frame(width: geo.size.width*3.0836, height: geo.size.height*1.8429)
                            .offset(x: -geo.size.width*1.0335, y: -geo.size.height*0.4359)
                    }
                    .frame(width: 17.67*sx, height: 16.63*sy).clipped()
                    Text("Google로 계속하기").font(.custom("Pretendard-Bold", size: 14.1*sx)).foregroundStyle(ink)
                }
                .frame(width: 304*sx, height: 49.5*sy).background(.white, in: Capsule())
                .overlay(Capsule().stroke(Color(red: 226/255, green: 230/255, blue: 228/255), lineWidth: 0.9*sx))
            }
            .offset(x: 18*sx, y: 318*sy)
        }
        .frame(width: 344*sx, height: 400*sy, alignment: .topLeading)
    }

    private var recoveryScreen: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / 402
            let sy = proxy.size.height / 874
            ZStack(alignment: .topLeading) {
                Color.white
                Button { page = "로그인" } label: {
                    Image("LoginBackArrow").resizable().scaledToFit()
                        .frame(width: 24*sx, height: 24*sy).frame(width: 44*sx, height: 36*sy)
                }
                .position(x: 49*sx, y: 76*sy)
                Text("비밀번호를\n잊으셨나요?").font(.custom("Pretendard-ExtraBold", size: 26*sx)).lineSpacing(8*sx)
                    .foregroundStyle(ink).frame(width: 220*sx, height: 80*sy, alignment: .leading)
                    .position(x: 138*sx, y: 172*sy)
                Text("가입한 이메일로 재설정 링크를 보내드릴게요.")
                    .font(.custom("Pretendard-Medium", size: 15*sx)).foregroundStyle(Color(red: 138/255, green: 145/255, blue: 142/255))
                    .frame(width: 345*sx, alignment: .leading).position(x: 201*sx, y: 237*sy)
                VStack(alignment: .leading, spacing: 10*sy) {
                    Text("이메일").font(.custom("Pretendard-SemiBold", size: 13*sx)).foregroundStyle(ink)
                    TextField("eco@email.com", text: $email).font(.custom("Pretendard-Medium", size: 17*sx))
                        .foregroundStyle(Color(red: 196/255, green: 201/255, blue: 199/255))
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    Rectangle().fill(ink).frame(height: 2*sy)
                }
                .frame(width: 343*sx, height: 58*sy, alignment: .topLeading)
                .position(x: 200.5*sx, y: 313*sy)
                Text("메일이 안 오면 스팸함을 확인해 주세요.")
                    .font(.custom("Pretendard-Medium", size: 13*sx)).foregroundStyle(Color(red: 138/255, green: 145/255, blue: 142/255))
                    .frame(width: 345*sx, alignment: .leading).position(x: 201*sx, y: 372*sy)
                Button { alertMessage = "비밀번호 재설정 기능이 아직 연결되지 않았어요." } label: {
                    Text("재설정 메일 보내기").font(.custom("Pretendard-Bold", size: 16*sx)).foregroundStyle(.white)
                        .frame(width: 343*sx, height: 56*sy).background(ink, in: Capsule())
                }
                .position(x: 200.5*sx, y: 764*sy)
                Button("로그인으로 돌아가기") { page = "로그인" }
                    .font(.custom("Pretendard-SemiBold", size: 14*sx)).foregroundStyle(Color(red: 138/255, green: 145/255, blue: 142/255))
                    .frame(width: 343*sx, height: 24*sy).position(x: 201*sx, y: 824*sy)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private var signupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("몇 가지만 알려주면\n바로 시작할 수 있어요")
                .font(.custom("Pretendard-Bold", size: 25)).lineSpacing(4).padding(.top, 28).padding(.bottom, 21)
            formField("닉네임", placeholder: "닉네임", value: $nickname, secure: false)
            formField("이메일", placeholder: "eco@email.com", value: $email, secure: false)
            formField("비밀번호", placeholder: "8자 이상, 영문+숫자", value: $password, secure: true)
            formField("비밀번호 확인", placeholder: "한 번 더 입력해주세요", value: $confirmedPassword, secure: true)
            Toggle("약관 전체 동의", isOn: $allTerms).tint(ink)
                .font(.custom("Pretendard-SemiBold", size: 15)).padding(.top, 20)
            Button("이용약관 보기") { page = "약관" }
                .font(.custom("Pretendard-Medium", size: 13)).foregroundStyle(.secondary).padding(.top, 14)
            primaryButton("다음") {
                guard !nickname.isEmpty, email.contains("@"), password.count >= 8, password == confirmedPassword, allTerms else {
                    alertMessage = "닉네임과 이메일을 확인하고, 비밀번호를 8자 이상으로 입력한 뒤 약관에 동의해주세요."; return
                }
                alertMessage = "회원가입 서버가 아직 연결되지 않았어요."
            }
            .padding(.top, 35)
            Button("로그인으로 돌아가기") { page = "로그인" }
                .font(.custom("Pretendard-Medium", size: 14)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
    }

    private var termsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("약관 보기").font(.custom("Pretendard-Bold", size: 25)).padding(.top, 28)
            Text("서비스 이용약관과 개인정보 처리 안내는 팀에서 확정한 내용을 연결해야 합니다.")
                .font(.custom("Pretendard-Regular", size: 15)).lineSpacing(5).foregroundStyle(.secondary)
            Text("현재는 로그인 없이 기본 분리배출 안내와 지도를 이용할 수 있어요. 사진 분석을 선택하면 사진이 EcoCheck 서버와 Google Gemini로 전송돼요.")
                .font(.custom("Pretendard-Regular", size: 14)).lineSpacing(5)
                .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 230)
            primaryButton("돌아가기") { page = "회원가입" }
        }
    }

    private func formField(_ title: String, placeholder: String, value: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.custom("Pretendard-Medium", size: 13)).foregroundStyle(.secondary)
            Group {
                if secure { SecureField(placeholder, text: value) }
                else { TextField(placeholder, text: value).textInputAutocapitalization(.never).keyboardType(title == "이메일" ? .emailAddress : .default) }
            }
            .font(.custom("Pretendard-Regular", size: 16)).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1) }
        }
        .padding(.top, 23)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.custom("Pretendard-SemiBold", size: 16)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56).background(ink, in: Capsule())
        }
    }
}

struct OnboardingFlowView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let canvas = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let ink = Color(red: 34/255, green: 34/255, blue: 34/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    private let titles = ["분리배출,\n스캔 한 번이면 끝!", "버리는 법까지\n바로 알려줘요", "버릴수록 쌓이는\n포인트"]
    private let details = ["쓰레기를 찍으면 올바른 배출 방법과\n적립 정보를 알려드려요.", "라벨을 떼야 하는지, 씻어야 하는지.\n재질별 배출 방법을 확인해요.", "포인트 기능은 준비 중이에요.\n기본 안내는 로그인 없이 이용할 수 있어요."]

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button("건너뛰기", action: onFinish)
                        .font(.custom("Pretendard-Medium", size: 15)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 29).padding(.top, 55)
                ZStack {
                    if page == 0 {
                        Image("HomeBottleCrushed").resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: proxy.size.height * 0.43)
                            .padding(.top, 18)
                    } else if page == 2 {
                        Image("HomeBottle").resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: proxy.size.height * 0.43)
                            .padding(.top, 18)
                    } else {
                        Spacer().frame(maxWidth: .infinity).frame(height: proxy.size.height * 0.43)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(titles[page]).font(.custom("Pretendard-Bold", size: 29)).tracking(-0.6).lineSpacing(4)
                    Text(details[page]).font(.custom("Pretendard-Regular", size: 15)).lineSpacing(5).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Capsule().fill(page == index ? lime : Color.gray.opacity(0.25))
                                .frame(width: page == index ? 28 : 8, height: 8)
                        }
                    }
                    .padding(.top, 17)
                }
                .padding(.horizontal, 29).padding(.top, 22)
                Spacer(minLength: 20)
                Button {
                    if page < 2 { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)) { page += 1 } }
                    else { onFinish() }
                } label: {
                    HStack {
                        Spacer()
                        Text(page == 2 ? "시작하기" : "다음").font(.custom("Pretendard-SemiBold", size: 16))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30).background(.white.opacity(0.13), in: Circle())
                    }
                    .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 58)
                    .background(ink, in: Capsule())
                }
                .buttonStyle(OnboardingPressStyle(reduceMotion: reduceMotion))
                .padding(.horizontal, 29).padding(.bottom, max(34, proxy.safeAreaInsets.bottom + 15))
            }
            .background(canvas.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }

    private struct OnboardingPressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
        }
    }
}
