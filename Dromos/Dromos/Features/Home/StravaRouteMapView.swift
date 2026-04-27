//
//  StravaRouteMapView.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import SwiftUI
import MapKit
import CoreLocation

/// Non-interactive map view that renders a GPS route from a Strava encoded polyline.
/// Uses SwiftUI MapKit (iOS 17+) with a MapPolyline overlay auto-fitted to the route bounds.
/// Intended as a static visual snapshot inside expanded completed session cards.
struct StravaRouteMapView: View {

    /// Google-encoded polyline string from Strava's activity map.
    let encodedPolyline: String

    /// Corner radius matching the parent session card style.
    private let cornerRadius: CGFloat = 12

    /// Pre-decoded coordinates — computed once in init to avoid O(N) work on every body evaluation.
    private let coordinates: [CLLocationCoordinate2D]

    /// Pre-computed camera position — derived from coordinates in init.
    private let cameraPosition: MapCameraPosition

    init(encodedPolyline: String) {
        self.encodedPolyline = encodedPolyline
        let coords = Self.decodePolyline(encodedPolyline)
        self.coordinates = coords
        self.cameraPosition = Self.computeCameraPosition(for: coords)
    }

    var body: some View {
        if coordinates.isEmpty {
            // Graceful fallback: show a placeholder when decoding yields no coordinates.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemFill))
                .frame(height: 150)
                .overlay(
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                )
        } else {
            Map(initialPosition: cameraPosition, interactionModes: []) {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.accentColor, lineWidth: 3)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    // MARK: - Camera Fitting

    /// Computes a MapCameraPosition that frames all route coordinates with padding.
    /// Static so it can be called from `init` before `self` is fully initialised.
    static func computeCameraPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coordinates.isEmpty else {
            return .automatic
        }

        // Find bounding box of the route
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return .automatic
        }

        // Add ~15% padding around the bounds so the route is not clipped at edges
        let latDelta = max((maxLat - minLat) * 1.3, 0.002)   // minimum delta for very short routes
        let lonDelta = max((maxLon - minLon) * 1.3, 0.002)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )

        return .region(region)
    }

    // MARK: - Polyline Decoder

    /// Decodes a Google-encoded polyline string into an array of geographic coordinates.
    ///
    /// Algorithm (standard Google Maps Encoded Polyline):
    /// 1. For each coordinate component (lat, then lon), read characters until a non-continuation byte.
    /// 2. Each character contributes 5-bit chunks to a varint accumulator.
    /// 3. Subtract 63 from each ASCII value, use the lowest bit as the sign bit.
    /// 4. Divide result by 1e5 to get decimal degrees.
    /// 5. All coordinates are deltas from the previous coordinate.
    ///
    /// No external dependencies — pure Swift implementation.
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            // Decode latitude delta
            var result = 0
            var shift = 0
            var byte: Int
            repeat {
                guard index < bytes.count else { return coordinates }
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            // Apply sign: if result is odd it was negative
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat

            // Decode longitude delta
            result = 0
            shift = 0
            repeat {
                guard index < bytes.count else { return coordinates }
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lon += deltaLon

            // Scale from 1e5 fixed-point integer to decimal degrees
            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lon) / 1e5
            )
            coordinates.append(coordinate)
        }

        return coordinates
    }
}
