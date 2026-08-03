// ============================================================
// BLANK TV — Downloads.swift
//
// Keeping a movie or an episode on the device so it plays with the network off.
// A live channel has no file behind it, so it is out of scope here.
//
// The transfer itself belongs to iOS, not to us: a background URLSession owns the
// socket, which is what lets the app be suspended, killed or relaunched while the
// bytes keep arriving. Everything we keep sits in one folder under Documents,
// flagged so it never rides along into someone's iCloud quota.
//
// The file reads bottom-up. The four small types at the top — disk layout, free
// space, the tag that survives a relaunch, the manifest — know nothing about the
// engine. The engine knows about them. The two screens know about the engine.
// Nothing points back up.
// ============================================================

import SwiftUI
import Foundation
import UserNotifications

// MARK: - Where a saved download lives on disk
private enum DownloadFiles {
    /// One folder holds everything this feature owns. Created on first use and
    /// marked out of backups: re-downloadable bytes have no business in a backup.
    static func folder() -> URL? {
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

    static func manifest() -> URL? { folder()?.appendingPathComponent("downloads.json") }

    /// A content id carries whatever the panel decided to send. This reduces it to
    /// something a filename can survive.
    static func slug(_ id: String) -> String {
        String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }

    static func resume(for id: String) -> URL? {
        folder()?.appendingPathComponent("dl_\(slug(id)).resume")
    }

    static func partPrefix(for id: String) -> String { "dl_\(slug(id)).part" }

    /// The playable file for a content id, when one finished. Sidecars are filtered
    /// out deliberately — handing the player a resume blob or a fragment would look
    /// to the user exactly like a corrupt movie.
    static func video(for id: String) -> URL? {
        guard let dir = folder() else { return nil }
        let prefix = "dl_\(slug(id))."
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let match = files.first(where: {
                  $0.hasPrefix(prefix) && !$0.hasSuffix(".resume") && !$0.contains(".part")
              }) else { return nil }
        return dir.appendingPathComponent(match)
    }

    /// Put a just-arrived temp file in its place. Synchronous by contract — read the
    /// delegate method that calls it before changing that. `false` means it did not
    /// land, for any reason.
    static func install(_ temp: URL, as id: String, ext: String) -> Bool {
        guard let dir = folder() else { return false }
        let dest = dir.appendingPathComponent("dl_\(slug(id)).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        return (try? FileManager.default.moveItem(at: temp, to: dest)) != nil
    }

    /// Erase every trace of one id: the video, its resume blob, and any numbered
    /// fragments. The fragments come from a segmented downloader this app no longer
    /// runs, but installed devices can still be carrying the leftovers.
    static func deleteEverything(for id: String) {
        if let v = video(for: id) { try? FileManager.default.removeItem(at: v) }
        if let r = resume(for: id) { try? FileManager.default.removeItem(at: r) }
        guard let dir = folder(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let prefix = partPrefix(for: id)
        for n in names where n.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }
}

/// Does what arrived actually look like a video? A refused request on a strict panel
/// often answers 200 with a few hundred bytes of HTML or JSON, and filing that away as
/// a finished movie is how a download "succeeds" and then plays nothing.
///
/// Plain, synchronous, non-isolated on purpose: its caller has to finish its work
/// before returning.
/// What actually arrived, when it is not a video — or nil when it is one.
///
/// This RECORDS, it does not INTERPRET. A first draft of this function mapped 403 to
/// "the line is busy" and 404 to "the link is gone", which is a theory about someone
/// else's server dressed up as a fact for the user. We do not know what this provider
/// answers or why; nobody has ever looked, because the old code returned a bare Bool
/// and every cause collapsed into one wordless "failed" row.
///
/// So the string is the evidence — status code, media type, size — in a form the owner
/// can read off a phone and hand back. Once we know what the server actually says, the
/// wording can become human. Not before.
///
/// Note this is where a REFUSED download lands, not the error callback: URLSession
/// treats an HTTP error as a successful download of the error body.
private func videoRejection(_ response: URLResponse?, tempFile: URL) -> String? {
    let http = response as? HTTPURLResponse
    let code = http?.statusCode ?? 200
    let mime = (http?.mimeType ?? "").lowercased()
    let attrs = try? FileManager.default.attributesOfItem(atPath: tempFile.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

    if !(200...299).contains(code) { return "HTTP \(code)" }
    if mime.contains("html") || mime.contains("json") || mime.contains("text") {
        return "\(mime) · \(size) B"
    }
    if size <= 64_000 { return "\(size) B" }
    return nil
}

// MARK: - How much room is left
private enum DownloadBudget {
    /// Under roughly a gigabyte free, ask before starting anything new.
    static let lowWaterMark: Int64 = 1_000_000_000

    /// What the system says it would actually hand over for important storage,
    /// purgeable space included. `.max` means it declined to say.
    static func freeForImportantUse() -> Int64 {
        guard let dir = DownloadFiles.folder(),
              let v = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage else { return .max }
        return Int64(free)
    }
}

// MARK: - The one string that survives a relaunch
/// `taskDescription` is the only field still attached to a transfer that iOS restored
/// from an earlier run of this process, so the content id and the container extension
/// travel inside it. Its layout is fixed by tasks already sitting on devices; this type
/// is the only place allowed to know that layout.
private enum DownloadTaskTag {
    static func make(id: String, ext: String) -> String { "\(id)|\(ext)" }

    static func id(of task: URLSessionTask) -> String {
        (task.taskDescription ?? "").components(separatedBy: "|").first ?? ""
    }

    static func idAndExt(of task: URLSessionTask) -> (id: String, ext: String) {
        let parts = (task.taskDescription ?? "").components(separatedBy: "|")
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "mp4")
    }

    static func belongs(_ task: URLSessionTask, to id: String) -> Bool {
        (task.taskDescription ?? "").hasPrefix(id + "|")
    }
}

// MARK: - The manifest on disk
private enum DownloadManifest {
    /// Serial, so snapshots always land in the order they were taken. Two detached
    /// tasks could otherwise finish out of order and leave the OLDER state on disk.
    private static let writer = DispatchQueue(label: "com.blanktv.downloads.persist",
                                              qos: .utility)

    /// Decodes each entry INDEPENDENTLY. `decode([SavedDownload].self, …)` is
    /// all-or-nothing: ONE entry this build cannot read — a manifest half-written when
    /// the app was killed, or an embedded model that gained a required field — made the
    /// whole decode throw, the `try?` swallowed it, and the user's ENTIRE download
    /// library vanished with every file still sitting on disk, unreachable. A per-entry
    /// decode loses only the entry that is actually broken.
    private struct Lenient: Decodable {
        let value: SavedDownload?
        init(from decoder: Decoder) throws { value = try? SavedDownload(from: decoder) }
    }

    static func load() -> [SavedDownload] {
        guard let url = DownloadFiles.manifest(),
              let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        if let rows = try? JSONDecoder().decode([Lenient].self, from: data) {
            return rows.compactMap(\.value)
        }
        // TOTAL failure — the payload is not even an array, so the per-entry decode
        // above never got to run. Returning [] on its own is NOT safe: the next
        // write(_:) puts that empty list straight over the file and the loss becomes
        // permanent. Move the original bytes aside first, so a manifest this build
        // cannot read is still a manifest that exists.
        let parked = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        try? FileManager.default.removeItem(at: parked)
        try? FileManager.default.moveItem(at: url, to: parked)
        return []
    }

    /// The array arrives already copied, taken by the caller on the main actor. What
    /// crosses over is the encode and the write: `SavedDownload` embeds the whole
    /// `Series` tree — every season and every episode — so this is not a small encode,
    /// and progress persistence reaches it every 3s for the life of a transfer.
    static func write(_ snapshot: [SavedDownload]) {
        guard let url = DownloadFiles.manifest() else { return }
        writer.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - One saved download
struct SavedDownload: Codable, Identifiable, Hashable {
    let id: String                 // the content id, straight off the model
    let kind: Kind
    let title: String
    let subtitle: String?
    let posterURL: String?
    var state: State
    var receivedBytes: Int64
    var totalBytes: Int64
    let createdAt: Double
    /// Where the bytes come from. Kept on the record because a paused item may have to
    /// begin again at zero, and the model's own directURL is not part of what we store.
    /// Optional so a manifest written before this field existed still reads.
    var remoteURL: String? = nil
    /// Why the last attempt stopped, in the user's language. Nil until something fails.
    ///
    /// Before this existed, a failure was a dead end: the row said "failed" and neither
    /// the user nor we could tell a refused connection from a dead link from a full
    /// disk. Optional, so a manifest written before this field existed still decodes —
    /// and it MUST stay optional for that reason. A non-optional with a default does
    /// NOT survive Swift's synthesised decoder: it throws on the missing key, the
    /// per-entry lenient decode drops the row, and every saved download silently
    /// disappears on update.
    var failureReason: String? = nil
    /// How many times we have restarted this item after a transient failure. Optional
    /// for exactly the same decoding reason.
    var attempts: Int? = nil
    // The models ride along so the item can be played with no network at all; the
    // directURL is swapped for the local file at play time.
    let movie:   Movie?
    let episode: Episode?
    let series:  Series?

    var progress: Double { totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0 }
    func hash(into h: inout Hasher) { h.combine(id) }
    static func == (a: SavedDownload, b: SavedDownload) -> Bool { a.id == b.id }

    enum Kind:  String, Codable { case movie, episode }
    /// `.queued` means the item is waiting for the single active transfer slot.
    enum State: String, Codable { case queued, downloading, paused, completed, failed }
}

// MARK: - Download engine
@MainActor
final class DownloadService: NSObject, ObservableObject {
    static let shared = DownloadService()

    /// The one source of truth both screens observe. Nothing else here is published,
    /// so every change a user can see has to arrive through this array.
    @Published private(set) var items: [SavedDownload] = []

    /// Handed over by the app delegate when iOS wakes the process to finish background
    /// transfers; called once the last event has been delivered.
    var backgroundCompletion: (() -> Void)?

    private var lastManifestWrite: TimeInterval = 0

    private lazy var bgSession: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.blanktv.player.downloads")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        // The Wi-Fi restriction is a property of the SESSION, not of a task — which is
        // the only way to make it hold for a task rebuilt from resume data too. Paired
        // with waitsForConnectivity it parks the transfer until Wi-Fi is back instead of
        // failing it. A fresh session is built every launch, so the switch is re-read
        // every launch as well.
        let wifiOnly = Store.shared.downloadWifiOnly
        cfg.allowsCellularAccess           = !wifiOnly
        cfg.allowsExpensiveNetworkAccess   = !wifiOnly
        cfg.allowsConstrainedNetworkAccess = !wifiOnly
        // HTTP/3 is negotiated by URLSession itself on current iOS. Lifting the per-host
        // ceiling off its default of four keeps a server that fans one file across
        // several channels from throttling against us.
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        items = DownloadManifest.load()
        // Touching the lazy session is not incidental: building it is what re-attaches
        // this process to transfers iOS kept running while we were gone.
        _ = bgSession
        resyncWithSession()
    }

    // MARK: One slot, oldest first
    // A provider line usually allows a single simultaneous connection, so two transfers
    // at once means the second is refused — and the user reads that as a download that
    // failed. One runs; the rest sit in `.queued` and are pulled in as the slot frees.
    private let slotCount = 1
    private var busySlots: Int { items.filter { $0.state == .downloading }.count }

    private func admit(_ new: SavedDownload) {
        items.removeAll { $0.id == new.id }
        items.insert(new, at: 0)          // it already carries .queued
        saveManifest()
        Self.promptForNotifications()
        advanceQueue()
    }

    /// Fill every free slot with the longest-waiting queued item.
    private func advanceQueue() {
        while busySlots < slotCount,
              let next = items.filter({ $0.state == .queued }).min(by: { $0.createdAt < $1.createdAt }) {
            transition(next.id, to: .downloading)
            startTransfer(next.id)
        }
    }

    // MARK: Handing a transfer to the system
    /// Owns the lifecycle of one transfer for an item already marked `.downloading`.
    private func startTransfer(_ id: String) {
        guard let it = item(id), let raw = it.remoteURL, let url = URL(string: raw) else {
            transition(id, to: .failed); advanceQueue(); return
        }
        let task = makeTask(id: id, url: url, ext: containerExt(for: id))
        task.resume()
    }

    /// Builds a configured but UN-started task: continued from a saved resume blob when
    /// one is waiting, otherwise a fresh request.
    private func makeTask(id: String, url: URL, ext: String) -> URLSessionDownloadTask {
        let task: URLSessionDownloadTask
        if let rf = DownloadFiles.resume(for: id), let blob = try? Data(contentsOf: rf) {
            try? FileManager.default.removeItem(at: rf)
            task = bgSession.downloadTask(withResumeData: blob)
        } else {
            var req = URLRequest(url: url)
            // Panels that filter on the client string answer an unrecognised one with a
            // tiny error body, which would land as a file that plays as nothing. Send
            // the same identity the player sends.
            req.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            task = bgSession.downloadTask(with: req)
        }
        // Nothing network-related is set per task: the session configuration above
        // already covers both shapes of task.
        task.taskDescription = DownloadTaskTag.make(id: id, ext: ext)
        task.priority = URLSessionTask.highPriority   // ask the system to favour this one
        return task
    }

    private func containerExt(for id: String) -> String {
        let e = item(id)?.movie?.containerExtension ?? item(id)?.episode?.containerExtension ?? "mp4"
        return e.isEmpty ? "mp4" : e
    }

    // MARK: What the screens ask for
    func downloadMovie(_ m: Movie) {
        guard items.first(where: { $0.id == m.id })?.state != .completed,
              item(m.id) == nil || item(m.id)?.state == .failed,
              let url = BasePlayerVM.remoteURL(for: .movie(m)) else { return }
        let entry = SavedDownload(id: m.id, kind: .movie, title: m.name,
                                  subtitle: m.year, posterURL: m.posterURL,
                                  state: .queued, receivedBytes: 0, totalBytes: 0,
                                  createdAt: Date().timeIntervalSince1970, remoteURL: url.absoluteString,
                                  movie: m, episode: nil, series: nil)
        admit(entry)
    }

    func downloadEpisode(_ ep: Episode, series: Series) {
        guard item(ep.id) == nil || item(ep.id)?.state == .failed,
              let url = BasePlayerVM.remoteURL(for: .episode(ep, series)) else { return }
        let entry = SavedDownload(id: ep.id, kind: .episode,
                                  title: "\(series.name) — \(L("episode.number")) \(ep.episodeNumber)",
                                  subtitle: ep.title.isEmpty ? nil : ep.title,
                                  posterURL: ep.posterURL ?? series.coverURL,
                                  state: .queued, receivedBytes: 0, totalBytes: 0,
                                  createdAt: Date().timeIntervalSince1970, remoteURL: url.absoluteString,
                                  movie: nil, episode: ep, series: series)
        admit(entry)
    }

    func pause(_ id: String) {
        guard item(id)?.state == .downloading else { return }
        // Cancel in the shape that produces resume data, and only flip to `.paused`
        // AFTER that blob is on disk — otherwise a fast tap-pause-tap-resume reads a
        // file that is not written yet and the transfer restarts from byte zero.
        bgSession.getAllTasks { [weak self] tasks in
            guard let task = tasks.first(where: { DownloadTaskTag.belongs($0, to: id) }) as? URLSessionDownloadTask else {
                Task { @MainActor [weak self] in self?.transition(id, to: .paused); self?.advanceQueue() }   // no live task
                return
            }
            task.cancel(byProducingResumeData: { data in
                if let data, let rf = DownloadFiles.resume(for: id) { try? data.write(to: rf, options: .atomic) }
                Task { @MainActor [weak self] in self?.transition(id, to: .paused); self?.advanceQueue() }
            })
        }
    }

    func resume(_ id: String) {
        guard let it = item(id), it.state == .paused || it.state == .failed else { return }
        // Back into the line: a free slot starts it immediately, otherwise it waits its
        // turn. `makeTask` is what notices the saved resume blob.
        transition(id, to: .queued)
        advanceQueue()
    }

    func remove(_ id: String) {
        bgSession.getAllTasks { tasks in
            tasks.first { DownloadTaskTag.belongs($0, to: id) }?.cancel()
        }
        DownloadFiles.deleteEverything(for: id)
        items.removeAll { $0.id == id }
        saveManifest()
        advanceQueue()   // if the removed item held the slot, the next one takes it
    }

    func clearAll() {
        for id in items.map(\.id) { remove(id) }   // snapshot the ids: remove() mutates items
    }

    // MARK: Every write to items goes through here
    private func transition(_ id: String, to state: SavedDownload.State) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        saveManifest()
    }

    private func recordProgress(id: String, received: Int64, total: Int64) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        // The figure the user is watching may only ever climb. A server with no
        // byte-range support answers a resumed item by sending the file again from the
        // top, and reporting that honestly would snap the bar back to 0% and read as
        // lost work; hold the old number until the second attempt overtakes it. On a
        // download that really is new the incoming value is already the larger one, so
        // max() decides nothing.
        items[i].receivedBytes = max(items[i].receivedBytes, received)
        if total > 0 { items[i].totalBytes = total }
        // Persist the figure, throttled. This ran in memory ONLY, so a relaunch showed
        // whatever percentage happened to be saved when the state last changed —
        // usually 0 — no matter how far the transfer had actually got. Throttled to
        // once every 3s because the delegate fires on every chunk and this writes the
        // whole manifest.
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastManifestWrite > 3 {
            lastManifestWrite = now
            saveManifest()
        }
    }

    private func settle(id: String, completed: Bool, why: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if completed {
            items[i].state = .completed
            items[i].failureReason = nil
            if items[i].totalBytes > 0 { items[i].receivedBytes = items[i].totalBytes }
            postCompletionNotice(title: items[i].title)
        } else {
            guard items[i].state == .downloading else { return }   // a finished item stays finished
            items[i].state = .failed
            items[i].failureReason = why
        }
        saveManifest()
        advanceQueue()
    }

    private func markFailed(id: String, why: String? = nil) {
        // Only something still transferring can fail. A late callback for anything else
        // is stale and must not overwrite the state the user is looking at.
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .downloading else { return }
        items[i].state = .failed
        items[i].failureReason = why
        saveManifest()
        advanceQueue()
    }

    private func saveManifest() { DownloadManifest.write(items) }

    // MARK: Picking up where the last process stopped
    /// Compare what we wrote down against what the session still has running: an item
    /// recorded as transferring whose task is gone goes back in the line, while one whose
    /// task is alive keeps the slot it is holding. Then run the queue, so anything
    /// persisted as waiting gets its turn.
    private func resyncWithSession() {
        guard items.contains(where: { $0.state == .downloading || $0.state == .queued }) else { return }
        bgSession.getAllTasks { [weak self] tasks in
            let live = Set(tasks.map { DownloadTaskTag.id(of: $0) })
            Task { @MainActor in
                guard let self else { return }
                var changed = false
                // OWNER-REPORTED: a download sat at 1% and never moved again. iOS
                // CANCELS background transfers when the user force-quits the app, so on
                // the next launch the task is gone — and this used to mark the item
                // `.paused` and stop there. Nothing anywhere called `resume`, so the
                // download was simply over, silently, and looked like a broken app.
                // `.queued` instead: `advanceQueue()` below restarts it in a free slot,
                // and `makeTask` picks up the saved resume data, so it continues from
                // where it stopped rather than from zero.
                for i in self.items.indices
                where self.items[i].state == .downloading && !live.contains(self.items[i].id) {
                    self.items[i].state = .queued; changed = true
                }
                if changed { self.saveManifest() }
                self.advanceQueue()   // start anything waiting, in the freed slot(s)
            }
        }
    }

    // MARK: Telling the user it finished
    /// iOS raises the system prompt only while the status is undetermined and simply
    /// reports the current one afterwards, so calling this both when a download starts
    /// and when the library opens costs nothing and gives the user two chances to say
    /// yes.
    static func promptForNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func postCompletionNotice(title: String) {
        guard Store.shared.notificationsEnabled else { return }
        let c = UNMutableNotificationContent()
        c.title = L("downloads.notif.title")
        c.body  = title
        c.sound = .default
        c.interruptionLevel = .active
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "blanktv.download.\(UUID().uuidString)", content: c, trigger: nil))
    }

    nonisolated static func completedFileURL(forContentID id: String) -> URL? { DownloadFiles.video(for: id) }
}

// MARK: - Reads the views depend on
extension DownloadService {
    func item(_ id: String) -> SavedDownload? { items.first { $0.id == id } }

    /// What the finished downloads occupy.
    var usedBytes: Int64 {
        items.filter { $0.state == .completed }.reduce(0) { $0 + max($1.receivedBytes, $1.totalBytes) }
    }

    /// Rebuild something playable whose URL is the local file rather than the panel.
    func contentItem(for d: SavedDownload) -> ContentItem? {
        guard let local = DownloadFiles.video(for: d.id) else { return nil }
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
}

// MARK: - Bridge from URLSession's queue back to the main actor
// Every method below is called on the session's own private queue, never on main —
// which is why each is nonisolated and why each ends by hopping.
extension DownloadService: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let id = DownloadTaskTag.id(of: downloadTask)
        Task { @MainActor in
            self.recordProgress(id: id, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // `location` stops existing the moment this method returns, so the inspection
        // and the move both have to happen right here, synchronously. `&&` short-circuits:
        // nothing is moved unless the response passed.
        let (id, ext) = DownloadTaskTag.idAndExt(of: downloadTask)
        // Evaluate the response BEFORE moving, and keep the reason. `&&` short-circuits,
        // so nothing is installed unless the response passed.
        let rejection = videoRejection(downloadTask.response, tempFile: location)
        var why = rejection
        var landed = false
        if rejection == nil {
            landed = DownloadFiles.install(location, as: id, ext: ext)
            if !landed { why = "install failed" }   // disk full, or the folder is gone
        }
        Task { @MainActor in self.settle(id: id, completed: landed, why: why) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }                       // a success arrives at the method above
        let ns = error as NSError
        let id = DownloadTaskTag.id(of: task)
        // Save resume data BEFORE the cancellation check below — it used to return
        // first, and that discarded the resume data on the one failure it exists for.
        // iOS CANCELS background transfers when the user force-quits, so the owner's
        // "stuck at 1%" download arrives here as NSURLErrorCancelled. With nothing
        // saved, the relaunch restarted it from byte 0 while the progress bar still
        // showed the old percentage — the download looked frozen all over again.
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           let rf = DownloadFiles.resume(for: id) {
            try? data.write(to: rf, options: .atomic)
            // `remove()` deletes the resume file BEFORE this callback arrives, so a
            // cancellation the USER caused would otherwise leave an orphan on disk
            // forever. Sweep it as soon as we can read `items`.
            Task { @MainActor in
                if !self.items.contains(where: { $0.id == id }) {
                    try? FileManager.default.removeItem(at: rf)
                }
            }
        }
        if ns.code == NSURLErrorCancelled { return }          // removed by the user, or force-quit
        // The domain and code, verbatim. Naming them ("no connection", "timed out")
        // would be a guess about which of ~60 URLError values this actually is.
        let why = "\(ns.domain) \(ns.code)"
        Task { @MainActor in self.markFailed(id: id, why: why) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}

// MARK: - Byte sizes, Western digits on every device
/// NOT `ByteCountFormatter`, and that is the point: it has no `locale` property at
/// all, so it always follows the DEVICE and renders ١٢٣ MB on an Arabic phone. The
/// app pins its numbering system once in BlankTVApp, but a formatter built in code
/// never sees that environment — and this one cannot be told. So the number is
/// formatted through a pinned NumberFormatter and the unit is appended.
///
/// Binary units (1024) with the SI-style labels, which is what a download UI wants:
/// the figure should match what the file occupies, not what the marketing says.
private enum DownloadByteText {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024; unit += 1
        }
        // Whole numbers below MB: "512 KB" reads better than "512.0 KB".
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return text + " " + units[unit]
    }
}

// MARK: - Library of saved downloads
struct DownloadsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var svc = DownloadService.shared
    @State private var play: ContentItem? = nil
    @State private var notifDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if svc.items.isEmpty { blankSlate } else { savedList }
            }
            .task {
                DownloadService.promptForNotifications()
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notifDenied = (s.authorizationStatus == .denied)
            }
            .navigationTitle(L("downloads.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { bar }
            .fullScreenCover(item: $play) { PlayerView(item: $0) }
        }
    }

    private var blankSlate: some View {
        VStack(spacing: 14) {
            if notifDenied { notifHint.padding(.horizontal, 20) }
            EmptyState(icon: "arrow.down.circle", title: L("downloads.empty.title"),
                       subtitle: L("downloads.empty.sub"))
        }
    }

    private var savedList: some View {
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

    @ToolbarContentBuilder
    private var bar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid)
        }
        if !svc.items.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("home.clear_all")) { svc.clearAll() }.foregroundColor(.s8kRed)
            }
        }
    }

    /// Offered when the user has turned notifications down — tapping it opens Settings.
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

    private var storageHeader: some View {
        let free = DownloadBudget.freeForImportantUse()
        let known = free != .max
        let low = known && free < DownloadBudget.lowWaterMark
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill").font(.system(size: 15)).foregroundColor(.s8kGoldMid)
                Text(L("downloads.storage_used")).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                Spacer()
                Text(svc.usedBytes > 0 ? DownloadByteText.string(svc.usedBytes) : "0")
                    .font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextPrimary).monospacedDigit()
            }
            if known {
                HStack(spacing: 10) {
                    Image(systemName: low ? "exclamationmark.triangle.fill" : "externaldrive.fill")
                        .font(.system(size: 14)).foregroundColor(low ? .s8kOrange : .s8kTextTertiary)
                    Text(L("downloads.free")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    Spacer()
                    Text(DownloadByteText.string(free)).font(S8KFont.caption2.weight(.semibold))
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

    private func row(_ d: SavedDownload) -> some View {
        HStack(spacing: 12) {
            S8KImage(url: d.posterURL, placeholder: d.kind == .movie ? "film" : "tv")
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
            VStack(alignment: .trailing, spacing: 6) {
                Text(d.title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .trailing)
                switch d.state {
                case .downloading, .paused:
                    S8KProgressBar(fraction: d.progress, track: Color.white.opacity(0.08), height: 4)
                    Text(d.state == .paused ? "\(L("downloads.paused")) · \(Int(d.progress * 100))%"
                                            : "\(Int(d.progress * 100))%")
                        .font(S8KFont.caption2)
                        .foregroundColor(d.state == .paused ? .s8kGoldMid : .s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                case .queued:
                    Text(L("downloads.queued")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                case .failed:
                    // The reason rides beside the word, unedited. A bare "failed" told
                    // nobody anything — not the user, and not us: this row is the only
                    // place the evidence can reach a person holding the phone.
                    HStack(spacing: 6) {
                        if let why = d.failureReason {
                            Text(why)
                                .font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                                .lineLimit(1).truncationMode(.middle)
                                .monospacedDigit()
                        }
                        Text(L("download.failed")).font(S8KFont.caption2).foregroundColor(.s8kOrange)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                case .completed:
                    Text(DownloadByteText.string(max(d.receivedBytes, d.totalBytes))).font(S8KFont.caption2)
                        .foregroundColor(.s8kTextTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            actionControl(for: d)
            Button(action: { svc.remove(d.id) }) {
                Image(systemName: "trash").font(.system(size: 16)).foregroundColor(.s8kTextTertiary)
                    // 16pt glyph → 44pt tall inside an 84pt row. Sideways it can only take
                    // 6: the state button is 12pt away, and this one deletes.
                    .s8kMinTouch(h: 6, v: 14)
            }.buttonStyle(S8KButtonStyle())
            .accessibilityLabel(L("common.delete"))
        }
        .padding(12)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kBorder, lineWidth: 1))
    }

    /// The single control that belongs to the row's current state.
    @ViewBuilder
    private func actionControl(for d: SavedDownload) -> some View {
        switch d.state {
        case .completed:   actionButton("play.circle.fill", size: 30, a11y: L("common.play")) { play = svc.contentItem(for: d) }
        case .downloading: actionButton("pause.circle.fill", size: 28, a11y: L("a11y.pause")) { svc.pause(d.id) }
        case .paused:      actionButton("play.circle.fill", size: 28, a11y: L("common.play")) { svc.resume(d.id) }
        case .failed:      actionButton("arrow.clockwise.circle.fill", size: 28, a11y: L("a11y.refresh")) { svc.resume(d.id) }
        case .queued:      Image(systemName: "hourglass").font(.system(size: 22))
                               .foregroundColor(.s8kTextTertiary)   // nothing to stop yet; the bin cancels it
        }
    }

    private func actionButton(_ icon: String, size: CGFloat, a11y: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size)).foregroundColor(.s8kGoldMid)
                // 28-30pt glyphs. 8 vertically clears 44 inside the 84pt row; 6 is half
                // the 12pt gap to the delete button, so pause/resume and delete cannot
                // reach into each other.
                .s8kMinTouch(h: 6, v: 8)
        }
        .buttonStyle(S8KButtonStyle())
        .accessibilityLabel(a11y.isEmpty ? icon : a11y)
    }
}

// MARK: - The inline download button
enum DownloadTarget {
    case movie(Movie)
    case episode(Episode, Series)
    var contentID: String {
        switch self {
        case .movie(let m):      return m.id
        case .episode(let e, _): return e.id
        }
    }
}

struct DownloadControl: View {
    let target: DownloadTarget
    var size: CGFloat = 22
    /// Set this to put the running "NN%" beside the ring.
    var showPercent: Bool = false
    @ObservedObject private var svc = DownloadService.shared
    @State private var showLowSpace = false

    var body: some View {
        let it = svc.item(target.contentID)
        Button(action: handleTap) {
            HStack(spacing: 5) {
                if showPercent, it?.state == .downloading || it?.state == .paused {
                    Text("\(Int((it?.progress ?? 0) * 100))%")
                        .font(.system(size: max(10, size * 0.5), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.s8kGoldMid)
                }
                glyph(for: it?.state, progress: it?.progress ?? 0)
            }
            // The icon is 18pt in an episode row. Callers wrap this control in a 40-48pt
            // frame, but that frame is applied OUTSIDE the Button and so does nothing for
            // the hit area — the tappable region was the glyph itself, and a miss landed
            // on the row behind it and PLAYED the episode instead of downloading it.
            // The minimum has to live inside the label, where the Button can see it.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
        .alert(L("downloads.space_low.title"), isPresented: $showLowSpace) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("downloads.space_low.continue")) { beginDownload() }
        } message: { Text(L("downloads.space_low.msg")) }
    }

    private func handleTap() {
        switch svc.item(target.contentID)?.state {
        case .downloading:        svc.pause(target.contentID)     // hold it, keeping the progress
        case .queued:             svc.remove(target.contentID)    // it never started — drop it
        case .paused, .failed:    svc.resume(target.contentID)    // carry on / try again
        case .completed:          break                           // removal happens on the library screen
        default:
            // Nothing saved yet. Ask first if the device is nearly full.
            if DownloadBudget.freeForImportantUse() < DownloadBudget.lowWaterMark { showLowSpace = true }
            else { beginDownload() }
        }
    }

    private func beginDownload() {
        switch target {
        case .movie(let m):           svc.downloadMovie(m)
        case .episode(let e, let s):  svc.downloadEpisode(e, series: s)
        }
    }

    @ViewBuilder
    private func glyph(for st: SavedDownload.State?, progress: Double) -> some View {
        switch st {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size)).foregroundColor(.s8kGreen)
        case .queued:
            Image(systemName: "hourglass")                 // holding for the slot; a tap drops it
                .font(.system(size: size * 0.9)).foregroundColor(.s8kTextSecondary)
        case .downloading:
            progressRing(progress, symbol: "pause.fill")   // a tap holds it
        case .paused:
            progressRing(progress, symbol: "play.fill")    // a tap carries on
        case .failed:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: size * 0.9)).foregroundColor(.s8kOrange)
        default:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size)).foregroundColor(.s8kTextSecondary)
        }
    }

    private func progressRing(_ progress: Double, symbol: String) -> some View {
        ZStack {
            Circle().stroke(Color.s8kBorder, lineWidth: 2)
            Circle().trim(from: 0, to: max(0.02, CGFloat(progress)))
                .stroke(S8KGradient.goldFlat, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol).font(.system(size: size * 0.34)).foregroundColor(.s8kGoldMid)
        }
        .frame(width: size, height: size)
    }
}
