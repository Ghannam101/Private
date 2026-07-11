// ============================================================
// BLANK TV — Models.swift
// All Data Models — Codable, Identifiable, Hashable
// ============================================================

import Foundation

// MARK: - Login Mode (Xtream Codes vs M3U Playlist)
enum LoginMode: String, Codable {
    case xtream, m3u
}

// MARK: - Saved Playlist (multiple playlists support)
struct SavedPlaylist: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var kind: LoginMode
    var url: String            // m3u url, or xtream server base
    var username: String? = nil
    var password: String? = nil

    var subtitle: String {
        kind == .m3u ? "M3U" : "Xtream · \(username ?? "")"
    }
}

// MARK: - Theme Config
struct ThemeConfig: Codable {
    let primaryColor:    String
    let accentColor:     String
    let backgroundColor: String
    let logoURL:         String?
    let serverName:      String
}

// MARK: - Features Config
struct FeaturesConfig: Codable {
    let catchUp:         Bool
    let multiScreen:     Bool
    let downloads:       Bool
    let quality4K:       Bool
    let epg:             Bool
    let parentalControl: Bool
    let sleepTimer:      Bool
    let watchlist:       Bool

    static let defaults = FeaturesConfig(
        catchUp: true, multiScreen: true, downloads: false,
        quality4K: true, epg: true, parentalControl: true,
        sleepTimer: true, watchlist: true
    )
}

// MARK: - App Config
struct AppConfig: Codable {
    let bannerURL:          String?
    let bannerLink:         String?
    let storeURL:           String?
    let supportWhatsApp:    String?
    let supportTelegram:    String?
    let announcement:       String?
    let maintenanceMode:    Bool
    let maintenanceMessage: String?
    let minAppVersion:      String

    static let defaults = AppConfig(
        bannerURL: nil, bannerLink: nil, storeURL: nil,
        supportWhatsApp: nil, supportTelegram: nil,
        announcement: nil, maintenanceMode: false,
        maintenanceMessage: nil, minAppVersion: "1.0.0"
    )
}

// MARK: - User Info
struct UserInfo: Codable, Identifiable {
    let id:             String
    let username:       String
    let maxConnections: Int
    let expiresAt:      TimeInterval
    let plan:           String
    let status:         String

    var isExpired: Bool {
        Date().timeIntervalSince1970 > expiresAt
    }
    var expiryDate: Date {
        Date(timeIntervalSince1970: expiresAt)
    }
    var daysRemaining: Int {
        max(0, Int((expiresAt - Date().timeIntervalSince1970) / 86400))
    }
}

// MARK: - Server Info
struct ServerInfo: Codable {
    let host:     String
    let username: String
    let password: String
    let port:     Int

    var baseURL: String { "\(host)" }
}

// MARK: - Login Request
struct LoginRequest: Encodable {
    let username:    String
    let password:    String
    let deviceID:    String
    let deviceModel: String
    let appVersion:  String
}

// MARK: - Login Response
struct LoginResponse: Decodable {
    let token:     String
    let expiresAt: TimeInterval
    let user:      UserInfo
    let server:    ServerInfo
    let theme:     ThemeConfig
    let features:  FeaturesConfig
    let config:    AppConfig
}

// MARK: - Remote Config Response
struct RemoteConfigResponse: Decodable {
    let theme:    ThemeConfig
    let features: FeaturesConfig
    let config:   AppConfig
}

// MARK: - Channel
struct Channel: Codable, Identifiable, Hashable {
    let id:           String
    let name:         String
    let logoURL:      String?
    let groupTitle:   String
    let epgChannelID: String?
    var isFavorite:   Bool = false
    // Direct stream URL (M3U playlists) — not part of the API payload
    var directURL:    String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Channel, r: Channel) -> Bool { l.id == r.id }

    func streamURL(host: String, user: String, pass: String) -> URL? {
        URL(string: "\(host)/live/\(user)/\(pass)/\(id).m3u8")
    }

    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case logoURL = "stream_icon"
        case groupTitle = "category_name"
        case epgChannelID = "epg_channel_id"
    }
}

// MARK: - Category
struct Category: Codable, Identifiable, Hashable {
    let id:       String
    let name:     String
    let parentID: String?

    static func == (l: Category, r: Category) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    enum CodingKeys: String, CodingKey {
        case id       = "category_id"
        case name     = "category_name"
        case parentID = "parent_id"
    }

    // All categories sentinel
    static let all = Category(id: "all", name: "الكل", parentID: nil)
    // Favorites pseudo-category sentinel (iPad sidebar): when selected, the pane
    // shows the user's favorites across all categories instead of a real folder.
    static let favoritesID = "s8k_favorites_sentinel"
    static let favorites = Category(id: favoritesID, name: "المفضلة", parentID: nil)
}

// MARK: - Movie (VOD)
struct Movie: Codable, Identifiable, Hashable {
    let id:                 String
    let name:               String
    let posterURL:          String?
    let backdropURL:        String?
    let year:               String?
    let rating:             String?
    let genre:              String?
    let plot:               String?
    let duration:           String?
    let director:           String?
    let cast:               String?
    let categoryID:         String
    let containerExtension: String
    var isFavorite: Bool = false
    // Direct stream URL (M3U playlists) — not part of the API payload
    var directURL: String? = nil

    var ratingDouble: Double { Double(rating ?? "") ?? 0 }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Movie, r: Movie) -> Bool { l.id == r.id }

    func streamURL(host: String, user: String, pass: String) -> URL? {
        URL(string: "\(host)/movie/\(user)/\(pass)/\(id).\(containerExtension)")
    }

    enum CodingKeys: String, CodingKey {
        case id                 = "stream_id"
        case name
        case posterURL          = "stream_icon"
        case backdropURL        = "backdrop_path"
        case year               = "releaseDate"
        case rating
        case genre
        case plot
        case duration
        case director
        case cast
        case categoryID         = "category_id"
        case containerExtension = "container_extension"
    }
}

// MARK: - Series
struct Series: Codable, Identifiable, Hashable {
    let id:         String
    let name:       String
    let coverURL:   String?
    let backdropURL:String?
    let year:       String?
    let rating:     String?
    let genre:      String?
    let plot:       String?
    let cast:       String?
    let director:   String?
    let categoryID: String
    var isFavorite: Bool = false
    var seasons:    [Season] = []

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Series, r: Series) -> Bool { l.id == r.id }

    enum CodingKeys: String, CodingKey {
        case id         = "series_id"
        case name
        case coverURL   = "cover"
        case backdropURL = "backdrop_path"
        case year, rating, genre, plot, cast, director
        case categoryID = "category_id"
    }
}

// MARK: - Season
struct Season: Codable, Identifiable, Hashable {
    let id:           String
    let seasonNumber: Int
    let name:         String
    var episodes:     [Episode] = []

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Season, r: Season) -> Bool { l.id == r.id }
}

// MARK: - Episode
struct Episode: Codable, Identifiable, Hashable {
    let id:                 String
    let title:              String
    let episodeNumber:      Int
    let seasonNumber:       Int
    let containerExtension: String
    let posterURL:          String?
    let plot:               String?
    let duration:           String?
    var watchProgress:      Double = 0.0
    var isWatched:          Bool   = false
    // Direct stream URL (M3U playlists) — not part of the API payload
    var directURL:          String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Episode, r: Episode) -> Bool { l.id == r.id }

    func streamURL(host: String, user: String, pass: String) -> URL? {
        URL(string: "\(host)/series/\(user)/\(pass)/\(id).\(containerExtension)")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, plot, duration
        case episodeNumber      = "episode_num"
        case seasonNumber       = "season"
        case containerExtension = "container_extension"
        case posterURL          = "info"
    }
}

// MARK: - EPG Program
struct EPGProgram: Codable, Identifiable {
    let id:          String
    let channelID:   String
    let title:       String
    let description: String?
    let startTime:   Date
    let endTime:     Date

    var isLive: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }
    var progress: Double {
        guard isLive else { return 0 }
        let total   = endTime.timeIntervalSince(startTime)
        let elapsed = Date().timeIntervalSince(startTime)
        return min(1, elapsed / total)
    }
    var durationText: String {
        let s = Int(endTime.timeIntervalSince(startTime))
        let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)س \(m)د" : "\(m) دقيقة"
    }
}

// MARK: - Watch History
struct WatchHistory: Codable, Identifiable {
    let id:           String
    let contentID:    String
    let contentType:  ContentType
    let contentName:  String
    let posterURL:    String?
    var progress:     Double
    var duration:     TimeInterval
    let lastWatched:  Date

    enum ContentType: String, Codable { case live, movie, episode }

    var progressSeconds: TimeInterval { progress * duration }
}

// MARK: - Content Type (for player)
// Identifiable required for .fullScreenCover(item:) and .sheet(item:)
enum ContentItem: Identifiable {
    case live(Channel)
    case movie(Movie)
    case episode(Episode, Series)

    var id: String {
        switch self {
        case .live(let ch):         return "live_\(ch.id)"
        case .movie(let m):         return "movie_\(m.id)"
        case .episode(let ep, _):   return "ep_\(ep.id)"
        }
    }
}

// MARK: - Stream Quality
enum StreamQuality: String, CaseIterable, Codable {
    case auto   = "تلقائي"
    case ultra  = "8K / 4K"
    case high   = "عالي HD"
    case medium = "متوسط"
    case low    = "منخفض"

    // rawValue stays as-is (persisted in UserDefaults); the UI shows this localized
    // name so "Automatic/High/…" follow the app language instead of always Arabic.
    var displayName: String {
        switch self {
        case .auto:   return L("quality.auto")
        case .ultra:  return "8K / 4K"
        case .high:   return L("quality.high")
        case .medium: return L("quality.medium")
        case .low:    return L("quality.low")
        }
    }
}

// MARK: - App Error
enum AppError: LocalizedError {
    case invalidCredentials
    case accountSuspended
    case accountExpired
    case maxConnections(Int)
    case maintenance(String?)
    case versionOutdated(String)
    case network(Error)
    case server(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:     return L("error.invalid_credentials")
        case .accountSuspended:       return L("error.account_suspended")
        case .accountExpired:         return L("error.account_expired")
        case .maxConnections(let n):  return String(format: L("error.max_connections"), n)
        case .maintenance(let msg):   return msg ?? L("error.maintenance")
        case .versionOutdated(let v): return String(format: L("error.version_outdated"), v)
        case .network(let e):         return String(format: L("error.network"), e.localizedDescription)
        case .server(let msg):        return msg   // already-localized/dynamic (server or Xtream message)
        case .unknown:                return L("error.unknown")
        }
    }
}

// MARK: - Series Detail Response
struct SeriesDetailResponse: Decodable {
    let info:     Series
    let episodes: [String: [Episode]]

    var sortedSeasons: [Season] {
        episodes.compactMap { key, eps -> Season? in
            guard let num = Int(key) else { return nil }
            return Season(
                id: key, seasonNumber: num,
                name: "الموسم \(num)",
                episodes: eps.sorted { $0.episodeNumber < $1.episodeNumber }
            )
        }.sorted { $0.seasonNumber < $1.seasonNumber }
    }
}
