// ============================================================
// BLANK TV — AuthViews.swift
// Splash + Login + Privacy + Terms
// iOS 17+ • Apple HIG Compliant
// ============================================================

import SwiftUI

// MARK: - Splash Screen
struct SplashView: View {
    let onComplete: () -> Void

    @State private var logoOpacity: Double  = 0
    @State private var logoScale:   CGFloat = 0.88
    @State private var textOpacity: Double  = 0
    @State private var macOpacity:  Double  = 0

    var body: some View {
        ZStack {
            // Pure charcoal — no ambient glow
            Color.s8kBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    BrandLogo(size: 132)
                        .opacity(logoOpacity)
                        .scaleEffect(logoScale)

                    S8KWordmark(size: 26)
                        .opacity(textOpacity)
                }

                Spacer()

                // Subtle progress + device id at the bottom
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.s8kGoldMid)
                        .scaleEffect(0.9)

                    VStack(spacing: 4) {
                        Text(L("splash.device_id"))
                            .font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
                        Text(DeviceIdentity.current)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.s8kTextTertiary)
                            .textSelection(.enabled)
                    }
                    .opacity(macOpacity)
                }
                .padding(.bottom, 54)
            }
        }
        .onAppear { startAnimation() }
        // Resolve activation WHILE the splash is showing, so by the time it
        // ends the gate is already decided — removes the separate
        // "جارٍ التحقق" flash between splash and the content loader.
        .task { if !Store.shared.demoMode { await ActivationService.shared.check() } }
    }

    private func startAnimation() {
        withAnimation(.easeOut(duration: 0.7)) { logoOpacity = 1; logoScale = 1.0 }
        withAnimation(.easeOut(duration: 0.6).delay(0.25)) { textOpacity = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.5))  { macOpacity = 1 }
        // Snappy splash: hold only long enough to register the branded intro, then
        // fade. The activation check runs in the background (optimistic gate), so we
        // never block the splash on the network. Hold trimmed 1.0s→0.5s = ~0.5s off
        // every relaunch, keeping a quick, elegant brand beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.32)) { logoOpacity = 0; textOpacity = 0; macOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onComplete() }
        }
    }
}

// MARK: - Logo Mark (real Logo asset, used everywhere)
struct S8KLogoMark: View {
    let size: CGFloat
    var showGlow: Bool = false

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Login View
struct LoginView: View {
    @StateObject private var auth  = AuthService.shared
    @StateObject private var theme = AppTheme.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var loc   = LocalizationManager.shared

    @State private var loginMode    = LoginMode.xtream
    @State private var username     = ""
    @State private var password     = ""
    @State private var advancedURL  = ""
    @State private var m3uURL       = ""
    @State private var showPrivacy  = false
    @State private var showTerms    = false
    @State private var logoFloat    = false
    @State private var shimmer      = false
    @State private var appear       = false

    /// Decide whether the value typed in the Server-URL field is a literal server
    /// URL or a bare reseller code. Owner's rule: anything with URL punctuation —
    /// a scheme ("://"), a host dot, a port colon, or a path slash — is a URL; a
    /// bare alphanumeric token (e.g. "strong", "100") is a reseller code. The
    /// charset guard also stops a stray value with spaces/odd characters from
    /// being sent to /resolve (it falls through to the URL path instead).
    private func looksLikeResellerCode(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.contains("://") || t.contains(".") || t.contains(":") || t.contains("/") { return false }
        return t.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            // Deep black base
            Color.s8kBlack.ignoresSafeArea()

            // Layered ambient gold glows for depth
            RadialGradient(colors: [Color.s8kGoldMid.opacity(0.10), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldDeep.opacity(0.06), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ===== Add-Subscription sheet header =====
                    VStack(spacing: 12) {
                        BrandLogo(size: 74)
                            .offset(y: logoFloat ? -5 : 0)
                            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true),
                                       value: logoFloat)
                            .onAppear { logoFloat = true }

                        Text(L("subs.add"))
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(.s8kTextPrimary)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(S8KGradient.goldFlat)
                            .frame(width: 46, height: 4)
                            .shadow(color: .s8kGoldHigh.opacity(0.55), radius: 5)
                    }
                    .padding(.top, 34)
                    .padding(.bottom, 26)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 14)

                    // ===== Form Card =====
                    VStack(spacing: 14) {
                        // Login type switcher: Xtream Codes / M3U
                        modeSwitcher

                        if loginMode == .xtream {
                            // Server URL is now a FIRST-CLASS field, shown first (it was
                            // buried under a gray "Advanced Options" disclosure, so new
                            // users couldn't find where to enter it). Reseller-code
                            // customers get the host injected automatically → hidden.
                            if Store.shared.resellerHost?.isEmpty != false {
                                S8KTextField(placeholder: L("login.server_or_code"), icon: "server.rack", text: $advancedURL, ltr: true,
                                             keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
                                Text(L("login.server_hint"))
                                    .font(S8KFont.caption2)
                                    .foregroundColor(.s8kGoldMid.opacity(0.8))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            S8KTextField(placeholder: L("login.username"), icon: "person.fill", text: $username, ltr: true,
                                         contentType: .username, disableAutocorrect: true, capitalization: .never)
                            S8KTextField(placeholder: L("login.password"), icon: "lock.fill", text: $password, isSecure: true,
                                         disableAutocorrect: true, capitalization: .never)
                        } else {
                            S8KTextField(placeholder: "http://server.com/playlist.m3u",
                                         icon: "link", text: $m3uURL, ltr: true,
                                         keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
                            Text(L("login.m3u_hint"))
                                .font(S8KFont.caption2)
                                .foregroundColor(.s8kTextDisabled)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if let err = auth.error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                                Text(err.errorDescription ?? L("common.error")).font(S8KFont.caption1)
                            }
                            .foregroundColor(.s8kRed)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .background(Color.s8kRed.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                            .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                .strokeBorder(Color.s8kRed.opacity(0.2), lineWidth: 1))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        GoldButton(title: loginMode == .xtream ? L("login.signin") : L("login.load_playlist"),
                                   icon: "play.fill",
                                   isLoading: auth.isLoading,
                                   isDisabled: loginMode == .xtream
                                       ? (username.isEmpty || password.isEmpty)
                                       : m3uURL.isEmpty) {
                            Task {
                                if loginMode == .xtream {
                                    let typed = advancedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if looksLikeResellerCode(typed) {
                                        // Bare token → resolve it as a reseller code, then log
                                        // in with the returned host + the user/pass typed. This
                                        // is the activated-device path (the dedicated code sheet
                                        // only exists on the activation gate, which an activated
                                        // device never sees).
                                        auth.error = nil
                                        auth.isLoading = true
                                        let ok = await activation.resolveCode(typed)
                                        guard ok, let host = Store.shared.resellerHost, !host.isEmpty else {
                                            auth.isLoading = false
                                            auth.error = .server(L("code.invalid"))
                                            return
                                        }
                                        // Clear the loading flag first — loginXtream early-returns
                                        // if isLoading is already true.
                                        auth.isLoading = false
                                        await auth.loginXtream(host: host, username: username, password: password)
                                    } else {
                                        // DIRECT connection. Reseller-code customers use the
                                        // injected reseller host automatically (they only type
                                        // user/pass); independent users type the server above.
                                        let host = !typed.isEmpty ? typed
                                            : (Store.shared.resellerHost ?? "")
                                        await auth.loginXtream(host: host, username: username, password: password)
                                    }
                                } else {
                                    await auth.loginM3U(urlString: m3uURL)
                                }
                            }
                        }

                    }
                    // Editorial: NO surrounding card — the fields sit open on the page
                    // (each already has its own glass surface). A structurally
                    // different login from the reference's boxed form.
                    .padding(.horizontal, 22)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    // ===== Legal (minimal — Demo / help / language live on the
                    // subscriptions gate now; the form stays focused on adding). =====
                    VStack(spacing: 6) {
                        Text(L("login.agree"))
                            .font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
                        HStack(spacing: 4) {
                            Button(L("set.privacy")) { showPrivacy = true }
                                .font(S8KFont.caption2).foregroundColor(.s8kGoldMid)
                            Text(L("login.and")).font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
                            Button(L("set.terms")) { showTerms = true }
                                .font(S8KFont.caption2).foregroundColor(.s8kGoldMid)
                        }
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 40)
                    .opacity(appear ? 1 : 0)
                }
                // Constrain + center on wide screens (iPad) so the form isn't
                // stretched edge-to-edge.
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
        }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
    }

    // Language picker — lets the user set their language before logging in.
    private var langMenu: some View {
        Menu {
            ForEach(AppLang.allCases) { l in
                Button(action: { loc.set(l) }) {
                    if loc.lang == l { Label(l.display, systemImage: "checkmark") }
                    else { Text(l.display) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 13))
                Text(loc.lang.display).font(S8KFont.caption1.weight(.semibold))
            }
            .foregroundColor(.s8kTextSecondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.06)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .padding(.top, 54).padding(.leading, 20)
    }

    // MARK: - Connection method picker (Xtream / M3U) — big selectable cards
    private var modeSwitcher: some View {
        HStack(spacing: 10) {
            methodCard(.xtream, title: "Xtream Codes", icon: "person.badge.key.fill")
            methodCard(.m3u,    title: L("login.mode_m3u"), icon: "link")
        }
    }

    private func methodCard(_ mode: LoginMode, title: String, icon: String) -> some View {
        let on = loginMode == mode
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                loginMode = mode
                auth.error = nil
            }
        }) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(on ? .s8kBlack : .s8kGoldHigh)
                    .frame(width: 46, height: 46)
                    .background(
                        Group {
                            if on { S8KGradient.goldFlat }
                            else { Color.s8kGoldHigh.opacity(0.12) }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                Text(title)
                    .font(S8KFont.subhead.weight(.heavy))
                    .foregroundColor(on ? .s8kTextPrimary : .s8kTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .fill(on ? Color.s8kGoldHigh.opacity(0.07) : Color.s8kCard))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .strokeBorder(on ? Color.s8kGoldHigh.opacity(0.6) : Color.s8kBorder,
                              lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(S8KButtonStyle())
    }
}



// MARK: - Privacy Policy View (Apple Required)
struct PrivacyView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    legalSection(L("privacy.collect.t"), L("privacy.collect.b"))
                    legalSection(L("privacy.use.t"), L("privacy.use.b"))
                    legalSection(L("privacy.share.t"), L("privacy.share.b"))
                    legalSection(L("privacy.security.t"), L("privacy.security.b"))
                    legalSection(L("privacy.rights.t"), L("privacy.rights.b"))
                    legalSection(L("privacy.content.t"), L("privacy.content.b"))
                    Text(L("privacy.updated"))
                        .font(S8KFont.caption2)
                        .foregroundColor(.s8kTextDisabled)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                .padding(20)
            }
            .background(Color.s8kBlack.ignoresSafeArea())
            .navigationTitle(L("set.privacy"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundColor(.s8kGoldMid)
                }
            }
        }
    }

    private func legalSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
            Text(body).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                .lineSpacing(4).multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(16)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

// MARK: - Terms View (Apple Required)
struct TermsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    termsSection(L("terms.accept.t"), L("terms.accept.b"))
                    termsSection(L("terms.use.t"), L("terms.use.b"))
                    termsSection(L("terms.content.t"), L("terms.content.b"))
                    termsSection(L("terms.terminate.t"), L("terms.terminate.b"))
                    termsSection(L("terms.changes.t"), L("terms.changes.b"))
                }
                .padding(20)
            }
            .background(Color.s8kBlack.ignoresSafeArea())
            .navigationTitle(L("set.terms"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundColor(.s8kGoldMid)
                }
            }
        }
    }

    private func termsSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
            Text(body).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                .lineSpacing(4).multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(16)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md).strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

// ============================================================
// BLANK TV — Multi-subscription entry gate (the NEW main gate).
// Lists the customer's saved subscriptions as elegant cards and lets them
// switch between accounts, add a new one, or browse the demo. Shown while
// NOT logged in (after logout, saved subscriptions persist). A structurally
// new entry experience — nothing like the reference single-form login.
// ============================================================
struct SubscriptionsGateView: View {
    @StateObject private var auth       = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var loc        = LocalizationManager.shared

    @State private var accounts: [SavedPlaylist] = Store.shared.savedPlaylists
    @State private var showAdd   = false
    @State private var entering: String? = nil    // id currently being entered
    @State private var appear    = false
    @State private var logoFloat = false

    var body: some View {
        ZStack {
            // Distinct backdrop — deep green base + lime/teal ambient glows.
            Color.s8kBlack.ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldHigh.opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 460).ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldMid.opacity(0.08), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 380).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    if accounts.isEmpty { emptyState } else { accountList }
                    footer
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) { langMenu }
        .onAppear {
            accounts = Store.shared.savedPlaylists
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
            logoFloat = true
        }
        // The add-form is the existing LoginView, as a dismissible sheet. On a
        // successful add it flips auth.loggedIn → the whole gate unmounts.
        .sheet(isPresented: $showAdd, onDismiss: { accounts = Store.shared.savedPlaylists }) {
            LoginView()
        }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 14) {
            BrandLogo(size: 84)
                .offset(y: logoFloat ? -5 : 0)
                .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: logoFloat)
            S8KWordmark(size: 26)
            RoundedRectangle(cornerRadius: 2)
                .fill(S8KGradient.goldFlat)
                .frame(width: 48, height: 4)
                .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 5)
        }
        .padding(.top, 56).padding(.bottom, 30)
        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 12)
    }

    // MARK: Account list
    private var accountList: some View {
        VStack(alignment: .trailing, spacing: 14) {
            HStack {
                Text(L("subs.title")).font(.system(size: 22, weight: .black)).foregroundColor(.s8kTextPrimary)
                Spacer()
                Text("\(accounts.count)")
                    .font(S8KFont.caption2.weight(.bold)).foregroundColor(.s8kGoldHigh)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.s8kGoldHigh.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 4)

            ForEach(accounts) { acc in accountCard(acc) }
            addCard
        }
        .padding(.horizontal, 22)
        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 18)
    }

    private func accountCard(_ acc: SavedPlaylist) -> some View {
        let isActive   = acc.id == Store.shared.activePlaylistID
        let isEntering = entering == acc.id
        let isXtream   = acc.kind == .xtream
        return Button(action: { enter(acc) }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .fill(S8KGradient.goldFlat)
                        .frame(width: 52, height: 52)
                        .shadow(color: .s8kGoldMid.opacity(0.4), radius: 8, y: 3)
                    Image(systemName: isXtream ? "person.badge.key.fill" : "link")
                        .font(.system(size: 20, weight: .bold)).foregroundColor(.s8kBlack)
                }
                VStack(alignment: .trailing, spacing: 3) {
                    Text(acc.name).font(S8KFont.title3).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    Text(acc.subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                if isEntering {
                    ProgressView().tint(.s8kGoldHigh)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundColor(.s8kGoldHigh)
                } else {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundColor(.s8kTextTertiary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).fill(Color.s8kCard))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .strokeBorder(isActive ? Color.s8kGoldHigh.opacity(0.5) : Color.s8kBorder,
                              lineWidth: isActive ? 1.5 : 1))
        }
        .buttonStyle(S8KButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                Task { await auth.deletePlaylist(acc.id); accounts = Store.shared.savedPlaylists }
            } label: { Label(L("common.delete"), systemImage: "trash") }
        }
    }

    private var addCard: some View {
        Button(action: { showAdd = true }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.s8kGoldMid.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundColor(.s8kGoldHigh)
                }
                Text(L("subs.add")).font(S8KFont.headline).foregroundColor(.s8kGoldHigh)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    // MARK: Empty state (first run)
    private var emptyState: some View {
        VStack(spacing: 22) {
            Text(L("subs.welcome")).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
            Text(L("login.welcome")).font(S8KFont.subhead).foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center)
            GoldButton(title: L("subs.add_first"), icon: "plus") { showAdd = true }
        }
        .padding(.horizontal, 30).padding(.top, 16)
        .opacity(appear ? 1 : 0)
    }

    // MARK: Footer — demo + help
    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: { auth.enterDemo() }) {
                HStack(spacing: 7) {
                    Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 13))
                    Text(L("login.demo")).font(S8KFont.callout.weight(.semibold))
                }
                .foregroundColor(.s8kTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())

            if let support = activation.supportURL, let u = URL(string: support) {
                Button(action: { UIApplication.shared.open(u) }) {
                    Text(L("login.need_help")).font(S8KFont.caption1.weight(.semibold))
                        .foregroundColor(.s8kGoldMid)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(S8KButtonStyle())
            }
        }
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 44)
        .opacity(appear ? 1 : 0)
    }

    private var langMenu: some View {
        Menu {
            ForEach(AppLang.allCases) { l in
                Button(action: { loc.set(l) }) {
                    if loc.lang == l { Label(l.display, systemImage: "checkmark") } else { Text(l.display) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 13))
                Text(loc.lang.display).font(S8KFont.caption1.weight(.semibold))
            }
            .foregroundColor(.s8kTextSecondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.06)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .padding(.top, 54).padding(.leading, 20)
    }

    private func enter(_ acc: SavedPlaylist) {
        guard entering == nil else { return }
        entering = acc.id
        Task {
            await auth.switchPlaylist(acc)
            auth.loggedIn = true     // enter the app with the chosen subscription
            entering = nil
        }
    }
}
