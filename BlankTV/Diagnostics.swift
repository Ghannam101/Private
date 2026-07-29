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


// MARK: - S8KPerf — local timing, readable on the device
//
// See the header of this section in PERF_MEASUREMENT.md for why this shape and not
// OSSignposter or MetricKit. Short version: both are right for an engineer with a Mac
// attached, and neither can hand a number back to the person holding the phone.
//
// `end` removes the open mark, so a second `end` for the same key is a no-op — that
// is what makes "first poster of the launch" one-shot without any extra machinery.
//
// Everything stays local. Nothing here is transmitted anywhere.
enum S8KPerf {
    struct Sample: Identifiable {
        let id = UUID()
        let name: String
        let ms:   Int
        let note: String
        let at:   Date
    }

    private static let lock = NSLock()
    private static var open: [String: TimeInterval] = [:]
    private static var samples: [Sample] = []
    private static let cap = 40

    static func begin(_ name: String) {
        let t = Date().timeIntervalSinceReferenceDate
        lock.lock(); open[name] = t; lock.unlock()
    }

    static func end(_ name: String, _ note: String = "") {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock(); defer { lock.unlock() }
        guard let t0 = open.removeValue(forKey: name) else { return }
        samples.insert(Sample(name: name, ms: Int((now - t0) * 1000), note: note, at: Date()), at: 0)
        if samples.count > cap { samples.removeLast(samples.count - cap) }
    }

    static var recent: [Sample] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    static func clear() {
        lock.lock(); samples = []; open = [:]; lock.unlock()
    }

    /// One block of text to paste back into a conversation — the whole point of the
    /// screen. Newest first, same order as the list.
    static var report: String {
        let f = DateFormatter()
        // POSIX locale on purpose: on an Arabic device the default renders
        // Arabic-Indic digits, and this text exists to be pasted back and read.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return recent.map { s in
            let note = s.note.isEmpty ? "" : "  ·  \(s.note)"
            return "\(f.string(from: s.at))  \(s.name)  \(s.ms)ms\(note)"
        }.joined(separator: "\n")
    }
}
