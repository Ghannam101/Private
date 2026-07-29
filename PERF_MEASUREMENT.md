# PERF_MEASUREMENT.md — تحويل «يبدو بطيئاً» إلى أرقام

> **المسار:** MEASUREMENT · **القاعدة الحاكمة:** بلا تخمين
> **الحالة:** تصميم مقترح — لا كود مكتوب في المشروع بعد (بروتوكول الأطوار: مراجعة قبل التنفيذ)
> **التاريخ:** 2026-07-29

---

## 0. الخلاصة التنفيذية

المشكلة ليست أن التطبيق بطيء. المشكلة أن **لا أحد في هذا الفريق يملك رقماً**. المالك يقول «ثلاث دقائق» و«ما زال بطيئاً»، والمهندس يقرأ الكود ويخمّن. كلاهما يخمّن.

الحل الأصغر الذي يعمل هو ثلاث قطع فقط:

1. **`PerfTrace`** — حلقة عدّادات (ring buffer) بعشر عيّنات، تُلحَق بملف `Diagnostics.swift` الموجود أصلاً (**بلا ملف جديد ⇒ بلا جراحة في `project.pbxproj`**).
2. **سبع علامات (marks)** في سبعة مواضع محدّدة بالسطر — خمس للإقلاع، أربع للتشغيل.
3. **صفحة `PerfStatsView`** بجوار `EngineStatsView` الموجودة أصلاً في `Settings ← الاتصال`، مع **زرّ نسخ** يضع تقريراً نصّياً واحداً في الحافظة يلصقه المالك في المحادثة.

**القرار الأهم في هذا المستند، وهو مخالف لما اقتُرح في الطلب:** لا تخفِ الشاشة خلف إيماءة سرّية. التطبيق **يشحن اليوم بالفعل** لوحة تشخيص رقمية ظاهرة (`EngineStatsView`, `SettingsView.swift:536`) مربوطة بصفّ ظاهر في الإعدادات (`SettingsView.swift:391`). إضافة قسم أداء ظاهر بجوارها = **صفر مخاطر** أمام App Review. أمّا الإيماءة السرّية فهي حرفياً النمط الذي يستهدفه البند 2.3.1(a): *"Don't include any hidden, dormant, or undocumented features in your app"*. سنشرح هذا بالتفصيل في القسم 3.

**اكتشاف يجب أن يُقرأ قبل أي تحسين:** الـ Splash فيه **أرضية صناعية ثابتة قدرها ~750ms** (`AuthViews.swift:72` تأخير 0.5s + `:74` تأخير 0.25s). أي رقم إقلاع نقيسه سيحتوي 750ms من التصميم المتعمّد، لا من البطء. هذا وحده قد يفسّر جزءاً من شكوى المالك، ولا يمكن معرفة حجمه إلا بالقياس.

---

## 1. ماذا نقيس بالضبط — التعريفات والخطّافات

### 1.أ الإقلاع البارد ← أول ملصق على الشاشة

الرقم الذي يشعر به المالك ليس رقماً واحداً؛ إنه **سلسلة**. قياسه كرقم واحد يعني أننا سنعرف أنه بطيء لكن لن نعرف أين. لذلك خمس علامات:

| # | العلامة | التعريف الدقيق | الخطّاف (ملف:سطر) |
|---|---------|----------------|---------------------|
| T0 | `launch` (البداية) | أول سطر من كودنا يُنفَّذ في العملية. لا يشمل زمن `dyld`/pre-main | `BlankTVApp.swift:159` — أول سطر داخل `init()`، قبل `configureAudio()` |
| T1 | `splash` | لحظة `splashDone = true`، أي انتهاء الـ Splash وبدء بناء شجرة المحتوى | `BlankTVApp.swift:196` — داخل `SplashView { splashDone = true }` |
| T2 | `data` | اكتمال `HomeVM.load()`: القنوات + الأفلام + المسلسلات كلها عادت | `HomeView.swift:150` — عند `isLoading = false` |
| T3 | `paint` | انقلاب `showSkeleton` من `true` إلى `false`، أي إزالة الهيكل العظمي وتركيب `mainScroll` | `HomeView.swift:743` — إضافة `.onChange(of: showSkeleton)` بجوار `.animation(...)` |
| T4 | `poster` **(النهاية)** | أول **بكسل ملصق حقيقي** يُسنَد إلى `image` في أي `S8KImage` في العملية | `DesignSystem.swift:1551` (إصابة كاش) و `DesignSystem.swift:1595` (بعد التنزيل) |

**لماذا T3 و T4 منفصلتان؟** لأنهما يشيران إلى علّتين مختلفتين تماماً:
- `T4 − T3` كبير ⇒ المشكلة في **تنزيل/فكّ ترميز الصور** (`S8KImageCache`, الشبكة، حجم الملصقات).
- `T3 − T1` كبير ⇒ المشكلة في **الكتالوج** (`ContentService`, `CatalogDB`, حجم قوائم M3U/Xtream).
- `T1 − T0` ≈ 750ms دائماً ⇒ هذه أرضية الـ Splash المتعمّدة، ليست عيباً.

خلط الثلاثة في رقم واحد هو بالضبط سبب أن الفريق ظلّ يخمّن.

**قاعدة صحّة إلزامية:** إذا هبط المستخدم على `GatewayView` (غير مسجَّل دخول)، فإن الزمن بين T1 و T2 يصبح **زمن إنسان يكتب كلمة مرور**، لا زمن تطبيق. يجب **إلغاء** أثر الإقلاع في تلك الحالة:
`BlankTVApp.swift:220` — إضافة `.onAppear { PerfTrace.shared.cancel("launch") }` على `GatewayView()`.
بدون هذا السطر، كل عيّنة إقلاع لمستخدم يسجّل الدخول ستقرأ «45 ثانية» وتكون كذباً.

### 1.ب الضغط على تشغيل ← أول إطار فيديو

| # | العلامة | التعريف الدقيق | الخطّاف (ملف:سطر) |
|---|---------|----------------|---------------------|
| P0 | `open` (البداية) | ظهور غلاف المشغّل. أقرب نقطة اختناق **واحدة** لكل مسارات التشغيل في التطبيق | `PlayerView.swift:72` — داخل `.onAppear` الموجود أصلاً على الـ wrapper |
| P1 | `setup` | بدء تجهيز المحرّك (بناء `AVURLAsset` أو التقاط عنصر دافئ من `MediaPrefetcher`) | `PlayerEngine.swift:321` — أول سطر في `override func setup()` |
| P2 | `ready` | `AVPlayerItem.status == .readyToPlay` — المشغّل *يستطيع* البدء (لكن لا صورة بعد) | `PlayerEngine.swift:459` — داخل `case .readyToPlay:` |
| P3 | `frame` **(النهاية)** | **`AVPlayerLayer.isReadyForDisplay == true`** — أول إطار مُهيّأ للعرض فعلاً | جديد: مسبار في `PlayerEngine.swift:296` `makeSurfaceView()` (الكود في 4.د) |
| P3' | `frame` (مسار VLC) | `VLCMediaPlayerState == .playing` | `VLCPlayer.swift:645` — داخل `case .playing:` |

**لماذا `isReadyForDisplay` وليس `.readyToPlay`؟**
`.readyToPlay` تعني «يمكن بدء التشغيل»، لا «هناك صورة». الفرق بينهما هو بالضبط ما يراه المالك كشاشة سوداء مع دوّار. Apple توثّق `isReadyForDisplay` كـ «أول إطار جاهز للعرض» وهي **قابلة للمراقبة عبر KVO**. الكود الحالي يقرأ هذه الخاصية فعلاً في `PlayerEngine.swift:437` داخل `startVideoWatchdog()` — أي أن الوصول إليها **مُثبَت أنه يُترجَم في هذا المشروع**، وهذا يقلّل مخاطر البناء الأعمى.

**بيانات بيئة إلزامية مع كل عيّنة تشغيل** (بدونها الرقم بلا معنى):
- `engine` = `av` أو `vlc`
- `warm` = هل التُقط عنصر دافئ من `MediaPrefetcher`؟ (`PlayerEngine.swift:330`) — عيّنة دافئة وعيّنة باردة رقمان مختلفان تماماً ولا يجوز خلطهما
- `live` = بثّ مباشر أم VOD (المباشر لا يملك buffer مسبق)
- `av_startup` = `AVPlayerItemAccessLogEvent.startupTime` — قياس Apple الداخلي لزمن البدء. **هذا الحقل هو الذي يفصل «الشبكة/السيرفر بطيء» عن «تطبيقنا بطيء»**، وهو أثمن حقل في الجدول كله.

---

## 2. كيف نقيس — المقارنة والقرار

المعيار الحاكم: **المالك لا يشغّل Instruments**. هو يمسك جهازاً، يضغط، ويكتب لنا في المحادثة بالعربية. أي حلّ يتطلّب Mac موصولاً أو Xcode مفتوحاً هو حلّ لشخص آخر، لا له.

| الخيار | يصل إلى المالك؟ | زمن الوصول | دقّة | كلفة الشحن | الحكم |
|--------|------------------|-------------|------|-------------|-------|
| `OSSignposter` + Instruments | ❌ **لا** — يحتاج Mac + Xcode + كابل | فوري (للمهندس فقط) | نانوثانية | رخيص جداً في release | **مساعد**، لا أساس |
| MetricKit `MXAppLaunchMetric` | ✅ نعم (بعد معالجة) | ⚠️ **حتى 24 ساعة** | histogram مجمّع، لا عيّنة مفردة | صفر (API عام) | **مرجع حقيقة**، لا حلقة تغذية راجعة |
| MetricKit `mxSignpost` مخصّص | ✅ نعم | ⚠️ حتى 24 ساعة | histogram مجمّع | صفر | نفس المشكلة + سقف مفروض من النظام |
| **Ring buffer داخل التطبيق ← ملف/UserDefaults ← زرّ نسخ** | ✅ **نعم، فوراً** | **ثوانٍ** | ميلي‌ثانية، عيّنة مفردة قابلة للعزل | ~180 سطر، بلا تبعيات | ✅ **الأساس** |

### القرار

**الحلقة الأساسية = ring buffer داخل التطبيق.** الأسباب ليست ذوقية:

1. **زمن الوصول هو كل شيء.** حلقة تغذية راجعة مدّتها 24 ساعة ليست حلقة تغذية راجعة؛ إنها أرشيف. المالك يجرّب، يرى الرقم فوراً، وينسخه. هذا يحوّل «ما زال بطيئاً» إلى «`play 2840ms، engine=vlc، warm=0`» في نفس الدقيقة.
2. **العيّنة المفردة هي المطلوبة، لا التوزيع.** MetricKit تعطي histogram لكل مستخدمي البناء مجمّعين. نحن نحتاج: *«هذا الفيلم بالذات، على 5G، استغرق 2.8 ثانية»*. الـ histogram لا يجيب على ذلك أبداً.
3. **الـ signposts لا يمكن قراءتها من داخل التطبيق.** هذه نقطة تقنية حاسمة كثيراً ما يُخطَأ فيها: `OSSignposter` **أحادي الاتجاه** — يكتب إلى unified log، ولا يوجد أي API عام يسمح للتطبيق باستعادة «كم استغرق الفاصل الذي فتحته للتو». لو بنينا الحلّ على signposts وحدها، لن يكون هناك رقم يعرضه المالك مطلقاً.

### الأدوار الثلاثة معاً (كلٌّ في مكانه الصحيح)

- **Ring buffer** ← الحلقة اليومية مع المالك. **الطور 1، يُشحن أولاً.**
- **`OSSignposter`** ← يُضاف على **نفس** نقاط العلامات السبع بسطر واحد لكل منها. بلا كلفة تقريباً في release، ويعني أنه في اليوم الذي يتوفّر فيه Mac، تفتح Instruments وتحصل على خطّ زمني كامل بدون إعادة كتابة أي شيء. **الطور 3.**
- **MetricKit** ← `Diagnostics.swift` يحفظ الحمولات فعلاً في `Caches/Diagnostics/`. `MXAppLaunchMetric.histogrammedTimeToFirstDraw` هي **الحقيقة المطلقة** لزمن الإقلاع لأنها تشمل `dyld` وما قبل `main` — وهو ما لا يستطيع `T0` عندنا رؤيته. تُستخدم لمعايرة رقمنا الداخلي: إن قال MetricKit 3.1s وقلنا نحن 2.3s، فالفارق 800ms هو ما قبل `main` وهو ملف عمل منفصل تماماً (حجم الثنائي، عدد الأطر الديناميكية). **الطور 2.**

هذا ليس تكديساً؛ كل طبقة تجيب على سؤال لا تستطيع الأخرى الإجابة عليه.

---

## 3. ما الذي يُشحن، وما الذي لا يُشحن

### يُشحن بأمان في TestFlight **وفي App Store** ✅

| العنصر | لماذا آمن |
|--------|-----------|
| `PerfTrace` (ring buffer) | `Date`/`DispatchTime` + `UserDefaults`. لا يجمع شيئاً عن المستخدم. لا يغادر الجهاز |
| `PerfStatsView` **ظاهرة** في الإعدادات | سابقة قائمة في نفس التطبيق: `EngineStatsView` تُشحن اليوم |
| `OSSignposter` | صُمّمت لتبقى في كود الإنتاج. WWDC18-405: *"we've done a lot of work to optimize them at emit time… they should take very few system resources"* |
| MetricKit | API عام، بلا entitlement، بلا مفتاح Info.plist. مصمّمة أصلاً للإنتاج |
| زرّ النسخ إلى الحافظة | إجراء يبدأه المستخدم بنفسه |

### لا يُشحن ❌

- **أي شاشة تشخيص مخفيّة خلف إيماءة غير موثّقة.**
- أي رفع تلقائي للقياسات إلى خادمنا بدون إفصاح في `PrivacyInfo.xcprivacy` وبطاقة الخصوصية.
- أي SDK طرف ثالث (انظر القسم 6.و).

### مخاطر App Review — بدقّة

النصّ الحرفي، من [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (اطُّلع عليه 2026-07-29)، البند **2.3.1(a)**:

> "Don't include any hidden, dormant, or undocumented features in your app; your app's functionality should be clear to end users and App Review. All new features, functionality, and product changes must be described with specificity in the Notes for Review section of App Store Connect (generic descriptions will be rejected) and accessible for review."

الكلمتان الحاكمتان: **"undocumented"** و **"accessible for review"**.

- **ضغطة مطوّلة سرّية على شاشة «حول»** ⇒ ميزة مخفية غير موثّقة، غير قابلة للوصول من قِبل المراجع. هذا هو النمط المستهدَف نصّاً. المخاطرة حقيقية وغير ضرورية بالكامل.
- **صفّ ظاهر باسم «قياس الأداء» في `Settings ← الاتصال`** ⇒ ليس مخفياً، ليس خاملاً، وقابل للوصول. المخاطرة **صفر**. وهو أيضاً **أسهل على المالك**: لا إيماءة يجب تذكّرها.

**التوصية:** اشحنه ظاهراً. إن كان يجب إخفاؤه لاحقاً لأسباب تجارية، فالوسيلة الصحيحة هي **build flag** (`#if DEBUG` أو تهيئة Codemagic منفصلة) وليست إيماءة مخفية — العلم المُترجَم يزيل الميزة من الثنائي تماماً، فلا يوجد شيء «مخفي» ليُعثر عليه.

**احتياط إضافي بلا كلفة:** اذكر السطر التالي في *Notes for Review* في App Store Connect:
> "Settings → Connection → Performance shows the last 10 on-device timing samples (app launch, playback start). All data is local to the device and is never transmitted. It exists so the developer can diagnose user-reported slowness."

هذا يستوفي شرط "described with specificity" ويغلق الملف نهائياً.

### تحذير امتثال واحد لم أستطع التحقّق منه (يجب حسمه قبل الرفع)

`DispatchTime.now().uptimeNanoseconds` يستدعي `mach_absolute_time()` داخلياً. حسب معرفتي، `mach_absolute_time` مُدرَجة ضمن فئة **`NSPrivacyAccessedAPICategorySystemBootTime`** في قائمة Required Reason API، والسبب المعتمد `35F9.1` يغطّي حرفياً حالتنا (قياس الزمن المنقضي بين أحداث داخل التطبيق). **لكنني لم أستطع تأكيد ذلك من مصدر Apple الأوّلي في هذه الجلسة** — صفحة Apple للفئات أعادت 404 في ست محاولات، وميزانية WebSearch نفدت (200/200).

**لذلك، خياران، والقرار للمالك:**

- **(أ) الأدقّ:** استخدم `DispatchTime` (ساعة رتيبة، محصّنة ضد تعديل ساعة النظام) وأضف إلى `BlankTV/PrivacyInfo.xcprivacy` — الذي يحتوي اليوم على ثلاث فئات فقط (`UserDefaults`, `FileTimestamp`, `DiskSpace`):
```xml
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>35F9.1</string>
    </array>
</dict>
```
**قبل الرفع، افتح صفحة Apple وتأكّد من رمز السبب `35F9.1` بعينك.** لا تعتمد على هذا المستند في هذه النقطة تحديداً.

- **(ب) الأبسط، صفر غموض:** لا تلمس `PrivacyInfo.xcprivacy` إطلاقاً. غيّر **سطراً واحداً** في `s8kNow()` إلى `Date()`. الفارق العملي معدوم في نوافذ قياس مدّتها 0.5–10 ثوانٍ، والعيّنة الفاسدة (لو قفزت الساعة) ستظهر كرقم سالب أو سخيف — أي أنها مرئية لا صامتة.

الكود في القسم 4 يعزل هذا القرار في **دالة واحدة من سطر واحد** حتى يكون التبديل بينهما تافهاً.

---

## 4. حلقة الإبلاغ — الكود الكامل

### قاعدة بناء إلزامية

**لا تنشئ ملف `.swift` جديداً.** إضافة ملف تتطلّب أربع تعديلات متطابقة في `BlankTV.xcodeproj/project.pbxproj` (`PBXBuildFile`، `PBXFileReference`، عضوية المجموعة، `PBXSourcesBuildPhase` — كما هو ظاهر في الأسطر 27، 59، 118، 221 لملف `Diagnostics.swift`)، وخطأ واحد فيها = بناء فاشل على Codemagic = **يوم ضائع تحت سقف الرفع اليومي من Apple**.

لذلك: **`PerfTrace` يُلحَق بنهاية `BlankTV/Diagnostics.swift`** (الملف موجود في المشروع بالفعل، ونطاقه «الرصد بلا تبعيات» — نفس النطاق تماماً).
و **`PerfStatsView` تُلحَق بـ `BlankTV/SettingsView.swift`** بعد `EngineStatsView` (ينتهي عند السطر 583).

---

### 4.أ — يُلحَق بنهاية `BlankTV/Diagnostics.swift`

```swift
// ============================================================
// MARK: - PerfTrace — قياس أداء داخل التطبيق يقرؤه المالك بنفسه
//
// حلقة عدّادات بعشر عيّنات. لا تجمع أي بيانات عن المستخدم ولا تغادر الجهاز
// إطلاقاً — أرقام توقيت فقط + معلومات بيئة تقنية. تُقرأ من
// Settings ← الاتصال ← قياس الأداء، وتُنسخ بزرّ واحد.
//
// لماذا ring buffer وليس signposts: OSSignposter أحادي الاتجاه (يكتب إلى
// unified log ولا يُقرأ من داخل العملية)، وMetricKit تصل بعد 24 ساعة كـ
// histogram مجمّع. المالك يحتاج العيّنة المفردة الآن.
// ============================================================

/// الساعة. `DispatchTime` رتيبة (لا تتأثر بتعديل ساعة النظام).
///
/// ⚠️ تستدعي `mach_absolute_time()` داخلياً، وهي على الأرجح ضمن فئة
/// `NSPrivacyAccessedAPICategorySystemBootTime` في Required Reason API
/// (السبب `35F9.1` = قياس الزمن المنقضي بين أحداث داخل التطبيق).
/// إمّا أن تُعلَن في PrivacyInfo.xcprivacy، وإمّا استبدل جسم هذه الدالة بـ:
///     UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
/// وهو ما يلغي السؤال تماماً بلا فرق عملي على نوافذ من ثوانٍ.
@inline(__always) func s8kNow() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

/// يُلتقط أول مرّة يُلمَس فيها هذا المتغيّر العام — ونحن نجبر ذلك في أول سطر
/// من `BlankTVApp.init()`، أي أبكر كود لنا في العملية. المتغيّرات العامة في
/// Swift كسولة، فهذا بالضبط ما نريده.
let s8kProcessMark: UInt64 = s8kNow()

@MainActor
final class PerfTrace {
    static let shared = PerfTrace()

    // MARK: نموذج البيانات
    struct Step: Codable { var name: String; var ms: Int }
    struct Sample: Codable {
        var kind: String                 // "launch" | "play"
        var totalMS: Int
        var steps: [Step]
        var env: [String: String]
        var at: Date
    }

    private(set) var samples: [Sample] = []

    private struct Open {
        var start: UInt64
        var steps: [Step] = []
        var env: [String: String] = [:]
        var seen: Set<String> = []
    }
    /// آثار مفتوحة، مفهرسة بالنوع — حتى لا يستطيع أثرُ تشغيلٍ بدأ مبكراً
    /// أن يمسح أثرَ إقلاعٍ ما زال مفتوحاً.
    private var open: [String: Open] = [:]

    private let key = "perfTrace.v1"
    private let maxSamples = 10

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode([Sample].self, from: d) {
            samples = s
        }
    }

    // MARK: التسجيل
    /// يبدأ (أو يعيد بدء) أثراً. `start` يسمح بتمرير ختم زمني أُخذ سابقاً —
    /// وهو ما يجعل أثر الإقلاع يبدأ من `s8kProcessMark` لا من لحظة الاستدعاء.
    func begin(_ kind: String, at start: UInt64? = nil) {
        open[kind] = Open(start: start ?? s8kNow())
    }

    /// نقطة تفتيش مسمّاة، مقيسة من `begin`. **أول نداء لكل اسم هو الذي يُحتسب**
    /// (لأن `S8KImage` قد تنادي `poster` عشرات المرّات في نفس الإطار).
    func mark(_ kind: String, _ name: String) {
        guard var o = open[kind], !o.seen.contains(name) else { return }
        o.seen.insert(name)
        o.steps.append(Step(name: name, ms: Self.ms(from: o.start)))
        open[kind] = o
    }

    /// يضيف حقل بيئة إلى الأثر المفتوح.
    func env(_ kind: String, _ k: String, _ v: String) {
        guard var o = open[kind] else { return }
        o.env[k] = v
        open[kind] = o
    }

    /// يغلق الأثر ويحفظ العيّنة. النداءات اللاحقة تُتجاهل (الأثر لم يعد مفتوحاً).
    func end(_ kind: String, _ name: String) {
        guard let o = open[kind] else { return }
        mark(kind, name)
        guard let closed = open[kind] else { return }
        open[kind] = nil

        var e = closed.env
        e["thermal"] = Self.thermal
        let s = Sample(kind: kind,
                       totalMS: closed.steps.last?.ms ?? Self.ms(from: closed.start),
                       steps: closed.steps, env: e, at: Date())
        samples.insert(s, at: 0)
        if samples.count > maxSamples { samples.removeLast(samples.count - maxSamples) }
        save()
    }

    /// يُسقط أثراً مفتوحاً بلا تسجيل — للحالات التي يتلوّث فيها القياس بزمن
    /// إنسان (مثال: الإقلاع الذي يهبط على شاشة تسجيل الدخول).
    func cancel(_ kind: String) { open[kind] = nil }

    func reset() { samples = []; open = [:]; save() }

    // MARK: التقرير النصّي (هذا ما يُلصَق في المحادثة)
    func report() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var out = "BLANK perf v1 · app \(v)(\(b)) · \(Self.osLabel) · \(Self.deviceLabel)\n"
        if samples.isEmpty { return out + "(no samples)" }
        for (i, s) in samples.enumerated() {
            let steps = s.steps.map { "\($0.name) \($0.ms)" }.joined(separator: ", ")
            let env = s.env.keys.sorted().map { "\($0)=\(s.env[$0] ?? "")" }.joined(separator: " ")
            out += "#\(i + 1) \(s.kind) \(s.totalMS)ms  [\(steps)]  \(env)\n"
        }
        return out
    }

    // MARK: مساعدات
    private static func ms(from start: UInt64) -> Int {
        let now = s8kNow()
        guard now > start else { return 0 }
        return Int((now - start) / 1_000_000)
    }
    private static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "?"
        }
    }
    private static var osLabel: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion)"
    }
    /// معرّف الجهاز (مثل "iPhone14,5") — أدقّ من `UIDevice.model` التي تعيد "iPhone" فقط.
    private static var deviceLabel: String {
        var info = utsname(); uname(&info)
        let m = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return m.isEmpty ? "?" : m
    }
    private func save() {
        if let d = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}
```

> ملاحظة على `deviceLabel`: يستخدم `utsname`/`uname` من `Foundation`+libc — لا يحتاج `import UIKit`، فيبقى `Diagnostics.swift` على استيراديه الحاليين (`Foundation`, `MetricKit`).

---

### 4.ب — العلامات السبع (تعديلات من سطر واحد)

**`BlankTVApp.swift:159`** — أول سطر داخل `init()`:
```swift
    init() {
        // القياس أولاً: لمس `s8kProcessMark` هنا هو ما يهيّئه، فيصبح أبكر
        // ختم زمني ممكن من كودنا. `Task { @MainActor }` لأن PerfTrace
        // معزول على الـ main actor بينما `App.init` ليس كذلك رسمياً.
        let mark = s8kProcessMark
        Task { @MainActor in PerfTrace.shared.begin("launch", at: mark) }
        configureAudio()
```

**`BlankTVApp.swift:196`** — نهاية الـ Splash:
```swift
            SplashView { splashDone = true; PerfTrace.shared.mark("launch", "splash") }
```

**`BlankTVApp.swift:220`** — إلغاء الأثر إذا هبطنا على بوابة الدخول:
```swift
                    GatewayView()
                        .onAppear { PerfTrace.shared.cancel("launch") }
                        .transition(.opacity)
```

**`HomeView.swift:150`** — اكتمال بيانات الكتالوج (داخل `load()`):
```swift
        isLoading = false
        PerfTrace.shared.mark("launch", "data")
        PerfTrace.shared.env("launch", "vod", "\(movies.count)")
        PerfTrace.shared.env("launch", "live", "\(liveChannels.count)")
        PerfTrace.shared.env("launch", "ser", "\(series.count)")
```
> ⚠️ `bootLoad()` عند `HomeView.swift:181` مسار ثانٍ ينتهي أيضاً بـ `isLoading = false`. أضِف السطور نفسها هناك، وإلا فقدتَ العلامة في ذلك المسار صامتاً.

**`HomeView.swift:743`** — إزالة الهيكل العظمي:
```swift
        .animation(.easeInOut(duration: 0.28), value: showSkeleton)
        .onChange(of: showSkeleton) { _, isSkeleton in
            if !isSkeleton { PerfTrace.shared.mark("launch", "paint") }
        }
```

**`DesignSystem.swift:1551` و `:1595`** — أول بكسل ملصق حقيقي. `S8KImage` هي `View` (معزولة على الـ main actor)، فالنداء مباشر:
```swift
        // السطر 1551 — إصابة كاش دافئة:
        if let hit = S8KImageCache.shared.cached(u) {
            image = hit; placeholderImage = nil; shownURL = u
            PerfTrace.shared.end("launch", "poster")
            return
        }
```
```swift
        // السطر 1595 — بعد التنزيل:
        if let img {
            phTask.cancel()
            withAnimation(.easeOut(duration: 0.25)) { image = img; placeholderImage = nil }
            shownURL = u
            PerfTrace.shared.end("launch", "poster")
        } else { failed = true }
```
> `end` آمنة للنداء المتكرّر: أول نداء يغلق الأثر ويجعل `open["launch"] == nil`، فكل النداءات اللاحقة (وهي مئات) تعود فوراً. **مهم:** الـ `ThumbHash` (السطر 1588) عمداً **لا** يُحتسب — إنه مربّع ضبابي، وليس ملصقاً. عدّه سيجعل الرقم أجمل وكاذباً.

**`PlayerView.swift:72`** — بداية أثر التشغيل:
```swift
            .onAppear {
                PerfTrace.shared.begin("play")
                PerfTrace.shared.env("play", "live", isLiveItem ? "1" : "0")
                AppDelegate.orientationLock = .allButUpsideDown
```
> يُنفَّذ مرّة واحدة لكل فتح من المستخدم. الـ wrapper يبقى حيّاً عبر تبديل المحرّك (`PlayerView.swift:68` يستخدم `.id()` على الـ **child**)، فأثرٌ واحد يقيس الزمن الحقيقي حتى الصورة **بما فيه أي failover** — وهذا هو الرقم الصحيح، لأنه ما يشعر به المستخدم.

**`PlayerEngine.swift:321`** — بداية تجهيز المحرّك:
```swift
    override func setup() {
        Task { @MainActor in
            PerfTrace.shared.mark("play", "setup")
            PerfTrace.shared.env("play", "engine", "av")
        }
        teardownObservers()
```
وفي `PlayerEngine.swift:330` سجّل ما إذا كان العنصر دافئاً:
```swift
        if let warm = MediaPrefetcher.shared.take(for: item) {
            pItem = warm
            Task { @MainActor in PerfTrace.shared.env("play", "warm", "1") }
        } else {
            Task { @MainActor in PerfTrace.shared.env("play", "warm", "0") }
```

**`PlayerEngine.swift:459`** — جاهز للتشغيل (لا صورة بعد):
```swift
                case .readyToPlay:
                    PerfTrace.shared.mark("play", "ready")
                    self.isLoading = false
```

**`VLCPlayer.swift:645`** — أول إطار على مسار VLC:
```swift
        case .playing:
            PerfTrace.shared.end("play", "frame")
            PerfTrace.shared.env("play", "engine", "vlc")
```
> ⚠️ رتّب `env` **قبل** `end` منطقياً، أو استخدم بدلاً منهما `env` أولاً ثم `end`. `end` تغلق الأثر، فأي `env` بعدها تُتجاهَل. الصياغة الصحيحة:
> ```swift
>         case .playing:
>             PerfTrace.shared.env("play", "engine", "vlc")
>             PerfTrace.shared.end("play", "frame")
> ```

---

### 4.ج — مسبار أول إطار على مسار AVPlayer

هذا الجزء الوحيد الذي يضيف آلية جديدة. صُمّم عمداً لـ **صفر مخاطر ترجمة**: يستخدم فقط `Timer.scheduledTimer` (نمط منسوخ حرفياً من `startVideoWatchdog` في `PlayerEngine.swift:432`) وقراءة `surface?.playerLayer.isReadyForDisplay` (مُثبَتة الترجمة في `PlayerEngine.swift:437`). لا keypath، لا KVO جديد، لا `@objc dynamic`.

أضِف إلى خصائص `AVPlayerVM` (بجوار `PlayerEngine.swift:273` `private var videoWatchdog: Timer?`):
```swift
    private var firstFrameProbe: Timer?
```

أضِف الدالة (بعد `startVideoWatchdog()`، أي بعد `PlayerEngine.swift:444`):
```swift
    /// أول إطار مُهيّأ للعرض. `AVPlayerItem.status == .readyToPlay` تعني
    /// «يمكن البدء»، لا «هناك صورة» — والفارق بينهما هو بالضبط الشاشة السوداء
    /// مع الدوّار التي يشتكي منها المستخدم. `AVPlayerLayer.isReadyForDisplay`
    /// هي الإشارة الصحيحة.
    ///
    /// استقصاء كل 50ms بدل KVO: التطبيق لا يُترجَم محلياً، وخطأ ترجمة واحد
    /// = بناء Codemagic فاشل تحت سقف الرفع اليومي من Apple. الاستقصاء يستخدم
    /// نمطاً وقراءةَ خاصيةٍ كلاهما مُثبَت في هذا الملف. خطأ 50ms على قياس
    /// من ~1500ms = 3%، وهو أرخص بكثير من يوم ضائع.
    private func startFirstFrameProbe() {
        firstFrameProbe?.invalidate()
        var elapsed = 0.0
        firstFrameProbe = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            elapsed += 0.05
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                let ready = self.surface?.playerLayer.isReadyForDisplay ?? false
                if ready {
                    // قياس Apple الداخلي لزمن البدء — يفصل «الشبكة/السيرفر»
                    // عن «تطبيقنا». سالب = غير معروف (تجاهله).
                    if let su = self.avPlayer.currentItem?.accessLog()?.events.last?.startupTime, su >= 0 {
                        PerfTrace.shared.env("play", "av_startup", String(format: "%.0f", su * 1000))
                    }
                    PerfTrace.shared.end("play", "frame")
                }
                if ready || elapsed > 20 {
                    t.invalidate()
                    self.firstFrameProbe = nil
                }
            }
        }
    }
```

نادِها من نهاية `setup()` (بعد `PlayerEngine.swift:359` `if isLive { startVideoWatchdog() }`):
```swift
        startFirstFrameProbe()
```

وأبطِلها في `teardownObservers()` (`PlayerEngine.swift:402`، بجوار `videoWatchdog?.invalidate()`):
```swift
        firstFrameProbe?.invalidate(); firstFrameProbe = nil
```

**ترقية اختيارية للطور 3** (بعد أن يثبت الطور 1 على TestFlight): استبدل المسبار بـ KVO حقيقي في `makeSurfaceView()` عند `PlayerEngine.swift:299`. `isReadyForDisplay` قابلة للمراقبة عبر KVO حسب توثيق Apple. لا تفعل هذا في نفس البناء الذي تشحن فيه بقيّة القياس.

---

### 4.د — الصفحة + زرّ النسخ

**مفاتيح `L10n`** — تُضاف إلى `Core.swift` بجوار السطر 160 (`"diag.engine.title"`)، بنفس الشكل خماسي اللغات:
```swift
        "diag.perf.title": [.ar: "قياس الأداء", .en: "Performance", .fr: "Performance", .tr: "Performans", .es: "Rendimiento"],
        "diag.perf.copy":  [.ar: "نسخ التقرير", .en: "Copy report", .fr: "Copier le rapport", .tr: "Raporu kopyala", .es: "Copiar informe"],
        "diag.perf.empty": [.ar: "لا توجد قياسات بعد — افتح التطبيق أو شغّل مقطعاً", .en: "No samples yet — launch the app or play something", .fr: "Aucune mesure", .tr: "Henüz ölçüm yok", .es: "Sin mediciones"],
        "diag.perf.reset": [.ar: "مسح القياسات", .en: "Clear samples", .fr: "Effacer", .tr: "Temizle", .es: "Borrar"],
```

**صفّ الدخول** — `SettingsView.swift:391`، مباشرة بعد صفّ تشخيص المحرّك:
```swift
                SetUI.navRow(icon: "chart.bar.xaxis", title: L("diag.engine.title"), chevron: true) { showEngineStats = true }
                SetUI.divider()
                SetUI.navRow(icon: "stopwatch", title: L("diag.perf.title"), chevron: true) { showPerf = true }
```
مع `@State private var showPerf = false` بجوار `SettingsView.swift:361`، و — بعد `SettingsView.swift:395`:
```swift
        .sheet(isPresented: $showPerf) { NavigationStack { PerfStatsView() } }
```

**الصفحة** — تُلحَق بـ `SettingsView.swift` بعد `EngineStatsView` (تنتهي عند السطر 583). مبنيّة حصراً من عناصر مُثبَتة الاستعمال في `EngineStatsView`:

```swift
// ============================================================
// MARK: - قياس الأداء — آخر 10 عيّنات توقيت، بزرّ نسخ
// شقيقة `EngineStatsView`: نفس الهيكل، نفس عناصر SetUI، ونفس الغرض —
// استبدال الانطباع بالرقم. تقرأ من PerfTrace (محلّي بالكامل، لا يغادر
// الجهاز أبداً). زرّ النسخ هو حلقة التغذية الراجعة كلها: يلصقها المالك
// في المحادثة وينتهي التخمين.
// ============================================================
struct PerfStatsView: View {
    @State private var samples: [PerfTrace.Sample] = []
    @State private var copied = false

    var body: some View {
        SetScaffold(title: L("diag.perf.title")) {
            if samples.isEmpty {
                SetUI.group(L("diag.perf.title")) {
                    Text(L("diag.perf.empty"))
                        .font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                        .padding(.horizontal, S8KSpace.lg)
                }
            }
            ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                SetUI.group("#\(i + 1)  \(s.kind)  ·  \(s.totalMS) ms") {
                    ForEach(Array(s.steps.enumerated()), id: \.offset) { j, st in
                        if j > 0 { SetUI.divider() }
                        row(st.name, "\(st.ms) ms")
                    }
                    ForEach(s.env.keys.sorted(), id: \.self) { k in
                        SetUI.divider()
                        row(k, s.env[k] ?? "")
                    }
                }
            }

            Button(action: copyReport) {
                Text(copied ? "✓" : L("diag.perf.copy"))
                    .font(S8KFont.callout.weight(.semibold)).foregroundColor(.s8kGoldMid)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).fill(Color.s8kGoldMid.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)

            Button(action: { PerfTrace.shared.reset(); samples = [] }) {
                Text(L("diag.perf.reset"))
                    .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.horizontal, S8KSpace.xl)
        }
        .onAppear { samples = PerfTrace.shared.samples }
    }

    private func copyReport() {
        UIPasteboard.general.string = PerfTrace.shared.report()
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { copied = false } }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.s8kGoldMid).lineLimit(1)
            Spacer(minLength: 8)
            Text(title).font(S8KFont.callout.weight(.semibold))
                .foregroundColor(.s8kTextPrimary).lineLimit(1)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 12)
    }
}
```

**ما يراه المالك عند النسخ** (وهذا هو المنتج النهائي كله):
```
BLANK perf v1 · app 1.4.2(231) · iOS 18.5 · iPhone14,5
#1 play 1930ms  [setup 12, ready 1180, frame 1930]  av_startup=1105 engine=av live=0 thermal=nominal warm=0
#2 launch 3402ms  [splash 781, data 3120, paint 3140, poster 3402]  live=8412 ser=940 thermal=nominal vod=12480
```

سطران يستبدلان محادثة كاملة.

### 4.هـ — نوع الشبكة (اختياري، الطور 2)

نوع الشبكة يفسّر تباعداً كبيراً بين العيّنات. عشرة أسطر، بلا تبعيات، بنمط `nonisolated(unsafe)` المستخدم أصلاً في `Core.swift:35`. **ابدأه في `BlankTVApp.init()`**، وانتبه أن أول عيّنة إقلاع قد تقرأ `?` لأن أول تحديث للمسار غير متزامن:

```swift
import Network   // في أعلى Diagnostics.swift

final class S8KNet {
    static let shared = S8KNet()
    nonisolated(unsafe) private(set) static var label = "?"
    private let mon = NWPathMonitor()
    private init() {
        mon.pathUpdateHandler = { p in
            if p.status != .satisfied                  { S8KNet.label = "off"  }
            else if p.usesInterfaceType(.wifi)         { S8KNet.label = "wifi" }
            else if p.usesInterfaceType(.cellular)     { S8KNet.label = "cell" }
            else if p.usesInterfaceType(.wiredEthernet){ S8KNet.label = "eth"  }
            else                                        { S8KNet.label = "other" }
        }
        mon.start(queue: DispatchQueue(label: "s8k.net"))
    }
}
```
ثم في `PerfTrace.end` أضِف `e["net"] = S8KNet.label`.

---

## 5. خط الأساس — الأرقام التي تُلتقَط **قبل** أي تحسين

بدون هذه القائمة، كل تحسين لاحق سيكون ادّعاءً. مع هذه القائمة، كل تحسين يصبح فرقاً في جدول.

### شروط الالتقاط (غير قابلة للتفاوض)

- **بناء واحد**، رقم واحد، مسجَّل في رأس الجدول.
- **جهاز حقيقي** — MetricKit لا تعمل على المحاكي أصلاً، والقياسات على المحاكي بلا معنى.
- **بين كل عيّنة إقلاع بارد وأختها: إنهاء قسري + انتظار 30 ثانية** (وإلا فالنظام يعيد الاستخدام من الذاكرة وتقيس إقلاعاً دافئاً وأنت تظنّه بارداً).
- المالك ينسخ التقرير بعد كل مجموعة ويلصقه. لا كتابة يدوية للأرقام.

### أ) الإقلاع — 10 عيّنات

| المجموعة | العدد | الشرط |
|----------|------|--------|
| بارد · Wi-Fi · قائمة حقيقية | 3 | إنهاء قسري + 30 ثانية |
| بارد · بيانات خلوية · قائمة حقيقية | 3 | نفس الشيء، مع إيقاف Wi-Fi |
| بارد · وضع Demo | 2 | يعزل زمن الشبكة تماماً — أي رقم كبير هنا **علّته عندنا** |
| بعد تثبيت نظيف (لا كاش) | 2 | حذف التطبيق وإعادة تثبيته |

يُسجَّل لكل عيّنة: `splash`، `data`، `paint`، `poster`، و `vod/live/ser`، و `thermal`، و `net`.

### ب) بدء التشغيل — 12 عيّنة

| المجموعة | العدد | الشرط |
|----------|------|--------|
| VOD بارد (فتح مباشر من الشبكة، بلا صفحة تفاصيل) | 4 | `warm=0` |
| VOD دافئ (دخول صفحة التفاصيل ثم تشغيل — `MediaPrefetcher` يعمل) | 4 | `warm=1` |
| قناة مباشرة | 4 | `live=1` |

يُسجَّل لكل عيّنة: `setup`، `ready`، `frame`، `engine`، `warm`، `live`، `av_startup`، `net`.

### ج) البيئة — تُسجَّل مرّة واحدة في رأس الجدول

- إصدار التطبيق + رقم البناء، إصدار iOS، طراز الجهاز (تلقائي في رأس التقرير)
- **حجم الكتالوج**: `vod` / `live` / `ser` (تلقائي)
- المزوّد المستخدم (Xtream أم M3U) — يؤثّر جذرياً على زمن التحليل
- Wi-Fi أم خلوي (تلقائي عبر `net`)
- الحالة الحرارية (تلقائي عبر `thermal`) — جهاز ساخن يعطي أرقاماً أسوأ بنسبة 30%+ ومقارنته بجهاز بارد بلا معنى
- المساحة الحرّة (تقريبية) — أقل من 1GB يجعل نظام الملفات بطيئاً

### د) الأرقام المرجعية للحكم

- **الإقلاع:** هدف Apple المعلن في [WWDC19-423 «Optimizing App Launch»](https://developer.apple.com/videos/play/wwdc2019/423/) هو **أول إطار خلال 400ms**. نحن نبدأ بـ **750ms أرضية Splash متعمّدة قبل أي عمل**. لا يمكن الحكم على أي رقم قبل طرح هذه الـ750ms.
- **بدء التشغيل:** المرجع العملي في صناعة البث هو ~1000ms إلى أول إطار. `av_startup` يخبرك أيّ جزء منها من الشبكة/السيرفر وأيّ جزء منّا.

### هـ) القاعدة الحاكمة للحلقة كلها

> **لا يُقبَل أي ادّعاء بتحسين بعد اليوم إلا مصحوباً بمجموعتَي أرقام: قبل وبعد، من نفس الجهاز، ونفس نوع الشبكة، ونفس حالة الحرارة تقريباً.**
> «صار أسرع» ليست نتيجة. `poster 3402ms → 1980ms` نتيجة.

---

## 6. البحث — الممارسة الحالية 2025-2026

### إفصاح منهجي إلزامي

**ميزانية WebSearch في هذه الجلسة نفدت بالكامل (200/200) قبل بدء هذا البحث.** كل ما يلي جُلب عبر `WebFetch` مباشرةً من مصادر Apple الأوّلية (صفحات التوثيق ونقاط `tutorials/data/...json` خلفها، وصفحات فيديو WWDC مع نصوصها)، بتاريخ **2026-07-29**. ما لم يُتحقَّق منه مُعلَّم صراحةً في 6.ز.

### 6.أ `OSSignposter`

[developer.apple.com/documentation/os/ossignposter](https://developer.apple.com/documentation/os/ossignposter) — iOS 15+. الواجهة: `beginInterval(_:id:) -> OSSignpostIntervalState`، `endInterval(_:_:)`، `withIntervalSignpost(_:id:around:)`، `emitEvent(_:id:)`، `makeSignpostID()`، `isEnabled`، `OSSignposter.disabled`.

الكلفة في release: [WWDC18-405 «Measuring Performance Using Logging»](https://developer.apple.com/videos/play/wwdc2018/405/) — نصّ حرفي: *"We built signposts to be lightweight… we've done a lot of work to optimize them at emit time… through some compiler optimizations that make sure that work is done in front instead of runtime. We've also deferred a lot of our work so that they're done on the Instruments backend… while signposts are being emitted, they should take very few system resources."*

**النقطة الحاسمة:** لا يوجد أي API عام يسمح للتطبيق بقراءة مدّة الفاصل الذي أصدره بنفسه. الـ signposts **تُكتَب فقط** إلى unified log وتُقرأ من Instruments/Console/`log`. لذلك لا يمكن أن تكون أساس هذا الحلّ.

### 6.ب MetricKit

- [MXAppLaunchMetric](https://developer.apple.com/documentation/metrickit/mxapplaunchmetric): `histogrammedTimeToFirstDraw`, `histogrammedOptimizedTimeToFirstDraw`, `histogrammedApplicationResumeTime`, `histogrammedExtendedLaunch` — كلها `MXHistogram<UnitDuration>`.
- [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager): حمولات المقاييس **مرّة واحدة يومياً على الأكثر**، تغطّي آخر 24 ساعة بالإضافة إلى ما لم يُسلَّم سابقاً. حمولات التشخيص (انهيار/تعليق) تصل **فوراً** منذ iOS 15. **جهاز حقيقي فقط — المحاكي غير مدعوم صراحةً.** لا يوجد أي API موثَّق لتوليد حمولة عند الطلب للاختبار.
- [MXSignpostMetric](https://developer.apple.com/documentation/metrickit/mxsignpostmetric) عبر `MXMetricManager.makeLogHandle(category:)` + `mxSignpost(...)`. تحذير Apple الحرفي: *"The system limits the number of custom signpost metrics saved to the log in order to reduce on-device memory overhead. Limit use of custom metrics to critical sections of code."* — لا يوجد رقم منشور للسقف.
- **تنبيه استشرافي مهم:** MetricKit أُعيدت هيكلتها في **iOS 27**. `MXMetricManager` و`MXAppLaunchMetric` و`MXSignpostMetric` ونمط `MXMetricManagerSubscriber` — أي كل ما يستخدمه `Diagnostics.swift:15-28` اليوم — **موسومة deprecated**. البديل: `MetricManager()` مع `for await report in manager.metricReports`، و`histogrammedTimeToFirstDraw` تصبح [`TimeToFirstDrawMetric.histogram`](https://developer.apple.com/documentation/metrickit/timetofirstdrawmetric) (تُقاس «عند أول Core Animation commit»). الكود الحالي لن ينكسر، لكن خطّط للهجرة، ولا تبنِ جديداً على السطح المُهمَل.

### 6.ج زمن الإقلاع

[WWDC19-423 «Optimizing App Launch»](https://developer.apple.com/videos/play/wwdc2019/423/): الهدف المعلن *"hit the goal of rendering our first frame within 400 milliseconds"* — تقريباً 100ms للنظام و300ms للمطوّر. وتحذير مباشر يخصّنا: *"it's very important to distinguish profiling with measurements… the profiling mechanism itself… has a cost of its own."*

### 6.د AVFoundation — أهمّ اكتشاف في هذا البحث

- [`AVPlayerLayer.isReadyForDisplay`](https://developer.apple.com/documentation/avfoundation/avplayerlayer/1389748-isreadyfordisplay) — `true` عند تهيّؤ أول إطار للعرض. **قابلة للمراقبة عبر KVO** (خلافاً لادّعاءات مدوّنات قديمة).
- [`AVPlayerItemAccessLogEvent.startupTime`](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent/1387448-startuptime) — «المدّة المتراكمة بالثواني حتى يصبح العنصر جاهزاً للتشغيل»، مطابقة لمقياس HLS `c-startup-time`. **سالبة إذا كانت غير معروفة**، و**ليست قابلة للمراقبة عبر KVO** — تُسحَب من سجلّ الوصول بعد الحدث. موثّقة لـ HLS؛ موثوقيتها على MP4 التقدّمي غير موثّقة.
- **iOS 18 أضافت [`AVMetrics`](https://developer.apple.com/documentation/avfoundation/avmetrics)** — `AVPlayerItem` أصبحت `AVMetricEventStreamPublisher`، مع `metrics(forType:)` و`allMetrics()` كـ `AsyncSequence`. الأهمّ: `AVMetricPlayerItemPlaybackSummaryEvent.timeSpentInInitialStartup: TimeInterval` — رقم بدء التشغيل مباشرةً وبصيغة مهيكلة وقابلة للقراءة **داخل التطبيق**، إلى جانب `stallCount` و`timeSpentRecoveringFromStall` و`variantSwitchCount`.
  الجلسة: [WWDC24-10113 «Discover media performance metrics in AVFoundation»](https://developer.apple.com/videos/play/wwdc2024/10113/) — من نصّها الحرفي: *"When the AVPlayer has buffered enough… This is represented by the 'likely to keep up' event on the timeline. This event provides the startup time as well as details about things which affected startup such as related playlist, media segment and content key events."*
  **الحكم لنا:** التطبيق حدّه الأدنى iOS 17، فهذا يحتاج `if #available(iOS 18, *)`. اجعله **الطور 4**، لا الآن. لكنه الاتجاه الصحيح ويجب توثيقه هنا حتى لا يُعاد اكتشافه.

### 6.هـ أمثلة مفتوحة المصدر

[kean/Pulse](https://github.com/kean/Pulse) (7.1k نجمة، MIT، iOS 15+) — وحدة تحكّم تسجيل/شبكة داخل التطبيق مبنيّة بالكامل على APIs من Apple فقط (`URLSession`, `OSLog`, SwiftUI)، ومصمَّمة لتُدمَج في تطبيق شاحن. أقرب سابقة موثَّقة لنمط «شاشة تشخيص داخل التطبيق، بلا SDK طرف ثالث».
**لم يُعثَر** على مشروع مفتوح معروف يقدّم «HUD أداء داخل التطبيق» تحديداً — انظر 6.ز، هذا أضعف جزء في البحث.

### 6.و لماذا **لا** SDK طرف ثالث — الحجّة صراحةً

الطلب يشترط ألّا نقترح SDK، ويطلب أن نجادل الأمر صراحةً إن رأينا خلاف ذلك. **لا نرى خلاف ذلك، والحجّة عددية لا ذوقية:**

| البند | Ring buffer (المقترح) | SDK طرف ثالث |
|-------|----------------------|---------------|
| تبعيات جديدة | 0 | 1+ (والتبعيات المتعدّية) |
| سطح `PrivacyInfo.xcprivacy` | 0 (أو فئة واحدة، انظر 3) | **بيان خصوصية كامل للطرف الثالث + توقيع + `NSPrivacyTracking` قد يتحوّل إلى `true`** |
| نمو حجم الثنائي | ~0 | مئات الكيلوبايتات ⇒ **يبطّئ `dyld` ⇒ يبطّئ الإقلاع الذي نحاول قياسه** |
| بطاقة خصوصية App Store | لا تغيير | تغيير مطلوب |
| زمن الوصول إلى المالك | ثوانٍ | دقائق–ساعات (عبر لوحة ويب) |
| ما نحتاجه فعلاً | 180 سطراً | إطار عمل كامل |

النقطة الثالثة قاتلة منطقياً: أداة قياس الإقلاع تصبح جزءاً من مشكلة الإقلاع. والنقطة الثانية استراتيجية: التطبيق يبني حجّته للقبول في App Store الآن، وبيان خصوصية جديد لطرف ثالث هو سطح مخاطرة مضاف مقابل صفر قدرة إضافية نحتاجها فعلاً. **لا يوجد ما يبرّره.**

### 6.ز ما لم أستطع التحقّق منه — يُقرأ ولا يُتخطّى

1. **جدول Required Reason API** — صفحة Apple `describing-use-of-required-reason-api` أعادت 404 في ست محاولات (صيغ URL مختلفة + نقاط JSON). **لم أؤكّد من مصدر أوّلي أن `mach_absolute_time` ضمن `NSPrivacyAccessedAPICategorySystemBootTime` ولا أن رمز السبب `35F9.1` صحيح.** هذا البند الوحيد الذي يمسّ الامتثال مباشرةً — **تحقّق منه بعينك قبل الرفع، أو استخدم الخيار (ب) في القسم 3 وتجنّب السؤال كلّياً.**
2. **WWDC17-413 «App Startup Time: Past, Present, and Future»** — لم أستطع تأكيد وجود هذه الجلسة؛ فهرس WWDC17 لا يُدرجها والعنوان المباشر يعيد 404. **لا تستشهد بها.**
3. **MetricKit على TestFlight** — تعمل عملياً، لكن لم أجد جملة نصّية من Apple تؤكّد ذلك حرفياً.
4. **مسح المشاريع المفتوحة (6.هـ)** — ضعيف بسبب غياب WebSearch. يستحقّ جولة بحث مخصّصة عند تجدّد الميزانية.

---

## 7. خطّة التنفيذ — بالأطوار، لحماية سقف الرفع اليومي

الذاكرة تسجّل أن Apple تفرض سقفاً يومياً على الرفع، وأن `chk.py` لا يمسك أخطاء الترجمة. لذلك: **لا تشحن كل هذا في بناء واحد.**

| الطور | المحتوى | مخاطرة الترجمة | القيمة |
|-------|---------|-----------------|--------|
| **1** | `PerfTrace` + العلامات السبع + `PerfStatsView` + مسبار أول إطار | منخفضة — كلّه أنماط منسوخة من كود قائم في نفس الملفات | **كل القيمة.** المالك يحصل على أرقام |
| 2 | `S8KNet` + `MXAppLaunchMetric` مُحلَّلة إلى نفس اللوحة | متوسطة — `MXHistogram.bucketEnumerator` جنيسة عبر ObjC، حسّاسة | معايرة ما قبل `main` |
| 3 | `OSSignposter` على النقاط السبع نفسها + KVO بدل المسبار | منخفضة | جاهزية Instruments |
| 4 | `AVMetrics` تحت `if #available(iOS 18, *)` | متوسطة | تفكيك زمن البدء إلى مكوّناته |

**اشحن الطور 1 وحده. لا تلمس شيئاً آخر حتى يعود المالك برقم.**

### قائمة تحقّق قبل الدفع (لأن لا مترجم محلّي)

- [ ] لم يُنشَأ أي ملف `.swift` جديد ⇒ `project.pbxproj` لم يُمَسّ
- [ ] كل نداء `PerfTrace` من سياق غير معزول على الـ main actor ملفوف بـ `Task { @MainActor in ... }` (`PlayerEngine.swift`، `VLCPlayer.swift`، `BlankTVApp.init`)
- [ ] كل نداء `env` يسبق نداء `end` المقابل له (بعد `end` يُتجاهَل)
- [ ] `PerfTrace.shared.mark("launch", "data")` مضافة في **كلا** المسارين: `load()` عند `HomeView.swift:150` و`bootLoad()` عند `HomeView.swift:181`
- [ ] `.onAppear { PerfTrace.shared.cancel("launch") }` مضافة على `GatewayView()` — بدونها كل عيّنة تسجيل دخول كذب
- [ ] `firstFrameProbe?.invalidate()` مضافة في `teardownObservers()`
- [ ] مفاتيح `L10n` الأربعة مضافة بخمس لغات كاملة (`brandlint.py` قد يفحص هذا)
- [ ] `PrivacyInfo.xcprivacy`: إمّا أُضيفت فئة `SystemBootTime` **بعد التحقّق**، وإمّا اختير الخيار (ب) وتُرك الملف كما هو
- [ ] نصّ *Notes for Review* محضَّر لصفحة الأداء الظاهرة
