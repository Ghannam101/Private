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

                    // ===== Logo Block =====
                    VStack(spacing: 18) {
                        // Clean logo — no halo, no ring (charcoal identity)
                        BrandLogo(size: 128)
                            .offset(y: logoFloat ? -6 : 0)
                            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true),
                                       value: logoFloat)
                            .onAppear { logoFloat = true }

                        VStack(spacing: 8) {
                            S8KWordmark(size: 27)

                            // Gold divider with center dot
                            HStack(spacing: 8) {
                                Rectangle().fill(LinearGradient(
                                    colors: [.clear, Color.s8kGoldDeep.opacity(0.6)],
                                    startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 50, height: 1)
                                Circle().fill(Color.s8kGoldHigh).frame(width: 4, height: 4)
                                Rectangle().fill(LinearGradient(
                                    colors: [Color.s8kGoldDeep.opacity(0.6), .clear],
                                    startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 50, height: 1)
                            }

                            Text(L("login.welcome"))
                                .font(S8KFont.footnote)
                                .foregroundColor(.s8kTextTertiary)
                        }
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 46)
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
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.s8kSurface.opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(LinearGradient(
                                    colors: [Color.s8kGoldDeep.opacity(0.35), Color.s8kBorder.opacity(0.2)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    )
                    .padding(.horizontal, 22)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    // ===== Demo Mode (App Review, Guideline 2.1) =====
                    Button(action: { auth.enterDemo() }) {
                        HStack(spacing: 7) {
                            Image(systemName: "play.rectangle.on.rectangle")
                                .font(.system(size: 13))
                            Text(L("login.demo"))
                                .font(S8KFont.callout.weight(.semibold))
                        }
                        .foregroundColor(.s8kTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                            .strokeBorder(Color.s8kBorder, lineWidth: 1))
                    }
                    .buttonStyle(S8KButtonStyle())
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .opacity(appear ? 1 : 0)

                    // ===== Activation help (compliant CONTACT link, no prices) =====
                    if let support = activation.supportURL, let u = URL(string: support) {
                        Button(action: { UIApplication.shared.open(u) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 13))
                                Text(L("login.need_help"))
                                    .font(S8KFont.caption1.weight(.semibold))
                            }
                            .foregroundColor(.s8kGoldMid)
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(S8KButtonStyle())
                        .padding(.horizontal, 22)
                        .padding(.top, 6)
                        .opacity(appear ? 1 : 0)
                    }

                    // ===== Legal =====
                    VStack(spacing: 8) {
                        // Player-only disclaimer (App Store 4.3 / legal) — shown
                        // here too so it appears regardless of entry screen.
                        Text(S8KLegal.disclaimer)
                            .font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22).padding(.bottom, 4)
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
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                    .opacity(appear ? 1 : 0)
                }
                // Constrain + center on wide screens (iPad) so the form isn't
                // stretched edge-to-edge.
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) { langMenu }
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

    // MARK: - Login Mode Switcher (Xtream / M3U)
    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeTab(.xtream, title: "Xtream Codes", icon: "person.badge.key.fill")
            modeTab(.m3u,    title: L("login.mode_m3u"),     icon: "link")
        }
        .padding(4)
        .background(Color.s8kBlack.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }

    private func modeTab(_ mode: LoginMode, title: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                loginMode = mode
                auth.error = nil
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(S8KFont.caption1.weight(.bold))
            }
            .foregroundColor(loginMode == mode ? .black : .s8kTextTertiary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                Group {
                    if loginMode == mode {
                        LinearGradient(colors: [.s8kGoldHigh, .s8kGoldMid],
                                       startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
            .shadow(color: loginMode == mode ? .s8kGoldMid.opacity(0.35) : .clear, radius: 6, y: 2)
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
