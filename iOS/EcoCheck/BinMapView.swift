import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class MapLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var message: String?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: message = "위치 권한이 없어 서울시청 주변을 보여줘요."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        coordinate = latest.coordinate
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "현재 위치를 가져오지 못해 서울시청 주변을 보여줘요."
    }
}

struct BinMapView: View {
    var onNavigate: (String) -> Void = { _ in }
    @StateObject private var location = MapLocation()
    @State private var bins: NearbyBins?
    @State private var errorMessage: String?
    @State private var selectedType = "all"
    @State private var loading = false
    @State private var needsRefresh = false
    @State private var searchText = ""
    @State private var selectedBin: NearbyBin?
    @State private var panelCollapsed = false
    @GestureState private var panelDragTranslation: CGFloat = 0
    private let seoulCityHall = CLLocationCoordinate2D(latitude: 37.579, longitude: 126.973)

    private var panelHeight: CGFloat {
        min(300, max(76, (panelCollapsed ? 82 : 230) - panelDragTranslation))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                OpenStreetMapView(center: center, bins: filteredBins, selectedBin: $selectedBin)
                    .ignoresSafeArea()
                LinearGradient(colors: [Color(red: 192/255, green: 251/255, blue: 62/255).opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 250).allowsHitTesting(false)
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 19))
                        TextField("주변 수거함·배출 장소 검색", text: $searchText)
                            .font(.custom("Pretendard-Regular", size: 15))
                            .submitLabel(.search)
                    }
                    .padding(.horizontal, 20).frame(height: 52)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .padding(.horizontal, 29)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            filterChip("전체", value: "all")
                            filterChip("재활용", value: "recycling")
                            filterChip("일반", value: "general")
                        }
                        .padding(.horizontal, 24)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Button { location.start(); Task { await refresh() } } label: {
                            Image(systemName: "location").font(.system(size: 22))
                                .frame(width: 48, height: 48)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        }
                        .accessibilityLabel("내 위치에서 다시 찾기")
                    }
                    .padding(.trailing, 28).padding(.bottom, 18)
                    resultPanel
                    mapTabBar
                }
                .padding(.top, max(60, geometry.safeAreaInsets.top + 10))
            }
            .overlay(alignment: .bottomTrailing) {
                Text("© OpenStreetMap contributors")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.trailing, 8)
                    .padding(.bottom, panelHeight + 104 + 5)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(Color(red: 31/255, green: 39/255, blue: 36/255))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            location.start()
            await refresh()
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in Task { await refresh() } }
        .onChange(of: location.coordinate?.longitude) { _, _ in Task { await refresh() } }
        .onChange(of: selectedType) { _, _ in Task { await refresh() } }
    }

    private var mapTabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            mapTab("EcoTabHome", "홈")
            mapTab("EcoTabClock", "기록")
            mapTab("EcoTabScan", "스캔")
            mapTab("EcoTabMap", "지도")
            mapTab("EcoTabProfile", "마이페이지")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
        .frame(height: 104, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(.white)
    }

    private func mapTab(_ image: String, _ title: String) -> some View {
        Button { if title != "지도" { onNavigate(title) } } label: {
            VStack(spacing: 4) {
                Image(image).resizable().renderingMode(.template).scaledToFit()
                    .frame(width: title == "스캔" ? 35 : 39, height: title == "스캔" ? 35 : 39)
                    .frame(width: title == "스캔" ? 61 : 39, height: title == "스캔" ? 61 : 39)
                    .background(title == "스캔" ? Color(red: 192/255, green: 251/255, blue: 62/255) : .clear,
                                in: Circle())
                Text(title).font(.custom("Pretendard-Medium", size: 11))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(title == "지도" || title == "스캔" ? .black : Color(red: 125/255, green: 125/255, blue: 125/255))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MapPressStyle())
    }

    private var filteredBins: [NearbyBin] {
        let items = bins?.items ?? []
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.bin.address.localizedCaseInsensitiveContains(searchText) }
    }

    private func filterChip(_ title: String, value: String) -> some View {
        Button { selectedType = value; selectedBin = nil } label: {
            Text(title).font(.custom("Pretendard-SemiBold", size: 13))
                .foregroundStyle(selectedType == value ? .white : Color(red: 68/255, green: 68/255, blue: 68/255))
                .padding(.horizontal, 18).frame(height: 34)
                .background(selectedType == value ? .black : .white, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(MapPressStyle())
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 40, height: 4).frame(maxWidth: .infinity)
            if panelCollapsed {
                HStack(spacing: 10) {
                    Text(selectedBin.map { panelTitle(for: $0) } ?? "주변 수거함")
                        .font(.custom("Pretendard-Bold", size: 16))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(filteredBins.count)개")
                        .font(.custom("Pretendard-Medium", size: 13)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            } else if let selectedBin {
                Text(bins?.source == "local-estimate" ? "주소 기준 추정 위치" : "수거함 위치")
                    .font(.custom("Pretendard-Bold", size: 19))
                Text(selectedBin.bin.address)
                    .font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.secondary)
                if bins?.source == "local-estimate" {
                    Text("실제 설치 지점은 확인되지 않았어요.")
                        .font(.custom("Pretendard-Regular", size: 12)).foregroundStyle(.secondary)
                }
                if let latitude = selectedBin.bin.latitude, let longitude = selectedBin.bin.longitude {
                    Button {
                        let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
                        destination.name = selectedBin.bin.address
                        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        Label("길 찾기", systemImage: "location.north.fill")
                            .font(.custom("Pretendard-SemiBold", size: 16))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Color(red: 31/255, green: 39/255, blue: 36/255), in: Capsule())
                    }
                    .buttonStyle(MapPressStyle())
                    .disabled(bins?.source == "local-estimate")
                }
            } else {
                Text(bins?.source == "local-estimate" ? "주소 기준 위치 샘플" : "주변 수거함")
                    .font(.custom("Pretendard-Bold", size: 19))
                if loading { ProgressView("주변 수거함을 불러오는 중…") }
                else if let errorMessage { Text(errorMessage).font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.red) }
                else { Text("표시된 핀을 눌러 위치를 확인하세요 · \(filteredBins.count)개")
                    .font(.custom("Pretendard-Regular", size: 13)).foregroundStyle(.secondary) }
                if let message = location.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if let notice = bins?.notice { Text(notice).font(.caption2).foregroundStyle(.secondary) }
                Button("다시 조회") { Task { await refresh() } }.disabled(loading)
                    .font(.custom("Pretendard-SemiBold", size: 15))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 29).padding(.top, 10)
        .frame(maxWidth: .infinity).frame(height: panelHeight, alignment: .topLeading)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .clipped()
        .shadow(color: .black.opacity(0.1), radius: 10, y: -4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($panelDragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let predicted = value.predictedEndTranslation.height
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                        if predicted > 45 { panelCollapsed = true }
                        else if predicted < -45 { panelCollapsed = false }
                    }
                }
        )
        .accessibilityAction(named: Text(panelCollapsed ? "패널 펼치기" : "패널 접기")) {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                panelCollapsed.toggle()
            }
        }
    }

    private func panelTitle(for bin: NearbyBin) -> String {
        bins?.source == "local-estimate" ? "주소 기준 위치" : "주변 수거함"
    }

    private var center: CLLocationCoordinate2D {
        let point = location.coordinate ?? seoulCityHall
        // The server currently supports Seoul and nearby coordinates only.
        guard (37...38).contains(point.latitude), (126...128).contains(point.longitude) else { return seoulCityHall }
        return point
    }

    @MainActor private func refresh() async {
        if loading { needsRefresh = true; return }
        loading = true
        errorMessage = nil
        defer {
            loading = false
            if needsRefresh {
                needsRefresh = false
                Task { await refresh() }
            }
        }
        do {
            bins = try await EcoCheckAPI.shared.nearbyBins(
                latitude: center.latitude, longitude: center.longitude, type: selectedType)
        } catch {
            bins = Self.offlineSample(type: selectedType, center: center)
            errorMessage = nil
        }
        if selectedBin == nil { selectedBin = bins?.items.first }
    }

    private static func offlineSample(type: String, center: CLLocationCoordinate2D) -> NearbyBins {
        let samples: [(String, String, Double, Double)] = [
            ("seoul-202511-3", "자하문로4길 6", 37.5771689, 126.9726386),
            ("seoul-202511-7", "효자로13길 45", 37.582559, 126.9729401)
        ]
        let items = type == "recycling" ? [] : samples.map { id, address, lat, lng in
            NearbyBin(bin: .init(id: id, district: "종로구", address: "\(address) · 추정 위치",
                                  wasteType: "general", latitude: lat, longitude: lng),
                      distanceMeters: CLLocation(latitude: center.latitude, longitude: center.longitude)
                        .distance(from: CLLocation(latitude: lat, longitude: lng)))
        }
        return NearbyBins(items: items, count: items.count, source: "local-estimate",
                          sourceDate: "2025-11",
                          notice: "2025년 서울시 자료의 주소 일치 추정 좌표 2개입니다. 실제 쓰레기통 위치가 아니므로 현장에서 확인하세요.")
    }
}

private struct OpenStreetMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let bins: [NearbyBin]
    @Binding var selectedBin: NearbyBin?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OpenStreetMapView
        var annotations: [BinAnnotation] = []
        var lastRequestedCenter: CLLocationCoordinate2D?
        init(_ parent: OpenStreetMapView) { self.parent = parent }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let bin = (view.annotation as? BinAnnotation)?.bin else { return }
            parent.selectedBin = bin
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is BinAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "EcoBin")
            view.markerTintColor = UIColor(red: 192/255, green: 251/255, blue: 62/255, alpha: 1)
            view.glyphImage = UIImage(systemName: "leaf.fill")
            view.glyphTintColor = .black
            return view
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tiles)
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.setRegion(region, animated: false)
        context.coordinator.lastRequestedCenter = center
        let tiles = OpenStreetMapTileOverlay()
        map.addOverlay(tiles, level: .aboveLabels)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if let previous = context.coordinator.lastRequestedCenter,
           abs(previous.latitude - center.latitude) > 0.00001 || abs(previous.longitude - center.longitude) > 0.00001 {
            map.setRegion(region, animated: true)
            context.coordinator.lastRequestedCenter = center
        }
        let previousIDs = context.coordinator.annotations.map { $0.bin.id }
        let updatedIDs = bins.map(\.id)
        if previousIDs != updatedIDs {
            map.removeAnnotations(context.coordinator.annotations)
            context.coordinator.annotations = bins.compactMap { item in
                guard let lat = item.bin.latitude, let lng = item.bin.longitude else { return nil }
                return BinAnnotation(bin: item, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
            map.addAnnotations(context.coordinator.annotations)
        }
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center,
                          latitudinalMeters: 2_500,
                          longitudinalMeters: 2_500)
    }
}

private final class OpenStreetMapTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        canReplaceMapContent = true
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("EcoCheck-iOS/1.0 (+https://github.com/justcallmelightt/EcoCheck)",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result(nil, error); return }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), let data else {
                result(nil, URLError(.badServerResponse))
                return
            }
            result(data, nil)
        }.resume()
    }
}

private final class BinAnnotation: NSObject, MKAnnotation {
    let bin: NearbyBin
    let coordinate: CLLocationCoordinate2D
    var title: String? { bin.bin.address }
    init(bin: NearbyBin, coordinate: CLLocationCoordinate2D) {
        self.bin = bin
        self.coordinate = coordinate
    }
}

private struct MapPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}
