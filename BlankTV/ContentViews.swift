// ============================================================
// BLANK TV — ContentViews.swift
// Live TV + Movies + Series + Search — Complete
// ============================================================

import SwiftUI
import UIKit

// MARK: ═══════════════════════════════════════
// LIVE TV
// ═══════════════════════════════════════════
@MainActor
final class LiveTVVM: ObservableObject {
    static let shared = LiveTVVM()
    @Published var categories: [Category]  = [.all]
    @Published var channels:   [Channel]   = []
    @Published var filtered:   [Channel]   = []
    @Published var selected:   String      = "all"
    @Published var search:     String      = ""
    @Published var isLoading:  Bool        = true
    @Published var error:      AppError?   = nil
    private var loaded = false

    // Precomputed once after load: channels grouped by their category NAME, and
    // the list of non-empty folders. Avoids the O(categories × channels) rescan
    // that the `folders`/`list(in:)` helpers used to run on every render.
    private(set) var grouped: [String: [Channel]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: channels, by: { $0.groupTitle })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.name]?.isEmpty ?? true) }
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }   // load once — keeps tab switches instant
        isLoading = true; error = nil
        do {
            async let cats  = ContentService.liveCategories()
            async let chans = ContentService.liveStreams()
            let (c, ch) = try await (cats, chans)
            categories = [.all] + c
            channels   = ch
            filtered   = ch
            rebuildGroups()
            loaded = true
        } catch let e as AppError { error = e }
          catch { self.error = .network(error) }
        isLoading = false
    }

    func filter() {
        var r = channels
        // Match by category NAME — channels carry the group/category name, not its id
        if selected != "all", let cat = categories.first(where: { $0.id == selected }) {
            r = grouped[cat.name] ?? []
        }
        if !search.isEmpty { r = r.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        filtered = r
    }

    func selectCat(_ id: String) { selected = id; filter() }
    func reset() {
        loaded = false; channels = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []
    }
}

/// Clears all cached content (called on logout / session change).
@MainActor
enum ContentCache {
    static func reset() {
        LiveTVVM.shared.reset()
        MoviesVM.shared.reset()
        SeriesVM.shared.reset()
        HomeVM.shared.reset()
    }
}

extension LiveTVVM {
    var folders: [Category] { Store.shared.orderedCategories(folderList, "live") }
    func list(in cat: Category) -> [Channel] {
        cat.id == "all" ? channels : (grouped[cat.name] ?? [])
    }
    var searchResults: [Channel] {
        channels.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

struct LiveTVView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = LiveTVVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var playerItem: ContentItem? = nil
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var tab: ContentTab = .all
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil
    @State private var padChannel: Channel? = nil
    @State private var currentChannel: Channel? = nil   // iPhone sticky mini-player selection

    private var favorites: [Channel] { vm.channels.filter { favs.channels.contains($0.id) } }
    private var liveHistory: [WatchHistory] { hist.items.filter { $0.contentType == .live } }
    // The channel shown in the iPhone sticky mini-player — the tapped one, else
    // the first channel (so the page auto-previews on open).
    private var previewing: Channel? { currentChannel ?? vm.channels.first }
    private func preview(_ ch: Channel) { currentChannel = ch }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Use the 3-pane split only when there's genuinely room (full-screen iPad).
    // In Split View / Slide Over the size class is still .regular but the width
    // is narrow, so fall back to the phone layout to avoid overflowing panes.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading {
                        LoadingView(message: L("loading.channels"))
                    } else if let e = vm.error {
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load() } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) } else { browser }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .live, categoryID: cat.id) {
                    ChannelListScreen(title: cat.name, channels: vm.list(in: cat)) { playerItem = .live($0) }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6) — corner-menu search field drives it.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $playerItem) { PlayerView(item: $0, channels: vm.channels) }
        .sheet(isPresented: $showCategories) {
            CategoryPickerSheet(title: L("cats.channels"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryReorderView(title: L("reorder.title"), categories: vm.folders, section: "live") { vm.objectWillChange.send() }
        }
    }

    // MARK: iPad 3-pane (categories | channels | player + info)
    private func padBrowser(_ width: CGFloat) -> some View {
        // Proportional pane widths so the player pane never gets squeezed on
        // portrait / smaller iPads (fixed 230+320 left only ~194–284pt for it).
        let sidebarW  = min(230, max(175, width * 0.20))
        let channelsW = min(320, max(240, width * 0.27))
        return HStack(spacing: 0) {
            CategorySidebar(title: L("title.live"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.channels.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padChannelsPane.frame(width: channelsW)
            Divider().background(Color.s8kBorder)
            padPlayerPane.frame(maxWidth: .infinity)
        }
        // Clear channel preview AND any leftover search query when switching
        // sidebar sections — a stale query would filter the new category to
        // "no results" (matches the Movies/Series iPad behavior).
        .onChange(of: padCat?.id) { _, _ in padChannel = nil; vm.search = "" }
        // While viewing Favorites, if the previewing channel is un-favorited it
        // leaves the middle list — clear the player so it doesn't keep showing a
        // channel that's no longer in view.
        .onChange(of: favs.channels) { _, _ in
            if padCat?.id == Category.favorites.id, let ch = padChannel,
               !favs.channels.contains(ch.id) { padChannel = nil }
        }
    }

    @ViewBuilder
    private var padChannelsPane: some View {
        if padCat?.id == Category.favorites.id {
            channelScroll(favorites)            // cross-category favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .live, categoryID: cat.id) { channelScroll(vm.list(in: cat)) }
        } else {
            channelScroll(vm.channels)
        }
    }
    private func channelScroll(_ chans: [Channel]) -> some View {
        // When a search query is active, show global results across all channels
        // (mirrors the Movies/Series iPad panes and the iPhone live browser);
        // otherwise show the selected category's channels.
        let list = vm.search.isEmpty ? chans : vm.searchResults
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                SearchField(text: $vm.search, placeholder: L("search.live"))
                    .padding(.horizontal, S8KSpace.lg)
                    .padding(.top, 50).padding(.bottom, S8KSpace.md)
                if list.isEmpty {
                    EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                               title: L("live.empty.title"), subtitle: L("live.empty.sub"))
                        .padding(.top, S8KSpace.xl)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { idx, ch in
                            ChannelRow(channel: ch, index: idx + 1) { padChannel = ch }
                                .background(padChannel?.id == ch.id ? Color.s8kGoldMid.opacity(0.12) : .clear)
                            Divider().background(Color.s8kBorder).padding(.leading, 74)
                        }
                    }
                }
                Color.clear.frame(height: 110)   // clear the floating AppTabBar
            }
        }
    }

    @ViewBuilder
    private var padPlayerPane: some View {
        if let ch = padChannel {
            VStack(spacing: 0) {
                InlineLivePlayer(channel: ch, isExpanded: playerItem != nil) { playerItem = .live(ch) }
                    .id(ch.id)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                channelInfoPane(ch)
                Spacer(minLength: 0)
            }
            .padding(.top, 50)        // align with the sidebar + channel list panes
        } else {
            VStack(spacing: 14) {
                Image(systemName: "play.tv").font(.system(size: 54)).foregroundColor(.s8kTextDisabled)
                Text(L("live.pick_channel")).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func channelInfoPane(_ ch: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: { favs.toggleChannel(ch.id) }) {
                    Image(systemName: favs.isChannelFav(ch.id) ? "heart.fill" : "heart")
                        .foregroundColor(favs.isChannelFav(ch.id) ? .s8kRed : .s8kTextSecondary)
                }
                .buttonStyle(S8KButtonStyle())
                Button(action: { playerItem = .live(ch) }) {
                    Label(L("live.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(S8KGradient.goldFlat).clipShape(Capsule())
                }
                .buttonStyle(S8KButtonStyle())
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ch.name).font(S8KFont.title3).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                        Text(L("home.live_now")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Divider().background(Color.s8kBorder)
            // Live program guide (now/next) — renders nothing if the provider has no EPG.
            EPGNowNext(channel: ch)
        }
        .padding(S8KSpace.xl)
    }

    // iPhone: a sticky mini-player (preview) pinned at the top + a scrolling
    // channel list under it. Tapping a row swaps the preview channel; tapping the
    // player expands to fullscreen. Auto-previews the first channel on open.
    @ViewBuilder
    private var browser: some View {
        VStack(spacing: 0) {
            liveTopBar
            if let ch = previewing {
                InlineLivePlayer(channel: ch, isExpanded: playerItem != nil) { playerItem = .live(ch) }
                    .id(ch.id)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                miniInfoBar(ch)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Search field removed — it now lives in the corner menu (owner #6).
                    Color.clear.frame(height: S8KSpace.md)
                    if !vm.search.isEmpty {
                        ChannelList(channels: vm.searchResults) { preview($0) }
                    } else {
                        ContentTabBar(selected: $tab)
                        tabContent
                    }
                    Color.clear.frame(height: 110)
                }
            }
            .reportsScrollToTabBar()   // collapse the corner puck on scroll (owner #4)
        }
    }

    // Slim top bar for the live page (title + reorder + categories).
    private var liveTopBar: some View {
        HStack(spacing: 10) {
            Text(L("title.live")).font(.system(size: 20, weight: .black)).foregroundColor(.s8kTextPrimary)
            RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat).frame(width: 22, height: 3)
            Spacer()
            liveBarButton("arrow.up.arrow.down") { showReorder = true }
            liveBarButton("line.3.horizontal.decrease.circle") { showCategories = true }
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, 56).padding(.bottom, 8)
    }
    private func liveBarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold)).foregroundColor(.s8kGoldHigh)
                .frame(width: 40, height: 40)
                .background(Color.s8kSurface, in: RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    // Compact info bar under the mini-player: favorite · fullscreen · name/live ·
    // now/next EPG (renders nothing if the provider has no guide).
    private func miniInfoBar(_ ch: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Button { favs.toggleChannel(ch.id) } label: {
                    Image(systemName: favs.isChannelFav(ch.id) ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(favs.isChannelFav(ch.id) ? .s8kRed : .s8kTextSecondary)
                }
                .buttonStyle(S8KButtonStyle())
                Button { playerItem = .live(ch) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.s8kBlack)
                        .frame(width: 34, height: 34).background(S8KGradient.goldFlat).clipShape(Circle())
                }
                .buttonStyle(S8KButtonStyle())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ch.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                        Text(L("home.live_now")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    }
                }
            }
            EPGNowNext(channel: ch, compact: true)
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, 10)
        .background(Color.s8kBlack)
        .overlay(GoldDivider(), alignment: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .all:
            if vm.folders.isEmpty {
                ChannelList(channels: vm.channels) { preview($0) }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vm.folders) { cat in
                        CategoryRow(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.live, cat.id),
                                    gated: parental.isGated(.live, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(16)) { ch in
                                ChannelChip(name: ch.name, logoURL: ch.logoURL, isLive: true) {
                                    preview(ch)
                                }
                            }
                        }
                    }
                }
            }
        case .favorites:
            ChannelList(channels: favorites) { preview($0) }
        case .newest:
            ChannelList(channels: vm.channels) { preview($0) }
        case .history:
            HistoryGrid(items: liveHistory, empty: L("history.empty")) { h in
                if let ch = vm.channels.first(where: { $0.id == h.contentID }) { preview(ch) }
            }
        }
    }
}

// MARK: - Channel list (shared) + per-category screen
struct ChannelList: View {
    let channels: [Channel]
    let onTap: (Channel) -> Void

    var body: some View {
        if channels.isEmpty {
            EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                       title: L("live.empty.title"), subtitle: L("live.empty.sub"))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(channels.enumerated()), id: \.element.id) { idx, ch in
                    ChannelRow(channel: ch, index: idx + 1) { onTap(ch) }
                    if idx < channels.count - 1 {
                        Divider().background(Color.s8kBorder).padding(.leading, 74)
                    }
                }
            }
            .onAppear { S8KImageCache.shared.prefetch(channels.prefix(40).compactMap { $0.logoURL }, maxPixel: 240) }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel
    let index: Int
    let onTap: () -> Void
    @StateObject private var favs = FavoritesService.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.s8kTextDisabled).frame(width: 22)

                    S8KImage(url: channel.logoURL, placeholder: "antenna.radiowaves.left.and.right", maxPixel: 240)
                        .frame(width: 46, height: 46).background(Color.s8kElevated)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(channel.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                        if !channel.groupTitle.isEmpty {
                            Text(channel.groupTitle).font(S8KFont.caption2)
                                .foregroundColor(.s8kTextTertiary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            .buttonStyle(S8KButtonStyle())

            // Favorite toggle
            Button(action: { favs.toggleChannel(channel.id) }) {
                Image(systemName: favs.isChannelFav(channel.id) ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .foregroundColor(favs.isChannelFav(channel.id) ? .s8kRed : .s8kTextDisabled)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(S8KButtonStyle())

            Button(action: onTap) {
                RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .fill(S8KGradient.goldFlat).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                        .foregroundColor(.s8kBlack))
                    .shadow(color: .s8kGoldMid.opacity(0.3), radius: 4)
            }
            .buttonStyle(S8KButtonStyle())
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, 10)
    }
}

// MARK: - Inline live player (iPad right pane). Recreated per channel via .id().
// iPad inline live preview. Thin wrapper that picks the engine (hardware
// AVPlayer for HLS, VLC otherwise — honoring the user's "Select Player"
// preference) and transparently retries on the other engine if one fails,
// mirroring the fullscreen PlayerView. (Full controls/zapping/PiP live in the
// expanded fullscreen player.)
struct InlineLivePlayer: View {
    let channel: Channel
    var isExpanded: Bool = false     // fullscreen is presented over this preview → pause it
    var onExpand: () -> Void
    @State private var engine: PlayerEngineKind
    @State private var triedFallback = false

    init(channel: Channel, isExpanded: Bool = false, onExpand: @escaping () -> Void) {
        self.channel = channel
        self.isExpanded = isExpanded
        self.onExpand = onExpand
        _engine = State(initialValue: PlayerEngineSelector.initialKind(for: .live(channel)))
    }

    var body: some View {
        InlineLiveEngineView(channel: channel, engine: engine, canFallback: !triedFallback,
                             isExpanded: isExpanded,
                             onExpand: onExpand,
                             onEngineFailed: {
                                 guard !triedFallback else { return }
                                 triedFallback = true
                                 engine = engine.other      // swap → .id rebuilds with a fresh attempt
                             })
            .id(engine)
    }
}

private struct InlineLiveEngineView: View {
    let channel: Channel
    let engine: PlayerEngineKind
    let canFallback: Bool
    let isExpanded: Bool
    var onExpand: () -> Void
    var onEngineFailed: () -> Void
    @StateObject private var vm: BasePlayerVM
    @State private var didReport = false

    init(channel: Channel, engine: PlayerEngineKind, canFallback: Bool, isExpanded: Bool,
         onExpand: @escaping () -> Void, onEngineFailed: @escaping () -> Void) {
        self.channel = channel
        self.engine = engine
        self.canFallback = canFallback
        self.isExpanded = isExpanded
        self.onExpand = onExpand
        self.onEngineFailed = onEngineFailed
        _vm = StateObject(wrappedValue: PlayerEngineSelector.make(item: .live(channel), kind: engine))
    }

    var body: some View {
        ZStack {
            Color.black
            PlayerSurfaceView(vm: vm)
            if vm.isLoading || vm.buffering {
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldHigh).scaleEffect(1.2)
            }
            // Error + retry — only once both engines have failed (a first failure
            // silently fails over via onEngineFailed below).
            if let err = vm.errorMsg, !canFallback {
                Color.black.opacity(0.85)
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26)).foregroundColor(.s8kTextDisabled)
                    Text(err).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                    Button(action: { vm.errorMsg = nil; vm.setup() }) {
                        Label(L("common.retry"), systemImage: "arrow.clockwise")
                            .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kGoldMid)
                    }
                }
            }
            VStack {
                HStack {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.45)).clipShape(Circle())
                    }
                    .buttonStyle(S8KButtonStyle())
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .onChange(of: vm.errorMsg) { _, msg in
            if msg != nil, canFallback, !didReport { didReport = true; onEngineFailed() }
        }
        .onAppear { vm.setup() }
        .onDisappear { vm.cleanup() }
        // When the fullscreen player is presented OVER this inline preview, SwiftUI
        // does NOT fire .onDisappear here (the cover sits on top, the preview stays
        // "appeared"), so without this the preview keeps decoding + playing audio
        // underneath → doubled audio/video (the reported iPad bug). Pause while
        // expanded; resume on return. Only ONE engine plays at a time.
        .onChange(of: isExpanded) { _, expanded in
            if expanded { vm.pause() } else { vm.play() }
        }
    }
}

// MARK: - EPG now/next strip (Xtream program guide)
// Shows the currently-airing program + a live progress bar (+ "Next: …" unless
// compact). Fetches on appear, refreshes the progress every 30s, and renders
// nothing when the provider has no EPG — so it's safe to drop in anywhere.
struct EPGNowNext: View {
    let channel: Channel
    var compact: Bool = false
    @State private var programs: [EPGProgram] = []
    @State private var now = Date()
    // Built once per view (not re-created on every body pass).
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var current: EPGProgram? { programs.first { $0.startTime <= now && now < $0.endTime } }
    private var upNext:  EPGProgram? { programs.first { $0.startTime > now } }

    var body: some View {
        Group {
            if let c = current {
                VStack(alignment: .trailing, spacing: compact ? 4 : 6) {
                    HStack(spacing: 8) {
                        Text(c.title).font(S8KFont.caption1.weight(.semibold))
                            .foregroundColor(.s8kTextPrimary).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(timeRange(c)).font(S8KFont.caption2)
                            .foregroundColor(.s8kTextTertiary).monospacedDigit()
                    }
                    S8KProgressBar(fraction: progress(c), track: Color.white.opacity(0.10))
                    if !compact, let n = upNext {
                        Text("\(L("epg.next")): \(n.title)").font(S8KFont.caption2)
                            .foregroundColor(.s8kTextTertiary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .task(id: channel.id) {
            programs = await ContentService.epg(for: channel)
            now = Date()
        }
        .onReceive(ticker) { _ in now = Date() }
    }

    private func progress(_ p: EPGProgram) -> Double {
        let total = p.endTime.timeIntervalSince(p.startTime)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(p.startTime) / total))
    }
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private func timeRange(_ p: EPGProgram) -> String {
        "\(Self.hhmm.string(from: p.startTime)) – \(Self.hhmm.string(from: p.endTime))"
    }
}

struct ChannelListScreen: View {
    let title: String
    let channels: [Channel]
    let onTap: (Channel) -> Void
    @State private var search = ""
    @Environment(\.dismiss) var dismiss

    private var shown: [Channel] {
        search.isEmpty ? channels : channels.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ContentTitleBar(title: title, subtitle: "\(channels.count) \(L("unit.channel"))", onBack: { dismiss() })
                    SearchField(text: $search, placeholder: "\(L("common.search_in")) \(title)…")
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                    ChannelList(channels: shown) { onTap($0) }
                    Color.clear.frame(height: 110)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: ═══════════════════════════════════════
// MOVIES
// ═══════════════════════════════════════════
@MainActor
final class MoviesVM: ObservableObject {
    static let shared = MoviesVM()
    @Published var categories: [Category] = [.all]
    @Published var movies:     [Movie]    = []
    @Published var filtered:   [Movie]    = []
    @Published var selected:   String     = "all"
    @Published var search:     String     = ""
    @Published var isLoading:  Bool       = true
    @Published var error:      AppError?  = nil
    @Published var sortBy:     Sort       = .newest
    // Editorial feed (Home-style, movies-only) — built once after load.
    @Published var heroItems:  [HomeVM.HeroItem] = []   // swipeable hero: newest movies
    @Published var topRanked:  [Movie]    = []          // Top-10 by rating
    private var loaded = false

    // Precomputed once after load: movies grouped by categoryID + non-empty folders.
    private(set) var grouped: [String: [Movie]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: movies, by: { $0.categoryID })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.id]?.isEmpty ?? true) }
    }

    // Editorial rows: Top-10 by rating (Movie has a ratingDouble helper) + a
    // newest-movies hero.
    private func rebuildEditorial() {
        topRanked = Array(movies.sorted { $0.ratingDouble > $1.ratingDouble }.prefix(10))
        let newest = movies.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .movie($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }

    enum Sort: String, CaseIterable { case newest = "الأحدث"; case rating = "التقييم"; case az = "أ-ي" }

    func load(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true; error = nil
        do {
            async let cats = ContentService.vodCategories()
            async let movs = ContentService.movies()
            let (c, m) = try await (cats, movs)
            categories = [.all] + c; movies = m
            rebuildGroups(); applyFilter(); rebuildEditorial(); loaded = true
        } catch let e as AppError { error = e }
          catch { self.error = .network(error) }
        isLoading = false
    }

    func applyFilter() {
        var r = movies
        if selected != "all" { r = r.filter { $0.categoryID == selected } }
        if !search.isEmpty   { r = r.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        switch sortBy {
        case .rating:  r = r.sorted { $0.ratingDouble > $1.ratingDouble }
        case .az:      r = r.sorted { $0.name < $1.name }
        case .newest: break
        }
        filtered = r
    }
    func reset() {
        loaded = false; movies = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []; heroItems = []; topRanked = []
    }
}

// MARK: ═══════════════════════════════════════
// SHARED: title bar · search field · folder card
// ═══════════════════════════════════════════
struct ContentTitleBar: View {
    let title: String
    var subtitle: String? = nil
    var onBack: (() -> Void)? = nil
    var trailingIcon: String? = nil
    var onTrailing: (() -> Void)? = nil
    var reorderAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                squareButton("chevron.right", action: onBack)
            }
            // Editorial: an oversized black-weight title with a short lime underline.
            VStack(alignment: .trailing, spacing: 6) {
                Text(title).font(.system(size: 28, weight: .black)).foregroundColor(.s8kTextPrimary).lineLimit(1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(S8KGradient.goldFlat)
                    .frame(width: 30, height: 3)
                    .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 4)
                if let subtitle {
                    Text(subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                }
            }
            Spacer()
            if let reorderAction {
                Button(action: reorderAction) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .bold))
                        Text(L("reorder.button")).font(S8KFont.caption1.weight(.semibold))
                    }
                    .foregroundColor(.s8kGoldMid)
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(Color.s8kSurface)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
            if let trailingIcon, let onTrailing {
                squareButton(trailingIcon, action: onTrailing)
            }
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, onBack == nil ? 60 : 24).padding(.bottom, S8KSpace.lg)
    }

    // Editorial: crisp rounded-square icon button (was a circle).
    private func squareButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold)).foregroundColor(.s8kGoldMid)
                .frame(width: 38, height: 38)
                .background(Color.s8kSurface)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Category reorder (tap-to-number)
// Arrange your lists like a pro: the ones you choose sit in a draggable "Your
// order" list (top = first) — drag to reorder, swipe to remove; every other list
// sits below with a + to add it. Only the user's explicit arrangement is saved,
// so a new user keeps the provider's default order (Store.orderedCategories).
// Persists per playlist across relaunch / logout.
// MARK: - Unified reorder page (owner #7)
// One place — reached from Settings — to organize ALL sections: a segmented
// Movies / Series / Live picker over the shared embedded reorder view. Each
// section auto-saves and carries the region quick-sort presets.
struct UnifiedReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var movies = MoviesVM.shared
    @StateObject private var series = SeriesVM.shared
    @StateObject private var live   = LiveTVVM.shared
    @State private var section: Sect = .movies

    enum Sect: String, CaseIterable, Identifiable {
        case movies, series, live
        var id: String { rawValue }
        var title: String {
            switch self {
            case .movies: return L("title.movies")
            case .series: return L("title.series")
            case .live:   return L("title.live")
            }
        }
    }

    private var cats: [Category] {
        switch section {
        case .movies: return movies.folders
        case .series: return series.folders
        case .live:   return live.folders
        }
    }
    private func notifyVM() {
        switch section {
        case .movies: movies.objectWillChange.send()
        case .series: series.objectWillChange.send()
        case .live:   live.objectWillChange.send()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $section) {
                        ForEach(Sect.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, S8KSpace.xl)
                    .padding(.top, S8KSpace.md).padding(.bottom, S8KSpace.sm)

                    CategoryReorderView(title: "", categories: cats, section: section.rawValue,
                                        onSaved: { notifyVM() }, embedded: true)
                        .id(section)   // fresh state per section → loads that section's saved order
                }
            }
            .navigationTitle(L("reorder.manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundColor(.s8kGoldMid).fontWeight(.bold)
                }
            }
            .task { await movies.load(); await series.load(); await live.load() }
        }
    }
}

struct CategoryReorderView: View {
    let title: String
    let categories: [Category]     // current display order
    let section: String            // "live" | "movies" | "series"
    var onSaved: () -> Void = {}   // parent notifies its VM so folders refresh instantly
    var embedded: Bool = false     // inside the unified reorder page: no nav chrome, auto-save
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var searchText = ""
    @State private var didLoad = false
    private let haptic = UISelectionFeedbackGenerator()

    // The chosen lists, in the saved order.
    private var pickedCats: [Category] { picked.compactMap { id in categories.first { $0.id == id } } }
    // Everything not yet chosen (search-filtered).
    private var poolCats: [Category] {
        let rest = categories.filter { !picked.contains($0.id) }
        guard !searchText.isEmpty else { return rest }
        return rest.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    // The arranged ("your order") list grows with its content, but never takes more
    // than ~42% of the available height — so the "available" pool ALWAYS keeps the
    // majority (≥~58%) and never collapses, on any device / orientation / screen
    // size. Beyond the cap the arranged list scrolls internally. When only a few
    // items are chosen it shrinks to their content, giving the pool even more room.
    private func arrangedHeight(_ available: CGFloat) -> CGFloat {
        let content = CGFloat(max(pickedCats.count, 1)) * 52 + 6
        // Short (landscape) heights spend more on fixed chrome, so hand the pool an
        // even bigger share there; tall layouts allow the arranged list up to ~42%.
        let fraction: CGFloat = available < 500 ? 0.32 : 0.42
        return min(content, available * fraction)
    }

    var body: some View {
        if embedded {
            // Inside the unified reorder page: no nav chrome; changes auto-save so
            // switching section tabs never loses the arrangement.
            reorderBody
                .onChange(of: picked) { _, p in Store.shared.setCategoryOrder(p, section); onSaved() }
        } else {
            NavigationStack {
                reorderBody
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.cancel")) { dismiss() }.foregroundColor(.s8kTextSecondary)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("common.save")) {
                                Store.shared.setCategoryOrder(picked, section)
                                onSaved(); dismiss()
                            }
                            .foregroundColor(.s8kGoldMid).fontWeight(.bold)
                        }
                    }
            }
        }
    }

    // Region quick-sort presets: one tap floats "your region" to the top; the user
    // can still drag to fine-tune. Offline keyword classification (RegionClassifier).
    private var presetBar: some View {
        HStack(spacing: 8) {
            Text(L("reorder.quick")).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextSecondary)
            Spacer()
            ForEach(ContentRegion.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        picked = RegionClassifier.presetOrder(categories, primary: r)
                    }
                    haptic.selectionChanged()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: r.icon).font(.system(size: 11, weight: .bold))
                        Text(r.title).font(S8KFont.caption2.weight(.bold))
                    }
                    .foregroundColor(.s8kGoldMid)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.s8kGoldMid.opacity(0.10)).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, S8KSpace.sm).padding(.bottom, 2)
    }

    private var reorderBody: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    presetBar
                    // ── Your order — drag to reorder, swipe to remove ──
                    sectionHeader(L("reorder.your_order"), count: pickedCats.isEmpty ? nil : pickedCats.count)
                    Text(L("reorder.drag_hint"))
                        .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, 4)

                    if pickedCats.isEmpty {
                        Text(L("reorder.empty_arranged"))
                            .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 22)
                    } else {
                        List {
                            ForEach(pickedCats) { cat in
                                arrangedRow(cat, number: (picked.firstIndex(of: cat.id) ?? 0) + 1)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Color.s8kBorder)
                                    .listRowInsets(EdgeInsets(top: 0, leading: S8KSpace.lg,
                                                              bottom: 0, trailing: S8KSpace.lg))
                            }
                            .onMove { from, to in
                                // Manual reorder (standard SwiftUI onMove semantics) — the
                                // move(fromOffsets:toOffsets:) helper failed to resolve under
                                // the Xcode 26.4 toolchain, so do it with plain array ops.
                                let moving = from.sorted().map { picked[$0] }
                                for i in from.sorted(by: >) { picked.remove(at: i) }
                                let dest = to - from.filter { $0 < to }.count
                                picked.insert(contentsOf: moving, at: min(max(dest, 0), picked.count))
                                haptic.selectionChanged()
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { pickedCats[$0].id }
                                picked.removeAll { ids.contains($0) }; haptic.selectionChanged()
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.editMode, .constant(.active))
                        .frame(height: arrangedHeight(geo.size.height))
                    }

                    Divider().background(Color.s8kBorder).padding(.vertical, S8KSpace.sm)

                    // ── Available lists — tap + to add to your order ──
                    sectionHeader(L("reorder.available"), count: nil)
                    SearchField(text: $searchText, placeholder: L("reorder.search"))
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, 4)
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(poolCats) { cat in
                                poolRow(cat)
                                Divider().background(Color.s8kBorder).padding(.leading, 64)
                            }
                            if poolCats.isEmpty {
                                Text(L("empty.no_results"))
                                    .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)
                                    .frame(maxWidth: .infinity).padding(.top, 30)
                            }
                            Color.clear.frame(height: 40)
                        }
                        .animation(.easeInOut(duration: 0.22), value: picked)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                // Pre-fill ONLY the user's previously-saved arrangement (still-existing
                // categories): empty for a new user, their own order for a returning one.
                picked = Store.shared.categoryOrder(section).filter { id in categories.contains { $0.id == id } }
            }
    }

    private func sectionHeader(_ text: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(text).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextSecondary)
            if let c = count {
                Text("\(c)").font(.system(size: 11, weight: .heavy)).foregroundColor(.black)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(S8KGradient.goldFlat).clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, S8KSpace.sm).padding(.bottom, 4)
    }

    // A row in the draggable "Your order" list: number badge + name. The drag
    // handle and delete control are supplied by the List (edit mode).
    private func arrangedRow(_ cat: Category, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy)).foregroundColor(.black)
                .frame(width: 26, height: 26)
                .background(S8KGradient.goldFlat).clipShape(Circle())
            Text(cat.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // A row in the available pool: tap the + to append it to the arranged order.
    private func poolRow(_ cat: Category) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.22)) { picked.append(cat.id) }
            haptic.selectionChanged()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.s8kGoldMid)
                Text(cat.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Content top tabs (الكل / المفضلة / الأجدد / السجل)
enum ContentTab: String, CaseIterable, Identifiable {
    case all = "الكل", favorites = "المفضلة", newest = "الأجدد", history = "السجل"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("ctab.all")
        case .favorites: return L("ctab.favorites")
        case .newest: return L("ctab.newest")
        case .history: return L("ctab.history")
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .newest: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// BLANK TV — Editorial: underline segmented control (no filled capsules). The
// active segment is marked by a lime underline; text brightens. Modern + clean.
struct ContentTabBar: View {
    @StateObject private var loc = LocalizationManager.shared
    @Binding var selected: ContentTab
    var allCount: Int = 0     // total items in the section, shown on the "All" tab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(ContentTab.allCases) { t in
                    let on = selected == t
                    Button(action: { withAnimation(.spring(response: 0.3)) { selected = t } }) {
                        VStack(spacing: 7) {
                            HStack(spacing: 6) {
                                Image(systemName: t.icon).font(.system(size: 11, weight: .bold))
                                Text(t.title).font(S8KFont.subhead.weight(.bold))
                                if t == .all && allCount > 0 {
                                    Text("\(allCount)")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(on ? .s8kGoldHigh : .s8kTextTertiary)
                                }
                            }
                            .foregroundColor(on ? .s8kTextPrimary : .s8kTextTertiary)

                            Capsule()
                                .fill(S8KGradient.goldFlat)
                                .frame(height: 3)
                                .opacity(on ? 1 : 0)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.bottom, S8KSpace.md)
    }
}

// MARK: - Horizontal category row (section + posters, tap header to open)
struct CategoryRow<Cell: View>: View {
    let category: Category
    var count: Int = 0
    var locked: Bool = false   // in the parental lock list → show a lock badge
    var gated:  Bool = false   // locked AND not unlocked this session → hide the
                               // content previews and require a PIN to enter
    @ViewBuilder let cells: () -> Cell

    var body: some View {
        VStack(spacing: 11) {
            NavigationLink(value: category) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(S8KGradient.goldFlat)
                        .frame(width: 3, height: 18)
                    Text(category.name).font(S8KFont.title3).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    if locked {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                            .foregroundColor(.s8kGoldMid)
                    }
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.s8kGoldMid)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.s8kGoldMid.opacity(0.12)).clipShape(Capsule())
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text(gated ? L("gate.enter_pin") : L("common.all")).font(S8KFont.caption1.weight(.semibold))
                        Image(systemName: gated ? "lock.fill" : "chevron.left").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.s8kGoldMid)
                }
                .padding(.horizontal, S8KSpace.xl)
            }
            .buttonStyle(S8KButtonStyle())

            // Hide the preview thumbnails for a gated folder so locked content
            // is never exposed; tapping the row opens the PIN gate instead.
            if !gated {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) { cells() }
                        .padding(.horizontal, S8KSpace.xl)
                }
            }
        }
        .padding(.bottom, S8KSpace.xxl)
    }
}

// MARK: - Category picker sheet (searchable)
struct CategoryPickerSheet: View {
    let title: String
    let categories: [Category]
    let count: (Category) -> Int
    let onPick: (Category) -> Void
    @State private var search = ""
    @Environment(\.dismiss) var dismiss

    private var shown: [Category] {
        search.isEmpty ? categories
                       : categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchField(text: $search, placeholder: L("search.cat"))
                        .padding(.horizontal, S8KSpace.xl).padding(.top, 16).padding(.bottom, S8KSpace.md)
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(shown) { cat in
                                Button(action: { onPick(cat); dismiss() }) {
                                    FolderCard(name: cat.name, count: count(cat))
                                }
                                .buttonStyle(S8KButtonStyle())
                            }
                            if shown.isEmpty {
                                EmptyState(icon: "folder.badge.questionmark",
                                           title: L("cats.empty.title"), subtitle: L("cats.empty.sub")).padding(.top, 40)
                            }
                        }
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.large])
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.s8kTextDisabled)
            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(Color.s8kTextDisabled))
                .font(S8KFont.callout).foregroundColor(.s8kTextPrimary)
                // RTL only when the app language is RTL (Arabic) — otherwise Latin
                // search text would right-align with reversed cursor behavior.
                .environment(\.layoutDirection, LocalizationManager.current.isRTL ? .rightToLeft : .leftToRight)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.s8kTextDisabled)
                }
            }
        }
        .padding(.horizontal, S8KSpace.lg).frame(height: 46)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

struct FolderCard: View {
    let name: String
    let count: Int
    var icon: String = "folder.fill"
    var color: Color = .s8kGoldMid

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14)).frame(width: 46, height: 46)
                Image(systemName: icon).font(.system(size: 19)).foregroundColor(color)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(count) \(L("unit.item"))").font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Image(systemName: "chevron.left").font(.system(size: 13)).foregroundColor(.s8kTextDisabled)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 13)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

// MARK: - iPad category sidebar (master pane for split layouts)
struct CategorySidebar: View {
    let title: String
    let folders: [Category]
    @Binding var selected: Category?     // nil = All, Category.favorites = Favorites
    var count: (Category) -> Int
    let allCount: Int
    /// When non-nil, a "Favorites" row is shown above "All" (iPad parity with the
    /// iPhone Favorites tab). Selecting it sets `selected = Category.favorites`.
    var favoritesCount: Int? = nil
    var onReorder: (() -> Void)? = nil

    private var isFavoritesSelected: Bool { selected?.id == Category.favorites.id }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 8) {
                if let onReorder {
                    Button(action: onReorder) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.s8kGoldMid)
                            .frame(width: 34, height: 34)
                            .background(Color.s8kElevated).clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.s8kBorder, lineWidth: 1))
                    }
                    .buttonStyle(S8KButtonStyle())
                }
                Spacer()
                Text(title)
                    .font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.top, 50).padding(.bottom, S8KSpace.md)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if let favCount = favoritesCount {
                        row(L("ctab.favorites"), favCount, isFavoritesSelected,
                            icon: "heart.fill") { selected = Category.favorites }
                    }
                    row(L("ctab.all"), allCount, selected == nil) { selected = nil }
                    ForEach(folders) { cat in
                        row(cat.name, count(cat), selected?.id == cat.id) { selected = cat }
                    }
                }
                .padding(.horizontal, S8KSpace.md).padding(.bottom, 110)  // clear the floating AppTabBar
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.s8kSurface.opacity(0.4))
    }

    private func row(_ label: String, _ n: Int, _ isOn: Bool, icon: String? = nil,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(n)").font(S8KFont.caption2)
                    .foregroundColor(isOn ? .black.opacity(0.7) : .s8kTextTertiary)
                Spacer()
                Text(label).font(S8KFont.subhead.weight(isOn ? .bold : .regular))
                    .foregroundColor(isOn ? .black : .s8kTextPrimary)
                    .lineLimit(1).multilineTextAlignment(.trailing)
                if let icon {
                    Image(systemName: icon).font(.system(size: 12))
                        .foregroundColor(isOn ? .black : .s8kRed)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(isOn ? AnyShapeStyle(S8KGradient.goldFlat) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

extension MoviesVM {
    /// Categories that actually contain movies (folders).
    var folders: [Category] { Store.shared.orderedCategories(folderList, "movies") }
    func list(in cat: Category) -> [Movie] {
        cat.id == "all" ? movies : (grouped[cat.id] ?? [])
    }
    var searchResults: [Movie] {
        movies.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

struct MoviesView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = MoviesVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selected: Movie? = nil
    @State private var tab: ContentTab = .all
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil

    private var favorites: [Movie] { vm.movies.filter { favs.movies.contains($0.id) } }
    private var movieHistory: [WatchHistory] { hist.items.filter { $0.contentType == .movie } }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Split only with real room (full-screen iPad); narrow Split View → phone layout.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    // Editorial hero height (mirrors Home, a touch shorter so the Top-10 peeks).
    private var heroHeight: CGFloat {
        hSize == .regular ? 520 : min(max(UIScreen.main.bounds.height * 0.58, 460), 600)
    }
    private func openHero(_ item: HomeVM.HeroItem) {
        if case .movie(let m) = item.kind { selected = m }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading { LoadingView(message: L("loading.movies"))
                    } else if let e = vm.error {
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load() } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) } else { browser }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .movie, categoryID: cat.id) {
                    MoviePosterScreen(title: cat.name, movies: vm.list(in: cat)) { selected = $0 }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6): the corner-menu search field drives
        // this section's live filter; typing swaps the feed for results.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $selected) { MovieDetailView(movie: $0) }
        .sheet(isPresented: $showCategories) {
            CategoryPickerSheet(title: L("cats.movies"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryReorderView(title: L("reorder.title"), categories: vm.folders, section: "movies") { vm.objectWillChange.send() }
        }
    }

    // MARK: iPad split (sidebar + wide poster grid)
    private func padBrowser(_ width: CGFloat) -> some View {
        let sidebarW = min(300, max(230, width * 0.26))   // proportional so the grid isn't cramped in portrait
        return HStack(spacing: 0) {
            CategorySidebar(title: L("title.movies"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.movies.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padGridPane
        }
        // A leftover search query would otherwise filter a freshly-selected
        // category to "no results" — clear it when switching sidebar sections.
        .onChange(of: padCat?.id) { _, _ in vm.search = "" }
    }
    @ViewBuilder
    private var padGridPane: some View {
        if padCat?.id == Category.favorites.id {
            padGrid(favorites, empty: L("movies.empty.fav"))   // favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .movie, categoryID: cat.id) { padGrid(vm.list(in: cat)) }
        } else {
            padGrid(vm.movies)
        }
    }
    private func padGrid(_ items: [Movie], empty: String = L("movies.empty")) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: S8KSpace.lg) {
                SearchField(text: $vm.search, placeholder: L("search.movies"))
                    .padding(.horizontal, S8KSpace.lg).padding(.top, 50)
                PosterGrid(movies: vm.search.isEmpty ? items : vm.searchResults,
                           empty: empty) { selected = $0 }
                Color.clear.frame(height: 110)   // clear the floating AppTabBar (iPad grid)
            }
        }
    }

    // BLANK TV "Stage + Collections" library (see DESIGN.md). No oversized title
    // bar, no 4-chip strip: a FIXED working top bar (safe-area inset) + an immersive
    // Stage + category "Collections" rails.
    @ViewBuilder
    private var browser: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !vm.search.isEmpty {
                    Color.clear.frame(height: 8)
                    PosterGrid(movies: vm.searchResults, empty: L("empty.no_results")) { selected = $0 }
                } else {
                    // The hero now leads the "All" editorial feed (in tabContent);
                    // the old single-shot featuredBanner Stage is retired.
                    tabContent                             // Collections (category rails) / filter grids
                }
                Color.clear.frame(height: 110)
            }
        }
        .reportsScrollToTabBar()   // collapse the corner puck on scroll (owner #4)
        // The top bar is a safe-area INSET, NEVER a ScrollView child — scroll-child
        // buttons go dead in this codebase. This keeps search/filter always tappable.
        .safeAreaInset(edge: .top, spacing: 0) { moviesTopBar }
    }

    private var moviesTopBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(L("title.movies"))
                    .font(.system(size: 21, weight: .black)).foregroundColor(.s8kTextPrimary)
                RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat).frame(width: 24, height: 3)
                Spacer()
                Menu {
                    Picker("", selection: $tab) {
                        ForEach(ContentTab.allCases) { t in Label(t.title, systemImage: t.icon).tag(t) }
                    }
                    Button { showReorder = true } label: {
                        Label(L("reorder.button"), systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.s8kGoldHigh)
                        .frame(width: 42, height: 42)
                        .background(Color.s8kSurface, in: RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.s8kBorder, lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
            // Search moved to the corner-menu search button (owner #6) — the top bar
            // is now a clean row. Only a "back to All" chip remains when a filter tab
            // (Favorites / Newest / History) is active.
            if tab != .all {
                Button { withAnimation { tab = .all } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .bold))
                        Text(tab.title).font(S8KFont.caption1.weight(.bold))
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.s8kBlack)
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(S8KGradient.goldFlat)
                    .clipShape(Capsule())
                }
                .buttonStyle(S8KButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 60).padding(.bottom, 12)
        .background(Color.s8kBlack)
    }

    // Featured spotlight banner at the top of the Movies browse (2026 VOD pattern:
    // a hero banner above the category rails). Uses the first movie as featured.
    @ViewBuilder
    private var featuredBanner: some View {
        if let m = vm.movies.first {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .overlay { S8KImage(url: m.backdropURL ?? m.posterURL, placeholder: "film") }
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                LinearGradient(colors: [Color.s8kBlack, .clear], startPoint: .bottom, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(m.name).font(.system(size: 20, weight: .black)).foregroundColor(.s8kTextPrimary)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat).frame(width: 34, height: 3)
                    Button(action: { selected = m }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                            Text(L("common.play")).font(S8KFont.caption1.weight(.bold))
                        }
                        .foregroundColor(.s8kBlack)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(S8KGradient.goldFlat)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                    }
                    .buttonStyle(S8KButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(S8KSpace.lg)
            }
            .frame(height: 200)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.lg)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .all:
            // Editorial feed (Home-style, movies-only): swipeable hero → Top-10 →
            // the user's own category shelves. Search/filter/reorder stay in the
            // top bar (per owner: "feed + categories button").
            LazyVStack(spacing: 0) {
                if !vm.heroItems.isEmpty {
                    HeroCarouselView(items: vm.heroItems, height: heroHeight,
                                     paused: selected != nil, onOpen: openHero)
                        .padding(.bottom, S8KSpace.lg)
                }
                if !vm.topRanked.isEmpty {
                    RankRail(title: L("home.top_movies"),
                             cells: vm.topRanked.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.posterURL, $0.element.rating, $0.element.year) }) { id in
                        if let m = vm.topRanked.first(where: { $0.id == id }) { selected = m }
                    }
                }
                if vm.folders.isEmpty {
                    PosterGrid(movies: vm.movies, empty: L("movies.empty")) { selected = $0 }
                } else {
                    ForEach(vm.folders) { cat in
                        CategoryRow(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.movie, cat.id),
                                    gated: parental.isGated(.movie, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(14)) { m in
                                MoviePosterCell(movie: m) { selected = m }.frame(width: 104)
                            }
                        }
                    }
                }
            }
        case .favorites:
            PosterGrid(movies: favorites, empty: L("movies.empty.fav")) { selected = $0 }
        case .newest:
            PosterGrid(movies: vm.movies, empty: L("movies.empty")) { selected = $0 }
        case .history:
            HistoryGrid(items: movieHistory, empty: L("history.empty")) { h in
                if let m = vm.movies.first(where: { $0.id == h.contentID }) { selected = m }
            }
        }
    }
}

// MARK: - Watch-history grid (shared)
struct HistoryGrid: View {
    let items: [WatchHistory]
    var empty: String = L("history.empty.generic")
    let onTap: (WatchHistory) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }

    var body: some View {
        if items.isEmpty {
            EmptyState(icon: "clock.badge.xmark", title: empty, subtitle: L("history.empty.sub"))
        } else {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(items) { h in
                    Button(action: { onTap(h) }) {
                        VStack(alignment: .trailing, spacing: 6) {
                            ZStack(alignment: .bottom) {
                                S8KImage(url: h.posterURL, placeholder: "play.rectangle")
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                                S8KProgressBar(fraction: h.progress, track: Color.white.opacity(0.15))
                            }
                            .frame(height: 150)
                            Text(h.contentName).font(S8KFont.caption2.weight(.semibold))
                                .foregroundColor(.s8kTextPrimary).lineLimit(1)
                        }
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(.horizontal, S8KSpace.lg)
        }
    }
}

// MARK: - Movie poster grid + per-category screen
struct PosterGrid: View {
    let movies: [Movie]
    var empty: String = L("grid.empty")
    let onSelect: (Movie) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    // Larger, more immersive posters (fewer per row) — a bolder catalog than the
    // reference's dense postage-stamp grid.
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }

    var body: some View {
        if movies.isEmpty {
            EmptyState(icon: "film.slash", title: empty, subtitle: L("grid.empty.sub"))
        } else {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(movies) { m in MoviePosterCell(movie: m) { onSelect(m) } }
            }
            .padding(.horizontal, S8KSpace.lg)
            // Warm the first screenful of posters so the grid paints instantly.
            .onAppear { S8KImageCache.shared.prefetch(movies.prefix(30).compactMap { $0.posterURL }, maxPixel: 800) }
        }
    }
}

struct MoviePosterCell: View {
    let movie: Movie
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    // Fixed-size box drives layout; the poster fills it as a
                    // clipped overlay. Prevents a non-2:3 poster from leaking its
                    // width and overlapping neighbours in the grid.
                    Color.clear
                        .frame(maxWidth: .infinity).frame(height: 150)
                        .overlay { S8KImage(url: movie.posterURL, placeholder: "film") }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    if let y = movie.year {
                        Text(y).font(S8KFont.caption3.weight(.bold)).foregroundColor(.s8kBlack)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(S8KGradient.goldFlat)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).padding(5)
                    }
                }
                Text(movie.name).font(S8KFont.caption2.weight(.bold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                if let r = movie.rating, let rv = Double(r), rv > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(.s8kGoldHigh)
                        Text(String(format: "%.1f", rv)).font(S8KFont.caption3).foregroundColor(.s8kGoldHigh)
                    }
                }
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

struct MoviePosterScreen: View {
    let title: String
    let movies: [Movie]
    let onSelect: (Movie) -> Void
    @State private var search = ""
    @Environment(\.dismiss) var dismiss

    private var shown: [Movie] {
        search.isEmpty ? movies : movies.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ContentTitleBar(title: title, subtitle: "\(movies.count) \(L("unit.movie"))", onBack: { dismiss() })
                    SearchField(text: $search, placeholder: "\(L("common.search_in")) \(title)…")
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                    PosterGrid(movies: shown) { onSelect($0) }
                    Color.clear.frame(height: 110)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: ═══════════════════════════════════════
// SERIES
// ═══════════════════════════════════════════
@MainActor
final class SeriesVM: ObservableObject {
    static let shared = SeriesVM()
    @Published var categories: [Category] = [.all]
    @Published var series:     [Series]   = []
    @Published var filtered:   [Series]   = []
    @Published var selected:   String     = "all"
    @Published var search:     String     = ""
    @Published var isLoading:  Bool       = true
    @Published var error:      AppError?  = nil
    // Editorial feed (Home-style, series-only) — built once after load.
    @Published var heroItems:  [HomeVM.HeroItem] = []   // swipeable hero: newest series
    @Published var topRanked:  [Series]   = []          // Top-10 by rating
    private var loaded = false

    // Precomputed once after load: series grouped by categoryID + non-empty folders.
    private(set) var grouped: [String: [Series]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: series, by: { $0.categoryID })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.id]?.isEmpty ?? true) }
    }

    // Build the editorial rows (Top-10 by rating + a newest-series hero). Series
    // has no `ratingDouble` helper, so parse the String rating inline (as Home does).
    private func rebuildEditorial() {
        topRanked = Array(series.sorted { (Double($0.rating ?? "") ?? 0) > (Double($1.rating ?? "") ?? 0) }.prefix(10))
        let newest = series.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .series($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true; error = nil
        do {
            async let cats = ContentService.seriesCategories()
            async let sers = ContentService.series()
            let (c, s) = try await (cats, sers)
            categories = [.all] + c; series = s
            rebuildGroups(); applyFilter(); rebuildEditorial(); loaded = true
        } catch let e as AppError { error = e }
          catch { self.error = .network(error) }
        isLoading = false
    }

    func applyFilter() {
        var r = series
        if selected != "all" { r = r.filter { $0.categoryID == selected } }
        if !search.isEmpty   { r = r.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        filtered = r
    }
    func reset() {
        loaded = false; series = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []; heroItems = []; topRanked = []
    }
}

extension SeriesVM {
    var folders: [Category] { Store.shared.orderedCategories(folderList, "series") }
    func list(in cat: Category) -> [Series] {
        cat.id == "all" ? series : (grouped[cat.id] ?? [])
    }
    var searchResults: [Series] {
        series.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

struct SeriesListView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = SeriesVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selected: Series? = nil
    @State private var tab: ContentTab = .all
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil

    private var favorites: [Series] { vm.series.filter { favs.series.contains($0.id) } }
    private var seriesHistory: [WatchHistory] { hist.items.filter { $0.contentType == .episode } }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Split only with real room (full-screen iPad); narrow Split View → phone layout.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    // Editorial hero height (mirrors Home, a touch shorter so the Top-10 peeks).
    private var heroHeight: CGFloat {
        hSize == .regular ? 520 : min(max(UIScreen.main.bounds.height * 0.58, 460), 600)
    }
    private func openHero(_ item: HomeVM.HeroItem) {
        if case .series(let s) = item.kind { selected = s }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading { LoadingView(message: L("loading.series"))
                    } else if let e = vm.error {
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load() } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) } else { browser }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .series, categoryID: cat.id) {
                    SeriesPosterScreen(title: cat.name, series: vm.list(in: cat)) { selected = $0 }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6) — corner-menu search field drives it.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $selected) { SeriesDetailView(series: $0) }
        .sheet(isPresented: $showCategories) {
            CategoryPickerSheet(title: L("cats.series"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryReorderView(title: L("reorder.title"), categories: vm.folders, section: "series") { vm.objectWillChange.send() }
        }
    }

    // MARK: iPad split (sidebar + wide poster grid)
    private func padBrowser(_ width: CGFloat) -> some View {
        let sidebarW = min(300, max(230, width * 0.26))   // proportional so the grid isn't cramped in portrait
        return HStack(spacing: 0) {
            CategorySidebar(title: L("title.series"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.series.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padGridPane
        }
        // Clear a leftover query when switching sidebar sections (see Movies).
        .onChange(of: padCat?.id) { _, _ in vm.search = "" }
    }
    @ViewBuilder
    private var padGridPane: some View {
        if padCat?.id == Category.favorites.id {
            padGrid(favorites, empty: L("series.empty.fav"))   // favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .series, categoryID: cat.id) { padGrid(vm.list(in: cat)) }
        } else {
            padGrid(vm.series)
        }
    }
    private func padGrid(_ items: [Series], empty: String = L("series.empty")) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: S8KSpace.lg) {
                SearchField(text: $vm.search, placeholder: L("search.series"))
                    .padding(.horizontal, S8KSpace.lg).padding(.top, 50)
                SeriesGrid(series: vm.search.isEmpty ? items : vm.searchResults,
                           empty: empty) { selected = $0 }
                Color.clear.frame(height: 110)   // clear the floating AppTabBar (iPad grid)
            }
        }
    }

    @ViewBuilder
    private var browser: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ContentTitleBar(title: L("title.series"), subtitle: "\(vm.series.count) \(L("count.series"))",
                                trailingIcon: "line.3.horizontal.decrease.circle",
                                onTrailing: { showCategories = true },
                                reorderAction: { showReorder = true })
                // Search field removed — it now lives in the corner menu (owner #6).
                if !vm.search.isEmpty {
                    SeriesGrid(series: vm.searchResults, empty: L("empty.no_results")) { selected = $0 }
                } else {
                    // The hero now leads the "All" editorial feed (in tabContent);
                    // the old single-shot featuredBanner is retired.
                    ContentTabBar(selected: $tab)
                    tabContent
                }
                Color.clear.frame(height: 110)
            }
        }
        .reportsScrollToTabBar()   // collapse the corner puck on scroll (owner #4)
    }

    // Featured spotlight banner atop the Series browse (mirrors Movies).
    @ViewBuilder
    private var featuredBanner: some View {
        if let s = vm.series.first {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .overlay { S8KImage(url: s.backdropURL ?? s.coverURL, placeholder: "tv") }
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                LinearGradient(colors: [Color.s8kBlack, .clear], startPoint: .bottom, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(s.name).font(.system(size: 20, weight: .black)).foregroundColor(.s8kTextPrimary)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat).frame(width: 34, height: 3)
                    Button(action: { selected = s }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                            Text(L("common.details")).font(S8KFont.caption1.weight(.bold))
                        }
                        .foregroundColor(.s8kBlack)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(S8KGradient.goldFlat)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                    }
                    .buttonStyle(S8KButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(S8KSpace.lg)
            }
            .frame(height: 200)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.lg)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .all:
            // Editorial feed (Home-style, series-only): swipeable hero → Top-10 →
            // the user's own category shelves. Categories/search/reorder stay
            // reachable from the title bar (per owner: "feed + categories button").
            LazyVStack(spacing: 0) {
                if !vm.heroItems.isEmpty {
                    HeroCarouselView(items: vm.heroItems, height: heroHeight,
                                     paused: selected != nil, onOpen: openHero)
                        .padding(.bottom, S8KSpace.lg)
                }
                if !vm.topRanked.isEmpty {
                    RankRail(title: L("home.top_series"),
                             cells: vm.topRanked.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.coverURL, $0.element.rating, $0.element.year) }) { id in
                        if let s = vm.topRanked.first(where: { $0.id == id }) { selected = s }
                    }
                }
                if vm.folders.isEmpty {
                    SeriesGrid(series: vm.series, empty: L("series.empty")) { selected = $0 }
                } else {
                    ForEach(vm.folders) { cat in
                        CategoryRow(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.series, cat.id),
                                    gated: parental.isGated(.series, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(14)) { s in
                                SeriesPosterCell(series: s) { selected = s }.frame(width: 104)
                            }
                        }
                    }
                }
            }
        case .favorites:
            SeriesGrid(series: favorites, empty: L("series.empty.fav")) { selected = $0 }
        case .newest:
            SeriesGrid(series: vm.series, empty: L("series.empty")) { selected = $0 }
        case .history:
            HistoryGrid(items: seriesHistory, empty: L("history.empty")) { h in
                if let s = vm.series.first(where: { h.contentName.hasPrefix($0.name) }) { selected = s }
            }
        }
    }
}

struct SeriesPosterCell: View {
    let series: Series
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 6) {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .overlay { S8KImage(url: series.coverURL, placeholder: "tv") }
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                Text(series.name).font(S8KFont.caption2.weight(.bold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let y = series.year {
                    Text(y).font(S8KFont.caption3).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

struct SeriesGrid: View {
    let series: [Series]
    var empty: String = L("grid.empty")
    let onSelect: (Series) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }

    var body: some View {
        if series.isEmpty {
            EmptyState(icon: "tv.slash", title: empty, subtitle: L("grid.empty.sub"))
        } else {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(series) { s in
                    Button(action: { onSelect(s) }) {
                        VStack(alignment: .trailing, spacing: 6) {
                            S8KImage(url: s.coverURL, placeholder: "tv")
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                            Text(s.name).font(S8KFont.caption2.weight(.semibold))
                                .foregroundColor(.s8kTextPrimary).lineLimit(1)
                            if let y = s.year {
                                Text(y).font(S8KFont.caption3).foregroundColor(.s8kTextTertiary)
                            }
                        }
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(.horizontal, S8KSpace.lg)
            .onAppear { S8KImageCache.shared.prefetch(series.prefix(30).compactMap { $0.coverURL }, maxPixel: 800) }
        }
    }
}

struct SeriesPosterScreen: View {
    let title: String
    let series: [Series]
    let onSelect: (Series) -> Void
    @State private var search = ""
    @Environment(\.dismiss) var dismiss

    private var shown: [Series] {
        search.isEmpty ? series : series.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ContentTitleBar(title: title, subtitle: "\(series.count) \(L("unit.series"))", onBack: { dismiss() })
                    SearchField(text: $search, placeholder: "\(L("common.search_in")) \(title)…")
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                    SeriesGrid(series: shown) { onSelect($0) }
                    Color.clear.frame(height: 110)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: ═══════════════════════════════════════
// MOVIE DETAIL
// ═══════════════════════════════════════════
struct MovieDetailView: View {
    let movie: Movie
    @StateObject private var favs = FavoritesService.shared
    @Environment(\.dismiss) var dismiss
    @State private var playItem: ContentItem? = nil
    @State private var enriched: Movie? = nil
    @State private var loadingInfo = true

    // The movie shown — enriched with full metadata once fetched
    private var m: Movie { enriched ?? movie }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        backdrop
                        actions
                        info
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .navigationTitle(m.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").foregroundColor(.s8kGoldMid)
                    }
                }
            }
        }
        .task {
            enriched = try? await ContentService.movieDetail(movie)
            loadingInfo = false
        }
        .fullScreenCover(item: $playItem) { PlayerView(item: $0) }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            // Taller, cinematic full-bleed backdrop with a layered scrim.
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 330)
                .overlay { S8KImage(url: m.backdropURL ?? m.posterURL, placeholder: "film") }
                .clipped()
                .overlay(LinearGradient(
                    stops: [
                        .init(color: .s8kBlack,                 location: 0.0),
                        .init(color: .s8kBlack.opacity(0.55),   location: 0.34),
                        .init(color: .clear,                    location: 0.72),
                        .init(color: .s8kBlack.opacity(0.35),   location: 1.0)
                    ],
                    startPoint: .bottom, endPoint: .top))

            HStack(alignment: .bottom, spacing: 14) {
                // Floating poster with a soft drop shadow.
                S8KImage(url: m.posterURL, placeholder: "film")
                    .frame(width: 100, height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 6)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(m.name).font(.system(size: 24, weight: .black)).foregroundColor(.s8kTextPrimary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                    // Editorial lime underline
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(S8KGradient.goldFlat)
                        .frame(width: 34, height: 3)
                    HStack(spacing: 6) {
                        if let y = m.year  { infoTag(y) }
                        if let g = m.genre { infoTag(g) }
                        if let d = m.duration { infoTag(d) }
                    }
                    if let r = m.rating, let rv = Double(r), rv > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.s8kGoldHigh)
                            Text(String(format: "%.1f", rv)).font(S8KFont.caption1.weight(.bold))
                                .foregroundColor(.s8kGoldHigh)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
        }
        // Swipe the header down to dismiss (in addition to the close button)
        .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height > 80 && abs(v.translation.width) < 120 { dismiss() }
        })
    }

    private var actions: some View {
        HStack(spacing: 10) {
            GoldButton(title: "▶  " + L("detail.play_movie")) {
                playItem = .movie(m)
            }
            Button(action: { favs.toggleMovie(m.id) }) {
                Image(systemName: favs.isMovieFav(m.id) ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundColor(favs.isMovieFav(m.id) ? .s8kRed : .s8kTextSecondary)
                    .frame(width: 52, height: 52)
                    .background(Color.s8kSurface)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())
            // Download for offline viewing (shows live %)
            DownloadControl(target: .movie(m), size: 20, showPercent: true)
                .frame(width: 64, height: 52)
                .background(Color.s8kSurface)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, S8KSpace.xl)
    }

    private var info: some View {
        VStack(alignment: .trailing, spacing: 18) {
            // Plot
            if let plot = m.plot, !plot.isEmpty {
                MetaSection(title: L("detail.story")) {
                    Text(plot).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .lineSpacing(5).multilineTextAlignment(.trailing)
                        // fixedSize(horizontal:false) stops the Text from reporting
                        // its full single-line width (which expanded the container
                        // past the screen and clipped the text); it now wraps.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if loadingInfo {
                HStack { Spacer(); ProgressView().tint(.s8kGoldMid); Spacer() }.padding(.vertical, 8)
            }

            // Clean info card (only rows that have a value)
            let rows: [(String, String?)] = [
                (L("detail.year"), m.year), (L("detail.duration"), m.duration),
                (L("detail.rating"), ratingText), (L("detail.genre"), m.genre), (L("detail.director"), m.director)
            ].filter { $0.1?.isEmpty == false }
            if !rows.isEmpty {
                MetaSection(title: L("detail.info")) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.1 ?? "").font(S8KFont.callout).foregroundColor(.s8kTextPrimary)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Text(row.0).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 11)
                            if idx < rows.count - 1 { GoldDivider() }
                        }
                    }
                    .padding(.horizontal, S8KSpace.lg)
                    .background(Color.s8kSurface)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                }
            }

            // Cast — chips
            if let cast = m.cast, !cast.isEmpty {
                MetaSection(title: L("detail.cast")) {
                    FlexWrap(items: castList(cast)) { name in
                        Text(name).font(S8KFont.caption1)
                            .foregroundColor(.s8kTextSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.s8kSurface).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.s8kBorder, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, S8KSpace.xl)
    }

    private func infoTag(_ t: String) -> some View {
        Text(t).font(S8KFont.caption3).foregroundColor(.s8kTextTertiary)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.s8kElevated)
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xs))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.xs).strokeBorder(Color.s8kBorder, lineWidth: 1))
    }

    private var ratingText: String? {
        guard let r = m.rating, let rv = Double(r), rv > 0 else { return nil }
        return "★ " + String(format: "%.1f", rv)
    }
    private func castList(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",،"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Detail section wrapper (gold-accent title + content)
struct MetaSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Spacer()
                Text(title).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
                RoundedRectangle(cornerRadius: 2).fill(S8KGradient.goldFlat).frame(width: 3, height: 16)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: ═══════════════════════════════════════
// SERIES DETAIL
// ═══════════════════════════════════════════
@MainActor
final class SeriesDetailVM: ObservableObject {
    @Published var seasons:  [Season]  = []
    @Published var selected: Season?   = nil
    @Published var isLoading: Bool     = true
    @Published var error:    AppError? = nil

    func load(series: Series) async {
        isLoading = true; error = nil
        do {
            // M3U: seasons are parsed locally; Xtream: fetched from API
            seasons  = try await ContentService.seasons(of: series)
            selected = seasons.first
        } catch let e as AppError { error = e }
          catch { self.error = .network(error) }
        isLoading = false
    }
}

struct SeriesDetailView: View {
    let series: Series
    @StateObject private var vm   = SeriesDetailVM()
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @Environment(\.dismiss) var dismiss
    @State private var playItem: ContentItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if vm.isLoading { LoadingView() }
                else if let e = vm.error { ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load(series: series) } } }
                else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            seriesHeader
                            if vm.seasons.count > 1 { seasonPicker }
                            episodeList
                            Color.clear.frame(height: 100)
                        }
                    }
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").foregroundColor(.s8kGoldMid)
                    }
                }
            }
        }
        .task { await vm.load(series: series) }
        .fullScreenCover(item: $playItem) { PlayerView(item: $0, queue: vm.selected?.episodes ?? []) }
    }

    private var seriesHeader: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 330)
                .overlay { S8KImage(url: series.backdropURL ?? series.coverURL, placeholder: "tv") }
                .clipped()
                .overlay(LinearGradient(
                    stops: [
                        .init(color: .s8kBlack,               location: 0.0),
                        .init(color: .s8kBlack.opacity(0.55), location: 0.34),
                        .init(color: .clear,                  location: 0.72),
                        .init(color: .s8kBlack.opacity(0.35), location: 1.0)
                    ],
                    startPoint: .bottom, endPoint: .top))
            HStack(alignment: .bottom, spacing: 14) {
                S8KImage(url: series.coverURL, placeholder: "tv")
                    .frame(width: 100, height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(series.name).font(.system(size: 24, weight: .black)).foregroundColor(.s8kTextPrimary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(S8KGradient.goldFlat)
                        .frame(width: 34, height: 3)
                    if let y = series.year { Text(y).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary) }
                    Button(action: { favs.toggleSeries(series.id) }) {
                        HStack(spacing: 5) {
                            Image(systemName: favs.isSeriesFav(series.id) ? "heart.fill" : "heart")
                                .font(.system(size: 13))
                            Text(favs.isSeriesFav(series.id) ? L("detail.fav_added") : L("detail.fav_add"))
                                .font(S8KFont.caption1.weight(.semibold))
                        }
                        .foregroundColor(favs.isSeriesFav(series.id) ? .s8kRed : .s8kTextSecondary)
                    }
                    .buttonStyle(S8KButtonStyle())
                }
                Spacer()
            }
            .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
        }
        .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height > 80 && abs(v.translation.width) < 120 { dismiss() }
        })
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(vm.seasons) { season in
                    FilterPill(title: "\(L("season.number")) \(season.seasonNumber)", isOn: vm.selected?.id == season.id) {
                        vm.selected = season
                    }
                }
            }
            .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.vertical, S8KSpace.lg)
    }

    private var episodeList: some View {
        LazyVStack(spacing: 8) {
            if let season = vm.selected {
                ForEach(season.episodes) { ep in
                    let progress = hist.progress(for: ep.id)
                    let watched  = progress >= 0.9
                    Button(action: { playItem = .episode(ep, series) }) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    // Stable thumbnail — falls back to series art (#5)
                                    S8KImage(url: ep.posterURL ?? series.backdropURL ?? series.coverURL,
                                             placeholder: "play.tv.fill")
                                        .frame(width: 120, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                            .strokeBorder(Color.s8kBorder, lineWidth: 1))
                                    Image(systemName: watched ? "checkmark" : "play.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(watched ? .s8kGoldHigh : .white.opacity(0.9))
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.5)).clipShape(Circle())
                                }
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(L("episode.number")) \(ep.episodeNumber)")
                                        .font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    if !ep.title.isEmpty {
                                        Text(ep.title).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    if let d = ep.duration {
                                        Text(d).font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                // Download this episode for offline viewing (shows %)
                                DownloadControl(target: .episode(ep, series), size: 20, showPercent: true)
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12)).foregroundColor(.s8kTextDisabled)
                            }
                            .padding(12)

                            // Simple resume bar underneath — shows where you stopped (#1)
                            if progress > 0.02 {
                                S8KProgressBar(fraction: progress, track: Color.white.opacity(0.08))
                            }
                        }
                        .background(Color.s8kSurface)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                    }
                    .buttonStyle(S8KButtonStyle())
                    .padding(.horizontal, S8KSpace.lg)
                }
            }
        }
        // Give the episode list a FRESH identity per season, so switching seasons
        // rebuilds it as a new subtree instead of recycling the row Buttons. Without
        // this, tapping a season pill mutates vm.selected and rebuilds this LazyVStack
        // *during the same touch cycle* — a recycled episode Button could then fire
        // mid-rebuild, making a season tap "open an episode" (the reported iPad bug).
        .id(vm.selected?.id)
    }
}

// MARK: ═══════════════════════════════════════
// SEARCH VIEW
// ═══════════════════════════════════════════
@MainActor
final class SearchVM: ObservableObject {
    @Published var query:   String         = ""
    @Published var results: [SearchResult] = []
    @Published var loading: Bool           = false
    @Published var failed:  Bool           = false
    @Published var recent:  [String]       = []
    @Published var scope:   SearchScope    = .movies

    /// The section the user is searching within (all / movies / series / live).
    /// `.all` (used on Home) searches every content type at once.
    enum SearchScope: String, CaseIterable, Identifiable {
        case all, movies, series, live
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:    return L("search.type.all")
            case .movies: return L("search.type.movie")
            case .series: return L("search.type.series")
            case .live:   return L("search.type.live")
            }
        }
        var icon: String {
            switch self {
            case .all:    return "magnifyingglass"
            case .movies: return "film"
            case .series: return "tv"
            case .live:   return "antenna.radiowaves.left.and.right"
            }
        }
        var prompt: String {
            switch self {
            case .all:    return L("search.all")
            case .movies: return L("search.movies")
            case .series: return L("search.series")
            case .live:   return L("search.live")
            }
        }
    }

    struct SearchResult: Identifiable {
        let id    = UUID()
        let type: ResultType
        let title, subtitle: String
        let imageURL: String?
        enum ResultType {
            case channel(Channel), movie(Movie), series(Series)
            var icon: String {
                switch self { case .channel: return "antenna.radiowaves.left.and.right"
                              case .movie:   return "film"
                              case .series:  return "tv" }
            }
            var label: String {
                switch self { case .channel: return L("search.type.live")
                              case .movie:   return L("search.type.movie")
                              case .series:  return L("search.type.series") }
            }
        }
    }

    private var task: Task<Void, Never>?

    init() { recent = UserDefaults.standard.stringArray(forKey: "s8k.search.recent") ?? [] }

    /// Switch the section and re-run the current query immediately.
    func setScope(_ s: SearchScope) {
        guard s != scope else { return }
        scope = s
        search()
    }

    /// Search ONLY within the selected section, against the real content source
    /// (ContentService → Xtream / M3U in real mode, DemoContent in demo).
    func search() {
        task?.cancel()
        failed = false
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; loading = false; return }
        loading = true
        let scope = self.scope
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)   // debounce
            guard !Task.isCancelled else { return }
            do {
                let low = q.lowercased()
                var r: [SearchResult] = []
                switch scope {
                case .all:
                    // Home: search movies + series + channels at once, merged.
                    async let am = (try? await ContentService.movies()) ?? []
                    async let asr = (try? await ContentService.series()) ?? []
                    async let ac = (try? await ContentService.liveStreams()) ?? []
                    let (mm, ss, cc) = await (am, asr, ac)
                    let rm = mm.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                        SearchResult(type: .movie($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.posterURL)
                    }
                    let rs = ss.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                        SearchResult(type: .series($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.coverURL)
                    }
                    let rc = cc.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                        SearchResult(type: .channel($0), title: $0.name, subtitle: "", imageURL: $0.logoURL)
                    }
                    r = Array(rm) + Array(rs) + Array(rc)
                case .movies:
                    let m = try await ContentService.movies()
                    r = m.filter { $0.name.lowercased().contains(low) }.prefix(60).map {
                        SearchResult(type: .movie($0), title: $0.name,
                                     subtitle: $0.year ?? "", imageURL: $0.posterURL)
                    }
                case .series:
                    let s = try await ContentService.series()
                    r = s.filter { $0.name.lowercased().contains(low) }.prefix(60).map {
                        SearchResult(type: .series($0), title: $0.name,
                                     subtitle: $0.year ?? "", imageURL: $0.coverURL)
                    }
                case .live:
                    let c = try await ContentService.liveStreams()
                    r = c.filter { $0.name.lowercased().contains(low) }.prefix(80).map {
                        SearchResult(type: .channel($0), title: $0.name,
                                     subtitle: "", imageURL: $0.logoURL)
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self.results = r; self.loading = false; self.saveRecent(q) }
            } catch {
                print("🔎 search failed (scope=\(scope.rawValue)): \(error)")
                await MainActor.run { self.loading = false; self.failed = true; self.results = [] }
            }
        }
    }

    private func saveRecent(_ q: String) {
        recent.removeAll { $0 == q }; recent.insert(q, at: 0)
        recent = Array(recent.prefix(8))
        UserDefaults.standard.set(recent, forKey: "s8k.search.recent")
    }
    func clearRecent() { recent = []; UserDefaults.standard.removeObject(forKey: "s8k.search.recent") }
}

struct SearchView: View {
    var onClose: (() -> Void)? = nil
    @StateObject private var vm = SearchVM()
    @State private var playerItem: ContentItem? = nil
    @State private var showMovie:  Movie?  = nil
    @State private var showSeries: Series? = nil
    @FocusState private var focused: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Poster grid: more columns on iPad (wider min) → uses the extra width.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: isPad ? 150 : 108), spacing: 14, alignment: .top)]
    }
    // Cap + center the content block on iPad so the field/results aren't an ugly
    // full-width stretch; full width on iPhone.
    private var contentMaxWidth: CGFloat { isPad ? 760 : .infinity }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    GoldDivider()
                    resultsArea
                }
                // Pin the header (search field) to the TOP — never let the block
                // center vertically when the results area is short/empty.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
        }
        .fullScreenCover(item: $playerItem) { PlayerView(item: $0) }
        .fullScreenCover(item: $showMovie)  { MovieDetailView(movie: $0) }
        .fullScreenCover(item: $showSeries) { SeriesDetailView(series: $0) }
        // Contextual search: open on the section the user came from (set by the
        // tab bar's search button). Applied once on present.
        .onAppear { vm.setScope(AppRouter.shared.searchScope) }
    }

    // MARK: Header (title + close, search field, scope chips)
    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Text(L("search.title")).font(S8KFont.title1).foregroundColor(.s8kTextPrimary)
                Spacer()
                Button(L("common.close")) {
                    if let onClose { onClose() } else { dismiss() }
                }.foregroundColor(.s8kGoldMid).font(S8KFont.subhead)
            }
            searchField
            scopeChips
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)                 // center the capped block
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 20)
        .padding(.bottom, S8KSpace.lg)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(focused ? .s8kGoldMid : .s8kTextDisabled)
                .animation(.easeInOut(duration: 0.2), value: focused)
            TextField("", text: $vm.query,
                     prompt: Text(vm.scope.prompt).foregroundColor(Color.s8kTextDisabled))
                .font(S8KFont.body).foregroundColor(.s8kTextPrimary)
                // RTL only when the app language is RTL (Arabic).
                .environment(\.layoutDirection, LocalizationManager.current.isRTL ? .rightToLeft : .leftToRight)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: vm.query) { vm.search() }
            if vm.loading {
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldMid).scaleEffect(0.7)
            } else if !vm.query.isEmpty {
                Button(action: { vm.query = ""; vm.results = []; vm.failed = false }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.s8kTextDisabled)
                }
            }
        }
        .padding(.horizontal, S8KSpace.lg).frame(height: 50)
        .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
            .strokeBorder(focused ? Color.s8kGoldMid : Color.s8kBorder, lineWidth: 1.5))
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    // Segmented section selector (Movies / Series / Live) — active = gold.
    private var scopeChips: some View {
        HStack(spacing: 8) {
            ForEach(SearchVM.SearchScope.allCases) { sc in
                let active = vm.scope == sc
                Button(action: { vm.setScope(sc) }) {
                    HStack(spacing: 6) {
                        Image(systemName: sc.icon).font(.system(size: 12, weight: .semibold))
                        Text(sc.label).font(S8KFont.caption1.weight(.semibold))
                    }
                    .foregroundColor(active ? .black : .s8kTextSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(active ? AnyShapeStyle(S8KGradient.goldFlat)
                                       : AnyShapeStyle(Color.s8kSurface))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(active ? Color.clear : Color.s8kBorder, lineWidth: 1))
                    .shadow(color: active ? .s8kGoldMid.opacity(0.35) : .clear, radius: 6, y: 2)
                }
                .buttonStyle(S8KButtonStyle())
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.scope)
    }

    // MARK: Results area (states)
    @ViewBuilder private var resultsArea: some View {
        if vm.query.isEmpty {
            startOrRecent
        } else if vm.failed {
            VStack {
                EmptyState(icon: "wifi.exclamationmark",
                           title: L("search.failed.title"), subtitle: L("search.failed.sub"))
                Button(action: { vm.search() }) {
                    Label(L("common.retry"), systemImage: "arrow.clockwise")
                        .font(S8KFont.subhead).foregroundColor(.s8kGoldMid)
                }.buttonStyle(S8KButtonStyle())
            }
        } else if vm.loading && vm.results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldMid).scaleEffect(1.2)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            EmptyState(icon: vm.scope.icon, title: L("search.empty.title"), subtitle: L("search.empty.sub"))
        } else {
            resultsScroll
        }
    }

    // No query yet → recent searches (if any) or a friendly hint.
    @ViewBuilder private var startOrRecent: some View {
        if vm.recent.isEmpty {
            EmptyState(icon: "magnifyingglass", title: L("search.start.title"), subtitle: L("search.start.sub"))
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 12) {
                    HStack {
                        Button(L("search.clear_all")) { vm.clearRecent() }
                            .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kGoldMid)
                        Spacer()
                        Text(L("search.recent")).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    }
                    FlexWrap(items: vm.recent) { term in
                        Button(action: { vm.query = term; vm.search() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "clock").font(.system(size: 11))
                                Text(term).font(S8KFont.caption1)
                            }
                            .foregroundColor(.s8kTextSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.s8kSurface).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.s8kBorder, lineWidth: 1))
                        }
                        .buttonStyle(S8KButtonStyle())
                    }
                }
                .frame(maxWidth: contentMaxWidth).frame(maxWidth: .infinity)
                .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
            }
        }
    }

    // Live → list rows (logos suit rows); Movies/Series → poster grid.
    private var resultsScroll: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if vm.scope == .live {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { r in
                            liveRow(r)
                            GoldDivider().padding(.leading, 72)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth).frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(vm.results) { posterCell($0) }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                    .frame(maxWidth: isPad ? 920 : .infinity).frame(maxWidth: .infinity)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 14)
        }
    }

    private func posterCell(_ r: SearchVM.SearchResult) -> some View {
        Button(action: { open(r) }) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                    .fill(Color.s8kElevated)
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                    .overlay(S8KImage(url: r.imageURL, placeholder: r.type.icon))
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                Text(r.title).font(S8KFont.caption1).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func liveRow(_ r: SearchVM.SearchResult) -> some View {
        Button(action: { open(r) }) {
            HStack(spacing: 12) {
                S8KImage(url: r.imageURL, placeholder: r.type.icon)
                    .frame(width: 50, height: 50)
                    .background(Color.s8kElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s8kBorder, lineWidth: 1))
                VStack(alignment: .trailing, spacing: 3) {
                    Text(r.title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    Text(r.type.label).font(S8KFont.caption3).foregroundColor(.s8kGoldMid)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 12)).foregroundColor(.s8kTextDisabled)
            }
            .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func open(_ r: SearchVM.SearchResult) {
        switch r.type {
        case .channel(let ch): playerItem = .live(ch)
        case .movie(let m):    showMovie  = m
        case .series(let s):   showSeries = s
        }
    }
}

// MARK: - Flex Wrap Layout
// Wrapping chips via the SwiftUI Layout protocol — correctly constrained to the
// available width (the old GeometryReader/alignmentGuide version mis-measured
// and pushed the whole detail page beyond the screen edges).
struct FlexWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxRowW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { maxRowW = max(maxRowW, x - spacing); x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        maxRowW = max(maxRowW, x - spacing)
        return CGSize(width: maxW.isFinite ? maxW : maxRowW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
