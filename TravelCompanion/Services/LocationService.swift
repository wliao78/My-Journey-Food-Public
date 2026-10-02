import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var placeName = String(localized: "正在定位…")
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = String(localized: "定位权限未开启，请在系统设置中允许定位。")
        @unknown default:
            errorMessage = String(localized: "暂时无法获取位置。")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        errorMessage = nil
        Task { await reverseGeocode(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        errorMessage = error.localizedDescription
    }

    private func reverseGeocode(_ location: CLLocation) async {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            placeName = String(localized: "当前位置")
            return
        }
        placeName = placemark.locality ?? placemark.subLocality ?? placemark.name ?? String(localized: "当前位置")
    }
}
