# زمن أول إطار (TTFF) — تشريح المراحل ومهاجمة كلٍّ منها بالدليل
**بحث هندسي مستقل · 2026-07-29 · Blank Prime (SwiftUI · iOS 17.0 كحدّ أدنى · MobileVLCKit + AVPlayer)**

> **هدف المالك بكلماته:** المستخدم يلمس قناةً أو فيلماً أو حلقة فتبدأ **فوراً**.
> هذا الملف يفكّك «فوراً» إلى مراحل قابلة للقياس، ويهاجم كلّ مرحلة بدليل، **ويقول بصراحة أين يقف
> الحدّ الفيزيائي** بدل أن يَعِد بكسره.

> **علاقته بما سبق:** `TECH_ADJUDICATION.md` (ثمانية بنود) و`TECH_HUNT_V2.md` (عشرة بنود) **لا
> يُعاد أيٌّ منهما هنا**. تحديداً: `:clock-synchro=0` **مرفوض** ولا نعود إليه؛ `:clock-jitter=0`
> **محسوم لصالح VOD وحده** وهذا الملف **يبني عليه** ولا يعيد تحكيمه؛ `automaticallyWaitsToMinimizeStalling`
> **محسوم بالتراجع الموثَّق** (`edd3d82`) ولا يُمَسّ.

---

## 0. جدول الترتيب — الفائدة الملموسة ÷ الخطر

| # | البند | المرحلة | الفائدة الملموسة | الخطر | جهد | بناء مخصّص؟ |
|---|-------|---------|------------------|-------|-----|-------------|
| **1** | **ملصق/خلفية تحت الفيديو حتى أول إطار حقيقي** | الإدراك | **الأعلى في التقرير** — يحذف الشاشة السوداء كلّها | شبه صفر | 2–3 س | لا (يُدمج) |
| **2** | `:clock-jitter=0` لـ VOD (مُقرّ سلفاً، لم يُشحن) | VLC demux | عالية — حتى **5000 مل.ث** موثَّقة من مصدر VLC | منخفض | 20 د | لا (يُدمج) |
| **3** | ترقية `MobileVLCKit` إلى 3.7.3 (مُقرّ سلفاً، لم يُشحن) | VLC demux | متوسطة–عالية — 100% من VOD يمرّ بهذا المُفكِّك | **متوسط** | 30 د | **نعم + قائمة فحص** |
| **4** | **قياس** الـ redirect ثم (إن ثبت) إعادة كتابة المضيف المحلولة | حلّ الرابط | غير معروفة حتى تُقاس — **قد تكون RTT كاملة مضاعفة** | القياس: صفر · التنفيذ: متوسط | 1 س + 4 س | **نعم** |
| **5** | `startsOnFirstEligibleVariant = true` للمباشر HLS | AVPlayer | متوسطة | منخفض–متوسط | 15 د | لا (يُدمج) |
| **6** | تجربة `.ts` بدل `.m3u8` للقنوات المباشرة | حلّ الرابط | **قد تكون عالية جداً** | **متوسط–عالٍ** (يخسر AVPlayer/PiP) | 3 س | **نعم** |
| **7** | تنظيفان بلا خطر: `:http-reconnect` المكرّر · `playImmediately(atRate: self.rate)` | كلاهما | صفر أداءً، وضوح صيانة | صفر | 10 د | لا |
| **—** | **لا تفعل** (قائمة §7): `--no-lua`, `:demux=`, `:avcodec-hw`, `preroll`, `PreferPreciseDuration`, `automaticallyWaits=false` | — | — | — | — | — |

**السطر الواحد:** أرخص مكسبٍ في هذا الملف **ليس في الشبكة إطلاقاً** — إنه أن نتوقّف عن عرض
مستطيل أسود بينما البايتات في الطريق. وأغلى مكسبٍ حقيقيّ في الشبكة (البند 2) **مُقرٌّ منذ تقرير سابق
ولم يُشحن بعد**. أمّا الـ redirect فلا أعرف — ولن أدّعي — حتى يُقاس على لوحة المالك.

---

## 0.1 تحذير عن المصادر — اقرأه قبل أن تثق بسطر

- **ميزانية `WebSearch` نفدت في هذه الجلسة (200/200) قبل أن أُجري بحثاً نصّياً واحداً.** كل ادّعاء
  خارجي أدناه مأخوذ **مباشرةً من مصدر أوّليّ** عبر جلب الملف الخام: شيفرة `videolan/vlc` فرع `3.0.x`،
  وشيفرة `videolan/VLCKit` فرع `3.0` (بما فيها سكربت البناء)، وشيفرة `androidx/media`، وشيفرة
  `mpv-player/mpv`، وشيفرة `kingslay/KSPlayer`، وواجهة توثيق Apple بصيغة JSON. **لا مدوّنات ولا
  ملخّصات.**
- **كل ادّعاء عن شيفرتنا متحقَّق منه بالقراءة المباشرة ومعه `file:line`.**
- حيث لم أجد مصدراً أوّلياً أقول **«غير متحقَّق منه»** صراحةً. وهناك ثلاث نتائج سلبية مؤكَّدة في هذا
  الملف — وهي أنفع من نصف توصياته.
- **الفريق لا يترجم محلّياً.** كل شيفرة مقترحة أدناه مكتوبة كاملة، ولا تستعمل أي API فوق `iOS 17.0`
  إلا مسيَّجة بـ`if #available`.

---

## 0.2 الأرضية الفيزيائية — ما لا يمكن كسره، بالأرقام

قبل أي توصية، هذا هو ما **يجب** دفعه على وصلة خلوية نموذجية (RTT ≈ 60 مل.ث) قبل أن يصل بايت وسائط واحد:

| الخطوة | الكلفة | هل نتحكّم؟ |
|---|---|---|
| استعلام DNS | 0 مل.ث إن كان مخزَّناً، وإلا 20–120 مل.ث | **جزئياً** — كاش النظام مشترك (انظر §1.3) |
| مصافحة TCP | 1 × RTT ≈ 60 مل.ث | لا |
| مصافحة TLS 1.3 | 1 × RTT ≈ 60 مل.ث (0-RTT غير متاح لنا) | لا |
| طلب HTTP + أول بايت (TTFB) | 1 × RTT + زمن الخادم ≈ 60–400 مل.ث | لا |
| **المجموع قبل أي بايت وسائط** | **≈ 200–650 مل.ث** | — |
| **+ redirect إلى مضيف آخر** | **يضاعف الأربعة أعلاه تقريباً** (DNS+TCP+TLS+TTFB جديدة) | **نعم — البند 4** |
| قراءة الترويسة/الفهرس (MKV: رحلتان إضافيتان) | 2 × (RTT + TTFB) ≈ 150–800 مل.ث | **لا** (بنية الملف) |
| أول GOP + فكّ شفرة VideoToolbox | 10–40 مل.ث للإطار | لا |

> **الأرضية الصادقة:**
> **قناة HLS مباشرة ≈ 0.4–0.8 ثانية.**
> **فيلم `.mkv` بعيد ≈ 1.0–2.0 ثانية** (لأن الفهرس عند ذيل الملف — البرهان في §2.4).
> **أي وعد بأقل من ذلك على شبكة حقيقية كذبٌ هندسي.**
>
> وما **نستطيع** مهاجمته هو كل ما فوق الأرضية: رحلة الـ redirect، وتضخّم مخزن VLC حتى **خمس ثوانٍ**،
> ولحظات السواد التي لا علاقة لها بالبايتات أصلاً.

---

# المرحلة 1 — حلّ الرابط (URL RESOLUTION)

## 1.1 ما يحدث اليوم، سطراً بسطر

الرابط يُبنى **نصّياً بالكامل** ولا يلمس الشبكة إطلاقاً:

```swift
// BlankTV/Core.swift:1600–1602  (XtreamDirect — المسار المباشر)
func liveURL(id: String)                -> String { "\(base)/live/\(user)/\(pass)/\(id).m3u8" }
func movieURL(id: String, ext: String)  -> String { "\(base)/movie/\(user)/\(pass)/\(id).\(ext)" }
func seriesURL(id: String, ext: String) -> String { "\(base)/series/\(user)/\(pass)/\(id).\(ext)" }
```
```swift
// BlankTV/Core.swift:1291–1302  (XtreamService — مسار الاعتمادات من الـ Keychain)
nonisolated func vodURL(id: String, ext: String) -> URL? {
    guard let c = Keychain.shared.serverCredentials() else { return nil }
    return URL(string: "\(c.host)/movie/\(c.user)/\(c.pass)/\(id).\(ext)")
}
```

ثم `BasePlayerVM.resolvedURL` (`BlankTV/PlayerEngine.swift:169–178`):

```swift
static func resolvedURL(for item: ContentItem) -> URL? {
    switch item {
    case .movie(let m):
        if let local = DownloadService.completedFileURL(forContentID: m.id) { return local }
    case .episode(let ep, _):
        if let local = DownloadService.completedFileURL(forContentID: ep.id) { return local }
    case .live: break
    }
    return remoteURL(for: item)
}
```

> 🔴 **اسم الدالّة يَعِد بما لا تفعله.** `resolvedURL` **لا تحلّ شيئاً شبكياً**: هي فحص ملفٍ محلّي ثم
> بناء نصّ. لا استعلام DNS، ولا `HEAD`، ولا اتّباع `Location`. الرابط يُسلَّم كما هو إلى المحرّك:
> - **VLC:** `VLCPlayer.swift:300` → `player.media = makeMedia(url)`
> - **AVPlayer:** `PlayerEngine.swift:333–341` → `AVURLAsset(url:options:)` ثم `replaceCurrentItem`

## 1.2 هل ندفع رحلة redirect وقت التشغيل؟ — نعم إن كانت اللوحة تُعيد التوجيه، وبثمنٍ **أعلى** على VLC

من شيفرة VLC الأصلية، `modules/access/http.c`:

```c
if( ( p_sys->i_code == 301 || p_sys->i_code == 302 ||
      p_sys->i_code == 303 || p_sys->i_code == 307 ) &&
    p_sys->psz_location != NULL )
{
    p_access->psz_url = p_sys->psz_location;
    p_sys->psz_location = NULL;
    ret = VLC_ACCESS_REDIRECT;
    goto disconnect;                 // ← لاحظ: قطعُ الاتصال، لا متابعةٌ عليه
}
```

> **الترجمة الهندسية:** وحدة `http` في libvlc **لا تتابع** الـ redirect على نفس الاتصال. تُعيد
> `VLC_ACCESS_REDIRECT` إلى النواة **وتقطع الاتصال** (`goto disconnect`). النواة تفتح وصولاً جديداً
> على الرابط الجديد — أي **DNS + TCP + TLS + TTFB من الصفر** على المضيف الجديد. هذه ليست
> «رحلة إضافية»؛ هذه **دورة اتصال كاملة إضافية**.
>
> و**AVPlayer** يتّبع الـ redirect داخل مكدّس CFNetwork بلا أي تحكّم منّا، وكلفته أقلّ نظرياً (قد يعيد
> استعمال الاتصال إن كان الـ redirect على نفس المضيف) — لكنّ الحالة الشائعة في لوحات Xtream هي
> **مضيف مختلف** (موازن أحمال)، وعندها لا فرق: اتصال جديد كاملاً.

⚠ **«لوحات Xtream تُعيد التوجيه غالباً» — هذا الادّعاء نفسه غير متحقَّق منه لدينا.** لم أستطع
اختبار لوحة المالك (لا وصول شبكي، وميزانية البحث نفدت). **ولهذا البند 4 في الجدول هو "قِس أولاً"،
لا "نفّذ".**

## 1.3 هل يوجد اتصال دافئ من جلب الكتالوج؟ وهل يعيد أيّ محرّك استعماله؟

**ثلاثة مكدّسات شبكة منفصلة تماماً في هذا التطبيق:**

| المكدّس | من يستعمله | الشيفرة |
|---|---|---|
| `URLSession.shared` | جلب الكتالوج والـ EPG والمصادقة | `Core.swift:2012`, `:2083`, `:1871` |
| `vlc_tls` (مقبس خاصّ داخل libvlc) | **كل VOD وكل قناة TS** | `modules/access/http.c` (مصدر VLC) |
| مكدّس AVFoundation (CFNetwork داخل خدمة الوسائط) | HLS على `AVPlayer` | `AVURLAsset` |

- **مجمّع اتصالات مشترك؟ لا — وهذا مؤكَّد لـ libvlc:** وحدة `access/http` تفتح مقبسها بنفسها ولا
  تعرف بوجود `URLSession` أصلاً. **لا إعادة استعمال، ولا استئناف جلسة TLS، صفر.**
- **بالنسبة لـ AVFoundation:** **غير متحقَّق منه نصّاً من Apple.** لا توجد أي واجهة تسمح بتمرير
  `URLSession` إلى `AVURLAsset` (الاعتراض الوحيد المتاح هو `AVAssetResourceLoader`)، وهذا **قرينة
  قوية** على مكدّس منفصل — لكنّي لا أرفعها إلى مرتبة الحقيقة الموثَّقة.
- ✅ **الشيء الوحيد المشترك فعلاً — وهو مجّانيّ وننتفع به اليوم بلا أن ندري: كاش DNS الخاص بالنظام
  (`mDNSResponder`) على مستوى الجهاز كلّه.** جلب الكتالوج من `player_api.php` يسخّن سجلّ DNS لنفس
  المضيف، فلا يدفعه المشغّل بعده (ما دام ضمن TTL). **أي أن سطر DNS في جدول §0.2 يساوي صفراً عندنا في
  الحالة الشائعة.** لا عمل مطلوب — فقط لا تكسره بتغيير المضيف عشوائياً.

## 1.4 المقترح — بمرحلتين، والأولى **قياس لا شيفرة**

### المرحلة (أ) — قِس. ساعة عمل، خطر صفر.

لا تكتب سطر إنتاج واحداً قبل أن تعرف الجواب. أضِف تشخيصاً مؤقّتاً في لوحة `EngineStatsView`
(`SettingsView.swift:532`) يُظهر، لآخر عنصر شُغِّل: الرابط الأصلي، والرابط النهائي بعد اتّباع
التوجيه، وزمن الرحلة.

```swift
// BlankTV/StreamRouter.swift — أضِفه إلى نفس الملف (لا تُنشئ ملفاً جديداً: إضافة ملف
// إلى المشروع تتطلّب تعديل pbxproj، وهو خطر لا يستحقّه تشخيص مؤقّت).
enum StreamURLProbe {
    /// يتّبع الـ redirect مرّة واحدة ويعيد (الرابط النهائي، زمن الرحلة بالثواني).
    /// `URLSession` يتّبع 3xx تلقائياً، و`response.url` هو الرابط بعد الاتّباع.
    static func probe(_ url: URL) async -> (final: URL, seconds: Double)? {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"                    // HEAD لا GET: لا نريد فتح بثّ
        req.timeoutInterval = 6
        req.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        let t0 = Date()
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (resp.url ?? url, Date().timeIntervalSince(t0))
    }
}
```

**اقرأ الرقم على جهاز حقيقي على لوحة المالك:**
- إن كان `final.host == url.host` ⇒ **لا يوجد redirect. أغلق البند 4 نهائياً** ووفّر أربع ساعات.
- إن اختلف المضيف ⇒ المكسب المحتمل ≈ زمن دورة اتصال كاملة (200–650 مل.ث حسب §0.2)، **وعندها فقط**
  انتقل إلى (ب).

### المرحلة (ب) — إعادة كتابة المضيف، بقاعدة واحدة صارمة

**لا تخزّن رابطاً محلولاً لكل عنصر.** خزّن **تحويل مضيف واحد لكل جلسة**، وتعلّمه من أول فحص:

```swift
// BlankTV/StreamRouter.swift
enum StreamHostMap {
    private static let lock = NSLock()
    private static var map: [String: (host: String, at: Date)] = [:]   // originHost → resolvedHost
    private static let ttl: TimeInterval = 30 * 60

    /// يُطبَّق فقط حين يكون الـ redirect قد غيّر **المضيف/المنفذ ولا شيء غير ذلك**.
    /// لو غيّر المسار أو أضاف استعلاماً، فالرابط الجديد على الأرجح **موقَّع بمهلة**
    /// (token) خاصّ بذلك البثّ وحده — وإعادة استعماله على بثٍّ آخر تُنتج 403.
    /// هذا الشرط هو كل ما يفصل هذه الميزة عن عطلٍ متقطّع لا يُشخَّص.
    static func learn(origin: URL, resolved: URL) {
        guard let oh = origin.host, let rh = resolved.host, oh != rh,
              origin.path == resolved.path, origin.query == resolved.query,
              origin.scheme == resolved.scheme else { return }
        lock.lock(); map[oh] = (rh, Date()); lock.unlock()
    }

    /// يعيد الرابط بعد استبدال المضيف إن كان لدينا تحويل طازج، وإلا يعيده كما هو.
    static func apply(_ url: URL) -> URL {
        guard let h = url.host else { return url }
        lock.lock(); let e = map[h]; lock.unlock()
        guard let e, Date().timeIntervalSince(e.at) < ttl,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.host = e.host
        return c.url ?? url
    }
}
```

ثم يُستدعى `StreamHostMap.apply(...)` في **موضع واحد فقط** — نهاية `BasePlayerVM.remoteURL`
(`PlayerEngine.swift:152–164`) — فيستفيد منه المحرّكان و`MediaPrefetcher` و`StreamRouter.classify`
معاً بلا ازدواج.

**الثمن والمخاطر — بصراحة:**

| الخطر | الوصف | التخفيف |
|---|---|---|
| **`max_connections`** | لوحات Xtream تُقنِّن الجلسات المتزامنة (1–3)، والفتحة تتحرّر بعد ~دقيقتين من الإنهاء (`RESEARCH.md:275–278`). **أي فحص مسبق قد يحرق فتحة.** | استعمل `HEAD` لا `GET`؛ **ولا تفحص أبداً على مسار المباشر**؛ افحص **مرّة واحدة لكل جلسة تطبيق** لا لكل عنصر. |
| **حظر `fail2ban`** | `>10 طلبات/10 دقائق ⇒ حظر 24 ساعة` (`RESEARCH.md:271–273`). | فحص واحد لكل جلسة، لا لكل صفحة تفاصيل. **هذا وحده يمنع الكارثة.** |
| **روابط موقّعة بمهلة** | بعض اللوحات تُعيد التوجيه إلى رابط يحمل token قصير العمر. | حارس `path == path && query == query` أعلاه يرفض هذه الحالة بنيوياً. |
| **موازن أحمال ديناميكي** | العقدة المختارة قد تتغيّر عمداً لكل طلب. | `ttl = 30 د` + التراجع الصامت (إن فشل التشغيل، فالمسار الحالي يتراجع إلى المحرّك الآخر أصلاً). |

**⚠ هذا البند يحتاج بناءً مخصّصاً وقائمة فحص جهاز، ولا يُدمج في دفعة.**

## 1.5 نقطة أخيرة في هذه المرحلة: `MediaPrefetcher` مسارٌ ميت اليوم — والفرصة فيه

بعد إصلاح `81213c0`، الحارس صحيح (`MediaPrefetcher.swift:45`):
```swift
guard StreamRouter.defaultEngine(for: item) == .av else { return }
```
لكن `StreamRouter.defaultEngine` (`StreamRouter.swift:45–49`) يعيد `.vlc` **لكل** VOD (لأن روابط
أفلام Xtream تنتهي بـ`.mkv`/`.mp4`). ⇒ **السطر `ContentViews.swift:2593` لا يفعل شيئاً على الإطلاق
في التهيئة الافتراضية.** هذا صحيح ومقصود (يوقف نزيف البيانات) — لكن **النتيجة هي أن مفهوم «التسخين»
غائب كلّياً عن مسار الأفلام والحلقات**، وهو المسار الأبطأ عندنا.

> **الفرصة:** صفحة التفاصيل هي المكان الطبيعي لتسخين **ما يمكن تسخينه فعلاً** — لا الفيديو (لا سبيل
> إليه على VLC، §2.6)، بل **حلّ الرابط** (البند 4) **والملصق الذي سيُعرض تحت الفيديو** (البند 1).
> كلاهما مجّاني نسبياً، وكلاهما يقع في نافذة الثواني التي يقضيها المستخدم على صفحة التفاصيل.

---

# المرحلة 2 — تفكيك واستكشاف VLC (DEMUX / PROBE)

هذه المرحلة تخصّ **100% من الأفلام والحلقات** في التطبيق (`StreamRouter.swift:45–49`).

## 2.1 ما نمرّره اليوم — الجرد الكامل

```swift
// BlankTV/VLCPlayer.swift:259–293
private func makeMedia(_ url: URL) -> VLCMedia {
    let media = VLCMedia(url: url)
    media.addOption(":http-user-agent=VLC/3.0.20 LibVLC/3.0.20")   // :263
    media.addOption(":http-reconnect")                              // :267
    if isLive {
        media.addOption(":network-caching=1500")                    // :272
    } else {
        media.addOption(":network-caching=1000")                    // :285
        media.addOption(":input-fast-seek")                         // :290
    }
    return media
}
```

## 2.2 ما هو مضبوط أصلاً عالمياً — ولم يكن أحد يعلم

من `videolan/VLCKit` فرع `3.0`، ملف `Sources/VLCLibrary.m`، الوسائط الافتراضية الممرَّرة إلى
`libvlc_new` على iOS:

```
--no-color   --no-osd   --no-video-title-show   --no-snapshot-preview
--http-reconnect   --text-renderer=freetype   --avi-index=3   --audio-resampler=soxr
--avcodec-fast        ← فقط حين __LP64__ غير معرَّف (أي 32-bit) ⇒ غير مفعَّل عندنا
```

> 🟡 **نتيجة مباشرة: سطرنا `:http-reconnect` (`VLCPlayer.swift:267`) مكرَّر — الراية مضبوطة عالمياً
> أصلاً.** لا ضرر في بقائه (تكرار الراية غير ضارّ)، لكن **علّق عليه بالحقيقة** بدل أن يوهم قارئاً
> لاحقاً أنه هو ما يُفعّل الميزة. (البند 7 في الجدول.)
>
> وكذلك `--no-video-title-show` و`--no-osd` مضبوطان — **فلا تضِف `:no-video-title-show`**، لا مكسب فيه.

## 2.3 ثلاث نتائج سلبية مؤكَّدة — وهي أنفع من ثلاث توصيات

**(أ) `--no-lua` عديم الأثر عندنا — Lua غير مبنيّة أصلاً.**
من سكربت البناء الرسمي `videolan/VLCKit:buildMobileVLCKit.sh`، ضمن وسائط `configure` لبناء iOS:

```
--disable-lua \
```

`src/libvlc-module.c` يعرّف `add_bool( "lua", true, … )` بنصّ مساعدة «Disable all lua plugins» —
فالخيار موجود في النواة، **لكن وحدات lua ليست في الثنائية أصلاً**. تمريره **لا يوفّر مل.ث واحدة**.
**لا تضِفه، ولا تُضِع وقتاً في مناقشته مجدّداً.**

**(ب) فكّ الشفرة العتاديّ مفعَّل بالفعل.** من `modules/codec/avcodec/avcodec.c`:
```c
add_module( "avcodec-hw", "hw decoder", "any", HW_TEXT, HW_LONGTEXT, false )
```
القيمة الافتراضية `"any"` تعني **اختيار تلقائي بين وحدات فكّ الشفرة العتادية** — وعلى iOS ذلك
VideoToolbox. **ضبط `:avcodec-hw=videotoolbox` صراحةً لا يشتري شيئاً** ويُلغي التراجع التلقائي عند
كوديك لا يدعمه العتاد. **لا تفعله.**

**(ج) `--avcodec-fast` ليس مفعَّلاً عندنا، ولا نريده.** `add_bool("avcodec-fast", false, …)` —
وVLCKit يضيفه على 32-bit فقط. هو **مقايضة جودة** (يسمح بتقنيات فكّ شفرة غير متوافقة مع المعيار)، لا
مُسرِّع بدء. **لا تفعّله.**

## 2.4 🔴 MKV — الفهرس عند **ذيل** الملف، والبرهان من شيفرة VLC

هذا أهمّ اكتشاف في هذه المرحلة، وهو يفسّر لماذا يبدأ فيلم `.mkv` أبطأ من `.mp4` بلا أي خطأ في شيفرتنا.

**١) المُفكِّك يقرأ `SeekHead` من رأس الملف ويسجّل موضع الـ Cues:**
```cpp
// modules/demux/mkv/matroska_segment_parse.cpp — ParseSeekHead()
else if( MKV_IS_ID( l, KaxSeekPosition ) ) {
    KaxSeekPosition &spos = *static_cast<KaxSeekPosition*>( l );
    spos.ReadData( es.I_O() );
    i_pos = (int64_t)segment->GetGlobalPosition( static_cast<uint64>( spos ) );
}
…
else if( id == EBML_ID(KaxCues) ) {
    msg_Dbg( &sys.demuxer, "|   - cues at %" PRId64, i_pos );
    LoadSeekHeadItem( EBML_INFO(KaxCues), i_pos );
}
```

**٢) و`LoadSeekHeadItem` يقفز فعلياً إلى ذلك الموضع:**
```cpp
// modules/demux/mkv/matroska_segment.cpp — LoadSeekHeadItem()
es.I_O().setFilePointer( i_element_position, seek_beginning );
```
**ولا يفحص قابلية القفز قبل ذلك** — يفترضها.

**٣) وفوق ذلك، مرشّح `prefetch` يعمل على HTTP بالتحديد.** من `modules/stream_filter/prefetch.c`،
تعليق `Open()` الحرفي:
> *«For local files, the operating system is likely to do a better work at caching/prefetching. Also,
> prefetching with this module could cause undesirable high load at start-up.»*

فهو **يتخطّى** المصادر ذات `STREAM_CAN_FASTSEEK` (الملفات المحلّية) **ويعمل على HTTP**. وخياراته:
```c
add_integer("prefetch-buffer-size", 1 << 14, …)   /* KiB ⇒ 16 MiB */
add_integer("prefetch-read-size",   1 << 24, …)   /* بايت ⇒ 16 MiB */
add_integer("prefetch-seek-threshold", 1 << 14, …) /* بايت ⇒ 16 KiB */
```
> **عتبة القفز 16 كيلوبايت.** أي قفزة أبعد من ذلك تُعيد تشغيل الوصول الأساسي ⇒ **طلب HTTP جديد**.

### الحصيلة، ولا مفرّ منها
لفتح `.mkv` بعيد، VLC تدفع تقريباً:
1. طلب من الإزاحة 0 (رأس الملف: EBML + SeekHead + Tracks)،
2. **قفزة إلى ذيل الملف لقراءة الـ Cues ⇒ طلب Range جديد**،
3. **عودة إلى أول Cluster ⇒ طلب Range ثالث**.

أي **رحلتَي شبكة إضافيتين قبل أوّل إطار**، كلٌّ منهما RTT + TTFB. على وصلة بـ 60 مل.ث RTT وخادم
بطيء، هذه **150–800 مل.ث** لا يمكن لأي خيار libvlc أن يحذفها.

### ماذا يمكن فعله؟ — الجواب الصادق: **لا شيء من جهتنا**
- **لا يمكن اختيار الحاوية.** واجهة Xtream تعطي `container_extension` قيمةً واحدة لكل فيلم
  (`Core.swift:2147`)، ولا تعرض بديلاً. **لا يوجد "اطلب mp4 بدل mkv".**
- **`:demux=mkv` لا يوفّر رحلة شبكة**، بل يوفّر استكشاف وحدات (CPU على بايتات مقروءة أصلاً).
  **ومرفوض لسبب أقوى:** لوحات IPTV تكذب في الامتداد بانتظام، وفرض المُفكِّك يحوّل «فيلم يعمل» إلى
  «فيلم لا يفتح». **لا تفعله.**
- **`mkv-preload-clusters` افتراضيّاً `false`** (`modules/demux/mkv/mkv.cpp`) — وتفعيله **يزيد**
  العمل قبل التشغيل لا ينقصه. **لا تفعله.**
- **ما يبقى:** إخفاء الزمن لا حذفه ⇒ **البند 1 (الملصق)**. وهذا بالضبط لماذا هو أعلى بند في الجدول.

> 📌 **وملاحظة تخصّ `.mp4` أيضاً:** ملفّ MP4 غير مُهيّأ للبثّ (`moov` عند النهاية بدل البداية) يدفع
> **نفس الثمن تماماً**. لا نتحكّم في كيفية ترميز اللوحة لملفّاتها. **هذا حدٌّ خارجيّ، لا عيب فينا.**

## 2.5 `:clock-jitter=0` — البناء على حكمٍ سابق، لا إعادته

`TECH_HUNT_V2.md §5` حكم: **يُتبنّى لـ VOD وحده**، بدليل من `src/input/es_out.c:2539–2568`، وأن
الافتراضي `5 * CLOCK_FREQ/1000` = **5000 مل.ث** من `src/libvlc-module.c` (**أعدتُ التحقّق من الملف
الخام في هذه الجلسة — الرقم صحيح**). **ولم يُشحن بعد:** `VLCPlayer.swift:259–293` لا يحتوي السطر.

**ما أضيفه هنا (وهو الجديد): كيف تعرف أنه نفع، وأين تضعه بالضبط.**

```swift
// BlankTV/VLCPlayer.swift — داخل makeMedia، فرع else (VOD)، بعد السطر 290
            media.addOption(":input-fast-seek")
            // clock-jitter هو السقف الذي تسمح به VLC لنفسها كي تُضخّم المخزن فوق
            // network-caching حين تقيس اضطراب وصول الحزم. الافتراضي 5000 مل.ث
            // (src/libvlc-module.c) — أي خمس ثوانٍ إضافية ممكنة قبل أول إطار
            // (src/input/es_out.c:2539–2568، فرع "buffering more"). ملفُّ VOD يُسلَّم
            // بنطاقات بايت ويُعاد طلب ما فُقد، فالتضخّم التكيّفي هنا كلفةٌ بلا مقابل.
            //
            // ⚠ لا تنقل هذا السطر إلى فرع isLive أبداً: هناك، تجاوزُ السقف يجعل VLC
            // تُعيد ضبط الساعة (نفس الموضع، فرع msg_Err) وذلك تقطيعٌ مرئيّ؛ والتضخّم
            // التكيّفي على المباشر آليةُ موثوقية لا عيب.
            // ⚠ ولا تُضِف ":clock-synchro=0" — مرفوض في TECH_HUNT_V2 §5 بدليل من
            //    src/input/input.c:2875. لا تُعِد فتح الملف.
            media.addOption(":clock-jitter=0")
```

**بروتوكول القياس (إلزامي — وهو ما يجعل هذا بنداً هندسياً لا تخميناً):**
نفس الفيلم · نفس الشبكة · خمس مرات قبل وخمس بعد · ساعة إيقاف من لمسة «تشغيل» إلى أول إطار.
**إن لم يتحرّك الوسيط، أعِد السطر.**

## 2.6 هل يمكن «تسخين» VLC كما نسخّن AVPlayer؟ — لا، ولا توصية

`VLCMediaPlayer` **لا يفصل التحضير عن التشغيل**، و`VLCMedia.parse` تقرأ البيانات الوصفية لا الحمولة.
وأقرب اقتراب هو `:start-paused`، وهو **يبني مُفكِّك شفرة كاملاً في الخلفية** — كلفة ذاكرة أعلى بكثير
من `AVPlayer`، وعلى جهاز محمّل قد يُنهي النظام التطبيق. **و`VLCMediaPlayer(initWithOptions:)` أسوأ:**
توثيق `Headers/Public/VLCMediaPlayer.h` ينصّ حرفياً أنه *«will allocate a new libvlc and VLCLibrary
instance, which will have a memory impact»* — أي محرّك VLC ثانٍ كامل في العملية. **لا تبنِه.**

---

# المرحلة 3 — مسار AVPlayer (المباشر HLS)

## 3.1 ما لدينا اليوم — وهو جيّد

```swift
// BlankTV/PlayerEngine.swift
:337   if !isLive { pItem.preferredForwardBufferDuration = 1 }   // instant-start
:339   pItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
:353   avPlayer.automaticallyWaitsToMinimizeStalling = true
:469   self.avPlayer.playImmediately(atRate: 1.0)                 // عند .readyToPlay
:502–505  // بعد أول tick حقيقي: preferredForwardBufferDuration = 0 (تلقائي)
```

**هذا النمط — «ابدأ بمخزن صغير ثم أرجِعه إلى التلقائي» — هو بالضبط ما تفعله أقوى المحرّكات المفتوحة.**
من `androidx/media` (`DefaultLoadControl.java`، المصدر الرسمي):

```java
DEFAULT_MIN_BUFFER_MS = 50_000;
DEFAULT_MAX_BUFFER_MS = 50_000;
DEFAULT_BUFFER_FOR_PLAYBACK_MS = 1000;                  // ← ثانية واحدة للبدء
DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 2000;
```
> ExoPlayer/Media3 يستهدف **50 ثانية** مخزناً في الحالة المستقرّة، **لكنه يبدأ التشغيل بعد
> ثانية واحدة فقط.** الفصل بين «مخزن البدء» و«مخزن الاستقرار» هو الفكرة كلها — **ونحن ننفّذها
> بالفعل** عبر `1 → 0`. **لا تغيير مطلوب. سجّل هذا كتصديق خارجيّ لقرار قائم.**

## 3.2 ما **لا** يُمَسّ — بأمرٍ موثَّق

**`automaticallyWaitsToMinimizeStalling` — لا تلمسه.** الالتزام `edd3d82` («Revert my own live-zap
change — it broke stall recovery») يقول حرفياً:

> *«Build 76 set `automaticallyWaitsToMinimizeStalling = !isLive` … with automatic waiting DISABLED
> the player does not resume by itself after a stall. So on a live channel a single buffer underrun
> froze the picture until our own 30-second stall monitor gave up … Nothing is lost by reverting.
> `playImmediately(atRate:)` on `.readyToPlay` already begins playback the moment the first chunk
> lands and by contract ignores this property, so the fast start was coming from there the whole
> time.»*

> 🔴 **هذا الملف يؤكّد ذلك ولا يعيد فتحه.** السرعة تأتي من `playImmediately`، والراية تشتري **التعافي**.
> **من يقترح `false` مرّة أخرى، أرِه هذا السطر.**

**`preroll(atRate:completionHandler:)` — لا تضِفه.** حُكِم عليه في `TECH_ADJUDICATION.md §2`:
يرمي استثناءً (**انهيار**) إن لم يكن العنصر `.readyToPlay`، ويشترط `rate == 0` قبل الاستدعاء. فهو
**مستهلكٌ لفحص الجاهزية لا بديلٌ عنه**، و`playImmediately` يحقّق الهدف بلا هذا الخطر. **مغلق.**

**`AVURLAssetPreferPreciseDurationAndTimingKey` — لا تضبطه.** توثيق Apple حرفياً:
> *«If you only intend to play the asset, the default value of `false` is sufficient because AVPlayer
> supports approximate random access by time when full precision isn't available.»*
وضبطه `true` يعني *«longer loading times are acceptable»* — أي **عكس هدفنا بالضبط**. (`TECH_HUNT_V2`
سجّلها كنتيجة سلبية؛ أعدتُ التحقّق من نصّ Apple هنا.)

**`preferredForwardBufferDuration` — الرقم 1 صحيح.** توثيق Apple: *«If set to 0, the player will
choose an appropriate level of buffering… Setting this property to a low value will increase the
chance that playback will stall and re-buffer»*. **ولهذا نعيده إلى 0 بعد أول tick** — وهو ما تفعله
`PlayerEngine.swift:502–505` بالضبط. **صحيح كما هو.**

## 3.3 البند الوحيد الجديد في هذه المرحلة: `startsOnFirstEligibleVariant`

توثيق Apple (`AVPlayerItem.startsOnFirstEligibleVariant`، **iOS 14.0+** — فوق أرضيتنا، فلا حاجة
لـ`if #available`):
> *«A Boolean value that indicates whether playback starts with the first eligible variant that
> appears in the stream's main playlist.»*

**لماذا يهمّ للمباشر:** بلا هذه الراية، يختار AVPlayer المتغيّر الأول بناءً على تقديره للنطاق، وقد
يعني ذلك انتظاراً/تجريباً قبل الالتزام. بـ`true` يلتزم بأول متغيّر في القائمة **فوراً**.

```swift
// BlankTV/PlayerEngine.swift — داخل setup()، بعد السطر 339
// المباشر فقط: ابدأ بأول متغيّر في القائمة الرئيسية بدل انتظار قرار اختيار المتغيّر.
// (Apple: "playback starts with the first eligible variant that appears in the
//  stream's main playlist"). ⚠ الثمن: إن كانت اللوحة تضع أعلى معدّل بت أولاً في
// القائمة، فقد نبدأ على متغيّر أثقل من الوصلة ونتوقّف. لهذا: المباشر فقط، وبقياس.
if isLive { pItem.startsOnFirstEligibleVariant = true }
```

**⚠ الخطر حقيقي وليس نظرياً:** ترتيب المتغيّرات في قوائم لوحات Xtream عشوائيّ عملياً. **قِس على
عشر قنوات مختلفة**، وراقب عدّاد التوقّفات لا زمن البدء وحده. **إن ساء التوقّف، أعِد السطر.**

## 3.4 تنظيف سطر واحد (مذكور في `TECH_ADJUDICATION §2`، لم يُنفَّذ)

```swift
// BlankTV/PlayerEngine.swift:469 — يتجاهل تفضيل سرعة المستخدم
self.avPlayer.playImmediately(atRate: 1.0)   // ← اجعلها self.rate
```
لا علاقة له بـ TTFF، لكنه في نفس الدالّة ويكلّف كلمةً واحدة.

---

# المرحلة 4 — البدء **المُدرَك** (وهذا هو البند الأول في الجدول)

## 4.1 ما يراه المستخدم اليوم — بالتحديد

```swift
// BlankTV/PlayerView.swift:334–354
var body: some View {
    ZStack {
        Color.black.ignoresSafeArea()          // :337  ← المستطيل الأسود
        PlayerSurfaceView(vm: vm).ignoresSafeArea()   // :338  ← سطحٌ أسود حتى أول إطار
        if showBufferingUI {                   // :342  ← بعد 300 مل.ث
            ProgressView()…
        }
```
و`updateBufferingUI` (`PlayerView.swift:1135–1157`) يؤخّر المؤشّر **0.3 ثانية** ويُبقيه **1.2 ثانية**
على الأقل.

> ✅ **تأخير الـ 300 مل.ث صحيح ومطابق للممارسة المطلوبة («لا دوّارة قبل ~250 مل.ث»). لا تغيّره.**
> 🔴 **لكن ما يملأ تلك الـ 300 مل.ث — وكل ما بعدها حتى أول إطار — هو أسودٌ خالص.** على فيلم `.mkv`
> بعيد، §0.2 و§2.4 يقولان إن ذلك **1–2 ثانية من السواد**. المستخدم لا يقيس مل.ث؛ يقيس **متى ظهرت
> صورة**. وأي صورة أفضل من لا شيء.

## 4.2 المقترح — طبقة واحدة، وشرط إخفاء واحد لكل محرّك

```
ZStack {
    Color.black
    ┌──────────────────────────────────────────┐
    │  جديد: S8KImage(ملصق/خلفية العنصر)        │  ← يملأ الشاشة، مموّه قليلاً ومعتم
    └──────────────────────────────────────────┘
    PlayerSurfaceView(vm: vm)                     ← يبقى شفافاً حتى أول إطار
    …
}
```

**الخطوة 1 — موصِّل الصورة (`BlankTV/Models.swift`، بجوار `ContentItem` عند `:387–399`):**

```swift
extension ContentItem {
    /// أفضل صورة متاحة لتغطية لحظة ما قبل أول إطار.
    /// تفضيل الخلفية (backdrop) على الملصق العمودي: نسبتها أقرب إلى نسبة الشاشة أفقياً،
    /// فالانتقال إلى الفيديو لا يقفز. تتدرّج بأمان إلى nil (قاعدة metadata-agnostic:
    /// لوحة بلا صور يجب أن تبقى صالحة — عندها تعود الشاشة السوداء الحالية بلا عطل).
    var artURL: String? {
        switch self {
        case .live(let ch):          return ch.logoURL                    // Models.swift:135
        case .movie(let m):          return m.backdropURL ?? m.posterURL  // Models.swift:227–228
        case .episode(let ep, let s):return ep.posterURL ?? s.backdropURL ?? s.coverURL
                                                                          // Models.swift:319, 276–277
        }
    }
}
```

**الخطوة 2 — علامة «ظهر أول إطار» في القاعدة المشتركة (`BlankTV/PlayerEngine.swift`، داخل
`BasePlayerVM` بجوار `:68`):**

```swift
    /// true بمجرّد أن يرسم المحرّك إطاراً حقيقياً على السطح. تُقاد من كل محرّك بطريقته
    /// (لا يوجد نداء موحّد لأول إطار في أيٍّ من الواجهتين — انظر التعليقين أدناه).
    @Published var hasFirstFrame: Bool = false
```
وأعِدها إلى `false` في `load(_:)` لكل محرّك (`PlayerEngine.swift:381` و`VLCPlayer.swift:138`)، وإلا
بقيت الحلقة التالية بلا غطاء.

**الخطوة 3(أ) — AVPlayer. المصدر الصحيح هو `AVPlayerLayer.isReadyForDisplay` وهو قابل لـ KVO
(ونستعمله أصلاً في `startVideoWatchdog`, `PlayerEngine.swift:437`):**

```swift
// BlankTV/PlayerEngine.swift — داخل makeSurfaceView()، بعد إسناد الطبقة (:298)
// isReadyForDisplay هي علامة Apple على "هناك ما يُرسَم الآن". نستعملها أصلاً في
// startVideoWatchdog (:437)؛ هنا نستعملها للغرض الإيجابي: رفع الغطاء.
readyObs = v.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
    let ready = l.isReadyForDisplay
    Task { @MainActor in if ready { self?.hasFirstFrame = true } }
}
```
(وأضِف `private var readyObs: NSKeyValueObservation?` بجوار `:271`، وأبطِلها في `teardownObservers()`
عند `:396–404`.)

⚠ **التحفّظ المنقول من `TECH_ADJUDICATION §2` وينطبق حرفياً هنا:** `.initial` يُطلَق **قبل عودة
`observe(...)`**، فـ`readyObs` لا يزال `nil` داخل النداء الأول. القفز إلى `Task { @MainActor in … }`
فوراً — كما أعلاه — هو ما يُبقي هذا آمناً. **لا تقرأ `readyObs` ولا تُبطلها من داخل المعالج.**

**الخطوة 3(ب) — VLC. لا يوجد نداء لأول إطار — نتيجة سلبية مؤكَّدة.**
عدّدتُ كامل `VLCMediaPlayerDelegate` في `Headers/Public/VLCMediaPlayer.h` (فرع 3.0):
`mediaPlayerStateChanged:` · `mediaPlayerTimeChanged:` · `mediaPlayerTitleChanged:` ·
`mediaPlayerChapterChanged:` · `mediaPlayerLoudnessChanged:` · `mediaPlayerSnapshot:` ·
`mediaPlayerStartedRecording:` · `mediaPlayer:recordingStoppedAtPath:`.
**لا شيء يعني «رُسِم أول إطار».** أقرب ما يوجد هو الخاصية `hasVideoOut` (`BOOL`, للقراءة فقط،
موثَّقة: *«Does the current media have a video output?»*).

فالمصدر الصحيح عندنا هو **أول تكّة زمنية متقدّمة**، وهي موجودة أصلاً:

```swift
// BlankTV/VLCPlayer.swift — داخل mediaPlayerTimeChanged، داخل if advanced (:688–698)
        if advanced {
            if isLoading { isLoading = false }
            if buffering { buffering = false }
            // ⬇ جديد: VLCMediaPlayerDelegate لا يملك نداءً لأول إطار (عُدّ كامل البروتوكول
            // في VLCKit 3.0). أول تكّة زمنية متقدّمة + وجود مخرج فيديو هو أدقّ ما نملك،
            // وهو متأخّر بجزء من الثانية عن الرسم الفعلي — وهذا في صالحنا: الغطاء يُرفع
            // بعد أن تصير هناك صورة، لا قبلها (وميض أسود لحظيّ هو ما نتجنّبه أصلاً).
            if !hasFirstFrame, player.hasVideoOut { hasFirstFrame = true }
```

**الخطوة 4 — الطبقة نفسها (`BlankTV/PlayerView.swift`، بين `:337` و`:338`):**

```swift
            Color.black.ignoresSafeArea()
            // غطاء ما قبل أول إطار. البايتات لا تصل أسرع، لكن المستخدم يرى صورة العمل
            // بدل مستطيل أسود — وعلى فيلم .mkv بعيد ذلك 1–2 ثانية من الفارق المُدرَك
            // (فهرس Matroska عند ذيل الملف: رحلتا Range إضافيتان قبل أول إطار).
            // يتدرّج بأمان: بلا صورة، يبقى السلوك الحالي حرفياً.
            if !vm.hasFirstFrame, let art = currentItem.artURL {
                S8KImage(url: art, placeholder: "play.tv.fill")
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))   // كي تقرأ الدوّارة فوقها
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)              // لا يبتلع أي إيماءة
            }
            PlayerSurfaceView(vm: vm).ignoresSafeArea()
```
وأضِف `.animation(.easeOut(duration: 0.25), value: vm.hasFirstFrame)` على الـ`ZStack` كي يكون
الانتقال تلاشياً لا قطعاً.

## 4.3 لماذا هذا البند هو الأول في الترتيب

| المعيار | التقييم |
|---|---|
| **الفائدة المُدرَكة** | يحذف **كل** لحظات السواد في كل مسار: مباشر، فيلم، حلقة، انتقال حلقة، تبديل قناة، وحتى أثناء التراجع بين المحرّكين. |
| **الخطر** | **شبه صفر.** طبقة عرض إضافية، `allowsHitTesting(false)`، ولا تمسّ أي منطق تشغيل. أسوأ فشل ممكن: صورة تبقى ظاهرة ثانيةً زائدة. |
| **التدرّج الآمن** | عنصر بلا صورة ⇒ `artURL == nil` ⇒ السلوك الحالي حرفياً. متوافق مع قاعدة [[metadata-agnostic-design]]. |
| **الاتساق البصريّ** | صفحة التفاصيل تعرض نفس الصورة، و`fullScreenCover` ينزلق فوقها — فيبدو الانتقال **متّصلاً** بدل قطعٍ إلى الأسود. |
| **الكلفة الشبكية** | **صفر.** الصورة في كاش الصور بالفعل (المستخدم كان ينظر إليها قبل ثانية). |

## 4.4 ما بحثتُه في هذه المرحلة ولم أوصِ به

| الفكرة | الحكم |
|---|---|
| **«الصوت أولاً»** | AVPlayer يبدأ الصوت قبل اكتمال أول إطار أصلاً؛ وVLC لا يُخرج شيئاً حتى تجهز الساعة. **لا رافعة برمجية عندنا.** |
| **`.transition` مخصّص من الملصق إلى الفيديو (matched geometry)** | فكرة جيّدة بصرياً، **لكن `fullScreenCover` لا يدعم `matchedGeometryEffect` عبر حدوده**. تنفيذها يعني استبدال `fullScreenCover` بعرضٍ مخصّص في **سبعة مواضع** (`ContentViews.swift:203, 2597, 2849, 3357` · `HomeView.swift:748` …). **خطر أعلى بكثير مما يشتريه. لا.** |
| **معاينات مصغّرة أثناء السحب (thumbnail scrub)** | خارج نطاق TTFF، **وغير ممكن عندنا أصلاً**: تحتاج مسار صور (I-frame playlist أو BIF)، ولوحات Xtream لا تعرضه. توليدها محلّياً يعني فكّ شفرة ثانياً. **لا.** |
| **رفع تأخير الدوّارة فوق 300 مل.ث** | **لا.** الرقم صحيح، والبند 1 يجعل السؤال بلا موضوع: مع الغطاء، الدوّارة تظهر **فوق صورة** لا فوق سواد. |

---

# 5. المشهد الخارجي — كيف يبدأ الآخرون بسرعة (مصادر أوّلية فقط)

## 5.1 mpv — الملف الرسمي `etc/builtin.conf`، تشكيلة `[low-latency]`

```
audio-buffer=0
vd-lavc-threads=1
cache-pause=no
demuxer-lavf-o-add=fflags=+nobuffer
demuxer-lavf-probe-info=nostreams
demuxer-lavf-analyzeduration=0.1
video-sync=audio
interpolation=no
video-latency-hacks=yes
stream-buffer-size=4k
```
ومن `demux/demux_lavf.c` (المصدر): `demuxer-lavf-probe-info` قيمه `{no,yes,auto=-1,nostreams=-2}`،
والافتراضي `auto`.

> **الدرس المنقول:** استراتيجية mpv للبدء السريع هي **تقليل الاستكشاف إلى أدنى حدّ**
> (`analyzeduration=0.1`, `probe-info=nostreams`, `fflags=+nobuffer`) — أي **نفس عائلة الفكرة**
> التي يمثّلها `:clock-jitter=0` عندنا (منع التضخّم التكيّفي قبل البدء).
> ⚠ **لكن لا يمكن نقل الخيارات حرفياً:** mpv يستعمل مُفكِّكات FFmpeg (`demuxer-lavf-*`)، بينما VLC
> تستعمل مُفكِّكاتها الأصلية `mp4`/`mkv`/`ts` لهذه الحاويات — **فلا وجود لـ`probesize` نقابله**.
> **الفكرة تُنقل، الأسماء لا.**

## 5.2 ExoPlayer / Media3 — `DefaultLoadControl.java` (المصدر الرسمي)

```java
DEFAULT_MIN_BUFFER_MS = 50_000;
DEFAULT_MAX_BUFFER_MS = 50_000;
DEFAULT_BUFFER_FOR_PLAYBACK_MS = 1000;
DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 2000;
DEFAULT_TARGET_BUFFER_BYTES = C.LENGTH_UNSET;
DEFAULT_BACK_BUFFER_DURATION_MS = 0;
```
وتوثيق `bufferForPlaybackMs`: *«The default duration of media that must be buffered for playback to
start or resume following a user action such as a seek.»*

> **الدرس:** فصلٌ صريح بين **مخزن البدء (1 ث)** و**مخزن الاستقرار (50 ث)**. **ونحن ننفّذه بالفعل**
> عبر `preferredForwardBufferDuration = 1` ثم `0` (`PlayerEngine.swift:337`, `:502–505`).
> **تصديق خارجيّ لقرار قائم — لا عمل مطلوب.**

## 5.3 KSPlayer — «秒开» (الفتح في ثانية)، وشهادته المضادّة

من `Sources/KSPlayer/AVPlayer/KSOptions.swift`:
```swift
formatContextOptions["user_agent"]         = userAgent
formatContextOptions["scan_all_pmts"]      = 1
formatContextOptions["reconnect"]          = 1
formatContextOptions["reconnect_streamed"] = 1
decoderOptions["threads"]                  = "auto"
preferredForwardBufferDuration = 3.0
maxBufferDuration              = 30.0
isSecondOpen = false        // 是否开启秒开 — "تفعيل الفتح الفوري"
```
والأهم — **الشهادة المضادّة**: خيارات «الفتح الفوري» الجريئة (`auto_convert`, `fps_probe_size`,
`rw_timeout`, `max_analyze_duration`) موجودة في الملف **معلَّقة عمداً**، مع ملاحظة أنها **تُعطِّل بعض
البثوث**.

> **الدرس، وهو الأهمّ في هذا القسم:** محرّكٌ بُني تحديداً حول «الفتح الفوري» يشحن أجرأ خياراته
> **مطفأةً بالافتراض**. هذا يدعم موقفنا: **قِس كل خيار على حدة، وشُدّ ما ينفع فقط.**
> (وملاحظة عابرة: `KSPlayer` هو المحرّك الثالث المؤجَّل عندنا — [[player-engine-ksplayer]]. **لا شيء
> في هذا التقرير يبرّر تقديمه.**)

## 5.4 Infuse · VidHub · TiviMate — **نتيجة سلبية، وأقولها صراحةً**

- جلبتُ مدوّنة Firecore الرسمية: **لا منشور واحد** يتناول زمن بدء التشغيل أو التخزين المؤقّت. أقرب
  ما فيها «Direct Mode» (فبراير 2024) وهو عن **تحميل المكتبة** لا عن التشغيل.
- **VidHub وTiviMate مغلقا المصدر بلا وثائق هندسية عامّة.** أي رقم أو تقنية تُنسب إليهما في المدوّنات
  **غير قابلة للتحقّق**.
- **وميزانية `WebSearch` نفدت (200/200) قبل بدء هذه الجلسة**، فلم أستطع مسح مصادر ثانوية للوصول إلى
  مصادر أوّلية.

> **لا أدّعي معرفةً عنها.** المحرّكات المفتوحة الثلاثة أعلاه (mpv · ExoPlayer · KSPlayer) + شيفرة VLC
> نفسها تغطّي المساحة الهندسية كاملةً، والادّعاء بأن Infuse يفعل «شيئاً سحرياً» بلا مصدر هو بالضبط ما
> يحظره أسلوب هذا الملف.

---

# 6. ماذا يُقاس، وكيف — بلا هذا فالباقي تخمين

الفريق **لا يترجم محلّياً**، فالقياس على الجهاز هو أداة التحقّق الوحيدة. أضِف عدّاداً واحداً بسيطاً
واعرضه في لوحة `EngineStatsView` القائمة (`SettingsView.swift:532`):

```swift
// BlankTV/EngineStats.swift — TTFF لكل محرّك، بلا أي تبعية جديدة.
// t0 يُلتقط عند لمسة التشغيل (فتح fullScreenCover)، وt1 عند hasFirstFrame = true.
// خزّن آخر 20 قياساً + الوسيط لكل محرّك. الوسيط لا المتوسّط: عيّنة واحدة سيّئة
// على شبكة متذبذبة تُفسد المتوسّط وتخفي أثر التغيير الذي نقيسه.
```

| ما يُقاس | كيف | ما يُثبته |
|---|---|---|
| **TTFF الوسيط لكل محرّك** | العدّاد أعلاه، 20 عيّنة | الأساس الذي يُقارَن به كل تغيير |
| **`:clock-jitter=0`** | نفس الفيلم · نفس الشبكة · 5 قبل و5 بعد | البند 2 — **أعِد السطر إن لم يتحرّك الوسيط** |
| **وجود redirect** | `StreamURLProbe` (§1.4أ)، مرّة على الجهاز | يفتح البند 4 أو **يغلقه** |
| **`startsOnFirstEligibleVariant`** | 10 قنوات · زمن البدء **و**عدّاد التوقّفات | البند 5 — التوقّف يهزم السرعة |
| **`.ts` مقابل `.m3u8` للمباشر** | نفس القناة بالامتدادين | البند 6 (§7.2) |
| **MobileVLCKit 3.7.3** | قائمة الفحص السبعة في `TECH_HUNT_V2 §3` | البند 3 |

---

# 7. قرارات صريحة: ما لا يُفعل، وما يحتاج بناءً مخصّصاً

## 7.1 «لا تفعله» — قائمة مغلقة، بدليلٍ لكلّ بند

| البند | لماذا لا | المصدر |
|---|---|---|
| `--no-lua` / `:no-lua` | **lua غير مبنيّة أصلاً** في MobileVLCKit | `buildMobileVLCKit.sh` → `--disable-lua` |
| `:avcodec-hw=videotoolbox` | الافتراضي `"any"` يفعلها أصلاً، والتقييد يُلغي التراجع | `modules/codec/avcodec/avcodec.c` |
| `:avcodec-fast` | مقايضة **جودة**، لا سرعة بدء؛ وVLCKit يضيفه على 32-bit فقط | `avcodec.c` + `VLCLibrary.m` |
| `:demux=mp4` / `:demux=mkv` | اللوحات تكذب في الامتداد ⇒ يحوّل «بطيء» إلى «لا يفتح» | حكم هندسي على `Core.swift:2147` |
| `mkv-preload-clusters=1` | **يزيد** العمل قبل التشغيل (افتراضي `false` لسبب) | `modules/demux/mkv/mkv.cpp` |
| `:clock-synchro=0` | مرفوض بدليل سابق ولا يُعاد فتحه | `TECH_HUNT_V2 §5` + `src/input/input.c:2875` |
| `automaticallyWaitsToMinimizeStalling = false` | يكسر التعافي من التوقّف؛ والسرعة من `playImmediately` أصلاً | `edd3d82` + توثيق Apple |
| `preroll(atRate:)` | يرمي **استثناءً** إن لم يكن `.readyToPlay`؛ مستهلكٌ لفحص الجاهزية لا بديل عنه | `TECH_ADJUDICATION §2` |
| `AVURLAssetPreferPreciseDurationAndTimingKey = true` | Apple: *«longer loading times are acceptable»* — عكس الهدف | توثيق Apple |
| تسخين VLC بـ`:start-paused` أو `initWithOptions:` | مُفكِّك شفرة كامل في الخلفية / **نسخة libvlc ثانية** | `VLCMediaPlayer.h` |
| `matchedGeometryEffect` عبر `fullScreenCover` | غير مدعوم؛ تنفيذه يعيد كتابة سبعة مواضع عرض | حكم على `ContentViews.swift:203, 2597, 2849, 3357` |
| `network-caching` — أي رقم جديد | لا تُغيّره قبل أن يستقرّ البند 2؛ وأرقام الأساطيل الأخرى لا تُنسخ | `TECH_HUNT_V2 §5` |

## 7.2 البند 6 — `.ts` بدل `.m3u8` للمباشر: فرصة حقيقية، وخطر حقيقي

```swift
// BlankTV/Core.swift:1600 — نحن نفرض HLS على كل قناة، دائماً
func liveURL(id: String) -> String { "\(base)/live/\(user)/\(pass)/\(id).m3u8" }
```

**المنطق:** خرج HLS من لوحة Xtream يعني أن المشغّل يجلب القائمة **ثم** يجلب مقطعاً كاملاً قبل أول
إطار. أمّا `.ts` فتيّار مستمرّ: أول إطار بعد أول GOP تقريباً. **نظرياً، `.ts` أسرع بدءاً.**

**والثمن مباشر ومعروف:** `StreamRouter.defaultEngine` (`StreamRouter.swift:45–49`) يرسل كل ما ليس
HLS إلى VLC ⇒ **نخسر فكّ الشفرة العتاديّ، وPiP الأصلي، وAirPlay، ونرفع استهلاك البطارية** — على
التبويب الذي يُستهلك بأطول جلسات.

**⚠ وطول المقطع في خرج Xtream غير متحقَّق منه** — لا مصدر أوّليّ متاح لي، والقيمة تختلف بين اللوحات.
**قد يكون الفارق 200 مل.ث وقد يكون 6 ثوانٍ.** لا أوصي بتغيير الافتراضي.

> **التوصية:** **قِس أولاً** (نفس القناة بالامتدادين، ساعة إيقاف). وإن ثبت فارق كبير، فالشكل الصحيح
> **ليس** تغيير الافتراضي، بل توسيع `EngineDecisionCache` (`EngineDecisionCache.swift`) ليحمل
> **صيغة** القناة إلى جانب محرّكها — فتتعلّم كل قناة أسرع طريقيها بعد أول تشغيل ناجح.
> **هذا بند بنائه مخصّص، وموافقة المالك أولاً (بروتوكول المراحل).**

## 7.3 ما يحتاج بناءً مخصّصاً وقائمة فحص جهاز (لا يُدمج في دفعة)

| البند | لماذا منفرداً | قائمة الفحص |
|---|---|---|
| **3 — MobileVLCKit 3.7.3** | تبديل مُفكِّك شفرة يمسّ 100% من VOD | القائمة السبعة في `TECH_HUNT_V2 §3` + مقارنة حجم `.ipa` |
| **4 — إعادة كتابة المضيف** | يمسّ كل رابط بثّ؛ وفشله يبدو «قناة لا تعمل» | 10 عناصر × 3 أنواع · تحقّق من عدم ظهور «حدّ الاتصالات» · إبطال الكاش عند تبديل الحساب |
| **6 — `.ts` للمباشر** | يغيّر المحرّك، والبطارية، وPiP | 10 قنوات · جلسة 30 دقيقة لقياس الحرارة/البطارية · PiP · AirPlay |
| **5 — `startsOnFirstEligibleVariant`** | صغير، **لكن قِسه وحده** وإلا اختلط أثره بالبند 2 | 10 قنوات · زمن البدء **وعدّاد التوقّفات** |

**البنود القابلة للدمج في دفعة واحدة:** **1** (الملصق) + **2** (`clock-jitter`) + **7** (التنظيفان).
الأول لا يمسّ منطق التشغيل، والثاني معزول في فرع VOD وقابل للتراجع بسطر، والثالث بلا أثر سلوكي.
⚠ **مع ذلك: قِس البند 2 وحده** (مبدئياً قبل الدمج) وإلا لن تعرف أيّ التغييرين حرّك الرقم.

---

# 8. المصادر

**شيفرة VLC الأصلية — `videolan/vlc`، فرع `3.0.x`** (جُلبت خاماً في هذه الجلسة، 2026-07-29)
- `src/libvlc-module.c` — تعريفات وقيم `network-caching` (=1000) · `clock-jitter` (=5000) · `clock-synchro` (=-1) · `input-fast-seek` (=false) · `lua` (=true) · `plugins-cache`
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/libvlc-module.c
- `modules/access/http.c` — `add_bool("http-reconnect", false, …)` ومعالجة 301/302/303/307 عبر `VLC_ACCESS_REDIRECT` + `goto disconnect`
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/access/http.c
- `modules/demux/mkv/matroska_segment_parse.cpp` — `ParseSeekHead()` وقراءة `KaxSeekPosition` وموضع الـ Cues
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/demux/mkv/matroska_segment_parse.cpp
- `modules/demux/mkv/matroska_segment.cpp` — `LoadSeekHeadItem()` → `es.I_O().setFilePointer( i_element_position, seek_beginning )`
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/demux/mkv/matroska_segment.cpp
- `modules/demux/mkv/mkv.cpp` — خيارات المُفكِّك (`mkv-preload-clusters` = false …)
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/demux/mkv/mkv.cpp
- `modules/stream_filter/prefetch.c` — `prefetch-buffer-size` (1<<14 KiB) · `prefetch-read-size` (1<<24) · `prefetch-seek-threshold` (1<<14) + تعليق «For local files, the operating system is likely to do a better work…»
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/stream_filter/prefetch.c
- `modules/codec/avcodec/avcodec.c` — `add_module("avcodec-hw", "hw decoder", "any", …)` · `avcodec-fast` (=false)
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/codec/avcodec/avcodec.c

**VLCKit — `videolan/VLCKit`، فرع `3.0`**
- `Sources/VLCLibrary.m` — الوسائط الافتراضية على iOS (`--no-video-title-show`, `--http-reconnect`, `--avcodec-fast` مشروطاً بـ`__LP64__`…)
  — https://raw.githubusercontent.com/videolan/VLCKit/3.0/Sources/VLCLibrary.m
- `buildMobileVLCKit.sh` — وسائط `configure`، وفيها **`--disable-lua`**
  — https://raw.githubusercontent.com/videolan/VLCKit/3.0/buildMobileVLCKit.sh
- `Headers/Public/VLCMediaPlayer.h` — كامل الخصائص والبروتوكول (`hasVideoOut`; **لا نداء لأول إطار**) و`initWithOptions:` («new libvlc … memory impact»)
  — https://raw.githubusercontent.com/videolan/VLCKit/3.0/Headers/Public/VLCMediaPlayer.h

**توثيق Apple** (واجهة JSON)
- `AVPlayerItem.preferredForwardBufferDuration` — https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration
- `AVURLAssetPreferPreciseDurationAndTimingKey` — https://developer.apple.com/documentation/avfoundation/avurlassetpreferprecisedurationandtimingkey
- `AVPlayerItem.startsOnFirstEligibleVariant` (iOS 14.0+) — https://developer.apple.com/documentation/avfoundation/avplayeritem/startsonfirsteligiblevariant

**محرّكات مفتوحة المصدر (للمقارنة)**
- `androidx/media` — `DefaultLoadControl.java` (`BUFFER_FOR_PLAYBACK_MS = 1000`)
  — https://raw.githubusercontent.com/androidx/media/release/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/DefaultLoadControl.java
- `mpv-player/mpv` — `etc/builtin.conf` (تشكيلة `[low-latency]`) — https://raw.githubusercontent.com/mpv-player/mpv/master/etc/builtin.conf
- `mpv-player/mpv` — `demux/demux_lavf.c` (`probesize` · `analyzeduration` · `probe-info`) — https://raw.githubusercontent.com/mpv-player/mpv/master/demux/demux_lavf.c
- `kingslay/KSPlayer` — `Sources/KSPlayer/AVPlayer/KSOptions.swift` (`isSecondOpen`، والخيارات الجريئة معلَّقة عمداً) — https://raw.githubusercontent.com/kingslay/KSPlayer/main/Sources/KSPlayer/AVPlayer/KSOptions.swift

**نتائج سلبية موثَّقة**
- مدوّنة Firecore الرسمية — **لا منشور** عن زمن البدء أو التخزين المؤقّت — https://firecore.com/blog
- VidHub · TiviMate — مغلقا المصدر، بلا وثائق هندسية عامّة. **لا ادّعاء.**
- **`WebSearch` نفدت (200/200) قبل هذه الجلسة** — كل ما سبق جُلب مباشرةً من المصدر.

**مصادر داخلية**
- `TECH_ADJUDICATION.md` §2 (الجاهزية · `preroll`) — لا يُعاد
- `TECH_HUNT_V2.md` §3 (`MobileVLCKit 3.7.3`) · §4 (`MediaPrefetcher`) · §5 (`clock-jitter` · رفض `clock-synchro`) — لا يُعاد
- `RESEARCH.md:271–278` (`fail2ban` · `max_connections`) · `PROJECT_HANDOFF.md §9` (P6)
- `git show edd3d82` — نصّ التراجع عن `automaticallyWaitsToMinimizeStalling`
