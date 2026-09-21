import Foundation
import UIKit

// MARK: - Exporters Helper
public struct ExportResult: Identifiable {
    public let id = UUID()
    public let fileURL: URL
    public let format: ExportFormat
}

// MARK: - Format Date Utils
public enum FormatUtils {
    public static func formatSpeed(_ speedKmh: Double) -> String {
        return String(format: "%.1f", speedKmh)
    }

    public static func formatAltitude(_ altitudeMeters: Double) -> String {
        return String(format: "%.0f", altitudeMeters)
    }

    public static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000.0 {
            return String(format: "%.2f km", meters / 1000.0)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    public static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func formatTimeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func formatIsoUtc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - GPX Exporter
public enum GpxExporter {
    public static func export(track: TrackItem, points: [TrackPointItem]) -> URL? {
        let dir = getExportDirectory()
        let safeTitle = track.title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let fileURL = dir.appendingPathComponent("Track_\(safeTitle).gpx")

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GeoTrack iOS" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escapeXml(track.title))</name>
            <time>\(FormatUtils.formatIsoUtc(track.startTime))</time>
          </metadata>
          <trk>
            <name>\(escapeXml(track.title))</name>
            <trkseg>

        """

        for p in points {
            let speedMps = p.speedKmh / 3.6
            let ptXml = String(
                format: """
                      <trkpt lat="%.7f" lon="%.7f">
                        <ele>%.2f</ele>
                        <time>%@</time>
                        <speed>%.2f</speed>
                      </trkpt>

                """,
                p.latitude,
                p.longitude,
                p.altitude,
                FormatUtils.formatIsoUtc(p.timestamp),
                speedMps
            )
            xml.append(ptXml)
        }

        xml.append("""
            </trkseg>
          </trk>
        </gpx>
        """)

        do {
            try xml.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to write GPX: \(error)")
            return nil
        }
    }

    private static func escapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - CSV Exporter
public enum CsvExporter {
    public static func export(track: TrackItem, points: [TrackPointItem]) -> URL? {
        let dir = getExportDirectory()
        let safeTitle = track.title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let fileURL = dir.appendingPathComponent("Track_\(safeTitle).csv")

        var csv = "index,timestamp,datetime_utc,latitude,longitude,altitude_m,speed_kmh,accuracy_m\n"
        for (index, p) in points.enumerated() {
            let line = String(
                format: "%d,%d,%@,%.7f,%.7f,%.2f,%.2f,%.2f\n",
                index + 1,
                Int(p.timestamp.timeIntervalSince1970 * 1000),
                FormatUtils.formatIsoUtc(p.timestamp),
                p.latitude,
                p.longitude,
                p.altitude,
                p.speedKmh,
                p.accuracy
            )
            csv.append(line)
        }

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to write CSV: \(error)")
            return nil
        }
    }
}

// MARK: - KMZ Exporter (Standard 3D KML in Zip Archive)
public enum KmzExporter {
    public static func export(track: TrackItem, points: [TrackPointItem]) -> URL? {
        let dir = getExportDirectory()
        let safeTitle = track.title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let kmzURL = dir.appendingPathComponent("Track_\(safeTitle).kmz")

        let kmlContent = buildKmlString(track: track, points: points)
        guard let kmlData = kmlContent.data(using: .utf8) else { return nil }

        // Create standard STORE zip format containing doc.kml
        let zipData = createZipArchive(fileName: "doc.kml", data: kmlData)
        do {
            try zipData.write(to: kmzURL, options: .atomic)
            return kmzURL
        } catch {
            print("Failed to write KMZ: \(error)")
            return nil
        }
    }

    private static func buildKmlString(track: TrackItem, points: [TrackPointItem]) -> String {
        var sb = ""
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        sb.append("<kml xmlns=\"http://www.opengis.net/kml/2.2\" xmlns:gx=\"http://www.google.com/kml/ext/2.2\">\n")
        sb.append("<Document>\n")
        sb.append("  <name>\(escapeXml(track.title))</name>\n")
        sb.append("  <description>\n")
        sb.append("    <![CDATA[\n")
        sb.append("      <b>Distance:</b> \(FormatUtils.formatDistance(track.totalDistanceMeters))<br/>\n")
        sb.append("      <b>Max Speed:</b> \(FormatUtils.formatSpeed(track.maxSpeedKmh)) km/h<br/>\n")
        sb.append("      <b>Avg Speed:</b> \(FormatUtils.formatSpeed(track.avgSpeedKmh)) km/h<br/>\n")
        sb.append("      <b>Max Altitude:</b> \(FormatUtils.formatAltitude(track.maxAltitude)) m<br/>\n")
        sb.append("      <b>Min Altitude:</b> \(FormatUtils.formatAltitude(track.minAltitude)) m<br/>\n")
        sb.append("      <b>Points:</b> \(points.count)<br/>\n")
        sb.append("      <b>Recorded:</b> \(FormatUtils.formatDateTime(track.startTime))\n")
        sb.append("    ]]>\n")
        sb.append("  </description>\n\n")

        sb.append("  <Style id=\"trackLine\">\n")
        sb.append("    <LineStyle>\n")
        sb.append("      <color>ff00e5ff</color>\n") // Cyan color
        sb.append("      <width>5</width>\n")
        sb.append("    </LineStyle>\n")
        sb.append("  </Style>\n\n")

        if let first = points.first, let last = points.last {
            // Start placemark
            sb.append("  <Placemark>\n")
            sb.append("    <name>Start</name>\n")
            sb.append("    <description>Start point at \(FormatUtils.formatDateTime(first.timestamp))</description>\n")
            sb.append("    <Point>\n")
            sb.append("      <altitudeMode>absolute</altitudeMode>\n")
            sb.append("      <coordinates>\(first.longitude),\(first.latitude),\(first.altitude)</coordinates>\n")
            sb.append("    </Point>\n")
            sb.append("  </Placemark>\n\n")

            // Finish placemark
            sb.append("  <Placemark>\n")
            sb.append("    <name>Finish</name>\n")
            sb.append("    <description>Finish point at \(FormatUtils.formatDateTime(last.timestamp))</description>\n")
            sb.append("    <Point>\n")
            sb.append("      <altitudeMode>absolute</altitudeMode>\n")
            sb.append("      <coordinates>\(last.longitude),\(last.latitude),\(last.altitude)</coordinates>\n")
            sb.append("    </Point>\n")
            sb.append("  </Placemark>\n\n")

            // Max speed point
            if let maxSpeedPoint = points.max(by: { $0.speedKmh < $1.speedKmh }), maxSpeedPoint.speedKmh > 0 {
                sb.append("  <Placemark>\n")
                sb.append("    <name>Max Speed: \(FormatUtils.formatSpeed(maxSpeedPoint.speedKmh)) km/h</name>\n")
                sb.append("    <description>\n")
                sb.append("      <![CDATA[\n")
                sb.append("        <b>Max Speed:</b> \(FormatUtils.formatSpeed(maxSpeedPoint.speedKmh)) km/h<br/>\n")
                sb.append("        <b>Altitude at peak:</b> \(FormatUtils.formatAltitude(maxSpeedPoint.altitude)) m<br/>\n")
                sb.append("        <b>Time:</b> \(FormatUtils.formatDateTime(maxSpeedPoint.timestamp))\n")
                sb.append("      ]]>\n")
                sb.append("    </description>\n")
                sb.append("    <Point>\n")
                sb.append("      <altitudeMode>absolute</altitudeMode>\n")
                sb.append("      <coordinates>\(maxSpeedPoint.longitude),\(maxSpeedPoint.latitude),\(maxSpeedPoint.altitude)</coordinates>\n")
                sb.append("    </Point>\n")
                sb.append("  </Placemark>\n\n")
            }

            // Max altitude point
            if let maxAltPoint = points.max(by: { $0.altitude < $1.altitude }) {
                sb.append("  <Placemark>\n")
                sb.append("    <name>Max Altitude: \(FormatUtils.formatAltitude(maxAltPoint.altitude)) m</name>\n")
                sb.append("    <description>\n")
                sb.append("      <![CDATA[\n")
                sb.append("        <b>Max Altitude:</b> \(FormatUtils.formatAltitude(maxAltPoint.altitude)) m<br/>\n")
                sb.append("        <b>Speed at peak:</b> \(FormatUtils.formatSpeed(maxAltPoint.speedKmh)) km/h<br/>\n")
                sb.append("        <b>Time:</b> \(FormatUtils.formatDateTime(maxAltPoint.timestamp))\n")
                sb.append("      ]]>\n")
                sb.append("    </description>\n")
                sb.append("    <Point>\n")
                sb.append("      <altitudeMode>absolute</altitudeMode>\n")
                sb.append("      <coordinates>\(maxAltPoint.longitude),\(maxAltPoint.latitude),\(maxAltPoint.altitude)</coordinates>\n")
                sb.append("    </Point>\n")
                sb.append("  </Placemark>\n\n")
            }

            // Route LineString
            sb.append("  <Placemark>\n")
            sb.append("    <name>Route Track</name>\n")
            sb.append("    <styleUrl>#trackLine</styleUrl>\n")
            sb.append("    <LineString>\n")
            sb.append("      <extrude>1</extrude>\n")
            sb.append("      <tessellate>1</tessellate>\n")
            sb.append("      <altitudeMode>absolute</altitudeMode>\n")
            sb.append("      <coordinates>\n")
            for p in points {
                sb.append(String(format: "        %.7f,%.7f,%.1f\n", p.longitude, p.latitude, p.altitude))
            }
            sb.append("      </coordinates>\n")
            sb.append("    </LineString>\n")
            sb.append("  </Placemark>\n")
        }

        sb.append("</Document>\n")
        sb.append("</kml>")
        return sb
    }

    private static func escapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // Pure Swift ZIP (Store mode) generator
    private static func createZipArchive(fileName: String, data: Data) -> Data {
        var zip = Data()
        let fileNameData = fileName.data(using: .utf8) ?? Data()
        let crc = crc32(data: data)
        let uncompressedSize = UInt32(data.count)
        let compressedSize = uncompressedSize
        let fileNameLength = UInt16(fileNameData.count)

        // 1. Local File Header
        var localHeader = Data()
        localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // Signature
        localHeader.append(contentsOf: [0x14, 0x00])             // Version 20
        localHeader.append(contentsOf: [0x00, 0x00])             // Flags
        localHeader.append(contentsOf: [0x00, 0x00])             // Compression: 0 (Store)
        localHeader.append(contentsOf: [0x00, 0x00])             // Mod time
        localHeader.append(contentsOf: [0x00, 0x00])             // Mod date
        localHeader.append(contentsOf: toBytes(crc))             // CRC32
        localHeader.append(contentsOf: toBytes(compressedSize))  // Compressed size
        localHeader.append(contentsOf: toBytes(uncompressedSize))// Uncompressed size
        localHeader.append(contentsOf: toBytes(fileNameLength))  // File name length
        localHeader.append(contentsOf: [0x00, 0x00])             // Extra field length
        localHeader.append(fileNameData)

        zip.append(localHeader)
        zip.append(data)

        let centralDirectoryOffset = UInt32(zip.count)

        // 2. Central Directory Header
        var centralDir = Data()
        centralDir.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // Signature
        centralDir.append(contentsOf: [0x14, 0x00])             // Version made by
        centralDir.append(contentsOf: [0x14, 0x00])             // Version needed
        centralDir.append(contentsOf: [0x00, 0x00])             // Flags
        centralDir.append(contentsOf: [0x00, 0x00])             // Compression: 0
        centralDir.append(contentsOf: [0x00, 0x00])             // Mod time
        centralDir.append(contentsOf: [0x00, 0x00])             // Mod date
        centralDir.append(contentsOf: toBytes(crc))             // CRC32
        centralDir.append(contentsOf: toBytes(compressedSize))  // Compressed size
        centralDir.append(contentsOf: toBytes(uncompressedSize))// Uncompressed size
        centralDir.append(contentsOf: toBytes(fileNameLength))  // File name length
        centralDir.append(contentsOf: [0x00, 0x00])             // Extra field length
        centralDir.append(contentsOf: [0x00, 0x00])             // File comment length
        centralDir.append(contentsOf: [0x00, 0x00])             // Disk number start
        centralDir.append(contentsOf: [0x00, 0x00])             // Internal file attributes
        centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External file attributes
        centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Relative offset of local header
        centralDir.append(fileNameData)

        zip.append(centralDir)

        let centralDirectorySize = UInt32(centralDir.count)

        // 3. End of Central Directory Record
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // Signature
        eocd.append(contentsOf: [0x00, 0x00])             // Number of disk
        eocd.append(contentsOf: [0x00, 0x00])             // Disk with central dir
        eocd.append(contentsOf: [0x01, 0x00])             // Total entries on disk (1)
        eocd.append(contentsOf: [0x01, 0x00])             // Total entries (1)
        eocd.append(contentsOf: toBytes(centralDirectorySize))   // Central dir size
        eocd.append(contentsOf: toBytes(centralDirectoryOffset)) // Offset of start
        eocd.append(contentsOf: [0x00, 0x00])             // Comment length

        zip.append(eocd)
        return zip
    }

    private static func toBytes(_ value: UInt16) -> [UInt8] {
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func toBytes(_ value: UInt32) -> [UInt8] {
        return [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private static func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = (crc ^ UInt32(byte)) & 0xFF
            var c = index
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            crc = (crc >> 8) ^ c
        }
        return crc ^ 0xFFFFFFFF
    }
}

private func getExportDirectory() -> URL {
    let fileManager = FileManager.default
    let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let exportDir = docs.appendingPathComponent("exported_tracks", isDirectory: true)
    if !fileManager.fileExists(atPath: exportDir.path) {
        try? fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
    }
    return exportDir
}

// MARK: - Native iOS Share Sheet Helper
public enum ShareSheetHelper {
    public static func share(fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootViewController.present(activityVC, animated: true)
    }
}
