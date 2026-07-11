// ============================================================
// BLANK TV — Diagnostics.swift
// Zero-dependency crash / performance observability via Apple's MetricKit.
//
// MetricKit delivers DIAGNOSTIC payloads (crashes, hangs, CPU/disk-write
// exceptions) and METRIC payloads (launch time, hang rate, memory, battery)
// at the next launch — no SDK, no third party, no tracking. We persist the
// latest payloads as JSON in the Caches dir so they can be inspected on-device
// or uploaded to the backend later (a future, backend-coordinated step).
// ============================================================

import Foundation
import MetricKit

final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    /// Register as a MetricKit subscriber (call once, early at launch).
    func start() { MXMetricManager.shared.add(self) }

    // MARK: - MXMetricManagerSubscriber
    func didReceive(_ payloads: [MXMetricPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "metric")
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Crashes / hangs / disk-write exceptions land here.
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "diag")
    }

    // MARK: - Local persistence (capped)
    private func persist(_ blobs: [Data], prefix: String) {
        guard !blobs.isEmpty, let dir = Self.dir() else { return }
        for (i, data) in blobs.enumerated() {
            let stamp = Int(Date().timeIntervalSince1970)
            try? data.write(to: dir.appendingPathComponent("\(prefix)_\(stamp)_\(i).json"))
        }
        trim(dir, keep: 24)
    }

    private static func dir() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let d = base.appendingPathComponent("Diagnostics", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private func trim(_ dir: URL, keep: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > keep else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
        for f in sorted.prefix(files.count - keep) { try? FileManager.default.removeItem(at: f) }
    }
}
