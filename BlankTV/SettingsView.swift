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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        navTitle
                        profileCard
                        playlistsGroup      // القوائم في رأس الصفحة
                        activationCard
                        subscriptionCard
                        serverCard
                        playerGroup
                        appGroup
                        legalGroup
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
    }

    // MARK: - Playlists Group (top of page — add / remove / switch M3U & Xtream)
    private var activePlaylistName: String {
        let id = Store.shared.activePlaylistID
        if let p = Store.shared.savedPlaylists.first(where: { $0.id == id }) { return p.name }
        return auth.mode == .m3u ? L("settings.m3u_list") : "Xtream"
    }
    private var playlistsGroup: some View {
        group(label: L("set.playlists")) {
            row(icon: "list.and.film", title: activePlaylistName,
                value: "\(Store.shared.savedPlaylists.count)", hasChevron: true) {
                showPlaylists = true
            }
        }
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
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .s8kGoldMid.opacity(0.4), radius: 10)
                Text(String((auth.user?.username.prefix(2) ?? "BT").uppercased()))
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.black)
            }
            VStack(alignment: .trailing, spacing: 5) {
                Text(auth.user?.username ?? (auth.mode == .m3u ? L("settings.m3u_list") : L("settings.user")))
                    .font(S8KFont.title3)
                    .foregroundColor(.s8kTextPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Color.s8kGreen).frame(width: 5, height: 5)
                    Text("\(L("common.connected")) — \(theme.serverName)")
                        .font(S8KFont.caption1)
                        .foregroundColor(.s8kGoldMid)
                }
            }
            Spacer()
            Text((auth.user?.plan ?? (auth.mode == .m3u ? "M3U" : "basic")).uppercased())
                .font(S8KFont.caption3)
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(S8KGradient.goldFlat)
                .clipShape(Capsule())
                .shadow(color: .s8kGoldMid.opacity(0.4), radius: 6)
        }
        .padding(S8KSpace.lg)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg)
            .strokeBorder(Color.s8kBorderGold, lineWidth: 1.5))
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.lg)
    }

    // MARK: - Subscription Card
    @ViewBuilder
    private var subscriptionCard: some View {
        if let user = auth.user {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: user.daysRemaining > 7 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(user.daysRemaining > 7 ? .s8kGreen : .s8kOrange)
                    Text(user.daysRemaining > 7 ? L("sub.active") : L("sub.expiring"))
                        .font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    Spacer()
                    Text("\(user.daysRemaining) \(L("unit.day"))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(user.daysRemaining > 7 ? .s8kGreen : .s8kOrange)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Color.s8kElevated.cornerRadius(2)
                        (user.daysRemaining > 7 ? Color.s8kGreen : Color.s8kOrange)
                            .frame(width: g.size.width * min(1, Double(user.daysRemaining) / 30))
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)

                if AppCompliance.allowsExternalPurchaseLinks,
                   user.daysRemaining <= 7, let store = config.appConfig.storeURL {
                    Button(action: { if let u = URL(string: store) { UIApplication.shared.open(u) } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text(L("sub.renew_now")).font(S8KFont.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(S8KGradient.goldFlat)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(S8KSpace.lg)
            .background(Color.s8kSurface)
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg)
                .strokeBorder(Color.s8kBorder, lineWidth: 1))
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    // MARK: - Server Card
    @ViewBuilder
    private var serverCard: some View {
        if auth.mode == .m3u, let url = Store.shared.m3uURL {
            serverCardBody(host: url, badge: "M3U")
        } else if let creds = Keychain.shared.serverCredentials() {
            serverCardBody(host: creds.host, badge: "Xtream")
        }
    }

    private func serverCardBody(host: String, badge: String) -> some View {
        group(label: L("settings.active_server")) {
            HStack(spacing: 12) {
                Circle().fill(Color.s8kGreen)
                    .frame(width: 9, height: 9)
                    .shadow(color: .s8kGreen.opacity(0.5), radius: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L("common.connected")).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    Text(host)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.s8kTextDisabled)
                        .lineLimit(1)
                }
                Spacer()
                Text(badge)
                    .font(S8KFont.caption3).foregroundColor(.s8kGoldMid)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.s8kGoldMid.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            }
            .padding(S8KSpace.lg)
        }
    }

    // MARK: - Activation Card (device id + status)
    private var activationCard: some View {
        group(label: L("set.activation")) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    iconBox(activationColor, icon: activationIcon)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(activationTitle)
                            .font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                        if let days = activation.daysLeft, activation.isAllowed {
                            Text("\(L("time.remaining")) \(days) \(L("unit.day"))")
                                .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                        }
                    }
                    Spacer()
                }

                Divider().background(Color.s8kBorder)

                // Device ID with copy
                HStack(spacing: 10) {
                    Button(action: copyDeviceID) {
                        Image(systemName: idCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 15))
                            .foregroundColor(.s8kGoldMid)
                    }
                    .buttonStyle(S8KButtonStyle())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L("settings.device_id"))
                            .font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                        Text(activation.deviceID)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.s8kTextPrimary)
                            .textSelection(.enabled)
                    }
                }

                // Subscription type + expiry (under the MAC)
                if activation.isAllowed {
                    Divider().background(Color.s8kBorder)
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 13)).foregroundColor(.s8kGoldMid)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(subscriptionKindText)
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kTextPrimary)
                            Text(expiryText)
                                .font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                        }
                    }
                }
            }
            .padding(S8KSpace.lg)
        }
    }

    private var subscriptionKindText: String {
        if activation.status == "trial" { return L("act.kind_trial") }
        return activation.expiresAt == nil ? L("act.kind_lifetime") : L("act.kind_yearly")
    }
    private var expiryText: String {
        if let exp = activation.expiresAt {
            let date = Date(timeIntervalSince1970: exp)
            let df = DateFormatter()
            df.locale = Locale(identifier: LocalizationManager.current.rawValue)
            df.dateStyle = .medium
            let days = activation.daysLeft ?? 0
            return "\(L("act.expires_on")) \(df.string(from: date)) · \(L("time.remaining")) \(days) \(L("unit.day"))"
        }
        return L("act.valid_forever")
    }

    private var activationTitle: String {
        switch activation.status {
        case "active":  return activation.activationType == "owner" ? L("act.active_owner") : L("act.active")
        case "trial":   return L("act.kind_trial")
        case "expired": return L("act.expired")
        case "blocked": return L("act.blocked")
        default:        return L("act.not_activated")
        }
    }
    private var activationColor: Color {
        switch activation.status {
        case "active": return .s8kGreen
        case "trial":  return .s8kOrange
        case "blocked", "expired": return .s8kRed
        default: return .s8kTextDisabled
        }
    }
    private var activationIcon: String {
        switch activation.status {
        case "active": return "checkmark.seal.fill"
        case "trial":  return "clock.badge.checkmark"
        case "blocked": return "lock.fill"
        default: return "exclamationmark.shield.fill"
        }
    }
    private func copyDeviceID() {
        UIPasteboard.general.string = activation.deviceID
        withAnimation { idCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { idCopied = false }
        }
    }

    // MARK: - Player Group
    private var playerGroup: some View {
        group(label: L("set.player")) {
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
    }

    private func engineLabel(_ p: String) -> String {
        switch p {
        case "av":  return L("player.engine.av")
        case "vlc": return L("player.engine.vlc")
        default:    return L("player.engine.auto")
        }
    }

    // MARK: - App Group
    private var appGroup: some View {
        group(label: L("set.app")) {
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
            divider()
            row(icon: "info.circle.fill", color: .s8kGoldMid, title: L("set.about"),
                value: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")",
                hasChevron: true) { showAbout = true }
        }
    }

    // MARK: - Legal Group
    private var legalGroup: some View {
        group(label: L("set.legal")) {
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
                let subject = "إبلاغ عن محتوى — BLANK TV"
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
            Text("BLANK TV")
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
            // Refined section header — clean Arabic-friendly weight, no uppercase
            // or heavy tracking (which break Arabic letterforms).
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.s8kTextTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24).padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.bottom, S8KSpace.xxl)
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
                        Text("BLANK TV")
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

    private var menu: some View {
        VStack(spacing: 14) {
            header
            ZStack {
                Circle().fill(Color.s8kGoldMid.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: parental.enabled ? "lock.shield.fill" : "lock.open")
                    .font(.system(size: 34)).foregroundColor(.s8kGoldMid)
            }
            .padding(.vertical, 8)
            if !parental.enabled {
                Text(L("pc.enable_hint")).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, S8KSpace.xl)
                GoldButton(title: L("pc.enable"), icon: "lock.shield.fill") { step = .create }
                    .padding(.horizontal, S8KSpace.xl).padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    optionRow(L("app.locked_cats"), "lock.rectangle.stack.fill") { step = .lockedCats }
                    Divider().background(Color.s8kBorder).padding(.leading, 56)
                    optionRow(L("pc.change_pin"), "key.fill") { step = .changeVerify }
                    Divider().background(Color.s8kBorder).padding(.leading, 56)
                    optionRow(L("pc.disable"), "lock.open.fill", danger: true) { step = .disable }
                }
                .background(Color.s8kSurface)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                .padding(.horizontal, S8KSpace.xl)
            }
            Spacer()
        }
    }

    private func optionRow(_ title: String, _ icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15))
                    .foregroundColor(danger ? .s8kRed : .s8kTextSecondary).frame(width: 26)
                Text(title).font(S8KFont.callout.weight(.semibold))
                    .foregroundColor(danger ? .s8kRed : .s8kTextPrimary)
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 12)).foregroundColor(.s8kTextDisabled)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.vertical, 15)
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
