// ============================================================
// BLANK TV — SettingsView.swift
// Settings — Apple HIG • Delete Account • Privacy
// ============================================================

import SwiftUI

// ============================================================
// MARK: - Shared settings row builders (hub + every detail page)
// Centralised so the hub and each sub-page render identical rows without
// duplication. Pure, RTL-natural, dark-luxury styling on the app font.
// ============================================================
enum SetUI {
    static func iconTile(_ icon: String, danger: Bool = false) -> some View {
        let tint = danger ? Color.s8kRed : Color.s8kTextSecondary
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(danger ? Color.s8kRed.opacity(0.12) : Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(danger ? Color.s8kRed.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 1))
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(tint)
        }
    }

    static func divider() -> some View { Divider().background(Color.s8kBorder).padding(.leading, 60) }

    @ViewBuilder
    static func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Text(title.uppercased())
                    .font(S8KFont.footnote.weight(.heavy)).tracking(0.5)
                    .foregroundColor(.s8kTextTertiary)
            }
            .padding(.horizontal, 28).padding(.bottom, 7)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .padding(.horizontal, S8KSpace.xl)
        }
    }

    static func proRow<T: View>(icon: String, title: String, danger: Bool = false,
                                @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            trailing()
            Spacer(minLength: 8)
            Text(title).font(S8KFont.callout.weight(.semibold))
                .foregroundColor(danger ? .s8kRed : .s8kTextPrimary).lineLimit(1)
            iconTile(icon, danger: danger)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    static func navRow(icon: String, title: String, value: String = "", chevron: Bool = false,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if chevron {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundColor(.s8kTextDisabled)
                }
                if !value.isEmpty {
                    Text(value).font(S8KFont.callout).foregroundColor(.s8kTextTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary).lineLimit(1)
                iconTile(icon)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }

    static func infoRow(icon: String, title: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(value).font(mono ? .system(size: 10, weight: .medium, design: .monospaced) : S8KFont.callout)
                .foregroundColor(.s8kTextDisabled).lineLimit(1)
            Spacer(minLength: 8)
            Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary)
            iconTile(icon)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 15)
    }

    static func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: isOn).toggleStyle(SwitchToggleStyle(tint: .s8kGoldMid)).labelsHidden()
            Spacer(minLength: 12)
            Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary).lineLimit(1)
            iconTile(icon)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
    }
}

// ============================================================
// MARK: - Settings hub (V2) — cinematic header + navigable sections
// Owner spec: respects the device safe-area on EVERY device (iPhone/iPad/Mac);
// each section is a dark rectangle that opens its OWN page; content-order +
// parental are first-class sections. Presented isolated via a full-screen cover.
// ============================================================
struct SettingsProV2: View {
    @Environment(\.s8kMetrics) private var metrics
    var onClose: (() -> Void)? = nil
    @StateObject private var auth   = AuthService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var parental = ParentalService.shared
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showAccounts    = false
    @State private var showLogoutAlert = false
    @State private var showReorder     = false
    @State private var showParental    = false

    // Name shown in the hero — the account's custom name (NOT the "قائمة m3u"
    // placeholder the owner asked to remove); falls back to the Xtream username.
    private var displayName: String {
        let id = Store.shared.activePlaylistID
        if let p = Store.shared.savedPlaylists.first(where: { $0.id == id }), !p.name.isEmpty { return p.name }
        if let u = auth.user?.username, !u.isEmpty { return u }
        return L("settings.user")
    }
    private var initials: String { String(displayName.prefix(2).uppercased()) }
    /// In demo mode this said "BASIC", which is a plan nobody is on.
    private var planText: String {
        if Store.shared.demoMode { return L("settings.demo_plan") }
        return (auth.user?.plan ?? (auth.mode == .m3u ? "M3U" : "basic")).uppercased()
    }
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color.s8kBlack.ignoresSafeArea()
                // Cinematic glow bleeds to the very top edge (behind the status bar)…
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: Color.s8kGoldMid.opacity(0.20), location: 0.0),
                        .init(color: Color.s8kBlack.opacity(0.0),    location: 1.0)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // …while the CONTENT respects the safe-area on every device.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        heroContent
                        VStack(spacing: 12) {
                            sections
                            logoutButton
                            footer
                            Color.clear.frame(height: metrics.bottomClearance)   // clear the floating AppTabBar (was 30 → logout sat under it)
                        }
                        .frame(maxWidth: metrics.readableMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 6)
                }

                // Only when presented modally (preview cover). As a root tab
                // onClose is nil → no stray close button.
                if onClose != nil { closeButton }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.s8kGoldMid)
        .overlay {
            if showLogoutAlert {
                S8KConfirm(icon: "rectangle.portrait.and.arrow.right", iconColor: .s8kRed,
                           title: L("set.logout"), message: L("alert.logout.msg"),
                           confirmTitle: L("set.logout"), destructive: true,
                           onConfirm: { showLogoutAlert = false; Task { await auth.logout() } },
                           onCancel: { withAnimation { showLogoutAlert = false } }).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLogoutAlert)
        .fullScreenCover(isPresented: $showReorder)  { UnifiedReorderView() }
        .fullScreenCover(isPresented: $showParental) { ParentalControlView() }
        .fullScreenCover(isPresented: $showAccounts) { AccountSwitcherView(onClose: { showAccounts = false }) }
    }

    // MARK: Cinematic header (safe-area-respecting · tappable → account switcher)
    private var heroContent: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle().fill(S8KGradient.goldFlat).frame(width: 84, height: 84)
                    .shadow(color: .s8kGoldHigh.opacity(0.45), radius: 18, y: 5)
                Text(initials).font(.system(size: 29, weight: .black)).foregroundColor(S8KBrand.accentInk)
            }
            Text(displayName).font(.system(size: 23, weight: .black))
                .foregroundColor(.s8kTextPrimary).lineLimit(1)
            HStack(spacing: 8) {
                Text(planText).font(S8KFont.caption3.weight(.heavy)).foregroundColor(S8KBrand.accentInk)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(S8KGradient.goldFlat))
                HStack(spacing: 5) {
                    // A GREEN dot means a live provider. In demo mode there is none —
                    // `theme.serverName` falls back to the app's own name, so this row
                    // used to read "Connected · Blank Prime" over nothing at all.
                    Circle().fill(Store.shared.demoMode ? Color.s8kTextDisabled : Color.s8kGreen)
                        .frame(width: 6, height: 6)
                    Text(Store.shared.demoMode
                         ? L("settings.demo_state")
                         : "\(L("common.connected")) · \(theme.serverName)")
                        .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary).lineLimit(1)
                }
            }
            HStack(spacing: 4) {
                Text(L("accounts.switch")).font(S8KFont.caption2.weight(.bold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.s8kGoldMid)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(Color.s8kGoldMid.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            .padding(.top, 4)
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { showAccounts = true }
    }

    // MARK: Section list — dark rectangles, each opening its own page
    @ViewBuilder private var sections: some View {
        sectionLink(icon: "server.rack", title: L("set.connection"), subtitle: L("set.connection.sub")) {
            SetConnectionPage()
        }
        sectionLink(icon: "play.rectangle.on.rectangle.fill", title: L("set.player"), subtitle: L("set.player.sub")) {
            SetPlayerPage()
        }
        sectionButton(icon: "arrow.up.arrow.down.circle.fill", title: L("reorder.manage"), subtitle: L("reorder.sub")) {
            showReorder = true
        }
        // UNCONDITIONAL. This was `if config.hasParental`, read from a remote
        // feature flag — the single clearest instance of finding L-3: a server able
        // to switch parental controls OFF after review is exactly what Guideline
        // 2.5.2 prohibits, and Guideline 1.2 expects the control to be there. With
        // `appConfig` gone the flag was permanently true anyway; now it cannot be
        // anything else.
        //
        // No `do { }` wrapper either: a ViewBuilder does not accept one, and reaching
        // for a block to keep the old indentation would have been a compile error in
        // service of nothing.
        sectionButton(icon: "lock.shield.fill", title: L("app.parental"),
                      subtitle: parental.enabled ? L("app.parental.on") : L("app.parental.off"),
                      tint: parental.enabled ? .s8kGreen : .s8kGoldMid) {
            showParental = true
        }
        sectionLink(icon: "slider.horizontal.3", title: L("set.app"), subtitle: L("set.app.sub")) {
            SetAppPage()
        }
        sectionLink(icon: "info.circle.fill", title: L("set.about_legal"), subtitle: L("set.about.sub")) {
            SetAboutPage()
        }
    }

    private func sectionRowLabel(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.s8kTextDisabled)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(title).font(S8KFont.headline).foregroundColor(.s8kTextPrimary).lineLimit(1)
                Text(subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary).lineLimit(1)
            }
            sectionIcon(icon, tint)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func sectionIcon(_ icon: String, _ tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.14)).frame(width: 42, height: 42)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 1))
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(tint)
        }
    }

    private func sectionLink<D: View>(icon: String, title: String, subtitle: String, tint: Color = .s8kGoldMid,
                                      @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: { sectionRowLabel(icon: icon, title: title, subtitle: subtitle, tint: tint) }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)
    }

    private func sectionButton(icon: String, title: String, subtitle: String, tint: Color = .s8kGoldMid,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { sectionRowLabel(icon: icon, title: title, subtitle: subtitle, tint: tint) }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)
    }

    private var closeButton: some View {
        Button { onClose?() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .s8kMinTouch(3)      // 38 → 44pt; nothing else is within 3pt of it
        }
        .buttonStyle(S8KButtonStyle())
        .padding(.leading, 18).padding(.top, 6)
        .accessibilityLabel(L("common.close"))
    }

    private var logoutButton: some View {
        Button(action: { showLogoutAlert = true }) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .semibold))
                Text(L("set.logout")).font(S8KFont.headline)
            }
            .foregroundColor(.s8kRed).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: S8KRadius.lg).fill(Color.s8kRed.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg).strokeBorder(Color.s8kRed.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 6)
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Image(S8KBrand.logoAsset).resizable().scaledToFit().frame(width: 28, height: 28).opacity(0.8)
            Text(S8KBrand.name).font(S8KFont.caption1.weight(.black)).tracking(2).foregroundColor(.s8kTextDisabled)
            Text("v\(appVersion)").font(.system(size: 10, design: .monospaced)).foregroundColor(.s8kTextDisabled.opacity(0.5))
        }
        .padding(.top, 10)
    }
}

// MARK: - Detail scaffold (dark page + inline nav title, width-capped for iPad/Mac)
struct SetScaffold<C: View>: View {
    @Environment(\.s8kMetrics) private var metrics
    let title: String
    @Environment(\.horizontalSizeClass) private var hSize
    @ViewBuilder var content: () -> C
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                // 110 = the app-wide spacer that clears the floating AppTabBar, which
                // overlays pushed pages too (was 30 → the last row of every settings
                // sub-page was covered by the bar).
                VStack(spacing: 20) { content(); Color.clear.frame(height: metrics.bottomClearance) }
                    .padding(.top, 14)
                    .frame(maxWidth: metrics.readableMaxWidth)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.s8kBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Connection & account page
struct SetConnectionPage: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @State private var idCopied = false
    @State private var showPlaylists = false
    @State private var showPerfStats   = false
    @State private var showEngineStats = false

    private var serverHost: String? {
        if auth.mode == .m3u { return Store.shared.m3uURL }
        return Keychain.shared.serverCredentials()?.host
    }
    private var activePlaylistName: String {
        let id = Store.shared.activePlaylistID
        if let p = Store.shared.savedPlaylists.first(where: { $0.id == id }) { return p.name }
        return auth.mode == .m3u ? L("settings.m3u_list") : "Xtream"
    }

    var body: some View {
        SetScaffold(title: L("set.connection")) {
            SetUI.group(L("set.connection")) {
                SetUI.navRow(icon: "list.and.film", title: activePlaylistName,
                             value: "\(Store.shared.savedPlaylists.count)", chevron: true) { showPlaylists = true }
                if let host = serverHost {
                    SetUI.divider()
                    SetUI.infoRow(icon: "server.rack", title: L("common.connected"), value: host, mono: true)
                }
                SetUI.divider()
                Button(action: copyDeviceID) {
                    SetUI.proRow(icon: idCopied ? "checkmark.circle.fill" : "doc.on.doc",
                                 title: L("settings.device_id"), trailing: {
                        Text(activation.deviceID).font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.s8kTextTertiary).lineLimit(1)
                    })
                }.buttonStyle(S8KButtonStyle())
                SetUI.divider()
                SetUI.navRow(icon: "chart.bar.xaxis", title: L("diag.engine.title"), chevron: true) { showEngineStats = true }
                SetUI.divider()
                SetUI.navRow(icon: "speedometer", title: "قياس السرعة", chevron: true) { showPerfStats = true }
            }
        }
        .sheet(isPresented: $showPlaylists) { PlaylistsView() }
        .sheet(isPresented: $showEngineStats) { NavigationStack { EngineStatsView() } }
        .sheet(isPresented: $showPerfStats)   { NavigationStack { PerfStatsView() } }
    }

    private func copyDeviceID() {
        UIPasteboard.general.string = activation.deviceID
        withAnimation { idCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { idCopied = false } }
    }
}

// MARK: - Player page
struct SetPlayerPage: View {
    @State private var sleepMins   = Store.shared.sleepTimerMins
    @State private var quality     = Store.shared.preferredQuality
    @State private var pipOn       = Store.shared.pipEnabled
    @State private var enginePref  = Store.shared.playerEnginePref
    @State private var autoNextOn  = Store.shared.autoPlayNext
    @State private var skipIntroOn = Store.shared.skipIntroEnabled

    var body: some View {
        SetScaffold(title: L("set.player")) {
            SetUI.group(L("set.player")) {
                SetUI.toggleRow(icon: "play.square.stack.fill", title: L("player.autonext.title"), isOn: $autoNextOn)
                    .onChange(of: autoNextOn) { _, v in Store.shared.autoPlayNext = v }
                SetUI.divider()
                SetUI.toggleRow(icon: "forward.end.fill", title: L("player.skipintro.title"), isOn: $skipIntroOn)
                    .onChange(of: skipIntroOn) { _, v in Store.shared.skipIntroEnabled = v }
                SetUI.divider()
                SetUI.navRow(icon: "play.circle.fill", title: L("player.quality"), value: quality.displayName) {
                    let all = StreamQuality.allCases
                    if let i = all.firstIndex(of: quality) { quality = all[(i + 1) % all.count]; Store.shared.preferredQuality = quality }
                }
                SetUI.divider()
                SetUI.navRow(icon: "cpu", title: L("player.engine"), value: engineLabel(enginePref)) {
                    let order = ["auto", "av", "vlc"]
                    enginePref = order[((order.firstIndex(of: enginePref) ?? 0) + 1) % order.count]
                    Store.shared.playerEnginePref = enginePref
                }
                SetUI.divider()
                SetUI.toggleRow(icon: "rectangle.inset.filled.on.rectangle", title: L("player.pip"), isOn: $pipOn)
                    .onChange(of: pipOn) { _, v in Store.shared.pipEnabled = v }
                SetUI.divider()
                SetUI.navRow(icon: "moon.stars.fill", title: L("player.sleep.default"), value: "\(sleepMins) \(L("unit.minute"))") {
                    let options = [15, 30, 45, 60, 90, 120]
                    sleepMins = options[((options.firstIndex(of: sleepMins) ?? 0) + 1) % options.count]
                    Store.shared.sleepTimerMins = sleepMins
                }
            }
        }
    }

    /// "AVPlayer · للبثّ المباشر" — the engine's real name first, then what it is for.
    ///
    /// The name comes from `PlayerEngineKind.displayName`, which is the same source the
    /// engine-diagnostics screen reads. That is the whole point: the two screens used to
    /// hard-code different names for the same two engines, so the row you SET and the
    /// row you READ two taps later disagreed with each other.
    private func engineLabel(_ p: String) -> String {
        switch p {
        case "av":  return "\(PlayerEngineKind.av.displayName) · \(L("player.engine.av"))"
        case "vlc": return "\(PlayerEngineKind.vlc.displayName) · \(L("player.engine.vlc"))"
        default:    return L("player.engine.auto")
        }
    }
}

// MARK: - App preferences page
struct SetAppPage: View {
    @StateObject private var loc = LocalizationManager.shared
    @State private var notifOn    = Store.shared.notificationsEnabled
    @State private var wifiOnlyOn = Store.shared.downloadWifiOnly
    @State private var showDownloads = false

    var body: some View {
        SetScaffold(title: L("set.app")) {
            SetUI.group(L("set.app")) {
                Menu {
                    ForEach(AppLang.allCases) { l in
                        Button(action: { loc.set(l) }) {
                            if loc.lang == l { Label(l.display, systemImage: "checkmark") } else { Text(l.display) }
                        }
                    }
                } label: {
                    SetUI.proRow(icon: "globe", title: L("settings.language"), trailing: {
                        Text(loc.lang.display).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                    })
                }
                SetUI.divider()
                SetUI.navRow(icon: "arrow.down.circle.fill", title: L("set.downloads"), chevron: true) { showDownloads = true }
                SetUI.divider()
                SetUI.toggleRow(icon: "wifi", title: L("downloads.wifi_only"), isOn: $wifiOnlyOn)
                    .onChange(of: wifiOnlyOn) { _, v in Store.shared.downloadWifiOnly = v }
                SetUI.divider()
                SetUI.toggleRow(icon: "bell.badge.fill", title: L("set.notifications"), isOn: $notifOn)
                    .onChange(of: notifOn) { _, v in Store.shared.notificationsEnabled = v }
            }
        }
        .sheet(isPresented: $showDownloads) { DownloadsView() }
    }
}

// MARK: - About & legal page
struct SetAboutPage: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @State private var showAbout = false
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showLicenses = false
    @State private var showDeleteAlert = false
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    var body: some View {
        SetScaffold(title: L("set.about_legal")) {
            SetUI.group(L("set.about_legal")) {
                SetUI.navRow(icon: "info.circle.fill", title: L("set.about"), value: "v\(appVersion)", chevron: true) { showAbout = true }
                if let u = S8KBrand.supportURL {
                    SetUI.divider()
                    SetUI.navRow(icon: "bubble.left.and.bubble.right.fill", title: L("set.support"), chevron: true) { UIApplication.shared.open(u) }
                }
                SetUI.divider()
                SetUI.navRow(icon: "hand.raised.fill", title: L("set.privacy"), chevron: true) { showPrivacy = true }
                SetUI.divider()
                SetUI.navRow(icon: "doc.text.fill", title: L("set.terms"), chevron: true) { showTerms = true }
                // Guideline 1.2 wants a way to report objectionable content in any app
                // that shows content it did not author, and this app plays whatever
                // stream the user's provider sends. The address existed in S8KBrand and
                // was rendered NOWHERE — zero call sites — so there was no mechanism at
                // all, only the appearance of having planned one.
                //
                // The mail is pre-composed because a reviewer checks that the button
                // WORKS, and because a report with no subject line is a report nobody
                // can action.
                SetUI.divider()
                SetUI.navRow(icon: "exclamationmark.bubble.fill", title: L("set.report"), chevron: true) {
                    openReportMail()
                }
                // MIT wants its notice carried with the copy; LGPL wants the user told the
                // library is here and able to reach its source. Three libraries ship in
                // this binary and none of them was named anywhere until now.
                SetUI.divider()
                SetUI.navRow(icon: "doc.badge.gearshape.fill", title: L("set.licenses"), chevron: true) {
                    showLicenses = true
                }
                SetUI.divider()
                Button(action: { showDeleteAlert = true }) {
                    SetUI.proRow(icon: "person.crop.circle.badge.minus", title: L("set.delete"), danger: true, trailing: { EmptyView() })
                }.buttonStyle(S8KButtonStyle())
            }
        }
        .sheet(isPresented: $showAbout)   { AboutView() }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
        .sheet(isPresented: $showLicenses) { LicensesView() }
        .overlay {
            if showDeleteAlert {
                S8KConfirm(icon: "person.crop.circle.badge.minus", iconColor: .s8kRed,
                           title: L("set.delete"), message: L("alert.delete.msg"),
                           confirmTitle: L("alert.delete.confirm"), destructive: true,
                           onConfirm: { showDeleteAlert = false; Task { await auth.deleteAccount() } },
                           onCancel: { withAnimation { showDeleteAlert = false } }).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDeleteAlert)
    }

    /// Open a pre-composed report to the address in `S8KBrand`.
    ///
    /// Percent-encoding the subject and body is not optional: they are Arabic, and a raw
    /// mailto: with non-ASCII query values produces a URL that `URL(string:)` refuses to
    /// build — the button would then silently do nothing, which is worse than not having
    /// it, because a reviewer taps it and sees a dead control.
    private func openReportMail() {
        let subject = L("report.subject")
        let body = L("report.body")
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = S8KBrand.reportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: subject),
                        URLQueryItem(name: "body", value: body)]
        guard let url = c.url else { return }
        UIApplication.shared.open(url)
    }
}

// ============================================================
// MARK: - Playback-engine diagnostics — numeric PROOF of the routing brain
// Reads the persistent EngineStats counters + the EngineDecisionCache summary so
// the owner can verify (with numbers, not impressions) that the memory is being
// populated, that opens are served from it, and that failovers trend down.
// ============================================================
struct EngineStatsView: View {
    @State private var s = EngineStats.shared.snapshot
    @State private var cache = EngineDecisionCache.shared.summary()

    var body: some View {
        SetScaffold(title: L("diag.engine.title")) {
            SetUI.group(L("diag.engine.memory")) {
                statRow(L("diag.remembered"), "\(cache.total)")
                // Same source as the Settings row above — see PlayerEngineKind.displayName.
                SetUI.divider(); statRow(PlayerEngineKind.av.displayName, "\(cache.av)")
                SetUI.divider(); statRow(PlayerEngineKind.vlc.displayName, "\(cache.vlc)")
            }
            SetUI.group(L("diag.engine.usage")) {
                statRow(L("diag.opens"), "\(s.opens)")
                SetUI.divider(); statRow(L("diag.from_cache"), "\(s.cacheHits)  ·  \(pct(EngineStats.shared.hitRate))")
                SetUI.divider(); statRow(L("diag.default_route"), "\(s.cacheMisses)")
                SetUI.divider(); statRow(L("diag.forced"), "\(s.forced)")
            }
            SetUI.group(L("diag.engine.health")) {
                statRow(L("diag.stable_plays"), "\(s.records)  ·  AV \(s.avGood) / VLC \(s.vlcGood)")
                SetUI.divider(); statRow(L("diag.failovers"), "\(s.failovers)  ·  \(pct(EngineStats.shared.failoverRate))")
            }
            Button(action: { EngineStats.shared.reset(); refresh() }) {
                Text(L("diag.reset")).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kGoldMid)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).fill(Color.s8kGoldMid.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        s = EngineStats.shared.snapshot
        cache = EngineDecisionCache.shared.summary()
    }
    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.s8kGoldMid).lineLimit(1)
            Spacer(minLength: 8)
            Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary).lineLimit(1)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
    }
}

// ============================================================
// MARK: - Account switcher (profile grid, opened from the hero)
// A grid of profile avatars: the current account (highlighted) + the other saved
// accounts (tap to switch) + a dashed "+" tile to add a new one (Xtream / M3U via
// the existing LoginView). Each account name is editable (owner spec). Switching
// reboots content (switchPlaylist → contentReady=false) which unmounts this cover.
// ============================================================
struct AccountSwitcherView: View {
    @Environment(\.s8kMetrics) private var metrics
    var onClose: () -> Void
    @StateObject private var auth = AuthService.shared
    @State private var accounts: [SavedPlaylist] = Store.shared.savedPlaylists
    @State private var showAdd = false
    @State private var switching = false
    /// Why a saved line refused to open — see AuthService.switchPlaylist.
    @State private var switchError: String? = nil
    @State private var renaming: SavedPlaylist? = nil
    @State private var renameText = ""

    private let cols = [GridItem(.adaptive(minimum: 118, maximum: 168), spacing: 20)]

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldMid.opacity(0.10), .clear],
                           center: .top, startRadius: 0, endRadius: 420).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.s8kTextSecondary)
                            .frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.06)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                            .s8kMinTouch(3)   // 38 → 44pt; a Spacer and the 20pt margin flank it
                    }.buttonStyle(S8KButtonStyle())
                    .accessibilityLabel(L("common.close"))
                    Spacer()
                    Text(L("accounts.title")).font(.system(size: 20, weight: .black)).foregroundColor(.s8kTextPrimary)
                }
                .padding(.horizontal, 20).padding(.top, max(56, metrics.safeTop + S8KSpace.md)).padding(.bottom, 26)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: cols, spacing: 26) {
                        ForEach(accounts) { tile($0) }
                        addTile
                    }
                    .padding(.horizontal, 24)
                    Color.clear.frame(height: 40)
                }
            }
            if switching {
                ZStack { Color.black.opacity(0.55).ignoresSafeArea(); ProgressView().tint(.s8kGoldMid).scaleEffect(1.3) }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { accounts = Store.shared.savedPlaylists }) { LoginView() }
        .alert(L("accounts.rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("accounts.name_ph"), text: $renameText)
            Button(L("common.save")) { commitRename() }
            Button(L("common.cancel"), role: .cancel) { renaming = nil }
        }
        .alert(L("accounts.cannot_open"),
               isPresented: Binding(get: { switchError != nil },
                                    set: { if !$0 { switchError = nil } })) {
            Button(L("common.close"), role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
    }

    private func tile(_ acc: SavedPlaylist) -> some View {
        let isActive = acc.id == Store.shared.activePlaylistID
        return VStack(spacing: 9) {
            Button { if !isActive { switchTo(acc) } } label: {
                ZStack {
                    Circle().fill(S8KGradient.goldFlat).frame(width: 88, height: 88)
                        .shadow(color: .s8kGoldMid.opacity(0.40), radius: 12, y: 4)
                    Text(String(acc.name.prefix(2).uppercased()))
                        .font(.system(size: 30, weight: .black)).foregroundColor(S8KBrand.accentInk)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: acc.kind == .m3u ? "link" : "person.badge.key.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.s8kBlack))
                        .overlay(Circle().strokeBorder(Color.s8kBorder, lineWidth: 1))
                }
                .padding(5)
                .overlay(Circle().strokeBorder(isActive ? Color.s8kGoldHigh : Color.clear, lineWidth: 3))
                .opacity(isActive ? 1 : 0.88)
            }.buttonStyle(S8KButtonStyle())

            Text(acc.name).font(S8KFont.subhead.weight(.bold)).foregroundColor(.s8kTextPrimary).lineLimit(1)
            Text(isActive ? L("accounts.current") : (acc.kind == .m3u ? "M3U" : "Xtream"))
                .font(S8KFont.caption2.weight(isActive ? .bold : .regular))
                .foregroundColor(isActive ? .s8kGoldHigh : .s8kTextTertiary)
            Button { renameText = acc.name; renaming = acc } label: {
                Text(L("accounts.rename")).font(S8KFont.caption2)
                    .foregroundColor(.s8kTextSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    // ~18 → 44pt tall. It is the last thing in the tile: above it are two
                    // labels, below it 26pt of grid spacing before the next tile's avatar.
                    .s8kMinTouch(h: 12, v: 13)
            }.buttonStyle(S8KButtonStyle())
        }
    }

    private var addTile: some View {
        VStack(spacing: 9) {
            Button { showAdd = true } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.04)).frame(width: 88, height: 88)
                        .overlay(Circle().strokeBorder(Color.s8kBorderGold, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    Image(systemName: "plus").font(.system(size: 32, weight: .bold)).foregroundColor(.s8kGoldMid)
                }.padding(5)
            }.buttonStyle(S8KButtonStyle())
            .accessibilityLabel(L("a11y.add_account"))
            Text(L("accounts.add")).font(S8KFont.subhead.weight(.bold)).foregroundColor(.s8kTextPrimary)
            Text("Xtream · M3U").font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
            Color.clear.frame(height: 22)   // align with the rename row height
        }
    }

    private func switchTo(_ acc: SavedPlaylist) {
        switching = true
        Task {
            let ok = await auth.switchPlaylist(acc)
            switching = false
            // Only close on success. Closing on a refusal would drop the user back into
            // the account they are ALREADY in, with nothing said — indistinguishable
            // from the switch having worked.
            if ok { onClose() } else { switchError = auth.error?.errorDescription ?? L("common.error") }
        }
    }
    private func commitRename() {
        guard let acc = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty else { return }
        var list = Store.shared.savedPlaylists
        if let i = list.firstIndex(where: { $0.id == acc.id }) {
            list[i].name = name
            Store.shared.savedPlaylists = list
            accounts = list
        }
    }
}

// MARK: - Playlists management
struct PlaylistsView: View {
    @StateObject private var auth = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State private var playlists: [SavedPlaylist] = Store.shared.savedPlaylists
    @State private var activeID  = Store.shared.activePlaylistID
    /// Why a saved line refused to open — see AuthService.switchPlaylist.
    @State private var switchError: String? = nil
    @State private var showAdd   = false
    @State private var switching = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if playlists.isEmpty {
                    EmptyState(icon: "list.and.film", title: L("playlists.empty.title"),
                               subtitle: L("playlists.empty.sub"))
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(playlists) { p in
                                playlistRow(p)
                            }
                        }
                        .padding(20)
                    }
                }
                if switching {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView().tint(.s8kGoldMid).scaleEffect(1.3)
                }
            }
        .alert(L("accounts.cannot_open"),
               isPresented: Binding(get: { switchError != nil },
                                    set: { if !$0 { switchError = nil } })) {
            Button(L("common.close"), role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
            .navigationTitle(L("playlists.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button(action: {
                            switching = true
                            Task { await auth.refreshContent(); switching = false; dismiss() }
                        }) {
                            Image(systemName: "arrow.clockwise").foregroundColor(.s8kGoldMid)
                        }
                        .accessibilityLabel(L("a11y.refresh"))
                        Button(action: { showAdd = true }) {
                            Image(systemName: "plus").foregroundColor(.s8kGoldMid)
                        }
                        .accessibilityLabel(L("a11y.add_account"))
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPlaylistView { refresh() }
        }
    }

    private func playlistRow(_ p: SavedPlaylist) -> some View {
        let isActive = p.id == activeID
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill((isActive ? Color.s8kGreen : Color.s8kBlue).opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: p.kind == .m3u ? "link" : "person.badge.key.fill")
                    .foregroundColor(isActive ? .s8kGreen : .s8kBlue)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(p.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(p.subtitle).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if isActive {
                Text(L("playlists.active")).font(S8KFont.caption2.weight(.bold)).foregroundColor(.s8kGreen)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.s8kGreen.opacity(0.12)).clipShape(Capsule())
            }
            Menu {
                if !isActive {
                    Button(L("common.activate")) { switchTo(p) }
                }
                Button(L("common.delete"), role: .destructive) {
                    Task { await auth.deletePlaylist(p.id); refresh() }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundColor(.s8kTextSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("common.more"))
        }
        .padding(S8KSpace.lg)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .strokeBorder(isActive ? Color.s8kGreen.opacity(0.4) : Color.s8kBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if !isActive { switchTo(p) } }
    }

    private func switchTo(_ p: SavedPlaylist) {
        switching = true
        Task {
            let ok = await auth.switchPlaylist(p)
            switching = false
            guard ok else {
                // `activeID` deliberately NOT moved: the refused line never became
                // active, and marking it so would leave this list showing a green
                // "current" badge on the one account the app just declined to open.
                switchError = auth.error?.errorDescription ?? L("common.error")
                return
            }
            activeID = p.id
            dismiss()
        }
    }
    private func refresh() {
        playlists = Store.shared.savedPlaylists
        activeID  = Store.shared.activePlaylistID
    }
}

struct AddPlaylistView: View {
    @Environment(\.s8kMetrics) private var metrics
    let onAdded: () -> Void
    @StateObject private var auth = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var url  = ""
    @State private var busy = false
    @State private var err: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                // SCROLLABLE: the keyboard is up on this sheet and the error row grows
                // — without a scroll view the Add button hides under the keyboard.
                ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    S8KTextField(placeholder: L("playlists.name_ph"), icon: "tag", text: $name)
                    S8KTextField(placeholder: L("playlists.url_ph"), icon: "link", text: $url, ltr: true)
                    if let err {
                        Text(err).font(S8KFont.caption1).foregroundColor(.s8kRed)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    GoldButton(title: L("playlists.add_activate"), icon: "plus", isLoading: busy,
                               isDisabled: url.isEmpty) {
                        busy = true; err = nil
                        Task {
                            let ok = await auth.addM3UPlaylist(name: name, urlString: url)
                            busy = false
                            if ok { onAdded(); dismiss() }
                            else { err = auth.error?.errorDescription ?? L("playlists.add_failed") }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: metrics.formMaxWidth)
                .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(L("playlists.add")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.cancel")) { dismiss() }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    Image(S8KBrand.logoAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .s8kGoldHigh.opacity(0.3), radius: 24)
                    VStack(spacing: 8) {
                        Text(S8KBrand.name)
                            .font(S8KFont.title1.weight(.black)).tracking(5)
                            .foregroundStyle(S8KGradient.goldFlat)
                        Text(L("about.subtitle"))
                            .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary).tracking(2)
                    }
                    VStack(spacing: 5) {
                        Text("\(L("about.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                        Text("iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.s8kTextTertiary)
                    }
                    Spacer()
                    // Apple-required player-only disclaimer
                    Text(S8KLegal.disclaimer)
                        .font(S8KFont.caption2)
                        .foregroundColor(.s8kTextDisabled)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, S8KSpace.lg)
                }
                .padding(32)
            }
            .navigationTitle(L("set.about"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid)
                }
            }
        }
    }
}

// ============================================================
// Parental Control — PIN entry, category gate, lock manager
// ============================================================

/// 4-digit PIN pad. `.set` asks twice (create + confirm) → returns the new PIN.
/// `.verify` checks against the saved PIN → returns the entered PIN on success.
/// Returns nil on cancel. Never dismisses itself — the parent drives navigation.
struct PINEntryView: View {
    @Environment(\.s8kMetrics) private var metrics
    enum Mode { case set, verify }
    let mode: Mode
    var allowForgot: Bool = false
    var onForgot: (() -> Void)? = nil
    var onDone: (String?) -> Void
    @State private var entry = ""
    @State private var firstPass = ""
    @State private var confirming = false
    @State private var error = ""
    @State private var shake = false

    private var title: String {
        switch mode {
        case .verify: return L("pin.verify")
        case .set:    return confirming ? L("pin.confirm") : L("pin.create")
        }
    }

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            // SCROLLABLE: icon + title + dots + error + a 4-row keypad ≈ 530pt — taller
            // than a short window (landscape / small Mac window) or a large text size.
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundColor(.s8kGoldMid)
                Text(title).font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(i < entry.count ? Color.s8kGoldMid : Color.clear)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color.s8kGoldMid, lineWidth: 1.5))
                    }
                }
                .offset(x: shake ? -9 : 0)
                Text(error).font(S8KFont.caption1).foregroundColor(.s8kRed).frame(height: 14)
                pinPad
                if allowForgot, mode == .verify {
                    Button { onForgot?() } label: {
                        // Explicit label so the expansion is inside it. The stack's spacing
                        // is 24 and the keypad above it is all buttons, so 12 a side is the
                        // most this can take without reaching into a neighbour.
                        Text(L("pin.forgot")).s8kMinTouch(h: 12, v: 12)
                    }
                        .font(S8KFont.caption1).foregroundColor(.s8kGoldMid)
                }
                Button { onDone(nil) } label: {
                    Text(L("common.cancel")).s8kMinTouch(h: 12, v: 13)   // see the note above
                }
                    .font(S8KFont.callout).foregroundColor(.s8kTextSecondary).padding(.top, 2)
            }
            .padding(30)
            .frame(maxWidth: metrics.formMaxWidth)
            .frame(maxWidth: .infinity)
            }
            // The PIN pad was vertically centred before it became scrollable — keep it
            // centred when it fits (iOS 17+), scroll only when the window is short.
            .defaultScrollAnchor(.center)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var pinPad: some View {
        let keys = ["1","2","3","4","5","6","7","8","9","","0","⌫"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            ForEach(keys, id: \.self) { k in
                if k.isEmpty {
                    Color.clear.frame(height: 62)
                } else {
                    Button(action: { press(k) }) {
                        Text(k).font(.system(size: 25, weight: .medium)).foregroundColor(.s8kTextPrimary)
                            .frame(maxWidth: .infinity).frame(height: 62)
                            .background(Color.s8kSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
        }
        .frame(maxWidth: 280)
    }

    private func press(_ k: String) {
        error = ""
        if k == "⌫" { if !entry.isEmpty { entry.removeLast() }; return }
        guard entry.count < 4 else { return }
        entry += k
        if entry.count == 4 { submit() }
    }

    private func submit() {
        switch mode {
        case .verify:
            if ParentalService.shared.verify(entry) { onDone(entry) }
            else { fail(L("pin.wrong")) }
        case .set:
            if !confirming { firstPass = entry; entry = ""; confirming = true }
            else if entry == firstPass { onDone(entry) }
            else { firstPass = ""; confirming = false; entry = ""; fail(L("pin.mismatch")) }
        }
    }
    private func fail(_ m: String) {
        error = m; entry = ""
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) { shake.toggle() }
    }
}

/// Wraps a category screen: shows a lock screen + PIN if the category is gated.
struct ParentalGate<Content: View>: View {
    let kind: ParentalKind
    let categoryID: String
    @ViewBuilder var content: () -> Content
    @StateObject private var parental = ParentalService.shared
    @State private var showPIN = false

    var body: some View {
        Group {
            if parental.isGated(kind, categoryID) {
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill").font(.system(size: 46)).foregroundColor(.s8kGoldMid)
                        Text(L("gate.locked")).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
                        Text(L("gate.protected")).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        GoldButton(title: L("gate.enter_pin"), icon: "lock.open.fill") { showPIN = true }
                            .frame(width: 220).padding(.top, 6)
                    }
                }
                .sheet(isPresented: $showPIN) {
                    PINEntryView(mode: .verify) { pin in
                        showPIN = false
                        if pin != nil { parental.unlockSession() }
                    }
                }
            } else {
                content()
            }
        }
    }
}

/// Parental-control hub: enable (with one-time recovery code), change PIN,
/// forgot-PIN reset via recovery code, disable, and locked-categories link.
struct ParentalControlView: View {
    @Environment(\.s8kMetrics) private var metrics
    @Environment(\.dismiss) var dismiss
    @StateObject private var parental = ParentalService.shared
    @State private var step: Step = .menu
    @State private var recoveryCode = ""
    @State private var recoveryEntry = ""
    @State private var recoveryError = ""

    enum Step { case menu, create, disable, changeVerify, changeSet, forgotEntry, forgotSet, showRecovery, lockedCatsVerify, lockedCats }

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .menu: menu
        case .create:
            PINEntryView(mode: .set) { pin in
                if let p = pin { recoveryCode = parental.setupPIN(p); parental.setEnabled(true); step = .showRecovery }
                else { step = .menu }
            }
        case .disable:
            PINEntryView(mode: .verify, allowForgot: true, onForgot: { step = .forgotEntry }) { pin in
                if pin != nil { parental.setEnabled(false); dismiss() } else { step = .menu }
            }
        case .changeVerify:
            PINEntryView(mode: .verify, allowForgot: true, onForgot: { step = .forgotEntry }) { pin in
                step = (pin != nil) ? .changeSet : .menu
            }
        case .changeSet:
            PINEntryView(mode: .set) { pin in
                if let p = pin { parental.changePIN(p) }
                step = .menu
            }
        case .forgotEntry: recoveryEntryView
        case .forgotSet:
            PINEntryView(mode: .set) { pin in
                if let p = pin { recoveryCode = parental.setupPIN(p); parental.setEnabled(true); step = .showRecovery }
                else { step = .menu }
            }
        case .showRecovery: recoveryDisplay
        // The PIN is verified BEFORE the locked-category list opens, like every other
        // door in this screen. It used to open straight from the menu: "Disable" and
        // "Change PIN" both demanded the PIN, while the one screen that can actually
        // UNLOCK the categories — and unlock them in bulk — asked for nothing. A child
        // who reaches Settings walks past the lock through the widest gate in it.
        //
        // We declare parentalControls = YES on the rating questionnaire, which is a
        // statement that this control works. It did not.
        case .lockedCatsVerify:
            PINEntryView(mode: .verify, allowForgot: true, onForgot: { step = .forgotEntry }) { pin in
                step = (pin != nil) ? .lockedCats : .menu
            }
        case .lockedCats: LockedCategoriesView(onClose: { step = .menu })
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text(L("pc.title")).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
            Spacer()
            Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid)
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, max(50, metrics.safeTop + S8KSpace.sm)).padding(.bottom, S8KSpace.lg)
    }

    // Redesigned (owner spec: distinct from the reference) — a luminous shield hero,
    // a live status pill, and dark-rectangle action cards matching the settings hub.
    private var menu: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [
                            (parental.enabled ? Color.s8kGreen : Color.s8kGoldMid).opacity(0.22), .clear],
                            center: .center, startRadius: 4, endRadius: 72)).frame(width: 156, height: 156)
                        Circle().strokeBorder(Color.s8kBorderGold, lineWidth: 1).frame(width: 110, height: 110)
                        Circle().fill((parental.enabled ? Color.s8kGreen : Color.s8kGoldMid).opacity(0.12))
                            .frame(width: 92, height: 92)
                        Image(systemName: parental.enabled ? "lock.shield.fill" : "lock.open.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(parental.enabled ? .s8kGreen : .s8kGoldMid)
                    }
                    .padding(.top, 6)
                    HStack(spacing: 6) {
                        Circle().fill(parental.enabled ? Color.s8kGreen : Color.s8kTextDisabled).frame(width: 7, height: 7)
                        Text(parental.enabled ? L("app.parental.on") : L("app.parental.off"))
                            .font(S8KFont.subhead.weight(.bold))
                            .foregroundColor(parental.enabled ? .s8kGreen : .s8kTextSecondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                    if !parental.enabled {
                        Text(L("pc.enable_hint")).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                            .multilineTextAlignment(.center).lineSpacing(3).padding(.horizontal, S8KSpace.xl)
                        GoldButton(title: L("pc.enable"), icon: "lock.shield.fill") { step = .create }
                            .padding(.horizontal, S8KSpace.xl).padding(.top, 4)
                    } else {
                        VStack(spacing: 10) {
                            actionCard(L("app.locked_cats"), L("pc.locked_cats.sub"), "lock.rectangle.stack.fill") { step = .lockedCatsVerify }
                            actionCard(L("pc.change_pin"), L("pc.change_pin.sub"), "key.fill") { step = .changeVerify }
                            actionCard(L("pc.disable"), L("pc.disable.sub"), "lock.open.fill", danger: true) { step = .disable }
                        }
                        .padding(.horizontal, S8KSpace.xl).padding(.top, 4)
                    }
                    Color.clear.frame(height: 30)
                }
            }
        }
    }

    private func actionCard(_ title: String, _ subtitle: String, _ icon: String,
                            danger: Bool = false, action: @escaping () -> Void) -> some View {
        let tint = danger ? Color.s8kRed : Color.s8kGoldMid
        return Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.s8kTextDisabled)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(title).font(S8KFont.headline).foregroundColor(danger ? .s8kRed : .s8kTextPrimary).lineLimit(1)
                    Text(subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary).lineLimit(1)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.14)).frame(width: 42, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 1))
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(tint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .strokeBorder(danger ? Color.s8kRed.opacity(0.2) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }

    private var recoveryDisplay: some View {
        VStack(spacing: 18) {
            header
            Image(systemName: "key.horizontal.fill").font(.system(size: 40)).foregroundColor(.s8kGoldMid)
            Text(L("pc.recovery_title")).font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
            Text(L("pc.recovery_hint")).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, S8KSpace.xl)
            Text(recoveryCode)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(S8KGradient.goldFlat).textSelection(.enabled)
                .padding(.vertical, 14).padding(.horizontal, 24)
                .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            Button(action: { UIPasteboard.general.string = recoveryCode }) {
                Label(L("actgate.copy_id"), systemImage: "doc.on.doc").font(S8KFont.subhead).foregroundColor(.s8kGoldMid)
                    // ~20 → 44pt tall. The code panel above and the Saved button below are
                    // 18 and 24pt away, so 12 a side clears both.
                    .s8kMinTouch(h: 12, v: 12)
            }
            GoldButton(title: L("pc.recovery_saved"), icon: "checkmark") { step = .menu }
                .padding(.horizontal, S8KSpace.xl).padding(.top, 6)
            Spacer()
        }
    }

    private var recoveryEntryView: some View {
        VStack(spacing: 16) {
            header
            Image(systemName: "key.horizontal").font(.system(size: 38)).foregroundColor(.s8kGoldMid)
            Text(L("recovery.enter")).font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                .multilineTextAlignment(.center).padding(.horizontal, S8KSpace.xl)
            TextField("", text: $recoveryEntry,
                      prompt: Text("XXXXXXXX").foregroundColor(Color.s8kTextDisabled))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundColor(.s8kTextPrimary)
                .padding().frame(maxWidth: 260)
                .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kBorder, lineWidth: 1))
            if !recoveryError.isEmpty {
                Text(recoveryError).font(S8KFont.caption1).foregroundColor(.s8kRed)
            }
            GoldButton(title: L("common.done"), icon: "arrow.right") {
                if parental.verifyRecovery(recoveryEntry) { recoveryError = ""; recoveryEntry = ""; step = .forgotSet }
                else { recoveryError = L("recovery.wrong") }
            }
            .padding(.horizontal, S8KSpace.xl)
            Button(L("common.cancel")) { recoveryEntry = ""; recoveryError = ""; step = .menu }
                .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
            Spacer()
        }
    }
}

/// Lets the parent pick which categories are locked.
struct LockedCategoriesView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @StateObject private var parental = ParentalService.shared
    @StateObject private var live   = LiveTVVM.shared
    @StateObject private var movies = MoviesVM.shared
    @StateObject private var series = SeriesVM.shared

    @State private var search = ""
    @State private var kind: ParentalKind = .movie

    private func cats(_ k: ParentalKind) -> [Category] {
        switch k { case .live: return live.folders; case .movie: return movies.folders; case .series: return series.folders }
    }
    private var filtered: [Category] {
        let all = cats(kind)
        return search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func lockedCount(_ k: ParentalKind) -> Int {
        cats(k).filter { parental.isLockedCategory(k, $0.id) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Type filter (one type at a time = fast) with locked count
                    HStack(spacing: 8) {
                        typeChip(.live,   L("locked.channels"))
                        typeChip(.movie,  L("locked.movies"))
                        typeChip(.series, L("locked.series"))
                    }
                    .padding(.horizontal, S8KSpace.lg).padding(.top, S8KSpace.md)

                    SearchField(text: $search, placeholder: L("search.cat"))
                        .padding(.horizontal, S8KSpace.lg).padding(.vertical, S8KSpace.md)

                    HStack(spacing: 14) {
                        Button(action: { parental.setLockedBulk(kind, ids: filtered.map { $0.id }, true) }) {
                            Label(L("locked.lock_all"), systemImage: "lock.fill")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kGoldMid)
                                // ~16 → 40pt tall. 12 is the ceiling: the search field is
                                // 12pt above and the category list starts 8pt below, and
                                // both of those take touches of their own.
                                .s8kMinTouch(h: 14, v: 12)
                        }
                        Spacer()
                        Button(action: { parental.setLockedBulk(kind, ids: filtered.map { $0.id }, false) }) {
                            Label(L("locked.unlock_all"), systemImage: "lock.open")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kTextSecondary)
                                .s8kMinTouch(h: 14, v: 12)   // see the note above
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.sm)

                    if filtered.isEmpty {
                        EmptyState(icon: "folder.badge.questionmark", title: L("empty.no_results"),
                                   subtitle: L("grid.empty.sub"))
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { cat in catRow(cat) }
                            }
                            .background(Color.s8kSurface)
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                                .strokeBorder(Color.s8kBorder, lineWidth: 1))
                            .padding(20)
                        }
                    }
                }
                // Capped and centred. This screen takes the whole window, so on a 12.9"
                // iPad each 44pt row put ~1200pt between a category name and its toggle,
                // and the three type chips became 439pt capsules around a 60pt word.
                // The cap sits on the COLUMN, not the ZStack — the ZStack carries the
                // black backdrop, and capping that would leave the sides unpainted.
                // Mis-tapping the wrong row silently unlocks a category; this is a
                // parental control, not a list.
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(L("app.locked_cats")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { if let onClose { onClose() } else { dismiss() } }
                    .foregroundColor(.s8kGoldMid) } }
        }
    }

    private func typeChip(_ k: ParentalKind, _ title: String) -> some View {
        let on = kind == k
        let n = lockedCount(k)
        return Button(action: { withAnimation(.spring(response: 0.3)) { kind = k; search = "" } }) {
            HStack(spacing: 5) {
                Text(title).font(S8KFont.caption1.weight(.bold))
                if n > 0 {
                    Text("\(n)").font(S8KFont.caption2.weight(.black))
                        .foregroundColor(on ? .black : .s8kGoldMid)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((on ? Color.black.opacity(0.15) : Color.s8kGoldMid.opacity(0.15)))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(on ? .black : .s8kTextSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(on ? AnyShapeStyle(S8KGradient.goldFlat) : AnyShapeStyle(Color.s8kSurface))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func catRow(_ cat: Category) -> some View {
        let isLocked = parental.isLockedCategory(kind, cat.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 14))
                    .foregroundColor(isLocked ? .s8kGoldMid : .s8kTextDisabled).frame(width: 22)
                Text(cat.name).font(S8KFont.callout).foregroundColor(.s8kTextPrimary).lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(get: { isLocked },
                                         set: { _ in parental.toggleLock(kind, cat.id) }))
                    .labelsHidden().toggleStyle(SwitchToggleStyle(tint: .s8kGoldMid))
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 12)
            Divider().background(Color.s8kBorder).padding(.leading, 44)
        }
    }
}


// MARK: - Performance readout
//
// Deliberately visible rather than behind a hidden gesture: Guideline 2.3.1(a) bans
// hidden or undocumented features, so concealing a diagnostics screen is the riskier
// choice, not the safer one. It sits beside the engine diagnostics that already ship.
//
// Two chains, because one total tells you it is slow and never tells you where:
//   الفتح ← أول بوستر   process start to the first real artwork on screen
//   التشغيل ← أول إطار   tap to the first video frame
//   الكتالوج            how long the catalogue took, and whether it came off the disk
struct PerfStatsView: View {
    @State private var samples = S8KPerf.recent
    @State private var tallies = S8KPerf.counted
    @State private var copied  = false
    @State private var vlcCopied = false
    // iOS hands this app every crash, hang and disk-write exception it records, and
    // until now they were written to disk and never read by anything. Surfacing them
    // HERE, rather than building a new screen, because this is already where someone
    // comes looking for numbers about the app itself.
    // Loaded in `.task`, NOT as this property's initial value. A `@State` default IS
    // the property's initialiser, and SwiftUI re-initialises a View struct on every
    // parent body pass — so `= Diagnostics.crashNotes()` there would open the
    // directory, read every payload and parse the JSON on the MAIN THREAD, again and
    // again, for a value SwiftUI then throws away. Empty here; filled off-thread once.
    @State private var crashes: [Diagnostics.CrashNote] = []
    @State private var crashCopied = false

    var body: some View {
        SetScaffold(title: "قياس السرعة") {
            SetUI.group("آخر القياسات") {
                if samples.isEmpty {
                    Text("لا توجد قياسات بعد. أغلق التطبيق تماماً، افتحه، ثم شغّل شيئاً — وارجع إلى هنا.")
                        .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(samples.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { SetUI.divider() }
                        row(s)
                    }
                }
            }
            // Separate group, because these are a different KIND of number. Above:
            // one thing, once, how long it took. Here: something asked repeatedly
            // during a single open, summed — where "four times, 210ms altogether" is
            // the finding and any one of the four would look harmless on its own.
            if !tallies.isEmpty {
                SetUI.group("متكرّرة خلال الفتح") {
                    ForEach(Array(tallies.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { SetUI.divider() }
                        tallyRow(t)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(action: copy) {
                    Text(copied ? "نُسخ ✓" : "نسخ الكل")
                        .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kGoldMid)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                            .fill(Color.s8kGoldMid.opacity(0.10)))
                        .s8kMinTouch(2)
                }
                .buttonStyle(S8KButtonStyle())
                Button(action: { S8KPerf.clear(); samples = []; tallies = [] }) {
                    Text("تصفير")
                        .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                            .fill(Color.white.opacity(0.06)))
                        .s8kMinTouch(2)
                }
                .buttonStyle(S8KButtonStyle())
            }
            .padding(.horizontal, S8KSpace.xl)
            SetUI.group("تقارير الأعطال") {
                if crashes.isEmpty {
                    Text("لا توجد أعطال مسجَّلة. يسجّلها النظام تلقائياً بعد انهيار أو تجمّد، وقد تصل متأخّرة يوماً.")
                        .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(crashes.prefix(6).enumerated()), id: \.element.id) { i, c in
                        if i > 0 { SetUI.divider() }
                        crashRow(c)
                    }
                }
            }
            if !crashes.isEmpty {
                Button(action: copyCrashes) {
                    Text(crashCopied ? "نُسخ ✓" : "نسخ تقرير الأعطال")
                        .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kOrange)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                            .fill(Color.s8kOrange.opacity(0.10)))
                        .s8kMinTouch(2)
                }
                .buttonStyle(S8KButtonStyle())
                .padding(.horizontal, S8KSpace.xl)
            }
            // The engine's own account of the last minutes. Separate button because it
            // is RAW — it still contains the stream URL, and an Xtream URL carries the
            // subscriber's username and password in its path. What travels to the panel
            // is redacted; what this copies is not, so it goes only where the owner
            // deliberately pastes it.
            Button(action: copyVLCLog) {
                Text(vlcCopied ? "نُسخ ✓" : "نسخ سجلّ المشغّل (خام)")
                    .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
                    .s8kMinTouch(2)
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)
            Text("كل شيء هنا محلي على جهازك. لا يُرسَل أي قياس إلى أي خادم.")
                .font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, S8KSpace.xl).padding(.top, 4)
        }
        .onAppear { samples = S8KPerf.recent; tallies = S8KPerf.counted }
        .task {
            // Detached: opening the directory and parsing the payloads must not sit on
            // the main thread while this screen is appearing.
            crashes = await Task.detached(priority: .utility) { Diagnostics.crashNotes() }.value
        }
    }

    private func row(_ s: S8KPerf.Sample) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(s.ms) ms")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(s.ms > 2500 ? .s8kRed : (s.ms > 900 ? .s8kGoldMid : .s8kTextSecondary))
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.name).font(S8KFont.footnote.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                if !s.note.isEmpty {
                    Text(s.note).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    /// Total first, then how many calls made it. The thresholds are tighter than the
    /// sample row's on purpose: 300ms spread over a dozen calls never shows up as a
    /// slow anything, and is still 300ms the picture waited for.
    private func tallyRow(_ t: S8KPerf.Tally) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(t.ms) ms")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(t.ms > 300 ? .s8kRed : (t.ms > 100 ? .s8kGoldMid : .s8kTextSecondary))
            VStack(alignment: .trailing, spacing: 2) {
                Text(t.name).font(S8KFont.footnote.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                Text("×\(t.calls)").font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func crashRow(_ c: Diagnostics.CrashNote) -> some View {
        // Two facts and a date. The full payload goes out through the copy button —
        // a wall of unsymbolicated offsets on screen helps nobody.
        let headline = c.facts.first(where: { $0.0 == "exceptionType" || $0.0 == "terminationReason" })
        VStack(alignment: .trailing, spacing: 3) {
            Text(headline.map { "\($0.0): \($0.1)" } ?? c.file)
                .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                .lineLimit(1)
            Text(c.date.formatted(date: .abbreviated, time: .shortened))
                .font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 12)
    }

    private func copyCrashes() {
        UIPasteboard.general.string = Diagnostics.crashReport()
        withAnimation { crashCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { crashCopied = false } }
    }

    private func copyVLCLog() {
        let lines = VLCLog.tail(120)
        let header = "app " + PanelClient.appVersion
        UIPasteboard.general.string = lines.isEmpty
            ? "لا يوجد سجلّ بعد — شغّل شيئاً على محرّك VLC ثم عد."
            : ([header, ""] + lines).joined(separator: "\n")
        withAnimation { vlcCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { vlcCopied = false } }
    }

    private func copy() {
        UIPasteboard.general.string = S8KPerf.report
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { copied = false } }
    }
}
