import SwiftUI
import MapKit
import Combine
import CoreLocation

extension SavedPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var region: MKCoordinateRegion { MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)) }
    init(mapItem: MKMapItem) {
        let coordinate: CLLocationCoordinate2D
        let address: String
        if #available(iOS 26.0, *) {
            coordinate = mapItem.location.coordinate
            address = mapItem.address?.fullAddress ?? ""
        } else {
            coordinate = mapItem.placemark.coordinate
            address = mapItem.placemark.title ?? ""
        }
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(name: name.isEmpty ? "Selected place" : name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
private struct PlaceResult: Identifiable {
    let id = UUID()
    let place: SavedPlace
}
@MainActor private final class PlaceLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var needsSettings = false
    private let manager = CLLocationManager()
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func locate() {
        coordinate = nil; message = nil; needsSettings = false; isLoading = true
        requestIfAuthorized()
    }
    private func requestIfAuthorized() {
        guard isLoading else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted:
            isLoading = false; needsSettings = manager.authorizationStatus == .denied
            message = "Location access is unavailable. Enable it in Settings or search by place and city."
        @unknown default:
            isLoading = false; message = "Location is unavailable. Search by place and city instead."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { coordinate = nil }
        requestIfAuthorized()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLoading else { return }
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            isLoading = false; message = "Couldn’t find a recent location. Try again or search by city."; return
        }
        coordinate = location.coordinate; isLoading = false
        message = "Search is now focused near you."
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLoading else { return }
        isLoading = false; message = "Couldn’t get your location. Try again or search by city."
    }
    func cancel() { manager.stopUpdatingLocation(); isLoading = false; coordinate = nil; message = nil }
}
@MainActor private final class PlaceSearchModel: ObservableObject {
    enum State { case idle, loading, loaded, failed(String) }
    @Published private(set) var results: [PlaceResult] = []
    @Published private(set) var state: State = .idle
    private var request: MKLocalSearch?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var isLoading: Bool { if case .loading = state { true } else { false } }
    func reset() {
        generation = UUID(); task?.cancel(); task = nil; request?.cancel(); request = nil
        results = []; state = .idle
    }
    func search(_ text: String, near coordinate: CLLocationCoordinate2D? = nil) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { reset(); return }
        reset()
        let token = generation
        let options = MKLocalSearch.Request()
        options.naturalLanguageQuery = query
        options.resultTypes = [.address, .pointOfInterest]
        if let coordinate { options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000) }
        let search = MKLocalSearch(request: options)
        request = search; state = .loading
        task = Task { [weak self] in
            do {
                let response = try await search.start()
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.results = response.mapItems.map { SavedPlace(mapItem: $0) }.filter(\.isValid).map { PlaceResult(place: $0) }
                self.state = .loaded; self.request = nil; self.task = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.state = .failed("Apple Maps couldn’t complete this search. Check your connection and try again, or enter the place manually.")
                self.request = nil; self.task = nil
            }
        }
    }
}
struct PlaceSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = PlaceSearchModel()
    @StateObject private var location = PlaceLocationModel()
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var camera: MapCameraPosition = .automatic
    let onSelect: (SavedPlace) -> Void
    private var selected: PlaceResult? { model.results.first { $0.id == selectedID } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.results.isEmpty {
                    Map(position: $camera, selection: $selectedID) {
                        ForEach(model.results) { result in
                            Marker(result.place.name, coordinate: result.place.coordinate).tag(result.id)
                        }
                    }.mapControls { MapCompass() }.frame(height: 220)
                        .accessibilityLabel("Search results map")
                    List(model.results) { result in
                        Button {
                            selectedID = result.id
                            camera = .region(result.place.region)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(JournalPalette.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.place.name).font(.headline).foregroundStyle(.primary)
                                    if !result.place.address.isEmpty { Text(result.place.address).font(.subheadline).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if selectedID == result.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(JournalPalette.accent).accessibilityLabel("Selected") }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
                } else {
                    searchStatus.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Find a place").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Place, address, or city")
            .onSubmit(of: .search) { model.search(query, near: location.coordinate) }
            .onChange(of: query) { _, _ in model.reset(); selectedID = nil; camera = .automatic }
            .onChange(of: selectedID) { _, _ in if let selected { camera = .region(selected.place.region) } }
            .onChange(of: phase) { _, phase in if phase == .background { model.reset(); location.cancel(); selectedID = nil } }
            .onDisappear { model.reset(); location.cancel() }
            .onChange(of: location.coordinate?.latitude) { _, _ in
                guard let coordinate = location.coordinate else { return }
                camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000))
                selectedID = nil
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.search(query, near: coordinate) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Search") { model.search(query, near: location.coordinate) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { location.locate() } label: {
                        Label(location.isLoading ? "Finding your location…" : "Use my location", systemImage: "location.fill")
                    }.disabled(location.isLoading)
                    if let message = location.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if location.needsSettings, let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
                    if let selected {
                        Button {
                            onSelect(selected.place); dismiss()
                        } label: { Text("Use this place").fontWeight(.semibold).frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent).controlSize(.large)
                    } else if !model.results.isEmpty { Text("Choose a result or map pin to continue.").font(.footnote).foregroundStyle(.secondary) }
                    Text("Search uses Apple Maps and requires internet. Use my location requests access while using the app to find places nearby.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding().background(.bar)
            }
        }.tint(JournalPalette.accent)
    }
    @ViewBuilder private var searchStatus: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView("Find somewhere to remember", systemImage: "map", description: Text("Search a landmark, cafe, hotel, or address. Include the city for better results."))
        case .loading: ProgressView("Searching Apple Maps…")
        case .loaded:
            ContentUnavailableView("No places found", systemImage: "magnifyingglass", description: Text("Try a different spelling, address, or city."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Try again") { model.search(query, near: location.coordinate) }.buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent)
                Button("Enter place manually") { dismiss() }
            }
        }
    }
}
struct SavedPlaceCard: View {
    let place: SavedPlace
    var allowsExternalMaps = true
    @State private var showMap = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(place.name, systemImage: "mappin.and.ellipse").font(.headline).foregroundStyle(JournalPalette.accent)
            if !place.address.isEmpty { Text(place.address).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            if showMap {
                Map(initialPosition: .region(place.region)) { Marker(place.name, coordinate: place.coordinate) }
                    .mapControls { MapCompass() }.frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 14))
                    .id("\(place.latitude),\(place.longitude)").accessibilityLabel("Map of \(place.name)")
                Button("Hide map") { showMap = false }.font(.subheadline)
            } else { Button("Show map", systemImage: "map") { showMap = true }.font(.subheadline) }
            if allowsExternalMaps, let url = place.mapsURL { Link(destination: url) { Label("Open in Apple Maps", systemImage: "arrow.up.right.square") }.font(.subheadline) }
        }
    }
}
