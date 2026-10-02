import MapKit
import SwiftUI

struct PlacePreviewImage: View {
    let mapItem: MKMapItem
    var offsetMeters: Double = 0
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Apple 实景预览")
            } else {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: mapItem.placemark.coordinate,
                    latitudinalMeters: 950,
                    longitudinalMeters: 950
                ))) {
                    Marker(mapItem.name ?? "地点", coordinate: mapItem.placemark.coordinate)
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
                .accessibilityLabel("地点地图预览")
            }
        }
        .task(id: "\(Recommendation.identity(for: mapItem))|\(offsetMeters)") {
            let request: MKLookAroundSceneRequest
            if offsetMeters == 0 {
                request = MKLookAroundSceneRequest(mapItem: mapItem)
            } else {
                let coordinate = mapItem.placemark.coordinate
                request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude + offsetMeters / 111_000,
                    longitude: coordinate.longitude + offsetMeters / (111_000 * max(0.2, cos(coordinate.latitude * .pi / 180)))
                ))
            }
            guard let scene = try? await request.scene else { return }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: 700, height: 420)
            image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        }
    }
}
