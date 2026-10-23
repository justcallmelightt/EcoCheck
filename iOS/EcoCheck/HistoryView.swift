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
