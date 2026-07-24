// ============================================================
// BLANK TV — SettingsView.swift
// Settings — Apple HIG • Delete Account • Privacy
// ============================================================

import SwiftUI

struct SettingsView: View {
    @StateObject private var auth   = AuthService.shared
    @StateObject private var config = ConfigService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var loc    = LocalizationManager.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var idCopied = false

    @State private var sleepMins     = Store.shared.sleepTimerMins
    @State private var quality       = Store.shared.preferredQuality
    @StateObject private var parental = ParentalService.shared
    @State private var showParental = false
    @State private var analyticsOn   = Store.shared.analyticsConsent
    @State private var notifOn       = Store.shared.notificationsEnabled
    @State private var pipOn         = Store.shared.pipEnabled
    @State private var enginePref    = Store.shared.playerEnginePref
    @State private var turboOn       = Store.shared.turboDownloads
    @State private var wifiOnlyOn    = Store.shared.downloadWifiOnly
    @State private var autoNextOn    = Store.shared.autoPlayNext
    @State private var autoNextSecs  = Store.shared.autoNextSeconds
    @State private var skipIntroOn   = Store.shared.skipIntroEnabled
    @State private var skipIntroSecs = Store.shared.skipIntroSeconds

    @State private var showDeleteAlert  = false
    @State private var showLogoutAlert  = false
    @State private var showPrivacy      = false
    @State private var showTerms        = false
    @State private var showAbout        = false
    @State private var showPlaylists    = false
    @State private var showDownloads    = false
    @State private var showReorder      = false   // unified content organizer (#7)
    @State private var showProV2        = false   // TEMP: preview the redesigned settings in isolation
    /// Which accordion sections are expanded (all collapsed on open for a clean,
    /// compact page). Keyed by the section id passed to `section(_:)`.
    @State private var openSections: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        navTitle
                        profileCard
                        // TEMP preview entry — verify the redesigned settings in
                        // isolation before swapping it in (removed after sign-off).
                        Button { showProV2 = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                                Text("معاينة التصميم الجديد (تجريبي)").font(S8KFont.subhead.weight(.bold))
                                Spacer()
                                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.s8kBlack)
                            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).fill(S8KGradient.goldFlat))
                            .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                        }
                        .buttonStyle(S8KButtonStyle())
                        // Consolidated collapsible sections (accordion). The page
                        // opens compact — just the profile header + four tidy
                        // section rows — and the user expands only what they need.
                        // This replaces the old long stack of separate cards +
                        // stand-alone sub-pages, per the owner's "simple & organized".
                        section("connection", label: L("set.connection"),
                                icon: "dot.radiowaves.left.and.right",
                                summary: activePlaylistName) { connectionContent }
                        section("player", label: L("set.player"),
                                icon: "play.rectangle.fill") { playerContent }
                        section("app", label: L("set.app"),
                                icon: "gearshape.fill",
                                summary: loc.lang.display) { appContent }
                        section("about", label: L("set.about_legal"),
                                icon: "info.circle.fill",
                                summary: "v\(appVersion)") { legalContent }
                        logoutBtn
                        footer
                        Color.clear.frame(height: 100)
                    }
                    // Cap + center the column on iPad so rows aren't stretched
                    // edge-to-edge (icon and toggle a foot apart).
                    .frame(maxWidth: hSize == .regular ? 700 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationBarHidden(true)
        }
        .overlay {
            if showLogoutAlert {
                S8KConfirm(icon: "rectangle.portrait.and.arrow.right", iconColor: .s8kRed,
                           title: L("set.logout"), message: L("alert.logout.msg"),
                           confirmTitle: L("set.logout"), destructive: true,
                           onConfirm: { showLogoutAlert = false; Task { await auth.logout() } },
                           onCancel: { withAnimation { showLogoutAlert = false } })
                    .zIndex(10)
            } else if showDeleteAlert {
                S8KConfirm(icon: "person.crop.circle.badge.minus", iconColor: .s8kRed,
                           title: L("set.delete"),
                           message: L("alert.delete.msg"),
                           confirmTitle: L("alert.delete.confirm"), destructive: true,
                           onConfirm: { showDeleteAlert = false; Task { try? await auth.deleteAccount() } },
                           onCancel: { withAnimation { showDeleteAlert = false } })
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLogoutAlert)
        .animation(.easeInOut(duration: 0.2), value: showDeleteAlert)
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
        .sheet(isPresented: $showAbout)   { AboutView() }
        .sheet(isPresented: $showPlaylists) { PlaylistsView() }
        .sheet(isPresented: $showParental) { ParentalControlView() }
        .sheet(isPresented: $showDownloads) { DownloadsView() }
        .sheet(isPresented: $showReorder) { UnifiedReorderView() }
        .fullScreenCover(isPresented: $showProV2) { SettingsProV2(onClose: { showProV2 = false }) }
    }

    // Active playlist/account name — shown in the connection row + section summary.
    private var activePlaylistName: String {
        let id = Store.shared.activePlaylistID
        if let p = Store.shared.savedPlaylists.first(where: { $0.id == id }) { return p.name }
        return auth.mode == .m3u ? L("settings.m3u_list") : "Xtream"
    }

    // MARK: - Nav Title
    private var navTitle: some View {
        // Unified page-title style — matches the shared ContentTitleBar used by
        // the Live / Movies / Series tabs (S8KFont.title1), so every top-level
        // page header looks identical.
        Text(L("set.title"))
            .font(S8KFont.title1)
            .foregroundColor(.s8kTextPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.top, 60)
            .padding(.bottom, S8KSpace.xl)
    }

    // MARK: - Profile Card
    private var profileCard: some View {
        HStack(spacing: S8KSpace.lg) {
            ZStack {
                S8KGradient.goldFlat
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .shadow(color: .s8kGoldMid.opacity(0.45), radius: 10, y: 3)
                Text(String((auth.user?.username.prefix(2) ?? "BT").uppercased()))
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.s8kBlack)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(auth.user?.username ?? (auth.mode == .m3u ? L("settings.m3u_list") : L("settings.user")))
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.s8kTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(Color.s8kGreen).frame(width: 6, height: 6)
                    Text("\(L("common.connected")) — \(theme.serverName)")
                        .font(S8KFont.caption1)
                        .foregroundColor(.s8kGoldHigh)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text((auth.user?.plan ?? (auth.mode == .m3u ? "M3U" : "basic")).uppercased())
                .font(S8KFont.caption3.weight(.heavy))
                .foregroundColor(.s8kBlack)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(S8KGradient.goldFlat)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .shadow(color: .s8kGoldMid.opacity(0.4), radius: 6)
        }
        .padding(S8KSpace.lg)
        .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).fill(Color.s8kCard))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.lg)
    }

    private func copyDeviceID() {
        UIPasteboard.general.string = activation.deviceID
        withAnimation { idCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { idCopied = false }
        }
    }

    // MARK: - Player content (rows inside the "Player" accordion section)
    @ViewBuilder private var playerContent: some View {
            toggleRow(icon: "play.square.stack.fill",
                      title: L("player.autonext.title"),
                      desc: L("player.autonext.desc"), isOn: $autoNextOn)
                .onChange(of: autoNextOn) { _, v in Store.shared.autoPlayNext = v }
            if autoNextOn {
                divider()
                row(icon: "timer", title: L("player.autonext.timer"), value: "\(autoNextSecs) \(L("unit.second_short"))") {
                    let options = [10, 20, 30, 50, 60, 120]
                    let next = options[((options.firstIndex(of: autoNextSecs) ?? 0) + 1) % options.count]
                    autoNextSecs = next
                    Store.shared.autoNextSeconds = next
                }
            }
            divider()
            toggleRow(icon: "forward.end.fill",
                      title: L("player.skipintro.title"),
                      desc: L("player.skipintro.desc"), isOn: $skipIntroOn)
                .onChange(of: skipIntroOn) { _, v in Store.shared.skipIntroEnabled = v }
            divider()
            row(icon: "timer", title: L("player.skipintro.dur"), value: "\(skipIntroSecs) \(L("unit.second_short"))") {
                let options = [60, 75, 85, 90, 120]
                let next = options[((options.firstIndex(of: skipIntroSecs) ?? 2) + 1) % options.count]
                skipIntroSecs = next
                Store.shared.skipIntroSeconds = next
            }
            divider()
            row(icon: "play.circle.fill", title: L("player.quality"), value: quality.displayName) {
                let all = StreamQuality.allCases
                if let i = all.firstIndex(of: quality) {
                    quality = all[(i + 1) % all.count]
                    Store.shared.preferredQuality = quality
                }
            }
            divider()
            toggleRow(icon: "rectangle.inset.filled.on.rectangle", color: .s8kGreen,
                      title: L("player.pip"), desc: L("player.pip.desc"), isOn: $pipOn)
                .onChange(of: pipOn) { _, newValue in Store.shared.pipEnabled = newValue }
            divider()
            // "Select Player" — matches pro IPTV apps (Smarters / OTT Navigator):
            // Auto (hardware AVPlayer for HLS/mp4, VLC otherwise) / force Hardware / force VLC.
            row(icon: "cpu", title: L("player.engine"), value: engineLabel(enginePref)) {
                let order = ["auto", "av", "vlc"]
                let next = order[((order.firstIndex(of: enginePref) ?? 0) + 1) % order.count]
                enginePref = next
                Store.shared.playerEnginePref = next
            }
            divider()
            row(icon: "moon.stars.fill", color: Color(hex: "5856D6"),
                title: L("player.sleep.default"), value: "\(sleepMins) \(L("unit.minute"))") {
                let options = [15, 30, 45, 60, 90, 120]
                let next = options[((options.firstIndex(of: sleepMins) ?? 0) + 1) % options.count]
                sleepMins = next
                Store.shared.sleepTimerMins = next
            }
    }

    private func engineLabel(_ p: String) -> String {
        switch p {
        case "av":  return L("player.engine.av")
        case "vlc": return L("player.engine.vlc")
        default:    return L("player.engine.auto")
        }
    }

    // MARK: - App content (rows inside the "App" accordion section)
    @ViewBuilder private var appContent: some View {
            // Language picker
            Menu {
                ForEach(AppLang.allCases) { l in
                    Button(action: { loc.set(l) }) {
                        if loc.lang == l { Label(l.display, systemImage: "checkmark") }
                        else { Text(l.display) }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    iconBox(.s8kGreen, icon: "globe")
                    Text(L("settings.language")).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                    Spacer()
                    Text(loc.lang.display).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.s8kTextDisabled)
                }
                .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
            }
            divider()
            toggleRow(icon: "bell.badge.fill", color: .s8kOrange,
                      title: L("set.notifications"), desc: L("app.notif.desc"), isOn: $notifOn)
                .onChange(of: notifOn) { _, newValue in Store.shared.notificationsEnabled = newValue }
            divider()
            // Unified content organizer (owner #7) — Movies/Series/Live in one place.
            row(icon: "arrow.up.arrow.down.circle.fill", color: .s8kGoldMid, title: L("reorder.manage"),
                hasChevron: true) { showReorder = true }
            divider()
            // Offline downloads management
            row(icon: "arrow.down.circle.fill", color: .s8kGreen, title: L("set.downloads"),
                value: DownloadService.shared.completedCount > 0 ? "\(DownloadService.shared.completedCount)" : "",
                hasChevron: true) { showDownloads = true }
            divider()
            // Turbo (parallel) downloads — opt-in, see note about IPTV connection limits.
            toggleRow(icon: "bolt.fill", color: .s8kGoldMid, title: L("downloads.turbo"),
                      desc: L("downloads.turbo.desc"), isOn: $turboOn)
                .onChange(of: turboOn) { _, v in Store.shared.turboDownloads = v }
            divider()
            toggleRow(icon: "wifi", color: .s8kBlue, title: L("downloads.wifi_only"),
                      desc: L("downloads.wifi_only.desc"), isOn: $wifiOnlyOn)
                .onChange(of: wifiOnlyOn) { _, v in Store.shared.downloadWifiOnly = v }
            divider()
            if config.hasParental {
                row(icon: "lock.shield.fill", title: L("app.parental"),
                    value: parental.enabled ? L("app.parental.on") : L("app.parental.off"),
                    hasChevron: true) { showParental = true }
                divider()
            }
            toggleRow(icon: "chart.bar.fill", color: .s8kBlue,
                      title: L("app.analytics"), desc: L("app.analytics.desc"), isOn: $analyticsOn)
                .onChange(of: analyticsOn) { _, newValue in Store.shared.analyticsConsent = newValue }
    }

    // MARK: - About & Legal content (rows inside the "About & Legal" section)
    @ViewBuilder private var legalContent: some View {
            // About the app (was a separate group row / sheet — now lives here).
            row(icon: "info.circle.fill", color: .s8kGoldMid, title: L("set.about"),
                value: "v\(appVersion)", hasChevron: true) { showAbout = true }
            divider()
            // Support / contact (compliant — no prices). Always findable here.
            if let support = activation.supportURL, let u = URL(string: support) {
                row(icon: "bubble.left.and.bubble.right.fill", title: L("set.support"),
                    hasChevron: true) { UIApplication.shared.open(u) }
                divider()
            }
            row(icon: "hand.raised.fill",   color: .s8kBlue,            title: L("set.privacy"), hasChevron: true) { showPrivacy = true }
            divider()
            row(icon: "doc.text.fill",      color: Color(hex: "5E5CE6"), title: L("set.terms"), hasChevron: true) { showTerms = true }
            divider()
            // APPLE REQUIRED (4.7.1): report objectionable content
            row(icon: "exclamationmark.bubble.fill", color: .s8kOrange,
                title: L("legal.report"), hasChevron: true) {
                let subject = "إبلاغ عن محتوى — Blank Prime"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "mailto:\(S8KLegal.reportEmail)?subject=\(subject)") {
                    UIApplication.shared.open(u)
                }
            }
            divider()
            // APPLE REQUIRED: Delete Account
            Button(action: { showDeleteAlert = true }) {
                HStack(spacing: 12) {
                    iconBox(.s8kRed, icon: "person.crop.circle.badge.minus")
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L("set.delete"))
                            .font(S8KFont.callout.weight(.semibold))
                            .foregroundColor(.s8kRed)
                        Text(L("legal.delete.desc"))
                            .font(S8KFont.caption2)
                            .foregroundColor(Color.s8kRed.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
            }
            .buttonStyle(S8KButtonStyle())
    }

    // MARK: - Logout Button
    private var logoutBtn: some View {
        Button(action: { showLogoutAlert = true }) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text(L("set.logout")).font(S8KFont.headline)
            }
            .foregroundColor(.s8kRed)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Color.s8kRed.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg)
                .strokeBorder(Color.s8kRed.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 8)
        .padding(.bottom, S8KSpace.lg)
    }

    // MARK: - Footer
    private var footer: some View {
        VStack(spacing: 5) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .opacity(0.8)
            Text("Blank Prime")
                .font(.system(size: 11, weight: .black)).tracking(2)
                .foregroundColor(.s8kTextDisabled)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.s8kTextDisabled.opacity(0.5))
        }
        .padding(.vertical, S8KSpace.xl)
    }

    // MARK: - Builders
    @ViewBuilder
    private func group<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            // Editorial section header — heavier label with a short lime accent bar
            // (RTL: bar sits on the trailing/right edge). Clean, Arabic-friendly.
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.s8kTextSecondary)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(S8KGradient.goldFlat)
                    .frame(width: 3, height: 14)
            }
            .padding(.horizontal, 24).padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.bottom, S8KSpace.xxl)
    }

    // MARK: - Accordion section (collapsible, consolidated group)
    // One glass card = one logical group. The header row toggles the section
    // open/closed with a snappy spring; the chevron rotates + goes gold, and the
    // border warms to gold while open. Collapsed sections show a one-line summary
    // on the trailing side so the user can scan state without expanding.
    @ViewBuilder
    private func section<Content: View>(_ id: String, label: String, icon: String,
                                        summary: String = "",
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = openSections.contains(id)
        VStack(spacing: 0) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.32)) {
                    if isOpen { openSections.remove(id) } else { openSections.insert(id) }
                }
            } label: {
                HStack(spacing: 12) {
                    iconBox(.s8kTextSecondary, icon: icon)
                    Text(label)
                        .font(S8KFont.callout.weight(.bold))
                        .foregroundColor(.s8kTextPrimary)
                    Spacer(minLength: 8)
                    if !summary.isEmpty && !isOpen {
                        Text(summary)
                            .font(S8KFont.caption1)
                            .foregroundColor(.s8kTextTertiary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isOpen ? .s8kGoldMid : .s8kTextDisabled)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, S8KSpace.lg)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(S8KButtonStyle())

            if isOpen {
                divider()
                VStack(spacing: 0) { content() }
                    .padding(.bottom, 4)
            }
        }
        .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .strokeBorder(isOpen ? Color.s8kBorderGold : Color.s8kBorder, lineWidth: 1))
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.md)
    }

    // MARK: - Connection & account content
    private var currentServerHost: String? {
        if auth.mode == .m3u { return Store.shared.m3uURL }
        return Keychain.shared.serverCredentials()?.host
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @ViewBuilder private var connectionContent: some View {
        // Saved playlists / accounts — opens the manager sheet.
        row(icon: "list.and.film", title: activePlaylistName,
            value: "\(Store.shared.savedPlaylists.count)", hasChevron: true) {
            showPlaylists = true
        }
        // Active server host (read-only status).
        if let host = currentServerHost {
            divider()
            HStack(spacing: 12) {
                iconBox(.s8kTextSecondary, icon: "server.rack")
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L("common.connected"))
                        .font(S8KFont.callout.weight(.semibold))
                        .foregroundColor(.s8kTextPrimary)
                    Text(host)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.s8kTextDisabled)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Circle().fill(Color.s8kGreen).frame(width: 8, height: 8)
                    .shadow(color: .s8kGreen.opacity(0.5), radius: 4)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
        }
        // Device ID — tap to copy (useful for support).
        divider()
        Button(action: copyDeviceID) {
            HStack(spacing: 12) {
                iconBox(.s8kTextSecondary, icon: idCopied ? "checkmark.circle.fill" : "doc.on.doc")
                Text(L("settings.device_id"))
                    .font(S8KFont.callout.weight(.semibold))
                    .foregroundColor(.s8kTextPrimary)
                Spacer(minLength: 8)
                Text(activation.deviceID)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.s8kTextTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func divider() -> some View {
        Divider().background(Color.s8kBorder).padding(.leading, 60)
    }

    // Luxury restraint: icons are a refined neutral monochrome on a subtle tile.
    // Only destructive actions (red) keep their color, so danger still reads.
    private func iconBox(_ color: Color = .s8kTextSecondary, icon: String) -> some View {
        let isDanger = color == .s8kRed
        let tint     = isDanger ? Color.s8kRed : Color.s8kTextSecondary
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDanger ? Color.s8kRed.opacity(0.12) : Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isDanger ? Color.s8kRed.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 1))
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(tint)
        }
    }

    private func row(icon: String, color: Color = .s8kTextSecondary, title: String, value: String = "",
                     hasChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconBox(color, icon: icon)
                Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                Spacer()
                if !value.isEmpty {
                    Text(value).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                }
                if hasChevron {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.s8kTextDisabled)
                }
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
            .contentShape(Rectangle())   // whole row tappable, not just the text
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func toggleRow(icon: String, color: Color = .s8kTextSecondary, title: String,
                           desc: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconBox(color, icon: icon)
            // .leading so the title sits right after the icon exactly like row(),
            // keeping every settings row's title on the same alignment.
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                Text(desc).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: .s8kGoldMid))
                .labelsHidden()
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 14)
    }
}

// ============================================================
// MARK: - Settings redesign V2 (isolated · previewed · then swapped)
// Built as a SEPARATE view (NOT in the tab bar, so it never evaluates at launch)
// so it can be verified on-device via a temporary preview button BEFORE replacing
// the live Settings — the big-tech safe-rollout the owner asked for. Uses only
// simple, proven SwiftUI patterns (plain card backgrounds, natural-order RTL rows)
// — deliberately avoiding the fancy nested background/overlay layering.
// Design: premium grouped cards (Apple-Settings-grade, Arabic-natural direction).
// ============================================================
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
                    .font(.system(size: 12, weight: .heavy)).tracking(0.5)
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
    var onClose: (() -> Void)? = nil
    @StateObject private var auth   = AuthService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var parental = ParentalService.shared
    @StateObject private var config = ConfigService.shared
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
    private var planText: String { (auth.user?.plan ?? (auth.mode == .m3u ? "M3U" : "basic")).uppercased() }
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
                            Color.clear.frame(height: 30)
                        }
                        .frame(maxWidth: hSize == .regular ? 640 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 6)
                }

                closeButton
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
                Text(initials).font(.system(size: 29, weight: .black)).foregroundColor(.s8kBlack)
            }
            Text(displayName).font(.system(size: 23, weight: .black))
                .foregroundColor(.s8kTextPrimary).lineLimit(1)
            HStack(spacing: 8) {
                Text(planText).font(S8KFont.caption3.weight(.heavy)).foregroundColor(.s8kBlack)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(S8KGradient.goldFlat))
                HStack(spacing: 5) {
                    Circle().fill(Color.s8kGreen).frame(width: 6, height: 6)
                    Text("\(L("common.connected")) · \(theme.serverName)")
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
        if config.hasParental {
            sectionButton(icon: "lock.shield.fill", title: L("app.parental"),
                          subtitle: parental.enabled ? L("app.parental.on") : L("app.parental.off"),
                          tint: parental.enabled ? .s8kGreen : .s8kGoldMid) {
                showParental = true
            }
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
        }
        .buttonStyle(S8KButtonStyle())
        .padding(.leading, 18).padding(.top, 6)
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
            Image("Logo").resizable().scaledToFit().frame(width: 28, height: 28).opacity(0.8)
            Text("Blank Prime").font(.system(size: 11, weight: .black)).tracking(2).foregroundColor(.s8kTextDisabled)
            Text("v\(appVersion)").font(.system(size: 10, design: .monospaced)).foregroundColor(.s8kTextDisabled.opacity(0.5))
        }
        .padding(.top, 10)
    }
}

// MARK: - Detail scaffold (dark page + inline nav title, width-capped for iPad/Mac)
struct SetScaffold<C: View>: View {
    let title: String
    @Environment(\.horizontalSizeClass) private var hSize
    @ViewBuilder var content: () -> C
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) { content(); Color.clear.frame(height: 30) }
                    .padding(.top, 14)
                    .frame(maxWidth: hSize == .regular ? 640 : .infinity)
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
            }
        }
        .sheet(isPresented: $showPlaylists) { PlaylistsView() }
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

    private func engineLabel(_ p: String) -> String {
        switch p { case "av": return L("player.engine.av"); case "vlc": return L("player.engine.vlc"); default: return L("player.engine.auto") }
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
    @State private var showDeleteAlert = false
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    var body: some View {
        SetScaffold(title: L("set.about_legal")) {
            SetUI.group(L("set.about_legal")) {
                SetUI.navRow(icon: "info.circle.fill", title: L("set.about"), value: "v\(appVersion)", chevron: true) { showAbout = true }
                if let support = activation.supportURL, let u = URL(string: support) {
                    SetUI.divider()
                    SetUI.navRow(icon: "bubble.left.and.bubble.right.fill", title: L("set.support"), chevron: true) { UIApplication.shared.open(u) }
                }
                SetUI.divider()
                SetUI.navRow(icon: "hand.raised.fill", title: L("set.privacy"), chevron: true) { showPrivacy = true }
                SetUI.divider()
                SetUI.navRow(icon: "doc.text.fill", title: L("set.terms"), chevron: true) { showTerms = true }
                SetUI.divider()
                Button(action: { showDeleteAlert = true }) {
                    SetUI.proRow(icon: "person.crop.circle.badge.minus", title: L("set.delete"), danger: true, trailing: { EmptyView() })
                }.buttonStyle(S8KButtonStyle())
            }
        }
        .sheet(isPresented: $showAbout)   { AboutView() }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
        .overlay {
            if showDeleteAlert {
                S8KConfirm(icon: "person.crop.circle.badge.minus", iconColor: .s8kRed,
                           title: L("set.delete"), message: L("alert.delete.msg"),
                           confirmTitle: L("alert.delete.confirm"), destructive: true,
                           onConfirm: { showDeleteAlert = false; Task { try? await auth.deleteAccount() } },
                           onCancel: { withAnimation { showDeleteAlert = false } }).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDeleteAlert)
    }
}

// ============================================================
// MARK: - Account switcher (Netflix-profile style, opened from the hero)
// A grid of profile avatars: the current account (highlighted) + the other saved
// accounts (tap to switch) + a dashed "+" tile to add a new one (Xtream / M3U via
// the existing LoginView). Each account name is editable (owner spec). Switching
// reboots content (switchPlaylist → contentReady=false) which unmounts this cover.
// ============================================================
struct AccountSwitcherView: View {
    var onClose: () -> Void
    @StateObject private var auth = AuthService.shared
    @State private var accounts: [SavedPlaylist] = Store.shared.savedPlaylists
    @State private var showAdd = false
    @State private var switching = false
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
                    }.buttonStyle(S8KButtonStyle())
                    Spacer()
                    Text(L("accounts.title")).font(.system(size: 20, weight: .black)).foregroundColor(.s8kTextPrimary)
                }
                .padding(.horizontal, 20).padding(.top, 56).padding(.bottom, 26)

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
    }

    private func tile(_ acc: SavedPlaylist) -> some View {
        let isActive = acc.id == Store.shared.activePlaylistID
        return VStack(spacing: 9) {
            Button { if !isActive { switchTo(acc) } } label: {
                ZStack {
                    Circle().fill(S8KGradient.goldFlat).frame(width: 88, height: 88)
                        .shadow(color: .s8kGoldMid.opacity(0.40), radius: 12, y: 4)
                    Text(String(acc.name.prefix(2).uppercased()))
                        .font(.system(size: 30, weight: .black)).foregroundColor(.s8kBlack)
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
            Text(L("accounts.add")).font(S8KFont.subhead.weight(.bold)).foregroundColor(.s8kTextPrimary)
            Text("Xtream · M3U").font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
            Color.clear.frame(height: 22)   // align with the rename row height
        }
    }

    private func switchTo(_ acc: SavedPlaylist) {
        switching = true
        Task { await auth.switchPlaylist(acc); switching = false; onClose() }
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
                        Button(action: { showAdd = true }) {
                            Image(systemName: "plus").foregroundColor(.s8kGoldMid)
                        }
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
                    .frame(width: 30, height: 30)
            }
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
            await auth.switchPlaylist(p)
            activeID = p.id
            switching = false
            dismiss()
        }
    }
    private func refresh() {
        playlists = Store.shared.savedPlaylists
        activeID  = Store.shared.activePlaylistID
    }
}

struct AddPlaylistView: View {
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
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(L("playlists.add")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.cancel")) { dismiss() }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium])
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
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .s8kGoldHigh.opacity(0.3), radius: 24)
                    VStack(spacing: 8) {
                        Text("Blank Prime")
                            .font(.system(size: 28, weight: .black)).tracking(5)
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
                    Button(L("pin.forgot")) { onForgot?() }
                        .font(S8KFont.caption1).foregroundColor(.s8kGoldMid)
                }
                Button(L("common.cancel")) { onDone(nil) }
                    .font(S8KFont.callout).foregroundColor(.s8kTextSecondary).padding(.top, 2)
            }
            .padding(30)
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
    @Environment(\.dismiss) var dismiss
    @StateObject private var parental = ParentalService.shared
    @State private var step: Step = .menu
    @State private var recoveryCode = ""
    @State private var recoveryEntry = ""
    @State private var recoveryError = ""

    enum Step { case menu, create, disable, changeVerify, changeSet, forgotEntry, forgotSet, showRecovery, lockedCats }

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
        .padding(.horizontal, S8KSpace.xl).padding(.top, 50).padding(.bottom, S8KSpace.lg)
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
                            actionCard(L("app.locked_cats"), L("pc.locked_cats.sub"), "lock.rectangle.stack.fill") { step = .lockedCats }
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
                        }
                        Spacer()
                        Button(action: { parental.setLockedBulk(kind, ids: filtered.map { $0.id }, false) }) {
                            Label(L("locked.unlock_all"), systemImage: "lock.open")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kTextSecondary)
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
                    Text("\(n)").font(.system(size: 10, weight: .black))
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
