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
    @StateObject private var location = MapLocation()
    @State private var bins: NearbyBins?
    @State private var errorMessage: String?
    @State private var selectedType = "all"
    @State private var loading = false
    @State private var needsRefresh = false
    private let seoulCityHall = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

    var body: some View {
        VStack(spacing: 0) {
            Picker("쓰레기통 종류", selection: $selectedType) {
                Text("전체").tag("all")
                Text("일반").tag("general")
                Text("재활용").tag("recycling")
            }
            .pickerStyle(.segmented)
            .padding()

            OpenStreetMapView(center: center, bins: bins?.items ?? [])
                .overlay {
                    if loading && bins == nil {
                        ProgressView("주변 쓰레기통을 불러오는 중…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                if loading { ProgressView("주변 쓰레기통 조회 중…") }
                if let message = location.message { Text(message) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let bins {
                    Text("1km 이내 \(bins.count)개 · \(bins.sourceDate) 기준")
                        .font(.headline)
                    Text(bins.notice).font(.footnote).foregroundStyle(.secondary)
                    if bins.items.isEmpty {
                        Text("좌표가 등록된 쓰레기통이 없어요. 서버의 주소 변환·좌표 적재 상태를 확인해주세요.")
                            .font(.footnote)
                    }
                }
                Button("다시 조회") { Task { await refresh() } }.disabled(loading)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("주변 쓰레기통")
        .task {
            location.start()
            await refresh()
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in Task { await refresh() } }
        .onChange(of: location.coordinate?.longitude) { _, _ in Task { await refresh() } }
        .onChange(of: selectedType) { _, _ in Task { await refresh() } }
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
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct OpenStreetMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let bins: [NearbyBin]

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var annotations: [MKPointAnnotation] = []
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.setRegion(region, animated: true)
        map.removeAnnotations(context.coordinator.annotations)
        context.coordinator.annotations.removeAll()
        for item in bins {
            guard let lat = item.bin.latitude, let lng = item.bin.longitude else { continue }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            annotation.title = item.bin.address
            map.addAnnotation(annotation)
            context.coordinator.annotations.append(annotation)
        }
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center,
                          latitudinalMeters: 2_500,
                          longitudinalMeters: 2_500)
    }
}
