// ============================================================
// BLANK TV — AuthViews.swift
// Splash + Login + Privacy + Terms
// iOS 17+ • Apple HIG Compliant
// ============================================================

import SwiftUI

// MARK: - Splash Screen
struct SplashView: View {
    let onComplete: () -> Void

    /// One named size the rest of the composition is derived from, so there is a
    /// single place to retune it and no bare literals scattered through the layout.
    private let markSize: CGFloat = 56

    // No scale anywhere. Fading in from 0.88 is the most-copied splash gesture there
    // is; a short rise reads as deliberate instead.
    @State private var enter:  Double  = 0     // ONE timeline for everything that fades
    @State private var rise:   CGFloat = 14
    @State private var drawn:  CGFloat = 0     // the rule, 0...1

    /// The brand lockup sits on the reading edge, so it lands where the eye already is
    /// in each language rather than dead centre.
    private var edge: Alignment { s8kFrameAlign }

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()

            VStack(alignment: s8kTextAlign, spacing: S8KSpace.xl) {
                // Two above, one below: the lockup settles about two thirds down on
                // ANY height. The first version pinned it 96pt off the bottom, which
                // put it in the corner of an 83%-empty iPad — a screen App Review sees.
                Spacer(minLength: 0)
                Spacer(minLength: 0)

                lockup
                rule

                Spacer(minLength: 0)
                deviceLine
            }
            .padding(.horizontal, S8KSpace.xxl)
            .padding(.bottom, S8KSpace.xxl)
        }
        .onAppear { startAnimation() }
        // Resolve activation WHILE the splash is showing, so by the time it ends the
        // gate is already decided — no separate "checking" flash afterwards.
        .task { if !Store.shared.demoMode { await ActivationService.shared.check() } }
    }

    /// HORIZONTAL lockup — mark beside the wordmark, not stacked above it.
    private var lockup: some View {
        HStack(spacing: S8KSpace.md) {
            // Mirrored for RTL. Without this the mark stayed to the LEFT of the
            // wordmark in Arabic, which is the app's default language.
            if s8kIsRTL {
                wordmarkBlock
                BrandLogo(size: markSize)
            } else {
                BrandLogo(size: markSize)
                wordmarkBlock
            }
        }
        // The bloom rides WITH the lockup instead of being centred on the screen, so
        // it actually sits behind the mark on every width. No blur: blurring a radial
        // ramp yields the same radial ramp and costs a full offscreen pass on the
        // coldest frame in the app.
        .background(
            RadialGradient(colors: [Color.s8kGoldHigh.opacity(0.18), .clear],
                           center: .center, startRadius: 0, endRadius: markSize * 3.4)
                .frame(width: markSize * 6.8, height: markSize * 6.8)
                .opacity(enter)
                .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, alignment: edge)
        .opacity(enter)
        .offset(y: rise)
    }

    private var wordmarkBlock: some View {
        VStack(alignment: s8kTextAlign, spacing: 2) {
            S8KWordmark(size: 30)
            Text(L("splash.tagline"))
                .font(S8KFont.footnote)
                .foregroundColor(.s8kTextSecondary)
                // Tracking is Latin-only. Letter-spacing a cursive script pulls its
                // joined glyphs apart and reads as broken text.
                .tracking(s8kIsRTL ? 0 : 1.2)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    /// A rule that draws itself, in place of a circular ProgressView — the same
    /// "something is happening" signal without the system control every app shares.
    private var rule: some View {
        ZStack(alignment: edge) {
            Capsule().fill(Color.white.opacity(0.08))
            Capsule().fill(S8KGradient.goldFlat)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: drawn, y: 1, anchor: s8kIsRTL ? .trailing : .leading)
        }
        .frame(height: 2)
        .frame(maxWidth: markSize * 4, alignment: edge)
        .frame(maxWidth: .infinity, alignment: edge)
        .opacity(enter)
    }

    /// The device id stays visible and LABELLED: the owner panel activates this exact
    /// string and support reads it back. The first rewrite dropped it to 20% white at
    /// 11pt — about 1.8:1 against the brand base, well under the 4.5:1 floor — and put
    /// it on its own fade that reversed halfway. One timeline, readable weight.
    private var deviceLine: some View {
        VStack(alignment: s8kTextAlign, spacing: 3) {
            Text(L("splash.device_id"))
                .font(S8KFont.caption2)
                .foregroundColor(.s8kTextTertiary)
            Text(DeviceIdentity.current)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.s8kTextSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: edge)
        .opacity(enter)
    }

    private func startAnimation() {
        withAnimation(.easeOut(duration: 0.5)) { enter = 1; rise = 0 }
        // Finishes at 0.42, BEFORE the fade-out starts at 0.50. The first version ran
        // 0.62s from a 0.06 delay, so the bar only ever reached full as it vanished.
        withAnimation(.easeInOut(duration: 0.42)) { drawn = 1 }
        // Timing unchanged from what shipped: ~0.75s to onComplete. The app now loads
        // the catalogue during this window (BlankTVApp), so the beat is no longer dead
        // time, and shortening it is a separate decision that belongs to the owner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.32)) { enter = 0; rise = -10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onComplete() }
        }
    }
}

// MARK: - Login View
struct LoginView: View {
    @Environment(\.s8kMetrics) private var metrics
    @StateObject private var auth  = AuthService.shared
    @StateObject private var theme = AppTheme.shared
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
    /// bare alphanumeric token (e.g. "demo", "100") is a reseller code. The
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
                                         keyboard: .asciiCapable,
                                         contentType: .username, disableAutocorrect: true, capitalization: .never)
                            // `ltr: true` + `.password` were missing: the field laid out
                            // right-to-left unlike its sibling, and without a paired
                            // .password content type iOS Password AutoFill never engages.
                            S8KTextField(placeholder: L("login.password"), icon: "lock.fill", text: $password, isSecure: true,
                                         ltr: true, keyboard: .asciiCapable, contentType: .password,
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
                                    // A bare token was sent to resolveCode, which returns false
                                    // unconditionally — the user always got "invalid code" for a
                                    // feature the binary cannot deliver. Say what the field wants.
                                    if looksLikeResellerCode(typed) {
                                        auth.error = .server(L("login.need_url"))
                                        return
                                    }
                                    // DIRECT connection. A reseller host injected by remote
                                    // branding is still used when the field is left empty.
                                    let host = !typed.isEmpty ? typed
                                        : (Store.shared.resellerHost ?? "")
                                    await auth.loginXtream(host: host, username: username, password: password)
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
                .frame(maxWidth: metrics.formMaxWidth)
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
        .padding(.top, metrics.safeTop).padding(.leading, 20)
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

// MARK: - Third-party licences
// Three libraries ship inside this binary and none of them was acknowledged anywhere in
// the app. That is a licence breach before it is an App Store problem: MIT requires the
// copyright notice and the permission text to travel with every copy, and LGPL v2.1
// requires the user to be TOLD the library is there and to be able to reach its source.
// Guideline 5.2.1 asks for the rights to everything you ship; these are the rights, shown.
//
// Every copyright line below was fetched from the project's own repository, not recalled:
// Evan Wallace 2023 and Gwendal Roué 2015-2025 both via the GitHub licence API. VideoLAN's
// own host sits behind a challenge page, so VLCKit carries the licence NAME and the source
// URL rather than a copyright year invented to fill the gap.
struct LicensesView: View {
    @Environment(\.dismiss) var dismiss

    private static let mit = """
    Permission is hereby granted, free of charge, to any person obtaining a copy of this \
    software and associated documentation files (the "Software"), to deal in the Software \
    without restriction, including without limitation the rights to use, copy, modify, \
    merge, publish, distribute, sublicense, and/or sell copies of the Software, and to \
    permit persons to whom the Software is furnished to do so, subject to the following \
    conditions:

    The above copyright notice and this permission notice shall be included in all copies \
    or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, \
    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A \
    PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT \
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
    CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE \
    OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Text(L("licenses.intro"))
                        .font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                        .lineSpacing(4).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, 2)

                    entry("MobileVLCKit",
                          "GNU Lesser General Public License, version 2.1",
                          L("licenses.vlc"),
                          "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html",
                          "https://code.videolan.org/videolan/VLCKit")

                    entry("GRDB.swift",
                          "MIT License · Copyright (C) 2015-2025 Gwendal Roué",
                          Self.mit, nil, "https://github.com/groue/GRDB.swift")

                    entry("ThumbHash",
                          "MIT License · Copyright (c) 2023 Evan Wallace",
                          Self.mit, nil, "https://github.com/evanw/thumbhash")
                }
                .padding(20)
            }
            .background(Color.s8kBlack.ignoresSafeArea())
            .navigationTitle(L("set.licenses"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundColor(.s8kGoldMid)
                }
            }
        }
    }

    /// One library: its name, its licence line, the licence body, and the links that make
    /// the LGPL obligation reachable rather than merely mentioned.
    private func entry(_ name: String, _ licence: String, _ body: String,
                       _ licenceURL: String?, _ sourceURL: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
            Text(licence).font(S8KFont.caption2).foregroundColor(.s8kGoldMid)
            Text(body).font(S8KFont.caption2).foregroundColor(.s8kTextSecondary)
                .lineSpacing(3).multilineTextAlignment(.leading)
            HStack(spacing: 14) {
                if let l = licenceURL, let u = URL(string: l) {
                    Link(L("licenses.text"), destination: u)
                }
                if let u = URL(string: sourceURL) {
                    Link(L("licenses.source"), destination: u)
                }
            }
            .font(S8KFont.caption2.weight(.semibold))
            .foregroundColor(.s8kGoldMid)
            .padding(.top, 2)
        }
        // Latin licence text stays left-aligned even under an Arabic UI: a paragraph of
        // English right-aligned is unreadable, and the wording is legally fixed anyway.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    termsSection(L("terms.accept.t"), String(format: L("terms.accept.b"), S8KBrand.name))
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
    @Environment(\.s8kMetrics) private var metrics
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
                .frame(maxWidth: metrics.formMaxWidth)
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
        .padding(.top, metrics.safeTop + S8KSpace.md).padding(.bottom, 30)
        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 12)
    }

    // MARK: Account list
    private var accountList: some View {
        VStack(alignment: .trailing, spacing: 14) {
            HStack {
                Text(L("subs.title")).font(S8KFont.title2.weight(.black)).foregroundColor(.s8kTextPrimary)
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
                        .font(.system(size: 20, weight: .bold)).foregroundColor(S8KBrand.accentInk)
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
            Text(String(format: L("subs.welcome"), S8KBrand.name)).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
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

            if let u = S8KBrand.supportURL {
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
        .padding(.top, metrics.safeTop).padding(.leading, 20)
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
