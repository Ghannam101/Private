// ============================================================
// BLANK TV — Downloads.swift
// Offline downloads — download VOD (movies / episodes) and watch without
// internet. Live channels are NOT downloadable.
//
// Engine: a BACKGROUND URLSession so downloads continue when the app is
// backgrounded and finish/relaunch cleanly. Files land in Documents/Downloads
// (excluded from iCloud backup). Playback is automatic: BasePlayerVM.resolvedURL
// prefers a completed local file for that content id, so the existing player +
// hybrid engine play the offline copy with zero extra wiring.
// ============================================================

import SwiftUI
import Foundation
import UserNotifications

// MARK: - Model
struct DownloadItem: Codable, Identifiable, Hashable {
    let id: String                 // raw content id (movie.id / episode.id)
    let kind: Kind
    let title: String
    let subtitle: String?
    let posterURL: String?
    var state: State
    var receivedBytes: Int64
    var totalBytes: Int64
    let createdAt: Double
    /// The source URL — kept so a paused download can RESTART from zero when no
    /// resume data is available (the model's directURL isn't persisted). Optional
    /// so older saved downloads still decode.
    var remoteURL: String? = nil
    // Stored so the item can be played fully offline (directURL is re-pointed to
    // the local file at play time).
    let movie:   Movie?
    let episode: Episode?
    let series:  Series?

    enum Kind:  String, Codable { case movie, episode }
    // .queued = waiting for the single active download slot to free up.
    enum State: String, Codable { case queued, downloading, paused, completed, failed }

    var progress: Double { totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0 }
    func hash(into h: inout Hasher) { h.combine(id) }
    static func == (a: DownloadItem, b: DownloadItem) -> Bool { a.id == b.id }
}

// MARK: - Service
@MainActor
final class DownloadService: NSObject, ObservableObject {
    static let shared = DownloadService()

    @Published private(set) var items: [DownloadItem] = []

    /// Set by the AppDelegate when the system relaunches us to finish background
    /// transfers; called once all events are delivered.
    var backgroundCompletion: (() -> Void)?

    /// In-flight Turbo (parallel) download tasks, keyed by content id.
    private var turboTasks: [String: Task<Void, Never>] = [:]

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.blanktv.player.downloads")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        // Wi-Fi only is enforced here at the session level so it covers BOTH fresh
        // and resume-data tasks (URLSessionTask has no per-task network flags). With
        // waitsForConnectivity this WAITS for Wi-Fi instead of failing. The session
        // is rebuilt every launch (init forces `_ = session`), so the setting is
        // re-read each launch.
        let wifiOnly = Store.shared.downloadWifiOnly
        cfg.allowsCellularAccess        = !wifiOnly
        cfg.allowsExpensiveNetworkAccess   = !wifiOnly
        cfg.allowsConstrainedNetworkAccess = !wifiOnly
        // Throughput: HTTP/3 (QUIC) is negotiated automatically by URLSession on
        // iOS 15+. Allow more connections per host so several downloads (or a
        // server that opens parallel data channels) aren't bottlenecked at the
        // default of 4.
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        items = Self.loadItems()
        _ = session   // recreate the background session → reconnect to in-flight tasks
        reconcileOnLaunch()
    }

    /// On launch, reconcile persisted state with the background session:
    /// - a `.downloading` item with no live task (app was force-quit) → `.paused`;
    /// - a `.downloading` item whose task is still live keeps the active slot;
    /// then pump() so any persisted `.queued` items start in order.
    private func reconcileOnLaunch() {
        guard items.contains(where: { $0.state == .downloading || $0.state == .queued }) else { return }
        session.getAllTasks { [weak self] tasks in
            let live = Set(tasks.compactMap { ($0.taskDescription ?? "").components(separatedBy: "|").first })
            Task { @MainActor in
                guard let self else { return }
                var changed = false
                for i in self.items.indices
                where self.items[i].state == .downloading && !live.contains(self.items[i].id) {
                    self.items[i].state = .paused; changed = true
                }
                if changed { self.persist() }
                self.pump()   // start any queued items in the freed slot(s)
            }
        }
    }

    // MARK: Queries
    func item(_ id: String) -> DownloadItem? { items.first { $0.id == id } }
    func isDownloaded(_ id: String) -> Bool { item(id)?.state == .completed }
    var completedCount: Int { items.filter { $0.state == .completed }.count }

    /// Total bytes used by completed downloads on disk.
    var usedBytes: Int64 {
        items.filter { $0.state == .completed }.reduce(0) { $0 + max($1.receivedBytes, $1.totalBytes) }
    }

    /// Rebuild a playable ContentItem pointing at the local file.
    func contentItem(for d: DownloadItem) -> ContentItem? {
        guard let local = Self.completedFileURL(forContentID: d.id) else { return nil }
        switch d.kind {
        case .movie:
            guard var m = d.movie else { return nil }
            m.directURL = local.absoluteString
            return .movie(m)
        case .episode:
            guard var ep = d.episode, let s = d.series else { return nil }
            ep.directURL = local.absoluteString
            return .episode(ep, s)
        }
    }

    // MARK: Start (enqueue → pump → launch)
    func downloadMovie(_ m: Movie) {
        guard items.first(where: { $0.id == m.id })?.state != .completed,
              item(m.id) == nil || item(m.id)?.state == .failed,
              let url = BasePlayerVM.remoteURL(for: .movie(m)) else { return }
        let it = DownloadItem(id: m.id, kind: .movie, title: m.name,
                              subtitle: m.year, posterURL: m.posterURL,
                              state: .queued, receivedBytes: 0, totalBytes: 0,
                              createdAt: Date().timeIntervalSince1970, remoteURL: url.absoluteString,
                              movie: m, episode: nil, series: nil)
        enqueue(it)
    }

    func downloadEpisode(_ ep: Episode, series: Series) {
        guard item(ep.id) == nil || item(ep.id)?.state == .failed,
              let url = BasePlayerVM.remoteURL(for: .episode(ep, series)) else { return }
        let it = DownloadItem(id: ep.id, kind: .episode,
                              title: "\(series.name) — \(L("episode.number")) \(ep.episodeNumber)",
                              subtitle: ep.title.isEmpty ? nil : ep.title,
                              posterURL: ep.posterURL ?? series.coverURL,
                              state: .queued, receivedBytes: 0, totalBytes: 0,
                              createdAt: Date().timeIntervalSince1970, remoteURL: url.absoluteString,
                              movie: nil, episode: ep, series: series)
        enqueue(it)
    }

    // MARK: - Serial download queue
    // IPTV/Xtream lines usually cap simultaneous connections (often 1), so a
    // movie + an episode downloading at once gets the second one REJECTED by the
    // provider ("download failed"). We therefore run ONE download at a time;
    // the rest wait as .queued and start automatically as the slot frees.
    private let maxConcurrent = 1
    private var activeCount: Int { items.filter { $0.state == .downloading }.count }

    private func enqueue(_ it: DownloadItem) {
        items.removeAll { $0.id == it.id }
        items.insert(it, at: 0)          // it.state is already .queued
        persist()
        Self.requestNotifPermission()
        pump()
    }

    /// Start the oldest queued item(s) while a slot is free (FIFO by createdAt).
    private func pump() {
        while activeCount < maxConcurrent,
              let next = items.filter({ $0.state == .queued }).min(by: { $0.createdAt < $1.createdAt }) {
            setState(next.id, .downloading)
            launch(next.id)
        }
    }

    /// Begin the actual transfer for an item already marked .downloading.
    /// Honors resume data (continue), Turbo (parallel), or a fresh background task.
    private func launch(_ id: String) {
        guard let it = item(id), let urlStr = it.remoteURL, let url = URL(string: urlStr) else {
            setState(id, .failed); pump(); return
        }
        let ext = extFor(id)
        if Store.shared.turboDownloads {
            turboTasks[id] = Task { [weak self] in await self?.runTurbo(id: id, url: url, ext: ext) }
        } else {
            launchBackground(id, url: url, ext: ext)   // resume-data-aware internally
        }
    }

    /// Standard, safe path: a single background transfer (resumable, HTTP/3).
    private func launchBackground(_ id: String, url: URL, ext: String) {
        // Resume an interrupted transfer instead of restarting from zero, if we
        // captured resume data from a prior failure (WWDC23 robust transfers).
        let task: URLSessionDownloadTask
        if let rf = Self.resumeFileURL(id), let data = try? Data(contentsOf: rf) {
            try? FileManager.default.removeItem(at: rf)
            task = session.downloadTask(withResumeData: data)
        } else {
            var req = URLRequest(url: url)
            // Identify as VLC — strict IPTV panels reject unknown clients and
            // return a tiny error page, which would "complete" as a corrupt file
            // that won't play. Matches the player + turbo path.
            req.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            task = session.downloadTask(with: req)
        }
        // Wi-Fi-only is enforced at the session-configuration level (covers both
        // the fresh and the resume-data task), so nothing to set per-task here.
        task.taskDescription = "\(id)|\(ext)"
        task.priority = URLSessionTask.highPriority   // ask the system to favor this transfer
        task.resume()
    }

    // MARK: Completion notification
    /// Ask for notification permission. iOS shows the system prompt only once
    /// (while status is undetermined); later calls simply return the current
    /// status, so it's safe to call on download start AND when the Downloads
    /// screen opens — ensuring the user actually gets the chance to allow it.
    static func requestNotifPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    private func notifyComplete(title: String) {
        guard Store.shared.notificationsEnabled else { return }
        let c = UNMutableNotificationContent()
        c.title = L("downloads.notif.title")
        c.body  = title
        c.sound = .default
        c.interruptionLevel = .active
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "s8kdl.\(UUID().uuidString)", content: c, trigger: nil))
    }

    /// Turbo path: download the file in 3 parallel byte-range segments and
    /// stream-concatenate them. Falls back to the safe single transfer when the
    /// server doesn't advertise Range support or the file is small. Runs OFF the
    /// main actor (nonisolated) so the heavy file I/O never blocks the UI.
    private nonisolated func runTurbo(id: String, url: URL, ext: String) async {
        let wifiOnly = Store.shared.downloadWifiOnly
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 7
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = true
        cfg.allowsExpensiveNetworkAccess = !wifiOnly
        cfg.allowsConstrainedNetworkAccess = !wifiOnly
        let s = URLSession(configuration: cfg)
        defer { s.finishTasksAndInvalidate() }   // never leak the turbo session

        // 1) Probe content length + Range support.
        var head = URLRequest(url: url); head.httpMethod = "HEAD"
        head.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        var length: Int64 = 0
        var ranges = false
        if let (_, resp) = try? await s.data(for: head), let http = resp as? HTTPURLResponse {
            length = http.expectedContentLength
            ranges = (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes")) ?? false
        }

        // Fallback to the safe single background transfer when not segmentable.
        guard ranges, length > 30_000_000, let dir = Self.downloadsDir() else {
            await MainActor.run { self.turboTasks[id] = nil; if self.item(id) != nil { self.launchBackground(id, url: url, ext: ext) } }
            return
        }
        // Adaptive parallelism: more connections for bigger files (capped for
        // safety with Xtream simultaneous-connection limits).
        let segments = length > 2_000_000_000 ? 6 : (length > 500_000_000 ? 4 : 3)

        // 2) Download N byte-range segments concurrently → part files.
        let total = length        // immutable snapshot for capture in concurrent tasks
        let chunk = total / Int64(segments)
        var partURLs = [URL?](repeating: nil, count: segments)
        await withTaskGroup(of: (Int, URL?).self) { group in
            for i in 0..<segments {
                let lo = Int64(i) * chunk
                let hi = (i == segments - 1) ? total - 1 : (lo + chunk - 1)
                group.addTask {
                    var req = URLRequest(url: url)
                    req.setValue("bytes=\(lo)-\(hi)", forHTTPHeaderField: "Range")
                    req.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
                    // Require a 206 Partial Content — if the server ignored the
                    // Range and sent 200 (full body), abort so we never stitch a
                    // corrupt file (the safe path will be used instead).
                    guard let (tmp, resp) = try? await s.download(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 206 else { return (i, nil) }
                    let part = dir.appendingPathComponent("dl_\(Self.safeName(id)).part\(i)")
                    try? FileManager.default.removeItem(at: part)
                    let ok = (try? FileManager.default.moveItem(at: tmp, to: part)) != nil
                    return (i, ok ? part : nil)
                }
            }
            for await (i, purl) in group {
                partURLs[i] = purl
                let done = partURLs.filter { $0 != nil }.count
                let received = Int64(Double(total) * Double(done) / Double(segments))
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[idx].totalBytes = total
                        // Don't move the bar backwards on a turbo restart (see pause()).
                        self.items[idx].receivedBytes = max(self.items[idx].receivedBytes, received)
                    }
                }
            }
        }

        // 3a) Cancelled by the user → stop and clean up.
        if Task.isCancelled {
            for p in partURLs.compactMap({ $0 }) { try? FileManager.default.removeItem(at: p) }
            await MainActor.run { self.turboTasks[id] = nil }
            return
        }
        // 3b) A segment failed → fall back to the safe single transfer.
        if partURLs.contains(where: { $0 == nil }) {
            for p in partURLs.compactMap({ $0 }) { try? FileManager.default.removeItem(at: p) }
            await MainActor.run { self.turboTasks[id] = nil; if self.item(id) != nil { self.launchBackground(id, url: url, ext: ext) } }
            return
        }

        // 4) Stream-concatenate the parts into the final file (low memory).
        let dest = dir.appendingPathComponent("dl_\(Self.safeName(id)).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        var success = false
        if let wh = try? FileHandle(forWritingTo: dest) {
            success = true
            for i in 0..<segments {
                guard let p = partURLs[i], let rh = try? FileHandle(forReadingFrom: p) else { success = false; break }
                while let d = try? rh.read(upToCount: 4_000_000), !d.isEmpty { try? wh.write(contentsOf: d) }
                try? rh.close()
                try? FileManager.default.removeItem(at: p)
            }
            try? wh.close()
        }
        // Validate the stitched file against the advertised length — a bogus
        // Content-Length or a truncated segment would otherwise yield a corrupt
        // file. On any doubt, fall back to the safe single transfer.
        let finalSize = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let ok = success && finalSize >= Int64(Double(length) * 0.9)
        if !ok { try? FileManager.default.removeItem(at: dest) }
        await MainActor.run {
            self.turboTasks[id] = nil
            guard self.item(id) != nil else { return }   // user removed it mid-download → no ghost task
            if ok { self.finish(id: id, success: true) }
            else  { self.launchBackground(id, url: url, ext: ext) }
        }
    }

    // MARK: Remove / cancel
    func remove(_ id: String) {
        turboTasks[id]?.cancel(); turboTasks[id] = nil
        session.getAllTasks { tasks in
            tasks.first { ($0.taskDescription ?? "").hasPrefix(id + "|") }?.cancel()
        }
        if let url = Self.completedFileURL(forContentID: id) {
            try? FileManager.default.removeItem(at: url)
        }
        if let rf = Self.resumeFileURL(id) { try? FileManager.default.removeItem(at: rf) }
        // Remove any leftover Turbo part files.
        if let dir = Self.downloadsDir(),
           let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let prefix = "dl_\(Self.safeName(id)).part"
            for f in files where f.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        items.removeAll { $0.id == id }
        persist()
        pump()   // if the removed item held the slot, start the next queued
    }

    func clearAll() {
        for id in items.map(\.id) { remove(id) }   // snapshot ids — remove() mutates items
    }

    // MARK: Pause / resume
    func pause(_ id: String) {
        guard item(id)?.state == .downloading else { return }
        // Turbo has no native partial-resume; resume() re-downloads from zero.
        // Keep the last known progress on screen (frozen) rather than wiping it —
        // updateProgress never lets the counter move backwards, so on resume the
        // bar holds until the restart catches up, instead of snapping to 0%.
        if let t = turboTasks[id] {
            t.cancel(); turboTasks[id] = nil
            setState(id, .paused)
            pump()                       // freed the slot → start next queued
            return
        }
        // Background path: cancel producing resume data, and only flip to .paused
        // AFTER that data is on disk — so a quick resume continues from the byte
        // offset instead of restarting from zero (avoids the write/read race).
        session.getAllTasks { [weak self] tasks in
            guard let task = tasks.first(where: { ($0.taskDescription ?? "").hasPrefix(id + "|") }) as? URLSessionDownloadTask else {
                Task { @MainActor [weak self] in self?.setState(id, .paused); self?.pump() }   // no live task → just mark paused
                return
            }
            task.cancel(byProducingResumeData: { data in
                if let data, let rf = Self.resumeFileURL(id) { try? data.write(to: rf, options: .atomic) }
                Task { @MainActor [weak self] in self?.setState(id, .paused); self?.pump() }
            })
        }
    }

    func resume(_ id: String) {
        guard let it = item(id), it.state == .paused || it.state == .failed else { return }
        // Re-enter the queue: if a slot is free pump() starts it now (launch →
        // launchBackground honors resume data); otherwise it waits its turn.
        setState(id, .queued)
        pump()
    }

    private func setState(_ id: String, _ state: DownloadItem.State) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        persist()
    }
    private func extFor(_ id: String) -> String {
        let e = item(id)?.movie?.containerExtension ?? item(id)?.episode?.containerExtension ?? "mp4"
        return e.isEmpty ? "mp4" : e
    }

    // MARK: Mutations (main-actor, called from delegate hops)
    private func updateProgress(id: String, received: Int64, total: Int64) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        // Never let the visible counter jump backwards: when a paused download
        // resumes on a server that doesn't support byte-range (so the transfer
        // restarts at 0), hold the prior progress until the restart surpasses it.
        // A fresh download starts at 0, so max() is a no-op there.
        items[i].receivedBytes = max(items[i].receivedBytes, received)
        if total > 0 { items[i].totalBytes = total }
    }
    private func finish(id: String, success: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if success {
            items[i].state = .completed
            if items[i].totalBytes > 0 { items[i].receivedBytes = items[i].totalBytes }
            notifyComplete(title: items[i].title)
        } else {
            guard items[i].state == .downloading else { return }   // never downgrade a completed item
            items[i].state = .failed
        }
        persist()
        pump()   // the slot is free → start the next queued download
    }
    private func fail(id: String) {
        // Only a still-downloading item can fail — ignore stale callbacks that
        // would otherwise overwrite a completed download.
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .downloading else { return }
        items[i].state = .failed
        persist()
        pump()   // free the slot for the next queued download
    }

    // MARK: Persistence
    private func persist() {
        guard let url = Self.storeURL(), let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private static func loadItems() -> [DownloadItem] {
        guard let url = storeURL(), let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return [] }
        return arr
    }

    // MARK: Filesystem helpers (nonisolated — pure file work)
    nonisolated static func downloadsDir() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var d = dir
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        return dir
    }
    nonisolated static func storeURL() -> URL? { downloadsDir()?.appendingPathComponent("downloads.json") }

    /// Free space the system is willing to give us for important storage (accounts
    /// for purgeable space — the modern, accurate value). `.max` means unknown.
    nonisolated static func freeBytes() -> Int64 {
        guard let dir = downloadsDir(),
              let v = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage else { return .max }
        return Int64(free)
    }
    /// Warn / confirm below this free-space threshold (~1 GB).
    static let lowSpaceThreshold: Int64 = 1_000_000_000
    nonisolated static func resumeFileURL(_ id: String) -> URL? {
        downloadsDir()?.appendingPathComponent("dl_\(safeName(id)).resume")
    }
    nonisolated static func safeName(_ id: String) -> String {
        String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }
    nonisolated static func ext(of urlString: String) -> String {
        let path = urlString.components(separatedBy: "?").first ?? urlString
        let e = (path as NSString).pathExtension.lowercased()
        return (e.isEmpty || e.count > 5) ? "mp4" : e
    }
    /// The completed local VIDEO file for a content id, if present. Excludes
    /// sidecar files (`.resume`, `.partN`) so we never hand the player a resume
    /// blob or a partial segment instead of the movie.
    nonisolated static func completedFileURL(forContentID id: String) -> URL? {
        guard let dir = downloadsDir() else { return nil }
        let prefix = "dl_\(safeName(id))."
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let match = files.first(where: {
                  $0.hasPrefix(prefix) && !$0.hasSuffix(".resume") && !$0.contains(".part")
              }) else { return nil }
        return dir.appendingPathComponent(match)
    }
}

// MARK: - URLSessionDownloadDelegate (callbacks on a background queue)
extension DownloadService: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let id = (downloadTask.taskDescription ?? "").components(separatedBy: "|").first ?? ""
        Task { @MainActor in
            self.updateProgress(id: id, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The temp file at `location` is valid only until this method returns —
        // move it synchronously NOW.
        let parts = (downloadTask.taskDescription ?? "").components(separatedBy: "|")
        let id  = parts.first ?? ""
        let ext = parts.count > 1 ? parts[1] : "mp4"
        // Validate: a rejected IPTV request often returns 200 with a small HTML/
        // JSON error body. Don't accept that as a finished video.
        let http = downloadTask.response as? HTTPURLResponse
        let code = http?.statusCode ?? 200
        let mime = (http?.mimeType ?? "").lowercased()
        let badBody = mime.contains("html") || mime.contains("json") || mime.contains("text")
        let attrs = try? FileManager.default.attributesOfItem(atPath: location.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        var moved = false
        if (200...299).contains(code), !badBody, size > 64_000, let dir = Self.downloadsDir() {
            let dest = dir.appendingPathComponent("dl_\(Self.safeName(id)).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            moved = (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        }
        let success = moved
        Task { @MainActor in self.finish(id: id, success: success) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }                       // success handled in didFinishDownloadingTo
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }          // user removed it
        let id = (task.taskDescription ?? "").components(separatedBy: "|").first ?? ""
        // Persist resume data (if any) so a later retry continues from where it
        // stopped instead of from zero.
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           let rf = Self.resumeFileURL(id) {
            try? data.write(to: rf, options: .atomic)
        }
        Task { @MainActor in self.fail(id: id) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}

// MARK: - Reusable download control (movie / episode)
enum DownloadTarget {
    case movie(Movie)
    case episode(Episode, Series)
    var id: String {
        switch self {
        case .movie(let m):      return m.id
        case .episode(let e, _): return e.id
        }
    }
}

struct DownloadControl: View {
    let target: DownloadTarget
    var size: CGFloat = 22
    /// When true, shows the live "NN%" next to the ring while downloading.
    var showPercent: Bool = false
    @ObservedObject private var svc = DownloadService.shared
    @State private var showLowSpace = false

    var body: some View {
        let it = svc.item(target.id)
        Button(action: tap) {
            HStack(spacing: 5) {
                if showPercent, it?.state == .downloading || it?.state == .paused {
                    Text("\(Int((it?.progress ?? 0) * 100))%")
                        .font(.system(size: max(10, size * 0.5), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.s8kGoldMid)
                }
                stateIcon(it?.state, progress: it?.progress ?? 0)
            }
        }
        .buttonStyle(S8KButtonStyle())
        .alert(L("downloads.space_low.title"), isPresented: $showLowSpace) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("downloads.space_low.continue")) { startNow() }
        } message: { Text(L("downloads.space_low.msg")) }
    }

    @ViewBuilder
    private func stateIcon(_ st: DownloadItem.State?, progress: Double) -> some View {
        switch st {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size)).foregroundColor(.s8kGreen)
        case .queued:
            Image(systemName: "hourglass")               // waiting for the slot; tap = cancel
                .font(.system(size: size * 0.9)).foregroundColor(.s8kTextSecondary)
        case .downloading:
            ringIcon(progress, glyph: "pause.fill")       // tap = pause
        case .paused:
            ringIcon(progress, glyph: "play.fill")        // tap = resume
        case .failed:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: size * 0.9)).foregroundColor(.s8kOrange)
        default:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size)).foregroundColor(.s8kTextSecondary)
        }
    }
    private func ringIcon(_ progress: Double, glyph: String) -> some View {
        ZStack {
            Circle().stroke(Color.s8kBorder, lineWidth: 2)
            Circle().trim(from: 0, to: max(0.02, CGFloat(progress)))
                .stroke(S8KGradient.goldFlat, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: glyph).font(.system(size: size * 0.34)).foregroundColor(.s8kGoldMid)
        }
        .frame(width: size, height: size)
    }

    private func tap() {
        switch svc.item(target.id)?.state {
        case .downloading:        svc.pause(target.id)      // pause (keeps progress)
        case .queued:             svc.remove(target.id)     // cancel a queued (not-yet-started) item
        case .paused, .failed:    svc.resume(target.id)     // resume / retry
        case .completed:          break                     // delete from the Downloads screen
        default:
            // not downloaded → confirm first if device storage is low.
            if DownloadService.freeBytes() < DownloadService.lowSpaceThreshold { showLowSpace = true }
            else { startNow() }
        }
    }

    private func startNow() {
        switch target {
        case .movie(let m):           svc.downloadMovie(m)
        case .episode(let e, let s):  svc.downloadEpisode(e, series: s)
        }
    }
}

// MARK: - Downloads management screen
struct DownloadsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var svc = DownloadService.shared
    @State private var play: ContentItem? = nil
    @State private var notifDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if svc.items.isEmpty {
                    VStack(spacing: 14) {
                        if notifDenied { notifHint.padding(.horizontal, 20) }
                        EmptyState(icon: "arrow.down.circle", title: L("downloads.empty.title"),
                                   subtitle: L("downloads.empty.sub"))
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if notifDenied { notifHint }
                            storageHeader
                            LazyVStack(spacing: 10) {
                                ForEach(svc.items) { d in row(d) }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .task {
                DownloadService.requestNotifPermission()
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notifDenied = (s.authorizationStatus == .denied)
            }
            .navigationTitle(L("downloads.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid)
                }
                if !svc.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("home.clear_all")) { svc.clearAll() }.foregroundColor(.s8kRed)
                    }
                }
            }
            .fullScreenCover(item: $play) { PlayerView(item: $0) }
        }
    }

    private func row(_ d: DownloadItem) -> some View {
        HStack(spacing: 12) {
            S8KImage(url: d.posterURL, placeholder: d.kind == .movie ? "film" : "tv")
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
            VStack(alignment: .trailing, spacing: 6) {
                Text(d.title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .trailing)
                if d.state == .downloading || d.state == .paused {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(S8KGradient.goldFlat).frame(width: g.size.width * CGFloat(d.progress))
                        }
                    }.frame(height: 4)
                    Text(d.state == .paused ? "\(L("downloads.paused")) · \(Int(d.progress * 100))%"
                                            : "\(Int(d.progress * 100))%")
                        .font(S8KFont.caption2)
                        .foregroundColor(d.state == .paused ? .s8kGoldMid : .s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if d.state == .queued {
                    Text(L("downloads.queued")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if d.state == .failed {
                    Text(L("download.failed")).font(S8KFont.caption2).foregroundColor(.s8kOrange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(byteText(max(d.receivedBytes, d.totalBytes))).font(S8KFont.caption2)
                        .foregroundColor(.s8kTextTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            // Per-state action + delete
            switch d.state {
            case .completed:   ctlBtn("play.circle.fill", 30) { play = svc.contentItem(for: d) }
            case .downloading: ctlBtn("pause.circle.fill", 28) { svc.pause(d.id) }
            case .paused:      ctlBtn("play.circle.fill", 28)  { svc.resume(d.id) }
            case .failed:      ctlBtn("arrow.clockwise.circle.fill", 28) { svc.resume(d.id) }
            case .queued:      Image(systemName: "hourglass").font(.system(size: 22))
                                   .foregroundColor(.s8kTextTertiary)   // waiting; delete to cancel
            }
            Button(action: { svc.remove(d.id) }) {
                Image(systemName: "trash").font(.system(size: 16)).foregroundColor(.s8kTextTertiary)
            }.buttonStyle(S8KButtonStyle())
        }
        .padding(12)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kBorder, lineWidth: 1))
    }

    private func ctlBtn(_ icon: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size)).foregroundColor(.s8kGoldMid)
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func byteText(_ b: Int64) -> String {
        guard b > 0 else { return "" }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    private var storageHeader: some View {
        let free = DownloadService.freeBytes()
        let known = free != .max
        let low = known && free < DownloadService.lowSpaceThreshold
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill").font(.system(size: 15)).foregroundColor(.s8kGoldMid)
                Text(L("downloads.storage_used")).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                Spacer()
                Text(svc.usedBytes > 0 ? byteText(svc.usedBytes) : "0")
                    .font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextPrimary).monospacedDigit()
            }
            if known {
                HStack(spacing: 10) {
                    Image(systemName: low ? "exclamationmark.triangle.fill" : "externaldrive.fill")
                        .font(.system(size: 14)).foregroundColor(low ? .s8kOrange : .s8kTextTertiary)
                    Text(L("downloads.free")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    Spacer()
                    Text(byteText(free)).font(S8KFont.caption2.weight(.semibold))
                        .foregroundColor(low ? .s8kOrange : .s8kTextTertiary).monospacedDigit()
                }
                if low {
                    Text(L("downloads.low_warning")).font(S8KFont.caption2).foregroundColor(.s8kOrange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
            .strokeBorder(low ? Color.s8kOrange.opacity(0.4) : Color.s8kBorder, lineWidth: 1))
    }

    // Shown when the user has denied notifications — tap to open iOS Settings.
    private var notifHint: some View {
        Button(action: {
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "bell.slash.fill").font(.system(size: 14)).foregroundColor(.s8kOrange)
                Text(L("downloads.notif.denied")).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.left").font(.system(size: 11)).foregroundColor(.s8kTextDisabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.s8kOrange.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kOrange.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }
}
