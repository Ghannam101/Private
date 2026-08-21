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

    /// APPLICATION SUPPORT, not Caches — and the move is the whole point of this file
    /// being worth anything.
    ///
    /// Apple documents Caches as the place for content that can be discarded when the
    /// device is low on space, and iOS acts on that. Crash reports were being written
    /// there: the one file you need after a bad launch is the one the system is
    /// entitled to delete, and it deletes it exactly when the device is under the kind
    /// of pressure that also causes crashes.
    ///
    /// Application Support persists, is invisible to the user, and is what Apple names
    /// for files an app needs and the user would never open. `isExcludedFromBackup` is
    /// deliberately NOT set: a crash report surviving a device restore is a feature.
    static func dir() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let d = base.appendingPathComponent("Diagnostics", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        migrateFromCaches(into: d)
        return d
    }

    /// Move anything an older build left in Caches, once.
    ///
    /// Without this the change only protects reports from here on and abandons the
    /// ones already collected — which are the reports about the builds that have
    /// actually shipped.
    private static var migrated = false
    private static func migrateFromCaches(into dest: URL) {
        guard !migrated else { return }
        migrated = true
        let fm = FileManager.default
        guard let old = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Diagnostics", isDirectory: true),
              let files = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)
        else { return }
        for f in files {
            let target = dest.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: f, to: target) }
        }
        try? fm.removeItem(at: old)
    }

    // MARK: - Reading them back
    //
    // THEY WERE WRITTEN AND NEVER READ. Every crash, hang and disk-write exception iOS
    // handed this app was serialised to disk and then abandoned — collected, and
    // thrown away, which is the same defect as not collecting at all but more
    // expensive. What follows turns the pile into something a person can paste into a
    // message.
    //
    // HONEST ABOUT THE LIMIT: MetricKit call stacks are NOT symbolicated. The frames
    // are binary offsets, and turning them into function names needs the dSYM for that
    // exact build, off the device. So the summary leads with the app VERSION and BUILD
    // — without those the offsets cannot be resolved by anyone, and with them they can.

    /// `Sendable` because the read runs off the main thread and these cross back.
    /// Every member already is one; the conformance just says so out loud, and keeps
    /// this from becoming an error under the Swift 6 migration.
    struct CrashNote: Identifiable, Sendable {
        let id = UUID()
        let file: String
        let date: Date
        /// `diagnosticMetaData` flattened to readable lines.
        let facts: [(String, String)]
    }

    /// Every persisted diagnostic, newest first.
    ///
    /// Schema-agnostic ON PURPOSE. Rather than reaching for `crashDiagnostics[0].
    /// diagnosticMetaData.exceptionType` — a path that is undocumented as JSON and has
    /// changed across releases — this walks the tree and collects every
    /// `diagnosticMetaData` object it finds, wherever it sits. A payload shape we have
    /// never seen still reports something useful instead of nothing.
    static func crashNotes() -> [CrashNote] {
        guard let dir = dir(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return files
            .filter { $0.lastPathComponent.hasPrefix("diag") }
            .compactMap { url -> CrashNote? in
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
                var facts: [(String, String)] = []
                collectMeta(json, into: &facts)
                guard !facts.isEmpty else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return CrashNote(file: url.lastPathComponent, date: date, facts: facts)
            }
            .sorted { $0.date > $1.date }
    }

    private static func collectMeta(_ node: Any, into out: inout [(String, String)]) {
        if let dict = node as? [String: Any] {
            if let meta = dict["diagnosticMetaData"] as? [String: Any] {
                for k in meta.keys.sorted() {
                    out.append((k, String(describing: meta[k] ?? "")))
                }
            }
            for v in dict.values { collectMeta(v, into: &out) }
        } else if let arr = node as? [Any] {
            for v in arr { collectMeta(v, into: &out) }
        }
    }

    /// One block of text to paste back. Leads with the build, because without it the
    /// unsymbolicated offsets below are unusable by anyone.
    static func crashReport() -> String {
        let notes = crashNotes()
        guard !notes.isEmpty else { return "لا توجد تقارير أعطال محفوظة." }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var out = ["app \(v) (\(b))  ·  \(notes.count) diagnostic payload(s)",
                   "NOTE: MetricKit stacks are not symbolicated; resolve offsets with the dSYM for this build.",
                   ""]
        for n in notes.prefix(6) {
            out.append("— \(f.string(from: n.date))  \(n.file)")
            for (k, val) in n.facts.prefix(24) { out.append("    \(k): \(val)") }
            out.append("")
        }
        return out.joined(separator: "\n")
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
