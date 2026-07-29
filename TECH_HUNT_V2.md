# صيد تقني — الجولة الثالثة (أداء الكتالوج · المشغّل · الصور · التنزيلات)
**بحث هندسي مستقل · 2026-07-29 · Blank Prime (SwiftUI · iOS 17.0 كحدّ أدنى · CocoaPods)**

> **القاعدة الحاكمة (بكلمات المالك):** لا تتبنَّ تقنية من المرجع على الثقة. ابحث عن أحدث ما وصلت
> إليه الصناعة **بالتوازي**، ودَع **الأحدث والأفضل** يفوز — ولو كان ذلك يعني تجاهل المرجع كلّياً.

> **القيود التي التزمتُ بها حرفياً:** `C:\Users\user\Strong8K-App\Strong8K\iOS\` **للقراءة فقط** —
> لم يُنشأ فيه ولم يُعدَّل ولم يُحذف شيء. ولم يُعدَّل أي ملف مصدري في `blankstor`. الملف الوحيد
> المكتوب هو هذا الملف.

> **علاقته بالتقريرين السابقين:** `TECH_ADJUDICATION.md` حكم على ثمانية بنود (FTS من الكاش، جاهزية
> المشغّل، `saveProgress` عند `load`، تحصين سجلّ التنزيلات، رايات AirPlay، `DatabasePool`،
> الـ Keychain، طبقة QoE) وثلاث إضافات. والجولة الثانية من هذا الملف حكمت على خمسة (التصفيح،
> `@Observable`، ميزانية الصور، `PosterCollectionView`، تسليم Turbo). **لا يُعاد أيٌّ من الثلاثة
> عشر بنداً هنا.** هذه الجولة تفتّش في مساحة لم تُفتَّش بعد: **مسار وصول المحتوى الأول**، و**زمن بدء
> المشغّل على المحرّك الذي يشغّل 100% من الأفلام عندنا**، و**نسخة محرّك VLC نفسه**.

---

## 0. جدول الأحكام

| # | البند | الحكم | الفائدة ÷ الخطر | جهد |
|---|-------|-------|------------------|-----|
| **1** | تسليم الكتالوج **تدريجياً لكل نوع** بدل انتظار الحمولة كاملة | **ADOPT THE IDEA, NOT THE IMPLEMENTATION** 🔴 | **الأعلى في التقرير** — تبويب المباشر محجوز اليوم خلف حمولة VOD | 6–8 س |
| **2** | Stale-While-Revalidate حقيقي بدل جُرف الـ TTL عند 12 ساعة | **ADOPT NEWER** 🔴 | عالية جداً · خطر منخفض. والتعليق عندنا **يدّعي** SWR ولا ينفّذها | 3–4 س |
| **3** | ترقية `MobileVLCKit` من 3.6.0 إلى **3.7.3** | **ADOPT NEWER — لا يملكه أيّ من التطبيقين** 🔴 | عالية · **خطر متوسط** (تبديل مُفكِّك شفرة) | 30 د + تحقّق جهاز |
| **4** | `MediaPrefetcher` يُسخّن **المحرّك الخطأ** — مسار ميت يستهلك شبكةً وذاكرة | **خلل حيّ — أصلحه** 🔴 | متوسطة–عالية · **خطر شبه صفر** (سطر واحد) | 15 د |
| **5** | `:clock-jitter=0` لـ VOD فقط · و**رفض** `:clock-synchro=0` | **ADOPT REFERENCE — مجزوءاً** | متوسطة · منخفض | 20 د |
| **6** | مهلة `get_vod_streams` من 22 ث إلى 45 ث | **ADOPT REFERENCE** | متوسطة · صفر | 5 د |
| **7** | قراءة كاش الكتالوج بـ `.mappedIfSafe` | **ADOPT NEWER (صغير)** | منخفضة–متوسطة · صفر | 5 د |
| **8** | كاش الصور على القرص يعتمد كلّياً على `URLCache` | **قِس أولاً — لا تبنِ بعد** | غير معروفة حتى تُقاس | — |
| **9** | `waitsForConnectivity` على جلسة الخلفية **لا أثر له** (موثَّق) | **KEEP OURS + وثّق** | صفر عملياً | 2 د |
| **10** | حفظ EPG في SQLite (`saveEPG`/`epgGuide` عند المرجع) | **مؤجَّل — خارج أولويات المالك** | منخفضة | 3 س |

**السطر الواحد:** أخطر ما وجدتُه ليس في الشيفرة التي تعمل، بل في **الترتيب**: التطبيق يجعل المستخدم
ينتظر أضخم حمولة في النظام (`get_vod_streams`) قبل أن يرى **أي** شيء — حتى قناة مباشرة. البند 1
والبند 2 معاً يعالجان هذا. والبند 3 هو أعلى فائدة لكل دقيقة عمل في التقرير كلّه: **سطر واحد في
`Podfile`** يرفعنا من مُفكِّك شفرة عمره سنتان إلى آخر إصدار مستقرّ.

---

## 0.1 تحذير عن المصادر — اقرأه قبل أن تثق بأي سطر

- **ميزانية البحث النصّي على الويب (`WebSearch`) نفدت في هذه الجلسة** (200/200). كل ادّعاء خارجي
  أدناه مأخوذ **من مصدر أوّليّ مباشرةً** عبر جلب الصفحة أو الملف: شيفرة VLC الأصلية من مستودع
  `videolan/vlc` على GitHub، وملف `NEWS` الرسمي، وواجهة CocoaPods trunk البرمجية، وواجهة GitHub
  البرمجية، وواجهة توثيق Apple بصيغة JSON. **لا مدوّنات، ولا مصادر ثانوية، ولا شيء قبل 2024 إلا
  موسوماً.**
- **كل ادّعاء عن شيفرتنا أو عن المرجع متحقَّق منه بالقراءة المباشرة، ومعه `file:line`.** هذا أقوى
  جزء في التقرير ولا يعتمد على أي مصدر خارجي.
- حيث لم أجد مصدراً أوّلياً أقول ذلك صراحةً بعبارة **«غير متحقَّق منه»** بدل ملء الفراغ.
- الفريق **لا يستطيع الترجمة محلّياً**. كل مقترح أدناه مكتوب بشيفرة كاملة وآمنة، ولا يستعمل أي API
  فوق `iOS 17.0` (`Podfile:2`).

---

# البند 1 — تسليم الكتالوج تدريجياً لكل نوع

## الحكم: **ADOPT THE IDEA, NOT THE IMPLEMENTATION** 🔴 — الفكرة عند المرجع صحيحة، وتنفيذه غير قابل للنقل

## المشكلة المتحقَّق منها في شيفرتنا — وهي جذر شكوى «ثلاث دقائق»

كل مستهلكي المحتوى في التطبيق يمرّون عبر **دالّة واحدة تعيد كائناً واحداً**:

```swift
// BlankTV/Core.swift:2345–2365
static func liveCategories()  async throws -> [Category] { try await PlaylistService.shared.load().liveCategories }
static func liveStreams()     async throws -> [Channel]  { try await PlaylistService.shared.load().channels }
static func movies()          async throws -> [Movie]    { try await PlaylistService.shared.load().movies }
static func series()          async throws -> [Series]   { try await PlaylistService.shared.load().series }
```

و`PlaylistService.load` (`Core.swift:1751–1758`) مهمّة **واحدة مشتركة** (single-flight)، و`_load`
تنتهي إلى `loadXtreamDirect` (`Core.swift:2072–2182`) التي **تنتظر الستّة كلّها قبل أن تعود بأي
شيء**:

```swift
// BlankTV/Core.swift:2109–2129
async let liveStreamsData = apiData(xd, action: "get_live_streams")
async let vodStreamsData  = apiData(xd, action: "get_vod_streams")     // ← أضخم حمولة في النظام
async let seriesData      = apiData(xd, action: "get_series")
let liveRaw = try? await liveStreamsData
let vodRaw  = try? await vodStreamsData      // ← الحاجز الحقيقي
let serRaw  = try? await seriesData
…
return c                                      // ← لا شيء يخرج قبل هذا السطر
```

### 🔴 والنتيجة: شاشة الإقلاع عندنا تعرض تقدّماً وهمياً

`HomeVM.bootLoad` (`HomeView.swift:169–204`) يقول في تعليقه حرفياً:

> *«Parallel boot load … each flipping its own progress flag as it finishes — so total time ≈ the
> slowest request, not the sum of all three.»*

**والتعليق صحيح على مستواه، وبلا معنى في الواقع.** الثلاثة (`loadChannels`, `loadMovies`,
`loadSeries`) تنتظر كلها **نفس** `PlaylistService.shared.load()`، وتلك تنتظر الستّة. أي أن
`doneChannels` و`doneMovies` و`doneSeries` **تنقلب كلها في اللحظة نفسها تقريباً**. المستخدم يرى ثلاثة
مؤشّرات تتحرّك معاً في النهاية، بعد أن انتظر أبطأ شيء في النظام.

**الحساب:** `get_live_streams` على خطّ نموذجي يعود في ~1–2 ثانية (بضعة آلاف قناة). و
`get_vod_streams` بحمولة 100 ألف عنوان يعود في 20–45 ثانية على 4G، وقد يبلغ المهلة (البند 6).
**نحن ندفع الثاني لنعرض الأول.**

## ما يفعله المرجع

`CatalogCentral` (`Strong8K/iOS/Strong8K/Core.swift:3265–3269`) يعرّف ثلاثة مسارات سريعة لكل نوع،
وتعليقه يصف بالضبط ما نفتقده:

```swift
/// Per-kind fast paths (live-first / progressive): each fetches ONLY its kind's light snapshot,
/// so the tabs render independently (live in ~1s) instead of waiting for the full 16MB catalog.
static func liveChannels(_ xd: XtreamDirect) async -> [Channel]? { await build(xd: xd, kinds: ["live", "cat_live"], suffix: ":live")?.channels }
static func vodMovies(_ xd: XtreamDirect)  async -> [Movie]?   { await build(xd: xd, kinds: ["vod", "cat_vod"], suffix: ":vod")?.movies }
static func seriesList(_ xd: XtreamDirect) async -> [Series]?  { await build(xd: xd, kinds: ["series", "cat_series"], suffix: ":series")?.series }
```

## لماذا **لا** يُنقل تنفيذه — ولماذا فكرته تُنقل رغم ذلك

- **تنفيذه غير قابل للنقل بنيوياً.** يعتمد كلّياً على خادمه: `/v2/catalog/snapshot?kinds=…`
  (`Core.swift:3316–3328`) ومصادقة `X-App-Key` بمفتاح **مكتوب في الشيفرة**
  (`ActivationService.swift:16`) — وهو ما حظرته الجولة الثانية صراحةً. وقد قطعنا الاتصال بـ `/v2`
  عمداً (`PROJECT_HANDOFF §11`).
- **لكن فكرته لا تحتاج خادمه إطلاقاً.** واجهة Xtream **أصلاً** تفصل الأنواع: `get_live_streams`
  و`get_vod_streams` و`get_series` نداءات مستقلّة تماماً. الحاجز عندنا **ليس في الشبكة، بل في
  توقيع الدالّة**: نجمع ثلاث استجابات مستقلّة في كائن واحد ثم نسلّمه دفعة واحدة.

## هل هناك ما هو أحدث في 2026؟

**لا يوجد API جديد يحلّ هذا نيابةً عنك، والحلّ الحديث هو تصميمي لا واجهيّ.** فحصتُ ثلاثة بدائل:

- **`AsyncStream` / `AsyncSequence`** — الأداة الطبيعية لبثّ نتائج جزئية، وهي متاحة على iOS 17 بلا
  أي شرط. لكن تحويل `PlaylistService` كلّه إلى بثّ يعني إعادة كتابة سبعة نماذج عرض، وهذا **خطر
  أعلى مما يشتريه**. المسار الأقل خطراً هو نشر النتائج الجزئية على المُمثِّل ثم إيقاظ المنتظرين.
- **`TaskGroup` بنتائج جزئية** — يعطي نفس الأثر بصياغة أنظف، لكنه يتطلّب أن يكون المستهلك حلقةً،
  وهو ليس شكل `ContentService` عندنا.
- **`URLSession.bytes(for:)` + فكّ JSON تدريجي** — يسمح ببدء البناء قبل وصول آخر بايت. ⚠ **لكن
  Foundation لا تملك مُحلّل JSON تدفّقياً**: لا `JSONDecoder` ولا `JSONSerialization` يقبلان تغذية
  جزئية. تنفيذه يعني كتابة مُحلِّل، وهو خطر غير مبرَّر. **لا توصية.**

> **الخلاصة:** فكرة المرجع (تسليم لكل نوع) هي الصحيحة في 2026، وتنفيذه ليس كذلك. **ننفّذ الفكرة
> بأدواتنا.**

## سكتش التنفيذ — أقلّ تغيير بأكبر أثر

الفكرة: أبقِ `load()` كما هي تماماً (فلا يُكسر أي مستدعٍ)، وأضِف **مساراً موازياً للمباشر فقط** —
لأنه أخفّ حمولة وأول ما يريده المستخدم.

**`BlankTV/Core.swift` — داخل `actor PlaylistService`:**

```swift
/// النتيجة الجزئية للقنوات المباشرة، منشورة فور وصولها ودون انتظار حمولة VOD.
/// السبب: `_load` لا تعود قبل أن تكتمل الستّة (Core.swift:2109–2129)، و`get_vod_streams`
/// على خطّ بـ 100 ألف عنوان يستغرق 20–45 ثانية — فتبويب المباشر ينتظر شيئاً لا يحتاجه.
private var liveOnly: (cats: [Category], channels: [Channel])?
private var liveWaiters: [CheckedContinuation<(cats: [Category], channels: [Channel]), Never>] = []

/// يُستدعى من داخل `loadXtreamDirect` بمجرّد أن تصل قائمة المباشر.
private func publishLive(_ cats: [Category], _ channels: [Channel]) {
    guard liveOnly == nil else { return }          // أوّل نشرة فقط؛ الحمل الكامل يصحّحها لاحقاً
    liveOnly = (cats, channels)
    let ws = liveWaiters; liveWaiters = []
    for w in ws { w.resume(returning: (cats, channels)) }
}

/// القنوات المباشرة بأسرع ما يمكن: من الحمل الكامل إن كان جاهزاً، وإلا من النشرة الجزئية.
func liveFast() async -> (cats: [Category], channels: [Channel]) {
    if let c = content { return (c.liveCategories, c.channels) }   // الحمل الكامل جاهز
    if let l = liveOnly { return l }
    // شغّل الحمل الكامل في الخلفية إن لم يكن يعمل، ثم انتظر النشرة الجزئية فقط.
    if inFlight == nil { Task { _ = try? await self.load() } }
    return await withCheckedContinuation { c in liveWaiters.append(c) }
}
```

**وداخل `loadXtreamDirect` (`Core.swift:2142`، مباشرةً بعد حلقة بناء القنوات):**

```swift
        }
        // ⬇ جديد: انشر المباشر الآن. حمولتا VOD والمسلسلات لا تزالان في الطريق،
        // ولا علاقة لهما بهذا التبويب.
        publishLive(c.liveCategories, c.channels)
```

⚠ **لكن انتبه:** `async let` في Swift **لا يبدأ التنفيذ عند التصريح فقط، بل تُنتَظر النتيجة عند
`await`**. في شيفرتنا الحالية `let liveRaw = try? await liveStreamsData` يقع **قبل** انتظار VOD
(`Core.swift:2120–2122`)، فترتيب الأسطر صحيح أصلاً وحلقة بناء القنوات تُنفَّذ قبل أن يُنتظر أي شيء
آخر — **بشرط ألّا يُعاد ترتيب تلك الأسطر الثلاثة أبداً.** وثّق ذلك بتعليق صريح عند `:2120`.

**والوصلة في `HomeVM`** (`HomeView.swift:184–188`):

```swift
private func loadChannels() async {
    // liveFast تعود عند وصول قائمة المباشر، لا عند اكتمال الكتالوج كلّه.
    // بهذا يصير مؤشّر التقدّم الثلاثي في شاشة الإقلاع صادقاً بدل أن ينقلب دفعةً واحدة.
    let l = await PlaylistService.shared.liveFast()
    liveChannels = l.channels
    doneChannels = true
}
```

## الفائدة، وكيف تُقاس

| ما يُقاس | كيف | المتوقَّع |
|---|---|---|
| زمن ظهور أول قناة بعد تسجيل الدخول | ساعة إيقاف على جهاز حقيقي، خطّ ذو 100 ألف عنوان VOD | من «زمن VOD» إلى ~1–2 ث |
| صدق مؤشّر التقدّم | مشاهدة: هل تنقلب الثلاثة معاً؟ | يجب أن ينقلب المباشر أولاً |
| زمن الإقلاع | `MXAppLaunchMetric` عبر MetricKit القائم (`Diagnostics.swift`, مُستدعىً من `BlankTVApp.swift:167`) | يجب ألّا يسوء |

- **الجهد:** 6–8 ساعات. **الخطر:** **متوسط** — يمسّ المُمثِّل الأكثر سخونة في التطبيق.
  **يحتاج موافقة المالك** بحسب بروتوكول المراحل. **لا تنفّذه في نفس البناء مع البند 2.**

---

# البند 2 — Stale-While-Revalidate حقيقي

## الحكم: **ADOPT NEWER** 🔴 — المرجع يملك نصف الآلية، والتعليق عندنا يَعِد بما لا يفعله

## الخلل المتحقَّق منه

عنوان القسم في شيفرتنا يقول حرفياً (`BlankTV/Core.swift:1593`):

```swift
// CATALOG DISK CACHE — instant cold-start (stale-while-revalidate)
```

**والتنفيذ ليس stale-while-revalidate.** إنه جُرفُ TTL صلب:

```swift
// BlankTV/Core.swift:1725–1731
static func load(scope: String) -> M3UContent? {
    guard let url = fileURL(scope), let data = try? Data(contentsOf: url),
          let env = try? JSONDecoder().decode(Envelope.self, from: data),
          Date().timeIntervalSince1970 - env.savedAt < ttl else { return nil }   // ← 12 ساعة، ثم لا شيء
    …
}
```

و`_load` (`Core.swift:1770–1776`) إمّا يعود بالكاش **أو** يذهب إلى الشبكة — ولا يوجد طريق ثالث:

```swift
if !force, let cached = CatalogDiskCache.load(scope: urlString) {
    content = cached
    if let xd = XtreamDirect.parse(urlString) { xtream = xd }
    return cached                    // ← يعود، ولا يُحدِّث شيئاً بعد ذلك أبداً
}
```

**فينشأ سلوكان سيّئان معاً:**

1. **بعد 12 ساعة وثانية**، مستخدمٌ يملك كتالوجاً كاملاً على قرصه ينتظر الشبكة من الصفر. وهذه هي
   الحالة الشائعة: من يفتح التطبيق مرّة في اليوم يقع **دائماً** خارج النافذة.
2. **داخل الـ 12 ساعة**، الكتالوج **لا يُحدَّث أبداً** ولو أضاف المزوّد ألف عنوان. ولا يوجد عندنا
   أي تحديث عند العودة إلى المقدّمة: `onChange(of: scenePhase)` (`BlankTVApp.swift:184–188`) يستدعي
   `validateSession()` و`ActivationService.check()` **فقط**.

## ما يفعله المرجع

يملك النصف الأول: `CatalogDiskCache.loadStale(scope:)` (`Strong8K/iOS/Strong8K/Core.swift:1731–1736`)
— نفس `load` بلا فحص TTL — و`exists(scope:)` (`:1721–1726`)، فحص وجود **بلا فكّ ترميز** يقرأ حجم
الملف فقط، وتعليقه: *«Used by instant-entry to decide "returning user → enter now" without paying the
decode.»*

ويملك النصف الثاني في `CentralRefresh.onForeground()` (`Core.swift:3414–3435`): إعادة تحقّق عند
العودة إلى المقدّمة، **بمانع ارتداد 10 دقائق** وحارس `running` يمنع التداخل.

**لكن حارس صلاحيته `CatalogCentral.hasBump(host:)` — نداء إلى خادمه.** غير قابل للنقل.

## هل هناك ما هو أحدث؟

- **النمط نفسه معياريّ ومسمّى:** `stale-while-revalidate` معرَّف في
  [RFC 5861](https://www.rfc-editor.org/rfc/rfc5861) — «HTTP Cache-Control Extensions for Stale
  Content». ⚠ **المعيار من 2010، وأنا أعامله كمصدر قديم عمداً**: لا أستشهد به كـ«أحدث ممارسة»،
  بل كدليل على أن هذا **مصطلح معياري له دلالة محدّدة**، وأن تعليقنا يستعمله بغير معناه.
- **هل تستطيع `URLCache` أن تفعلها نيابةً عنا؟ لا.** لوحات IPTV **لا ترسل ترويسات تخزين مؤقّت**
  أصلاً (لا `Cache-Control` ولا `ETag` ولا `Last-Modified`) — والنداءات `player_api.php` استعلامات
  ديناميكية. آلية HTTP بلا ترويسات لا تفعل شيئاً. الحلّ يدويّ بالضرورة.
- **هل يوجد بديل «صحّة الخادم» بلا خادمنا؟ نعم، ورخيص.** واجهة Xtream تعرض `user_info` في نداء
  `player_api.php` بلا `action` — وهو النداء الذي نستعمله أصلاً في `validateAuth`
  (`Core.swift:2048`, بمهلة 12 ث). لكنه **لا يحمل رقم نسخة كتالوج**، فلا يوجد مكافئ لـ`hasBump`.
  ⚠ **غير متحقَّق منه:** لم أجد حقلاً معياريّاً في Xtream يعطي نسخة الكتالوج. **لذلك: لا تبنِ بوّابة
  نسخة — أعِد التحقّق بمانع ارتداد زمني، وهو أبسط وأصدق.**

> **الخلاصة:** لا يوجد API أحدث. المرجع يملك القطعتين لكن مربوطتين بخادمه. **نأخذ الشكل ونرمي
> الرباط.**

## سكتش التنفيذ

**(أ) `BlankTV/Core.swift` — أضِف إلى `enum CatalogDiskCache` (بجوار `load`, `:1731`):**

```swift
/// نفس `load` **بلا** فحص الـ TTL. الطازجة تحكمها إعادة التحقّق في الخلفية، لا الساعة:
/// كتالوج عمره 13 ساعة أفضل بما لا يُقاس من شاشة فارغة تنتظر الشبكة.
/// nil فقط إن كان الملف مفقوداً أو فارغاً أو تالفاً.
static func loadStale(scope: String) -> M3UContent? {
    guard let url = fileURL(scope),
          // .mappedIfSafe: الملف عشرات الميغابايتات على خطٍّ كبير — انظر البند 7.
          let data = try? Data(contentsOf: url, options: .mappedIfSafe),
          let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
    let c = content(from: env)
    return (c.channels.isEmpty && c.movies.isEmpty && c.series.isEmpty) ? nil : c
}

/// عمر الكاش بالثواني، بلا فكّ ترميز — لقرار «هل أعيد التحقّق؟».
/// nil إن لم يوجد ملف. يقرأ سمة نظام الملفات فقط، فهو مجّاني عملياً.
static func age(scope: String) -> TimeInterval? {
    guard let url = fileURL(scope),
          let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let mod = attrs[.modificationDate] as? Date else { return nil }
    return Date().timeIntervalSince(mod)
}
```

**(ب) `BlankTV/Core.swift` — بدّل كتلة الكاش في `_load` (`:1770–1776`) بهذه:**

```swift
// STALE-WHILE-REVALIDATE. سابقاً كان هذا جُرفاً: بعد 12 ساعة يعود `load` بـ nil ويقف
// المستخدم أمام شاشة فارغة بينما كتالوج كامل يرقد على قرصه. والأسوأ أنه **داخل**
// النافذة لم يكن يُحدَّث أبداً. الآن: اخدم المحفوظ فوراً دائماً، ثم أعِد التحقّق في
// الخلفية إن تجاوز عمره النافذة. المستخدم لا ينتظر الشبكة في أي من الحالتين.
if !force, let cached = CatalogDiskCache.loadStale(scope: urlString) {
    content = cached
    if let xd = XtreamDirect.parse(urlString) { xtream = xd }
    let age = CatalogDiskCache.age(scope: urlString) ?? .greatestFiniteMagnitude
    if age > CatalogDiskCache.ttl, !revalidating {
        revalidating = true
        // مُنفصلة تماماً عن هذا الإرجاع: تجلب، وتُحدِّث `content`، وتكتب الكاش.
        // فشلها لا يكلّف المستخدم شيئاً — المحفوظ يظلّ معروضاً.
        Task { [weak self] in
            defer { Task { await self?.endRevalidate() } }
            _ = try? await self?.load(force: true)
        }
    }
    return cached
}
```

**وأضِف إلى `PlaylistService`:**

```swift
/// حارس إعادة التحقّق. بدونه: كل مستدعٍ يجد الكاش قديماً يُطلق جلبةً كاملة،
/// وسبعة نماذج عرض تعني سبع جلبات لكتالوج واحد على لوحةٍ تُقيّد المعدّل.
private var revalidating = false
private func endRevalidate() { revalidating = false }
```

⚠ **مأخذٌ يجب أن يُقرأ قبل التنفيذ — وهو المصيدة التي وثّقها المرجع بنفسه:**
`load(force: true)` تُطلق `CatalogDB.save` **مُنفصلة** (`Core.swift:1803`) وتعود **قبل** أن تُودَع
المعاملة. تعليق المرجع عند `Core.swift:3427–3429` يصف العاقبة حرفياً:

> *«PlaylistService fires its save DETACHED and returns before it commits, so the serialized
> DatabaseQueue could hand loadPaged() the OLD rows.»*

فإن نُفِّذ البند 1 من الجولة الثانية (القراءة المُصفَّحة) لاحقاً، **يجب أن تُنتظر الكتابة** قبل
إعادة تحميل التبويبات، كما يفعل هو عند `:3431`.

⚠ **ومأخذ ثانٍ:** `loadStale` **لا يجوز** أن تخدم كتالوجاً موسوماً `isPartial`. الحارس موجود عندنا
على الكتابة (`Core.swift:1791`) — لا تُضعِفه على القراءة.

- **الجهد:** 3–4 ساعات. **الخطر:** منخفض. **الفائدة:** يزيل انتظار الشبكة من **كل** إقلاع بارد
  لمستخدم عائد، ويُدخل أول تحديث تلقائي للكتالوج في تاريخ التطبيق.

---

# البند 3 — ترقية `MobileVLCKit` من 3.6.0 إلى 3.7.3

## الحكم: **ADOPT NEWER** 🔴 — **ولا يملكه أيٌّ من التطبيقين. هذا حكمٌ ضدّ المرجع وضدّنا معاً.**

## الحقيقة المتحقَّق منها

```ruby
# blankstor/Podfile:8   — ونفس السطر حرفياً في Strong8K/iOS/Podfile:8
pod 'MobileVLCKit', '~> 3.6.0'
```

عامل `~>` مع ثلاثة مقاطع يعني `>= 3.6.0, < 3.7.0`. **أي أننا محبوسون خارج كل 3.7.x بحكم الصياغة،
لا بحكم قرار.**

**وما هو منشور فعلاً** (من واجهة CocoaPods trunk الرسمية، `trunk.cocoapods.org/api/v1/pods/MobileVLCKit`):

| الإصدار | تاريخ النشر |
|---|---|
| 3.6.0 | 2023 |
| 3.6.1b1 | 2024-06-23 |
| **3.7.0** | **2025-12-04** |
| 3.7.1 | 2026-01-07 |
| 3.7.2 | 2026-01-21 |
| **3.7.3** | **2026-02-25** |

**وما تغيّر بينهما** (من واجهة GitHub، `compare/3.6.0...3.7.3` على `videolan/VLCKit` — 20 دفعة):

```
2024-06-22  libvlc: update to ac310b4b
2025-04-09  VLCLibrary: Add currentErrorMessage class property
2025-08-06  libvlc: update to latest 3.0.x head
2025-12-01  libvlc: update to 3.0.22
2026-01-02  libvlc: update to 3.0.23
2026-01-21  libvlc: backport prefetch cancellation simplification
2026-02-24  libvlc: add patch to prevent crashes on NULL MRLs
```

**ولماذا يهمّنا هذا تحديداً؟** لأن `StreamRouter.defaultEngine` (`StreamRouter.swift:45–49`) يرسل
**كل** VOD وكل ملف محلّي إلى VLC. أي أن **100% من الأفلام والحلقات في هذا التطبيق تُفكَّك شفرتها
بهذا المُفكِّك بالذات** — وهو اليوم بناءٌ من يونيو 2024.

**وما يحمله التحديث، من ملف `NEWS` الرسمي في `videolan/vlc` فرع `3.0.x`:**

*بين 3.0.21 و3.0.22:*
- `Multiple fixes in MPEG-TS` ← **حاويةُ كل قناة مباشرة على لوحات Xtream**
- `Fix crashes in multiple demuxers (reported by rub.de, oss-fuzz and others) Including fixes for malformed WAV, VOC, MMS, ASF and AVI files`
- `Prevent FLAC seeking logic get stuck`
- `Fix hardware decoding with VideoToolbox of XVID MPEG-4 video` ← **فكّ شفرة عتاديّ على iOS**
- `Fix playback of very short ASF files`

*بين 3.0.22 و3.0.23:*
- `Security: Fix null deref in libass, undefined shift in theora and cc-708, integer overflow in daala, Infinite loop in h264 parsing, buffer overflow in png and multiple format-overflows`
- `Fix malformed stream handling in Blu-ray, WebVTT and subtitle modules`

> **«ملفات مشوّهة» و«بثّ مشوّه» ليستا حالتين نادرتين في تطبيق IPTV — إنهما يوم العمل العادي.**
> لوحات المزوّدين ترسل TS بغير ترويسات صحيحة، وMKV بفهارس ناقصة، وترجمات بترميزات عجيبة. هذه
> الإصلاحات مكتوبة لنا حرفياً.

## هل الأحدث فعلاً هو 3.7.3؟ — نعم، مع تحفّظ واضح على 4.x

- `MobileVLCKit 4.0.0a2` منشور منذ **2023-03-07** — و**«a2» تعني alpha**. وأحدث وسم 4.x في المستودع
  هو `4.0.0-a22`، ولم يُنشَر إلى CocoaPods. **لا تقترب من 4.x**: ألفا، وواجهته البرمجية تغيّرت
  (تسمية `VLCKit` الموحّدة بدل `MobileVLCKit`)، وستكسر `VLCPlayer.swift` كلّه.
- **إذن 3.7.3 هو آخر مستقرّ، والقفزة داخل نفس الخطّ الرئيسي (3.x).** واجهة `VLCMediaPlayer` /
  `VLCMedia` / `addOption` التي نستعملها لم تتغيّر.

## الثمن — بصراحة

| البند | التقييم |
|---|---|
| **تبعية جديدة؟** | **لا.** نفس الـ pod، نفس الاسم، رقم أعلى. |
| **الترخيص** | `LGPL v2.1` في الحالتين — بلا تغيير في التزاماتنا. |
| **خطر مراجعة App Store** | **بلا تغيير.** نفس المُورِّد ونفس الأطر المرتبطة (تحقّقتُ من الـ podspec: `QuartzCore, CoreText, AVFoundation, Security, CFNetwork, AudioToolbox, OpenGLES, CoreGraphics, VideoToolbox, CoreMedia` — مطابقة). |
| **حجم الثنائية** | ⚠ **غير متحقَّق منه.** الـ podspec يشير إلى `xcframework` مُسبَق البناء، ولم أستطع قياس حجمه دون تنزيله. **مقارنة `.ipa` قبل/بعد إلزامية** قبل الرفع (وميزانية الرفع اليومية محدودة — انظر [[testflight-upload-limit]]). |
| **الصيانة** | **تنخفض.** نحن اليوم على بناءٍ لن يتلقّى إصلاحات أمنية. |
| **الخطر الحقيقي** | **تبديل مُفكِّك شفرة.** إصلاح في MPEG-TS قد يغيّر سلوك قناةٍ كانت تعمل «بالصدفة». |

## سكتش التنفيذ

**`blankstor/Podfile:8`:**

```ruby
  # Stable production VLC engine. مُثبَّت على 3.7.3 (2026-02-25) لا `~> 3.6.0`:
  # ذلك العامل يعني `< 3.7.0`، فكان يحبسنا على libvlc من يونيو 2024 بينما
  # 3.7.x تحمل libvlc 3.0.23 — وفيه "Multiple fixes in MPEG-TS" (حاوية كل قناة
  # مباشرة عندنا)، وإصلاحات انهيار في المُفكِّكات على الملفات المشوّهة، وإصلاحات
  # أمنية. StreamRouter يرسل 100% من الـ VOD إلى هذا المحرّك. مصدر: videolan/vlc NEWS.
  # ⚠ لا تقفز إلى 4.x: أحدث ما نُشر منها alpha (4.0.0a2, 2023) وواجهتها مختلفة.
  pod 'MobileVLCKit', '3.7.3'
```

ثم `pod update MobileVLCKit` وارفع `Podfile.lock` مع التغيير.

## بروتوكول التحقّق الإلزامي (فالفريق لا يترجم محلّياً)

هذا البند **لا يجوز** أن يُشحن مع أي بند آخر. قائمة الفحص على جهاز حقيقي بعد البناء:

1. قناة مباشرة (HLS) — تفتح وتعمل.
2. قناة مباشرة (TS) — تفتح وتعمل. **هذا هو الفحص الحرج.**
3. فيلم `.mkv` — يفتح، ويقبل القفز ±10، ويحفظ الموضع.
4. فيلم `.mp4` — نفسه.
5. مسار الترجمات ومسار الصوت البديل — القائمتان تُملآن.
6. ملف منزَّل محلّياً — يعمل بلا شبكة.
7. الانتقال التلقائي بين المحرّكين لا يزال يعمل.

- **الجهد:** 30 دقيقة عمل + جولة تحقّق. **الخطر:** **متوسط**، ومحصور تماماً في المشغّل.

---

# البند 4 — `MediaPrefetcher` يُسخّن المحرّك الخطأ

## الحكم: **خلل حيّ — أصلحه** 🔴 — وهذا **ليس** سؤال «أحدث»، بل تناقضٌ داخلي متحقَّق منه

## البرهان — ثلاثة أسطر تكفي

**١) نُسخّن `AVPlayer` لكل فيلم يُفتح:**
```swift
// BlankTV/ContentViews.swift:2593  (داخل .task لصفحة تفاصيل الفيلم)
MediaPrefetcher.shared.prefetch(.movie(movie))   // warm the stream while the page loads
```
و`MediaPrefetcher.prefetch` (`MediaPrefetcher.swift:27–45`) يبني `AVURLAsset` + `AVPlayerItem` +
`AVPlayer` ويبدأ التخزين المؤقّت فعلياً.

**٢) لكن روابط أفلام Xtream عندنا ليست HLS إطلاقاً:**
```swift
// BlankTV/Core.swift:1588
func movieURL(id: String, ext: String) -> String { "\(base)/movie/\(user)/\(pass)/\(id).\(ext)" }
```
حيث `ext` = `container_extension` من اللوحة (`Core.swift:2147`) — أي `mkv` أو `mp4` أو `avi`.

**٣) و`StreamRouter` يرسل كل ما ليس HLS إلى VLC:**
```swift
// BlankTV/StreamRouter.swift:45–49
static func defaultEngine(for item: ContentItem) -> PlayerEngineKind {
    let s = classify(item)
    if s.isLocalFile { return .vlc }
    return s.container == .hls ? .av : .vlc        // ← فيلم .mkv/.mp4 ⇒ .vlc دائماً
}
```

**والاستهلاك الوحيد للتسخين يقع داخل `AVPlayerVM` فقط:**
```swift
// BlankTV/PlayerEngine.swift:330
if let warm = MediaPrefetcher.shared.take(for: item) { pItem = warm }
```

### النتيجة، وهي قاطعة

`PlayerEngineSelector.initialKind` (`PlayerEngine.swift:757–768`) يختار `.av` لفيلم في حالتين فقط:
تفضيل صريح من المستخدم (`playerEnginePref == "av"`)، أو ذاكرة قرار سابقة `.av` — **وتلك لا تُكتَب إلا
بعد نجاح على AVPlayer، أي بعد التفضيل الصريح أو انتقالٍ فاشل من VLC**. وفي التهيئة الافتراضية:
**`take(for:)` لا تُستدعى أبداً، ويُهدَر كل تسخين.**

**والثمن الفعلي:**
- **بيانات وبطارية.** كل فتحة صفحة تفاصيل فيلم تبدأ تنزيلاً لن يُستعمل. تصفّح 20 فيلماً = 20 بدايةً
  مهدورة (السقف `cap = 2` يحدّ الذاكرة **لا** الشبكة: المطرود قد بدأ التنزيل فعلاً،
  `MediaPrefetcher.swift:40–43`).
- **ذاكرة.** مشغّلان دافئان يُخزّنان فيديو VOD، وهما بالضبط ما وصفته الجولة الثانية بأنه أخطر ما
  يبقى حيّاً تحت ضغط الذاكرة (بند 3 هناك).

## هل هناك «أحدث» هنا؟ — السؤال غير ذي موضوع

هذا **تناقض توجيه داخليّ**، لا اختيار API. لا توجد واجهة في iOS 17/18/26 تجعل `AVPlayer` يسخّن
مسارَ VLC. والمرجع يملك المشكلة نفسها (`PlayerEngine.swift`: `prefetch`/`take` موجودتان عنده أيضاً)
— **إذن هذا ليس بنداً يُنقل من المرجع، بل خللٌ ورثناه معه.**

## الخياران — واختَر واحداً، لا نصفاً

**(أ) الحلّ الأصغر والأصحّ اليوم — سطر واحد. `BlankTV/ContentViews.swift:2593`:**

```swift
// سخّن فقط إن كان المحرّك الذي سيُشغّل هذا العنصر فعلاً هو AVPlayer.
// StreamRouter يوجّه كل VOD غير HLS إلى VLC (StreamRouter.swift:45–49)، وروابط
// أفلام Xtream تنتهي بـ .mkv/.mp4 (Core.swift:1588) — فالتسخين في التهيئة
// الافتراضية كان يُبنى ثم يُرمى، ويكلّف بياناتٍ وبطاريةً وذاكرةً بلا مقابل.
// `take` تُستدعى من AVPlayerVM وحده (PlayerEngine.swift:330).
if PlayerEngineSelector.initialKind(for: .movie(movie)) == .av {
    MediaPrefetcher.shared.prefetch(.movie(movie))
}
```

**(ب) الحلّ الأكبر (لاحقاً، وبموافقة):** بناء مكافئ للتسخين على VLC. ⚠ **ولا توجد له طريقة نظيفة:**
`VLCMediaPlayer` لا يفصل «التحضير» عن «التشغيل»، و`VLCMedia.parse` تقرأ البيانات الوصفية لا الحمولة.
الأقرب هو `libvlc` وخيار `:start-paused`، وهو **غير مختبر عندنا** و**سيبني مُفكِّك شفرة كاملاً في
الخلفية** — كلفة ذاكرة أعلى بكثير من `AVPlayer`. **توصيتي: لا تبنِه. نفّذ (أ) واكتفِ.**

- **الجهد:** 15 دقيقة. **الخطر:** شبه معدوم. **الفائدة:** توقّف نزيفٍ صامت في البيانات والذاكرة.
  **هذا أعلى بند «فائدة ÷ خطر» في التقرير.**

---

# البند 5 — خيارا الساعة في VLC: واحدٌ يُتبنّى مجزوءاً، وآخر يُرفض

## الحكم: **ADOPT REFERENCE — مجزوءاً**، بعد قراءة شيفرة VLC الأصلية

## ما يفعله المرجع، وما ندّعيه نحن

`Strong8K/iOS/Strong8K/VLCPlayer.swift:283–284` — يضيفهما **لكل وسيط، مباشراً كان أو VOD**:

```swift
media.addOption(":clock-jitter=0")
media.addOption(":clock-synchro=0")
```

وتعليقه (`:277–282`) يحمل **بيانات ميدانية تخصّنا مباشرةً**:

> *«Field data showed VOD/VLC TTFF ~16s vs AVPlayer ~4s. clock-jitter=0 shrinks the drift-acceptance
> window (default 5000ms) and clock-synchro=0 disables input clock sync for these provider streams
> → the first frame lands sooner.»*

**ونحن لا نملك أيّاً منهما** (`BlankTV/VLCPlayer.swift:259–293`).

## البحث — ولم أعتمد على تعليق المرجع، بل قرأتُ شيفرة VLC

من `videolan/vlc` فرع `3.0.x` (المصدر الأوّليّ، لا وثيقة ثانوية):

**`src/libvlc-module.c` — التعريفات والقيم الافتراضية:**
```c
add_integer( "network-caching", CLOCK_FREQ / 1000, … )   /* = 1000 ms */
add_integer( "clock-jitter", 5 * CLOCK_FREQ/1000, … )    /* = 5000 ms */
add_integer( "clock-synchro", -1, … )                    /* = -1 (تلقائي) */
add_bool   ( "input-fast-seek", false, … )
```
ونصّ المساعدة لـ`clock-jitter`: *«This defines the maximum input delay jitter that the synchronization
algorithms should try to compensate (in milliseconds).»*
ولـ`clock-synchro`: *«It is possible to disable the input clock synchronisation **for real-time
sources**. Use this if you experience jerky playback of network streams.»*

**✅ ملاحظة جانبية مؤكَّدة:** تعليقنا عند `VLCPlayer.swift:280` يقول *«1000 is libVLC's OWN default
for network input»* — **صحيح حرفياً**، مُتحقَّق منه من المصدر.

### `clock-jitter` — كيف يعمل فعلاً (`src/input/es_out.c:2539–2568`)

```c
const vlc_tick_t i_pts_delay_base = p_sys->i_pts_delay - p_sys->i_pts_jitter;
vlc_tick_t i_pts_delay = input_clock_GetJitter( p_pgrm->p_clock );
const vlc_tick_t i_jitter_max = INT64_C(1000) * var_InheritInteger( p_sys->p_input, "clock-jitter" );
if( i_pts_delay > __MIN( i_pts_delay_base + i_jitter_max, INPUT_PTS_DELAY_MAX ) )
{
    msg_Err( ... "ES_OUT_SET_(GROUP_)PCR is called too late (jitter of %d ms ignored)" ... );
    i_pts_delay = p_sys->i_pts_delay;
    /* … reset clock … */
}
else { msg_Warn( ... "buffering more (%d ms)" ... ); }
```

> **الترجمة الهندسية:** `clock-jitter` هو **السقف الذي تسمح به VLC لنفسها كي تُضخّم المخزن فوق
> `network-caching`** حين تقيس اضطراباً في وصول الحزم. بالقيمة الافتراضية (5000 مل.ث) تستطيع VLC أن
> تضيف حتى **خمس ثوانٍ** من التأخير قبل أول إطار. **`=0` يمنع هذا التضخّم كلّياً** — وهذا يفسّر
> تماماً الفارق «16 ث مقابل 4 ث» الذي قاسه المرجع.

**⚠ لكن الشيفرة تكشف ثمناً لم يذكره المرجع:** حين يُتجاوَز السقف، VLC **لا تكتفي بالرفض — بل تُعيد
ضبط الساعة** وتسجّل خطأً. وإعادة ضبط ساعة في منتصف بثٍّ مباشر مضطرب = **تقطيع مرئيّ**. والفرع
الآخر (`buffering more`) هو **السلوك التكيّفي المقصود لمصادر الشبكة المضطربة** — وIPTV على الإنترنت
المفتوح **هو** المصدر المضطرب النموذجي.

### `clock-synchro` — والحكم هنا سلبيّ (`src/input/input.c:2875–2876`)

```c
if( var_GetInteger( p_input, "clock-synchro" ) != -1 )
    in->b_can_pace_control = !var_GetInteger( p_input, "clock-synchro" );
```

`clock-synchro=0` ⇒ `b_can_pace_control = true` — أي **إخبار نواة VLC بأن المصدر يمكن قراءته
بالسرعة التي نشاء** (سلوك ملف).

- **لملف VOD عبر HTTP** المصدر **أصلاً** كذلك (وحدة `http` تُبلّغ عن ذلك)، فالخيار **بلا أثر**.
- **لبثّ مباشر** الخيار **يكذب على النواة**: يقول إن المصدر في الزمن الحقيقي ليس في الزمن الحقيقي.
  ونصّ VLC نفسه يصف الخيار كعلاج لـ«التشغيل المتقطّع»، **لا كمُسرِّع بدء**.
- **ولا توجد أي علاقة موثَّقة بينه وبين زمن أول إطار.**

> 🔴 **الحكم: ارفض `:clock-synchro=0`.** المرجع يشحنه بلا دليل، وهو في أحسن الأحوال بلا أثر على VOD
> وفي أسوئها ضارّ على المباشر. **هذه بالضبط الحالة التي تقول فيها القاعدة الحاكمة: تجاهل المرجع.**

## سكتش التنفيذ — `BlankTV/VLCPlayer.swift`، داخل `makeMedia` (بعد `:290`)

```swift
            media.addOption(":input-fast-seek")
            // ⬇ جديد، للـ VOD وحده:
            // clock-jitter هو السقف الذي تسمح به VLC لنفسها كي تُضخّم المخزن فوق
            // network-caching حين تقيس اضطراباً في الوصول. الافتراضي 5000 مل.ث، أي
            // خمس ثوانٍ إضافية قبل أول إطار (es_out.c:2543، فرع "buffering more").
            // ملف VOD يُسلَّم بنطاقات بايت ويُعاد طلب ما فُقد، فالتضخّم التكيّفي هنا
            // تكلفة بلا مقابل. المصدر: videolan/vlc 3.0.x, src/input/es_out.c:2539–2568.
            //
            // ⚠ لا تنقل هذا السطر إلى فرع isLive أبداً: على المباشر، تجاوز السقف
            // يجعل VLC تُعيد ضبط الساعة (نفس الموضع، فرع msg_Err) — وذلك تقطيع
            // مرئيّ، والتضخّم التكيّفي هناك هو آلية الموثوقية لا عيباً فيها.
            //
            // ⚠ ولا تُضِف ":clock-synchro=0" (المرجع يفعل، ونحن رفضناه): input.c:2875
            // يجعله يضبط b_can_pace_control — وهو true أصلاً لملف HTTP، فبلا أثر على
            // VOD؛ وعلى المباشر يكذب على النواة. لا دليل يربطه بزمن أول إطار.
            media.addOption(":clock-jitter=0")
```

**وكيف تُقاس:** ساعة إيقاف من لمسة «تشغيل» إلى أول إطار، على **نفس الفيلم** و**نفس الشبكة**،
خمس مرات قبل وخمس بعد. **إن لم يتحرّك الرقم، أعِد السطر.** هذا ما قاله المرجع عن نفسه (*«MEASURED
via ttff_vlc — revert if it doesn't move the number»*)، وهو الموقف الصحيح.

## ملاحظة مرافقة عن `network-caching` — ولا أوصي بتغييره الآن

المرجع رفع الافتراضي من 1500 إلى **3000** استناداً إلى بيانات أسطول حقيقية (*«stall counts
52→2691»*)، وجعله قابلاً للضبط عن بُعد `vlc_net_cache` مقيَّداً بـ`[1500, 8000]`. **ونحن على 1000
لـ VOD و1500 للمباشر** (`VLCPlayer.swift:272, 285`) بعد قرارٍ مُوثَّق لتسريع القفز.

⚠ **لا تنسخ الرقم 3000.** هو قياسٌ لأسطولٍ آخر على مزوّدٍ آخر، والمرجع نفسه يقول ذلك. **والأهم:
البند أعلاه (`clock-jitter=0`) يشتري زمن بدءٍ بلا أن يمسّ المخزن إطلاقاً** — وهو الطريق الصحيح.
إن ظهرت شكوى «تقطيع» بعد ذلك، فالرافعة هي `network-caching` للـ VOD من 1000 إلى 1500، **بقياس لا
بتخمين**، وليس اليوم.

- **الجهد:** 20 دقيقة. **الخطر:** منخفض (VOD فقط، وقابل للتراجع بسطر).

---

# البند 6 — مهلة `get_vod_streams`

## الحكم: **ADOPT REFERENCE** — أصغر تغيير في التقرير، وأثره ليس صغيراً

## الحقيقة

```swift
// BlankTV/Core.swift:2109–2111 — الثلاثة على المهلة الافتراضية 22 ثانية
async let liveStreamsData = apiData(xd, action: "get_live_streams")
async let vodStreamsData  = apiData(xd, action: "get_vod_streams")
async let seriesData      = apiData(xd, action: "get_series")
```

**والمرجع يميّزها** (`Strong8K/iOS/Strong8K/Core.swift:2587–2589`) بتعليق يشرح السبب:

```swift
// VOD is the largest list (often 100k+ items) → it needs a longer ceiling than the
// 22s default to finish on a slow cellular link before the default would time it out.
async let vodStreamsData  = apiData(xd, action: "get_vod_streams", timeout: 45)
```

**والعاقبة عندنا محدَّدة تماماً:** انتهاء المهلة على VOD يُشعل `c.isPartial = true`
(`Core.swift:2126`)، ومسار `isPartial` (`:1791`) يمنع الكتابة إلى القرص وإلى `CatalogDB`. أي أن
**تجاوزاً واحداً للمهلة يعني: تبويب أفلام فارغ في هذه الجلسة، ولا شيء يُحفَظ، ونفس النتيجة في
الإقلاع التالي.** ودالّة `apiData` لا تعيد المحاولة بعد المهلة عمداً (`Core.swift:1971`) — وهو قرار
صحيح، لكنه يجعل الرقم 22 هو الحكم النهائي.

**هل هناك أحدث؟** لا. `URLRequest.timeoutInterval` هو الآلية، وهي غير مهجورة. البديل الأحدث
(`URLSessionConfiguration.timeoutIntervalForResource`) يعمل على مستوى الجلسة لا الطلب، وهو أخشن هنا
لأننا نشارك `URLSession.shared`.

## سكتش التنفيذ — `BlankTV/Core.swift:2110`

```swift
// VOD هي أضخم قائمة في النظام (100 ألف عنوان فأكثر على خطّ نموذجي) وتحتاج سقفاً
// أعلى من 22 ث كي تكتمل على وصلة خلوية بطيئة. وانتهاء مهلتها ليس عَرَضاً بسيطاً:
// يرفع isPartial (:2126) فيمنع الحفظ إلى القرص وإلى CatalogDB (:1791) — فيصير
// تبويب الأفلام فارغاً هذه الجلسة والتالية. المرجع تعلّم هذا ميدانياً.
async let vodStreamsData  = apiData(xd, action: "get_vod_streams", timeout: 45)
```

**⚠ تعارض يجب حلّه أولاً:** إن نُفِّذ **البند 1** (التسليم التدريجي)، فرفع مهلة VOD يصير **مجّانياً
تماماً** — لأن المستخدم يشاهد المباشر بينما VOD في الطريق. **إن لم يُنفَّذ البند 1، فأنت تشتري
اكتمال الكتالوج بـ 23 ثانية إضافية من شاشة الانتظار في أسوأ الحالات.** نفّذ البند 6 **بعد** البند 1،
أو معه.

- **الجهد:** 5 دقائق. **الخطر:** صفر تقنياً؛ الأثر على تجربة الانتظار يعتمد على البند 1.

---

# البند 7 — قراءة كاش الكتالوج بـ `.mappedIfSafe`

## الحكم: **ADOPT NEWER (صغير، وصادق في حجمه)**

## الحقيقة

```swift
// BlankTV/Core.swift:1726
guard let url = fileURL(scope), let data = try? Data(contentsOf: url),
```

`Data(contentsOf:)` بلا خيارات **يقرأ الملف كلّه إلى ذاكرة العملية**. وملف
`Caches/S8KCatalog/cat_*.json` على خطٍّ بـ 100 ألف فيلم هو **عشرات الميغابايتات من JSON**. ثم
`JSONDecoder` يبني `Envelope`، ثم `content(from:)` (`Core.swift:1669–1697`) يبني **نسخة ثانية كاملة**
من كل النماذج. **الذروة = الملف + المفكوك + المُحوَّل، حاضرة كلها في آن.**

## البحث

- `NSData.ReadingOptions.mappedIfSafe` (متحقَّق من توثيق Apple عبر واجهة JSON): *«A hint indicating
  the file should be mapped into virtual memory, if possible and safe.»* — متاح **منذ iOS 2.0**،
  غير مهجور. النواة تُصفّح الملف عند الطلب بدل نسخه دفعةً واحدة، فتسقط ذروة النسخة الأولى.
- ⚠ **«hint» تعني تلميحاً لا ضماناً**، وTوثيق Apple لا يَعِد بمكسب. والملف في `Caches/` فقد
  يُزيله النظام أثناء التصفيح — **لكن كل استدعاءاتنا ملفوفة بـ`try?` أصلاً**، فالفشل يعود بـ`nil`
  وهو السلوك القائم.
- **الأحدث حقيقةً هو ألّا نقرأ الملف إطلاقاً**، بل نقرأ من `CatalogDB` بالتصفيح — وذلك **بند 1 من
  الجولة الثانية**، مؤجَّل بموافقة المالك. هذا البند **جسرٌ رخيص إلى أن يُنفَّذ ذاك**، لا بديل عنه.

## سكتش التنفيذ — `BlankTV/Core.swift:1726` (وفي `loadStale` من البند 2)

```swift
    // .mappedIfSafe: الملف عشرات الميغابايتات على خطٍّ كبير، والمسار كلّه يبني
    // نسختين كاملتين بعده (JSONDecoder ثم content(from:), :1669). التصفيح عند
    // الطلب يُسقط ذروة النسخة الأولى. تلميحٌ لا ضمانة — وكل شيء هنا ملفوف بـtry?
    // فسلوك الفشل لا يتغيّر.
    guard let url = fileURL(scope),
          let data = try? Data(contentsOf: url, options: .mappedIfSafe),
```

**⚠ وكن صادقاً مع الحجم:** هذا **لا يُسرّع** فكّ الترميز ولا يقلّل الذاكرة النهائية. يقلّل
**الذروة**. وقياسه الوحيد الصادق هو `MXMemoryMetric.peakMemoryUsage` عبر MetricKit القائم
(`Diagnostics.swift`). **إن كنت تبحث عن ثوانٍ، هذا ليس البند — البندان 1 و2 هما.**

- **الجهد:** 5 دقائق. **الخطر:** صفر. **الترتيب:** منخفض، ولا يُشحن وحده.

---

# البند 8 — كاش الصور على القرص: **قِس أولاً، لا تبنِ**

## الحكم: **مفتوح — لا توصية بلا قياس**

## ما لاحظته

```swift
// BlankTV/DesignSystem.swift:1329–1335
let disk = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
let cfg = URLSessionConfiguration.default
cfg.urlCache = disk
cfg.requestCachePolicy = .returnCacheDataElseLoad
```

طبقة القرص عندنا هي `URLCache` كلّها. و`URLCache` **تخزّن استجابةً فقط إن اعتبرتها قابلة للتخزين**
— أي بحسب ترويسات HTTP. ومضيفو ملصقات اللوحات متفاوتون تماماً؛ منهم من يرسل `Cache-Control: no-store`.
**إن لم تُخزَّن، فكل إقلاع بارد يعيد تنزيل كل ملصق** — والبصمة (ThumbHash) تُخفي ذلك بصرياً لكنها
**لا توفّر بايتاً واحداً من الشبكة**.

## لماذا لا أوصي بشيء بعد

- **لم أتحقّق أن المشكلة قائمة.** لا أملك التقاطاً للشبكة ولا استجابة حقيقية من مضيف ملصقات المالك.
  **بناء كاش قرصٍ خاص (~60 سطراً) لحلّ مشكلة قد لا توجد يخالف قاعدة التقرير.**
- **ولا أوصي بتبعية طرف ثالث.** `Kingfisher`/`Nuke`/`SDWebImage` تحلّ هذا، **والثمن حقيقي:** تبعية
  ثالثة في `Podfile`، ونموّ في حجم الثنائية، و**إعادة كتابة `S8KImage` كلّها** — وهي عنصر عرضٍ
  مركزيّ ملموس التصميم عندنا. **وطبقتنا بالفعل أحدث من المرجع** بمذكِّرة البصمات السالبة
  (الجولة الثانية، «نتائج سلبية مؤكَّدة»). لا مبرّر.

## القياس المطلوب — رخيص، وسطران

أضِف عدّادين ذرّيّين في `S8KImageCache.fetch` (`DesignSystem.swift:1374`) وفي `load` (`:1349`):
كم مرّة أُصيبت الذاكرة، وكم مرّة خرجنا إلى `session.data(from:)`. اعرضهما في `EngineStatsView`
القائمة (`SettingsView.swift:532`). ثم **أعِد تشغيل التطبيق من بارد وتصفّح الشبكة نفسها مرتين**:

- إن انخفض عدّاد التنزيل بوضوح في المرة الثانية ⇒ **`URLCache` تعمل. أغلق البند.**
- إن لم ينخفض ⇒ **المشكلة مؤكَّدة**، وعندها يُفتح ملف «كاش قرصٍ خاص» بمعطيات لا بتخمين.

- **الجهد:** 30 دقيقة للقياس. **الخطر:** صفر. **القرار:** مؤجَّل بحق.

---

# البند 9 — `waitsForConnectivity` على جلسة الخلفية

## الحكم: **KEEP OURS — لكن وثّق أنه بلا أثر**

```swift
// BlankTV/Downloads.swift:62–79
let cfg = URLSessionConfiguration.background(withIdentifier: "com.blanktv.player.downloads")
…
cfg.waitsForConnectivity = true          // ← السطر 79
```

**توثيق Apple لـ`waitsForConnectivity`** (متحقَّق منه نصّاً عبر واجهة JSON):

> *«This property is ignored by background sessions, which always wait for connectivity.»*

**أي أن السطر 79 لا يفعل شيئاً** — والسلوك المرغوب **قائم بالفعل ومجّاناً** لأن الجلسة جلسة خلفية.
والمرجع يحمل نفس السطر الزائد (`Strong8K/iOS/Strong8K/Downloads.swift:79`).

**لا تحذفه** — حذفه لا يغيّر سلوكاً ويفتح باب سوء فهم لاحق («هل كنّا ننتظر الاتصال؟»). **أضِف تعليقاً:**

```swift
        // Apple: "This property is ignored by background sessions, which always wait
        // for connectivity." مضبوط للتوثيق لا للأثر — السلوك مضمون بحكم نوع الجلسة.
        cfg.waitsForConnectivity = true
```

⚠ **والسطر 261 (`URLSessionConfiguration.default` لمسار Turbo) حالة أخرى تماماً**: هناك الخاصية
**فعّالة**. لكن الجولة الثانية أثبتت أن `runTurbo` **شيفرة لا يمكن لأي مستخدم بلوغها**
(`Store.shared.turboDownloads` بلا ضابط في الواجهة)، وأن `4e76bd9` أطفأته قسراً. **القرار هناك
قرار المالك، لا هندسة.**

- **الجهد:** دقيقتان. **الخطر:** صفر.

---

# البند 10 — حفظ EPG في SQLite

## الحكم: **مؤجَّل — خارج أولويات هذه الجولة**

المرجع يملك `CatalogDB.saveEPG(host:channelID:programs:)` و`epgGuide(host:channelID:)`
(`Strong8K/iOS/Strong8K/Core.swift:1969–1993`) — جدول `EpgRow` دائم في نفس قاعدة البيانات.
**ونحن نملك ذاكرةً مؤقّتة في الـ RAM فقط**: `epgCache` داخل `PlaylistService` بمدّة 5 دقائق
(`BlankTV/Core.swift:1871–1876`)، تُمحى مع كل إقلاع.

**لكن:** جزؤه المفيد الآخر (`nowNext`, `guide`, `Core.swift:2940, 2960`) يعتمد على خادمه ومفتاحه
المكتوب في الشيفرة. والباقي هو جدول SQLite عاديّ — تقنيةٌ لا يوجد فيها «أحدث» يُبحث عنه.
**والمالك لم يضع EPG في أولويات هذه الجولة.** يُسجَّل ولا يُنفَّذ.

---

# ما فحصتُه ولم أجد فيه شيئاً يُضاف — نتائج سلبية مؤكَّدة

| ما فُحص | النتيجة |
|---|---|
| **إعدادات جلسة التنزيل في الخلفية** | `Downloads.swift:62–79` و`Strong8K/…/Downloads.swift:62–79` **متطابقتان سطراً بسطر**. و`isExcludedFromBackup` مضبوط عندنا (`Downloads.swift:531`) كما عنده (`:558`). **لا شيء يُنقل.** |
| **موضع تخزين التنزيلات** | `documentDirectory/Downloads` مع راية استثناء النسخ الاحتياطي — مطابق لتوصية Apple. **صحيح كما هو.** |
| **`AVURLAsset` والخيارات** | لا نضبط `AVURLAssetPreferPreciseDurationAndTimingKey` — **وهذا صحيح**؛ ضبطه `true` يجبر AVFoundation على مسح الملف كلّه قبل التشغيل. لا تضبطه. |
| **`HostFailover` / `CatalogCentral` / `Telemetry` / `HLSProbe`** | كلها معلَّقة بخادم المرجع وبمفتاحه المكتوب في الشيفرة. **مرفوضة سلفاً في الجولتين السابقتين، ولا جديد.** |
| **`ReminderService`** (تذكيرات البرامج) | ميزة مستخدم لا تقنية أداء. خارج نطاق هذه الجولة. |
| **`EngineDecisionCache` / `StreamRouter`** | **نحن الأحدث** — المرجع لا يملك مكافئاً لذاكرة القرار لكل محتوى. لا شيء يُؤخذ. |
| **فكّ JSON تدفّقي لحمولة Xtream** | **لا يوجد في Foundation.** لا `JSONDecoder` ولا `JSONSerialization` يقبل تغذية جزئية. التنفيذ يعني كتابة مُحلِّل — **خطر غير مبرَّر، لا توصية.** |
| **`MobileVLCKit 4.x`** | آخر ما نُشر إلى CocoaPods هو `4.0.0a2` (2023-03-07) — **alpha**، وواجهته البرمجية مختلفة. **لا تقترب.** |

---

# ما يجب ألّا نُنسخ من المرجع في هذه الجولة

**١. `:clock-synchro=0`** (`Strong8K/iOS/Strong8K/VLCPlayer.swift:284`). شرحتُه في البند 5: بلا أثر
على VOD، ومضلّل للنواة على المباشر، وبلا أي دليل يربطه بزمن أول إطار. **هذا مثالٌ نموذجيّ للقاعدة
الحاكمة: المرجع شحنه على حدس، والمصدر الأصليّ يقول غير ذلك.**

**٢. الرقم `3000` لـ`network-caching`** — قياسُ أسطولٍ آخر. خُذ **الطريقة** (قِس، ثم اضبط) لا
**الرقم**.

**٣. `Dictionary(uniqueKeysWithValues:)`** في `loadXtreamDirect` (`Strong8K/…/Core.swift:2582`) —
**يتوقّف (trap) على مفتاح مكرّر**، ولوحات IPTV تُعيد `category_id` مكرّراً بانتظام. **نحن نستعمل
الشكل الآمن `uniquingKeysWith:` (`BlankTV/Core.swift:2104–2105`) — لا تتراجع عنه أبداً.**

**٤. مانع الانحدار الذي يرمي عند فراغ نوعٍ كان مملوءاً** (`Strong8K/…/Core.swift:2656–2660`) —
**نهجنا (`isPartial`) أفضل**: يخدم ما وصل لهذه الجلسة ولا يسجّله حقيقة، بينما نهجه يرمي فلا يرى
المستخدم شيئاً. **أبقِ نهجنا.**

---

# ترتيب التنفيذ الموصى به

| ترتيب | العمل | لماذا هنا | جهد | خطر |
|---|---|---|---|---|
| **0** | البند 4 — حارس المحرّك على `MediaPrefetcher.prefetch` | سطر واحد، يوقف نزيفاً صامتاً. أعلى فائدة ÷ خطر في التقرير | 15 د | ~0 |
| **1** | البند 9 — تعليق `waitsForConnectivity` + البند 7 — `.mappedIfSafe` | تنظيفان بلا خطر، يمهّدان لمسار الكاش | 10 د | 0 |
| **2** | البند 3 — `MobileVLCKit 3.7.3` | **وحده في بنائه**، ومعه قائمة الفحص السبعة | 30 د + جهاز | متوسط |
| **3** | البند 5 — `:clock-jitter=0` لـ VOD | بعد أن يستقرّ المحرّك الجديد، وإلا اختلط أثر التغييرين | 20 د | منخفض |
| **4** | البند 2 — SWR | أكبر مكسب لكل ساعة، ومستقلّ عن البند 1 | 3–4 س | منخفض |
| **5** | البند 1 — التسليم التدريجي (**موافقة المالك أولاً**) | يمسّ المُمثِّل الأسخن؛ لا يُشحن مع غيره | 6–8 س | متوسط |
| **6** | البند 6 — مهلة VOD 45 ث | **بعد** البند 1، وإلا اشترينا الاكتمال بانتظار أطول | 5 د | 0 |
| **—** | البند 8 — قياس كاش الصور | قرار مؤجَّل حتى تصل الأرقام | 30 د | 0 |

**قاعدة واحدة تحكم الجدول:** بندٌ واحد لكل بناء، ومراجعة خصومية قبل كلٍّ منها. سجّل
`PROJECT_HANDOFF §11` أن المراجعة الخصومية **وجدت عيباً حقيقياً في كل جولة بلا استثناء** — وسجلّ
`40b5438` يؤكّده (خمسة عيوب حقيقية في دفعة الجولة الأولى نفسها). لا يوجد في هذا التقرير بندٌ يستحقّ
أن يكون الاستثناء الأول.

---

## ملحق — المصادر المُستشهَد بها

**شيفرة VLC الأصلية (مستودع `videolan/vlc`، فرع `3.0.x`)**
- `src/libvlc-module.c` — التعريفات والقيم الافتراضية لـ`network-caching` / `clock-jitter` / `clock-synchro` / `input-fast-seek`
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/libvlc-module.c
- `src/input/es_out.c:2539–2568` — كيف يُطبَّق سقف `clock-jitter` وماذا يحدث عند تجاوزه
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/input/es_out.c
- `src/input/input.c:2875–2876` — دلالة `clock-synchro` الحقيقية (`b_can_pace_control`)
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/input/input.c
- `NEWS` — تغييرات 3.0.21 → 3.0.22 → 3.0.23
  — https://raw.githubusercontent.com/videolan/vlc/3.0.x/NEWS

**سجلّ إصدارات المحرّك**
- CocoaPods trunk API — قائمة إصدارات `MobileVLCKit` وتواريخها
  — https://trunk.cocoapods.org/api/v1/pods/MobileVLCKit
- `MobileVLCKit 3.7.3` podspec (الأطر المرتبطة والترخيص)
  — https://raw.githubusercontent.com/CocoaPods/Specs/2784b87814ee092b4961f524ff3205c76515bf56/Specs/b/f/7/MobileVLCKit/3.7.3/MobileVLCKit.podspec.json
- GitHub API — `videolan/VLCKit` compare `3.6.0...3.7.3` (20 دفعة)
  — https://api.github.com/repos/videolan/VLCKit/compare/3.6.0...3.7.3

**توثيق Apple**
- `URLSessionConfiguration.waitsForConnectivity` (بما فيه جملة تجاهل جلسات الخلفية)
  — https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity
- `NSData.ReadingOptions.mappedIfSafe`
  — https://developer.apple.com/documentation/foundation/nsdata/readingoptions/mappedifsafe

**معايير**
- ⚠ RFC 5861 — *HTTP Cache-Control Extensions for Stale Content* (2010 — **مصدر قديم، مُستشهَد به
  كتعريف مصطلح فقط، لا كممارسة حديثة**) — https://www.rfc-editor.org/rfc/rfc5861

**مصادر داخلية (وهي الأقوى في هذا التقرير)**
- `TECH_ADJUDICATION.md` — البنود الثمانية للجولة الأولى، لا تُعاد
- `TECH_HUNT_V2.md` (النسخة السابقة من هذا الملف) — البنود الخمسة للجولة الثانية، لا تُعاد
- `PROJECT_HANDOFF.md` §3 (القيود) · §6 (المؤجَّل بموافقة) · §9 (P2–P8) · §11 (المراجعة الخصومية) · §13 (المفتوح)
- `git show 4e76bd9` و`git show 40b5438` — العيوب الثلاثة المُبلَّغة من الجهاز، والخمسة التي وجدتها المراجعة الخصومية بعدها
