# PERF_COLD_START.md — مسار الإقلاع البارد: من إنشاء العملية إلى أوّل محتوى حقيقي

**التاريخ:** 2026-07-29 · **النطاق:** `process launch → first real poster on screen` لمستخدم **مسجَّل دخوله مسبقاً**
**المشروع:** `C:\Users\user\Strong8K-App\blankstor` · SwiftUI · iOS 17 min · CocoaPods (`use_frameworks!`)

---

## 0 — قواعد القراءة: ما قِسناه، وما استنتجناه، وما نخمّنه

هذا التقرير يفصل بين ثلاث درجات من اليقين، ويلتزم بها في كل جدول:

| الوسم | المعنى |
|---|---|
| **[مقيس]** | رقم أخرجناه بأنفسنا من ملف حقيقي: قراءة سطر من الكود، أو تحليل رؤوس Mach‑O لثنائي VLC الفعلي المشحون، أو حجم ملف. |
| **[مستنتَج]** | رقم مبنيّ على مصدر أوّلي موثّق (WWDC / وثائق Apple / منتدى Swift) مطبَّق على بنية كودنا. ليس قياساً على جهاز. |
| **[تخمين]** | تقدير هندسي معقول بلا مصدر مباشر. نضعه فقط حين لا يوجد بديل، ونقوله صراحةً. |

> **قيد جوهري يجب ذكره أوّلاً:** لا نستطيع البناء ولا التشغيل محلياً. **لم يُقَس أي رقم زمني على جهاز حقيقي في هذا التقرير.** كل زمن بالمللي ثانية هنا هو **[مستنتَج]** أو **[تخمين]**. الشيء الوحيد المقيس بدقة تامة هو **بنية الكود** (ما الذي يُنفَّذ، وبأي ترتيب، وعلى أي خيط) و**بنية ثنائي MobileVLCKit**. القسم 8 يشرح كيف تُحوَّل هذه الاستنتاجات إلى قياسات حقيقية.

---

## 1 — الخلاصة التنفيذية

مسار الإقلاع البارد لدينا يتكوّن من أربع كتل. حجمها النسبي كالتالي:

```
  ┌─ pre-main (dyld: MobileVLCKit + GRDB) ──────────┐  ~60–150 ms   [مستنتَج]
  ├─ App.init + @StateObject + أول إطار ────────────┤  ~40–120 ms   [مستنتَج]
  ├─ ⛔ تأخير splash ثابت ──────────────────────────┤  750 ms       [مقيس من الكود — بالضبط]
  └─ فكّ ترميز الكتالوج JSON + بناء النماذج ────────┘  ~1.5–5 s     [مستنتَج]
                                                        ────────────
                              حتى أوّل بوستر:            ~2.4–6 ثانية
```

**النتيجتان الأهمّ:**

1. **`750 ms` من كل إقلاع هي وقت ميت خالص**، مُشفَّر كمؤقّت ثابت في `AuthViews.swift:72-75`. وهي ليست مجرّد انتظار: هي أيضاً **تُسلسِل** المسار — تحميل الكتالوج لا يبدأ إلا *بعدها*، لأن `HomeView` لا يُركَّب قبل `splashDone`. إصلاح هذا يوفّر 500 ms مباشرة **ويُخفي** جزءاً كبيراً من الكتلة الرابعة خلف الـ splash.

2. **`CatalogDB` (SQLite/GRDB) مُعبَّأ لكن القوائم لا تقرأ منه إطلاقاً.** كل قائمة تمرّ عبر `ContentService → PlaylistService.load() → CatalogDiskCache` أي **فكّ ترميز JSON للكتالوج كاملاً (≈35 MB) لعرض 8 بوسترات**. القراءة المصفَّحة من SQLite تحتاج ~70–200 صفّاً بدل ذلك.

**وما ليس صحيحاً، خلافاً للحدس:** الحلّ ليس في `use_frameworks! :linkage => :static`. لقد **أثبتنا بتحليل الثنائي** أن `MobileVLCKit` مستحيل ربطه ساكناً، وأن الربط الساكن لـ `GRDB` وحده يوفّر أرقاماً **لا يشعر بها أحد**. القسم 2 يشرح لماذا، والقسم 7 يضعه في أدنى الترتيب صراحةً.

---

## 2 — المرحلة 1: ما قبل `main` (pre-main / dyld)

### 2.1 ماذا يقول الـ Podfile

`Podfile:5-12` (مقروء حرفياً):

```ruby
target 'BlankTV' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'
  pod 'GRDB.swift', '~> 6.24'
end
```

`use_frameworks!` بلا `:linkage` يعني — بنصّ دليل CocoaPods — أُطُراً **ديناميكية**: كل pod يصير `.framework` مُضمَّناً في `App.app/Frameworks/`، أي **تحميل dyld مستقلّ لكلٍّ منهما**.
المصدر: <https://guides.cocoapods.org/syntax/podfile.html>

> **[مقيس]** مجلّد `Pods/` غير موجود في المستودع (يُولَّد على Codemagic، `codemagic.yaml` سطر «Install CocoaPods»). لذلك حلّلنا الحزمة المشحونة مباشرةً من مصدرها.

### 2.2 تشريح `MobileVLCKit 3.6.0` — قياس أوّلي أجريناه بأنفسنا

نزّلنا الأرشيف الفعلي الذي يشير إليه الـ podspec وحلّلنا رؤوس Mach‑O:

- **podspec** (CocoaPods CDN, نُشر 2024‑06‑06):
  `"source": {"http": "https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz"}`
  `"ios": {"vendored_frameworks": "MobileVLCKit.xcframework"}` — **لا `source_files`، لا `static_framework`**. أي **pod ثنائي مُسبَق البناء بالكامل**.
  الترخيص المعلن في الـ podspec: **`LGPL v2.1`**.

**[مقيس] — نتائج تحليل شريحة `arm64` من `MobileVLCKit.framework/MobileVLCKit`:**

| الخاصيّة | القيمة | الدلالة عند الإقلاع |
|---|---:|---|
| `filetype` | **6 = `MH_DYLIB`** | **مكتبة ديناميكية مُسبَقة البناء. لا يوجد `.a` في التوزيعة إطلاقاً.** |
| حجم شريحة `arm64` | **35,323,064 B (33.7 MB)** | هذا ما يُشحن للجهاز فعلاً |
| `__TEXT` | 30,113,792 B (28.7 MB) | كود؛ يُحمَّل بالصفحات عند الحاجة |
| `__DATA` (vmsize / filesize) | 11,108,352 / 1,196,032 | الفارق ≈ 9.9 MB هو `__bss` (صفر على القرص) |
| `__LINKEDIT` | 3,996,856 B (3.8 MB) | جداول الرموز والـ fixups |
| `LC_LOAD_DYLIB` | **20** | 20 مكتبة تابعة يجب على dyld حلّها |
| `LC_VERSION_MIN_IPHONEOS` | **9.0** | ← انظر السطر التالي |
| `LC_DYLD_INFO_ONLY` / `LC_DYLD_CHAINED_FIXUPS` | **موجود / غائب** | ⛔ **مستبعَد من page‑in linking** |
| `__mod_init_func` | **40** | 40 مُهيّئاً ساكناً (C/C++) تعمل **قبل `main`** |
| `__objc_classlist` | 38 | 38 صنف ObjC للتسجيل |
| `__objc_nlclslist` | **1** | صنف واحد له `+load` |
| `__objc_catlist` | 0 | لا فئات (categories) — جيّد |
| `__objc_selrefs` | 514 | 514 مُحدِّداً للتوحيد |

الشرائح الأخرى في الأرشيف: `armv7` و`armv7s` (28.8 MB لكلٍّ) — ميتة عندنا (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`)، ويزيلها سكربت `[CP] Embed Pods Frameworks` (`strip_invalid_archs`) عند البناء. لا أثر لها على الإقلاع.

### 2.3 ماذا يعني هذا فعلياً عند الإقلاع في 2026

**ما تغيّر منذ الحكمة القديمة:** WWDC22‑110362 *"Link fast: Improve build and launch times"* وثّق أن dyld4 يخزّن نتائج الربط في `PrebuiltLoaderSet`، وأن **page‑in linking** ينقل تطبيق الـ fixups إلى النواة تحميلاً كسولاً عند الصفحة. عرضهم الحيّ: *«the launch took 15ms overall, but only 1ms for fixups, thanks to page‑in linking. The vast majority of time is now spent in static initializers.»*
<https://developer.apple.com/videos/play/wwdc2022/110362/> (يونيو 2022)

**⛔ لكن `MobileVLCKit` مستثنى من هذه التحسينات.** الجلسة نفسها تشترط: *"page‑in linking only works for binaries built with chained fixups"*، وتحدّد أن الدعم موجود لـ *"deployment target iOS 13.4 or later"*. وقياسنا أعلاه يُظهر أن VideoLAN ما زالت تبني بـ `minos = 9.0` مع `LC_DYLD_INFO_ONLY` الكلاسيكي. **النتيجة: هذا الإطار يدفع تكلفة rebase+bind كاملة وبتلهُّف في كل إقلاع، بينما لا تدفعها الأُطر الحديثة.** هذه معلومة غير بديهية وتستحقّ التسجيل: **VLC أغلى عند الإقلاع ممّا يوحي حجمه.**

وما بقي غالياً بعد dyld4 — بشهادة وثائق dyld نفسها (<https://github.com/apple-oss-distributions/dyld/blob/main/doc/dyld4.md>) — هو: التحقّق التعاودي `isValid()` لكل dylib تابعة، وأخطاء الصفحات على `__DATA`، وتسجيل أصناف ObjC، **والمُهيّئات الساكنة**. عندنا 40 منها في VLC.

**التكلفة التقديرية:**
- WWDC16‑406 قاس ≈ 9 ms لكل dylib مُضمَّنة على عتاد 2016 (26 dylib = 240 ms). dyld4 قلّص ذلك كثيراً. **[مستنتَج]** على عتاد A15+ مع PrebuiltLoaderSet: **10–25 ms** لتحميل الـ dylib‑ين معاً.
- **[تخمين]** حصّة VLC من rebase/bind اللاهف + الـ 40 مُهيّئاً: **20–80 ms**. المُهيّئات على الأرجح رخيصة (بناء libvlc لبنك الوحدات لا يحدث هنا بل عند إنشاء `VLCLibrary`، وهو ما لا يقع عند الإقلاع — تحقّقنا: `VLCPlayer.swift:62` يُنشئ `VLCMediaPlayer()` كخاصية مخزَّنة داخل `VLCPlayerVM`، وهذا الصنف لا يُنشَأ إلا عند فتح المشغّل).

**المجموع pre‑main: [مستنتَج] 60–150 ms.**

### 2.4 هل الربط الساكن ممكن؟ وما الذي ينكسر؟

| الحزمة | ممكن ساكناً؟ | لماذا |
|---|---|---|
| **MobileVLCKit** | **❌ مستحيل** | **[مقيس]** الثنائي المشحون هو `MH_DYLIB`. `:linkage => :static` في CocoaPods يحكم فقط الحزم التي **تُبنى من المصدر**؛ أما `vendored_frameworks` المُشير إلى إطار ديناميكي مُسبَق البناء فيبقى مُضمَّناً ومُوقَّعاً كما هو. لا توجد نسخة `.a` في توزيعة VideoLAN إطلاقاً. |
| **GRDB.swift** | ✅ ممكن ونظيف | `GRDB.swift.podspec` يعلن `source_files` فقط، `s.library = 'sqlite3'`، **بلا `resources` ولا `resource_bundles` ولا `vendored_frameworks`** — فلا ينطبق عليه أيٌّ من مطبّات الربط الساكن (تصادم الموارد، `Bundle(for:)`). دعم Swift كمكتبة ساكنة موجود منذ CocoaPods 1.5.0. |

**وهناك سبب ثانٍ، قانوني، لعدم ملاحقة الربط الساكن لـ VLC:** الـ podspec يعلن **LGPL v2.1**. الربط الساكن لمكتبة LGPL داخل تطبيق مغلق المصدر يُفعّل التزام إتاحة ملفات الكائنات لإعادة الربط. الربط الديناميكي هو مسار الامتثال المعتاد. أي أن هذا ليس خياراً هندسياً معلّقاً، بل مسار **لا نريد** سلوكه.

### 2.5 التغيير الدقيق في `Podfile` — والخطر الدقيق

لو أردنا رغم ذلك تقليص dylib واحدة (GRDB):

```ruby
target 'BlankTV' do
  use_frameworks! :linkage => :static
  pod 'MobileVLCKit', '~> 3.6.0'
  pod 'GRDB.swift', '~> 6.24'
end
```

- **المكسب:** dylib واحدة أقلّ. **[مستنتَج] 5–15 ms.**
- **الخطر:** `:linkage => :static` يغيّر كيفية بناء مشروع `Pods` كلّه. لا نستطيع تجربته محلياً؛ أوّل تحقّق سيكون بناءً على Codemagic. وذاكرة المشروع تسجّل أن Apple تحدّد سقفاً يومياً لرفعات TestFlight — أي أن بناءً فاشلاً يكلّف فتحة رفع.
- **الحكم: ⛔ لا تفعل.** 5–15 ms **لا يشعر بها إنسان**. النسبة (أثر محسوس ÷ خطر كسر البناء) هي الأسوأ في هذا التقرير كلّه. هذا البند مُدرَج هنا لأنه سُئل عنه، لا لأنه يُنصح به.

### 2.6 ملاحظة جانبية موثّقة تستحقّ قراراً منفصلاً (خارج نطاق الأداء)

`GRDB.swift` على CocoaPods **مجمَّد عند 6.24.1 (يناير 2024)**. الـ README الرسمي يقول حرفياً: *"Due to an issue in CocoaPods, it is currently not possible to deploy new versions of GRDB to CocoaPods. The last version available on CocoaPods is 6.24.1."* (السبب: <https://github.com/CocoaPods/CocoaPods/issues/11839>). النسخة الحالية 7.x. هذا **ليس مشكلة أداء إقلاع**، لكنه دَين تقني يجب أن يعرفه المالك.

---

## 3 — المرحلة 2: المُهيّئات الساكنة والـ singletons على المسار

كل ما في هذا القسم **[مقيس] بنيوياً** (قرأنا السطر)، وتكلفته الزمنية **[مستنتَج]**.

### 3.1 قبل `main`

| ما يعمل | الموقع | التكلفة |
|---|---|---|
| 40 مُهيّئاً ساكناً C/C++ | داخل `MobileVLCKit` (قياس §2.2) | [تخمين] 10–50 ms |
| تسجيل 38 صنف ObjC + `+load` واحد + 514 مُحدِّداً | داخل `MobileVLCKit` | [مستنتَج] < 10 ms — سطح ObjC صغير فعلاً |
| **لا شيء من كودنا** | — | ✅ لا `+load`، ولا مُتغيّر عام في `BlankTV/` ذو أثر جانبي عند التحميل. `L10n.table` هو `static let` أي **كسول** (`swift_once`) لا pre‑main. |

WWDC22‑110362 يحذّر صراحةً: *"Anything that can take more than a few milliseconds should never be done in an initializer."* — وهي حزمة طرف ثالث، فلا سلطة لنا عليها.

### 3.2 `BlankTVApp.init()` — الخيط الرئيسي، قبل أي إطار

`BlankTV/BlankTVApp.swift:159-168`:

| # | السطر | ما يفعله | التكلفة | الحكم |
|---|---|---|---|---|
| 1 | `BlankTVApp.swift:160` → `:303-313` | `configureAudio()`: `AVAudioSession.setCategory(.playback, …)` **ثم `setActive(true)`** | [مستنتَج] **5–30 ms** (رحلة XPC إلى `mediaserverd`) | ⛔ **`setActive(true)` زائدة تماماً** — انظر §3.6 |
| 2 | `BlankTVApp.swift:161` → `:316-335` | `configureAppearance()`: `UINavigationBarAppearance` + `UIColor(Color.s8kBlack)` (جسر SwiftUI→UIKit) + `UIFont.systemFont` ×2 + وكلاء المظهر | [تخمين] 2–8 ms | مقبول — ضروري قبل أوّل إطار |
| 3 | `BlankTVApp.swift:165` → `Core.swift:1198-1207` | `Store.shared.migrateLegacyScopedDataIfNeeded()`: **أوّل لمسة لـ `UserDefaults.standard`** (تحميل نطاق التطبيق من القرص) + قراءة `Bool` واحدة ثم `return` | [مستنتَج] 1–5 ms بعد أوّل إقلاع | مقبول — محميّ براية |
| 4 | `BlankTVApp.swift:167` → `Diagnostics.swift:19` | `Diagnostics.shared.start()` → `MXMetricManager.shared.add(self)` | [تخمين] 5–25 ms | ⚠️ **قابل للتأجيل بالكامل** — MetricKit يسلّم الحمولات مرّة يومياً على استدعاء خلفي؛ الاشتراك بعد ثانية لا يفقد شيئاً |

### 3.3 أوّل تقييم لـ `body` — إيقاظ الـ `@StateObject`

`@StateObject var x = Y.shared` يستخدم `@autoclosure` — أي أن `Y.shared` **يُنشَأ عند أوّل تقييم لـ `body`**، لا في `init()`. لكنه ما زال على الخيط الرئيسي وقبل أوّل إطار.

`BlankTVApp.swift:151-154`:

| # | Singleton | الموقع | ما يعمل في `init` |
|---|---|---|---|
| 5 | `AuthService.shared` | `Services.swift:14-20` | ← تفصيل أدناه |
| 6 | `AppTheme.shared` | `DesignSystem.swift:986` | `restoreBrand()` (`:1039-1042`، قراءة UD) + `loadCached()` (`:1044-1052`، `UD.data` + `JSONDecoder<ThemeConfig>`). [تخمين] < 2 ms |
| 7 | `AppRouter.shared` | `BlankTVApp.swift:14-15` | `private init() {}` — مجّاني |
| 8 | `LocalizationManager.shared` | `Core.swift:32-44` | قراءة `String` واحدة من UD. مجّاني |

**تفصيل `AuthService.shared` — أثقل singleton على المسار:**

| السطر | ما يفعله | التكلفة |
|---|---|---|
| `Services.swift:18` → `Core.swift:764-772` | `Keychain.upgradeAccessibilityIfNeeded()` — بعد أوّل تشغيل: **قراءة `Bool` واحدة من UD ثم `return`**. في أوّل تشغيل بعد الترقية فقط: 8 مفاتيح × (load+delete+add) = حتى 24 نداء `SecItem` | [مستنتَج] بعد الأولى: < 1 ms · في الأولى: 20–80 ms **مرّة واحدة في العمر** |
| `Services.swift:19` → `Services.swift:381-402` | `restore()`: `Store.demoMode` (UD) → `Store.loginMode` (UD) → **`Store.shared.m3uURL`** (`Core.swift:1010-1049`) → **`Keychain.shared.m3uURL` → `SecItemCopyMatching`** | **⚠️ انظر أدناه** |

**هذه هي المخالفة الوحيدة الموثّقة صراحةً من Apple على مسارنا.** وثيقة `SecItemCopyMatching` تقول حرفياً:

> *"`SecItemCopyMatching` blocks the calling thread, so it can cause your app's UI to hang if called from the main thread. Instead, call `SecItemCopyMatching` from a background dispatch queue or `async` function."*
> <https://developer.apple.com/documentation/security/secitemcopymatching(_:_:)> (© 2026)

**لكن — وهذا مهم للأمانة — لم نعثر على رقم مليّ ثانية موثوق لتكلفة رحلة Keychain واحدة.** بحثنا عن ذلك ولم نجد مصدراً يذكر رقماً؛ الموجود هو التحذير الكيفي فقط. أي ادّعاء بأن «Keychain يكلّف N مليّ ثانية» هو **[تخمين]** حتى يُقاس على الجهاز. ونضيف: الكود **يُخزّن النتيجة مؤقتاً** بعد أوّل قراءة (`m3uURLCache`, `Core.swift:1001`, `1048`)، فهي **قراءة واحدة لا ثلاثين**، وهذا صحيح هندسياً.

في الفرع `.xtream` فقط تُضاف قراءتان أخريان (`Keychain.tokenValid` → `token` + `tokenExpiry`) و`JSONDecoder` على `UserInfo`/`ServerInfo`. لكن **الحالة السائدة عندنا هي `.m3u`**: كلٌّ من `loginXtream` (`Services.swift:130`) و`loginM3U` (`Services.swift:189`) يكتب `Store.shared.loginMode = .m3u`، ويعود `restore()` عند `Services.swift:387-390` بعد قراءة Keychain واحدة.

### 3.4 أثناء عرض الـ splash

| # | ما يعمل | الموقع | التكلفة | الحكم |
|---|---|---|---|---|
| 9 | بناء `L10n.table` — **[مقيس] 372 مفتاحاً × حتى 5 لغات ≈ 1,800 سلسلة + 373 قاموساً** — عبر `swift_once` على الخيط الرئيسي | `Core.swift:55-515`، أوّل لمسة من `AuthViews.swift:45` | [تخمين] 1–5 ms | 🟢 **منخفض. لا تلاحقه.** كسول وصحيح البنية |
| 10 | **`DeviceIdentity.current`** | `DeviceID.swift:16-21`، يُقرأ من `AuthViews.swift:47` ومن `ActivationService.swift:108` | **⚠️ انظر أدناه** | 🟡 خلل حقيقي، إصلاحه مجّاني |
| 11 | `ActivationService.shared` يستيقظ عبر `.task` | `AuthViews.swift:61` → `ActivationService.swift:43-46` | 3 قراءات UD (`brandName/Color/Logo`, `:91-93`) + `DeviceIdentity.current` (`:108`) | 🟡 عبء صافٍ — `check()` صار **no‑op** (`:116-119`) بعد فصل الخادم |

**تفصيل البند 10 — تناقض بين التوثيق والكود:**

`DeviceID.swift:15-21` يقول تعليقه: *"Cached, stable ID"*. لكن الكود:

```swift
    /// Cached, stable ID in the form `AA:BB:CC:DD:EE:FF` (uppercase).
    static var current: String {
        if let saved = Keychain.shared.deviceID, isValid(saved) { return saved }
        ...
    }
```

هذا **`static var` محسوب بلا أي تخزين مؤقّت**. كل قراءة تُنفّذ:
1. `Keychain.shared.deviceID` → **`SecItemCopyMatching` كامل**؛
2. `isValid(saved)` (`DeviceID.swift:23-25`) → `id.range(of: "^([0-9A-F]{2}:){5}[0-9A-F]{2}$", options: .regularExpression)` → **بناء `NSRegularExpression` من جديد في كل نداء**.

وكم مرّة يُنادى أثناء الـ splash؟ `SplashView.body` يقرؤه في `AuthViews.swift:47`، و`startAnimation()` (`AuthViews.swift:64-76`) يقلب **ثلاث** خصائص `@State` (`logoOpacity/logoScale`، `textOpacity`، `macOpacity`) — كل قلبة تعيد تقييم `body`. أضف قراءة `ActivationService.swift:108`. **[مستنتَج] ≈ 4–5 رحلات Keychain + 4–5 عمليات ترجمة regex في نافذة الـ 750 ms.**

### 3.5 `applicationDidBecomeActive` — حول أوّل إطار

`BlankTVApp.swift:94-106`، على الخيط الرئيسي:

| # | ما يعمل | السطر | التكلفة | الحكم |
|---|---|---|---|---|
| 12 | `KeyboardDismisser.shared.install()` — يمشي على `connectedScenes`/`windows` | `:96` → `:126-137` | [تخمين] < 1 ms | ✅ رخيص |
| 13 | `UNUserNotificationCenter.current().delegate = self` — **أوّل لمسة تفتح اتصال XPC مع `usernotificationd`** | `:97` | [تخمين] 5–20 ms | 🟡 قابل للتأجيل |
| 14 | `_ = DownloadService.shared` | `:105` → `Downloads.swift:83-88` | **⚠️ أثقل بند هنا** | 🟡 قابل للتأجيل |

**تفصيل البند 14:** `DownloadService.init` (`Downloads.swift:83-88`) يفعل ثلاثة أشياء:
1. `items = Self.loadItems()` — قراءة UD + `JSONDecoder`؛
2. `_ = session` → `Downloads.swift:61-81` — **إنشاء `URLSessionConfiguration.background(withIdentifier:)`**، وهو تسجيل عبر XPC مع `nsurlsessiond`. [تخمين] 10–40 ms، وهو من أغلى نداء مفرد على المسار؛
3. `reconcileOnLaunch()` (`:94-95`) — يعود فوراً إذا لا توجد تنزيلات نشطة (الحالة السائدة).

التعليق في `BlankTVApp.swift:98-105` محقّ تماماً في أن **لمس** الـ singleton حمّال معنى (يعيد الوصل بالتنزيلات التي قتلها الإغلاق القسري). لكن لا شيء يوجب أن يحدث ذلك **متزامناً** قبل تسليم أوّل إطار.

### 3.6 اكتشاف: `setActive(true)` عند الإقلاع زائدة ومضرّة

**[مقيس]** — تتبّعنا كل نداءات `AVAudioSession` في المشروع:

- `BlankTVApp.swift:305-309` — `setCategory(.playback, mode:.moviePlayback, options:[.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP])` **ثم `setActive(true)`** عند الإقلاع.
- `VLCPlayer.swift:748-752` — `NowPlayingManager.configure()` يفعل `setCategory(.playback, mode:.moviePlayback)` **و`setActive(true)`** عند بدء التشغيل.
- ويُنادى `configure()` من **كلا المحرّكين**: `PlayerEngine.swift:364` (مسار AVPlayer) و`VLCPlayer.swift:311` (مسار VLC).

**إذن `setActive(true)` عند الإقلاع لا تضيف شيئاً.** وهي ليست مجرّد إهدار زمن: تفعيل جلسة صوت من فئة `.playback` **يقاطع صوت التطبيقات الأخرى**. أي أن فتح BLANK اليوم **يوقف موسيقى المستخدم** حتى لو لم يشغّل شيئاً. هذا **خلل تجربة حقيقي** بقدر ما هو بند أداء.

---

## 4 — المرحلة 3: أوّل إطار — الـ splash

### 4.1 ما الذي يقود `splashDone`؟ — **[مقيس بدقّة تامّة]**

`BlankTVApp.swift:157` يعرّف `@State private var splashDone = false`، و`BlankTVApp.swift:194-196` يعرض `SplashView { splashDone = true }`. المُغلِق `onComplete` يُنادى من مكان واحد فقط:

`AuthViews.swift:64-76`:

```swift
    private func startAnimation() {
        withAnimation(.easeOut(duration: 0.7)) { logoOpacity = 1; logoScale = 1.0 }
        withAnimation(.easeOut(duration: 0.6).delay(0.25)) { textOpacity = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.5))  { macOpacity = 1 }
        // Snappy splash: hold only long enough to register the branded intro, then
        // fade. … Hold trimmed 1.0s→0.5s = ~0.5s off every relaunch …
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.32)) { logoOpacity = 0; textOpacity = 0; macOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onComplete() }
        }
    }
```

**التقرير المطلوب بالضبط:**

> **الـ splash تأخير ثابت بالكامل. `splashDone` يُقاد بمؤقّتين متسلسلين — `0.5 s` ثم `0.25 s` — أي `750 ms` غير مشروطة في كل إقلاع، لا تنتظر أي عمل حقيقي.**

وأنه **تأخير ميت** مثبت من ثلاث جهات:
1. `ActivationService.check()` (`ActivationService.swift:116-119`) صار **`no-op` محضاً** بعد فصل الخادم — لا شبكة، لا انتظار. التعليق في `AuthViews.swift:58-60` («resolve activation WHILE the splash is showing») يصف واقعاً لم يعد قائماً.
2. تحميل الكتالوج **لم يبدأ بعد**: `HomeView` لا يُركَّب قبل `splashDone` (`BlankTVApp.swift:193-213`)، و`.task { await vm.load() }` (`HomeView.swift:744`) لا يعمل إلا بعد التركيب.
3. لا شيء آخر في `SplashView` ينتظر شيئاً.

**فالـ 750 ms ليست تغطيةً لعمل — هي انتظار خالص، ثم يبدأ العمل.** الضرر مضاعف: `750 ms` مدفوعة + تأخير `750 ms` لبداية فكّ ترميز الكتالوج متعدّد الثواني.

### 4.2 ما تقوله Apple عن هذا تحديداً

- **HIG «Launching»**: *"Launch instantly. People want to start interacting with your app or game right away."* — و: *"Don't advertise. The launch screen isn't a branding opportunity."* — و: *"If you need a splash screen, consider displaying it at the beginning of your onboarding flow."*
  <https://developer.apple.com/design/human-interface-guidelines/launching>
- **WWDC19‑423 «Optimizing App Launch»**: *"we need to hit the goal of rendering our first frame within 400 milliseconds."*
  <https://developer.apple.com/videos/play/wwdc2019/423/> (يونيو 2019)
- **Apple، «Addressing watchdog terminations»**: عدّاد `scene-create` يعني حرفياً *"the app didn't render the first frame of its UI to the screen within the allowed wall clock time"*، بسقف مرصود `19.97 s`. الـ splash يجري **داخل** هذه النافذة.
  <https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations>

**تصحيح للأمانة:** لا توجد قاعدة في App Store Review تمنع تأخير splash. الحجّة ضدّه هي HIG + المقاييس، لا المراجعة. البند 2.3.3 يخصّ لقطات الشاشة فقط.

### 4.3 اكتشاف ثانوي: وميض أبيض قبل الـ splash

**[مقيس]** — `BlankTV.xcodeproj/project.pbxproj:300` و`:330` يضعان `INFOPLIST_KEY_UILaunchScreen_Generation = YES` بلا أي مفتاح لون، و**`BlankTV/Info.plist` لا يحتوي `UIUserInterfaceStyle` إطلاقاً** (تحقّقنا بالبحث عبر المشروع كلّه: لا `UIUserInterfaceStyle` ولا `overrideUserInterfaceStyle`).

النتيجة: شاشة الإقلاع المولَّدة تُرسم بـ `systemBackground` = **أبيض على جهاز في الوضع الفاتح**، ثم تُقطع إلى `Color.s8kBlack` في `AuthViews.swift:21`. التطبيق يفرض `.preferredColorScheme(.dark)` في `BlankTVApp.swift:176` — لكن **شاشة الإقلاع لا تعرف ذلك**، فهي نظامية وتسبق كودنا.

وHIG صريح: *"Design a launch screen that's nearly identical to the first screen of your app or game."*

---

## 5 — المرحلة 4: أوّل محتوى حقيقي

### 5.1 السلسلة الكاملة، مُتحقَّقاً منها سطراً بسطر

لمستخدم مسجَّل دخوله بوضع `.m3u` (الحالة السائدة — انظر §3.3):

| # | الخطوة | الموقع | الخيط |
|---|---|---|---|
| 1 | `splashDone = true` عند `t ≈ 750 ms` | `AuthViews.swift:74` | main |
| 2 | `ActivationGate` يعرض `content()` فوراً (`act.gate == .allowed` من `init`) | `ActivationView.swift:31-33`، `ActivationService.swift:45` | main |
| 3 | `tabView` → `TabView` يعرض `HomeView()` فقط (البقيّة كسولة) | `BlankTVApp.swift:250-263` | main |
| 4 | `.task { await vm.load() }` | `HomeView.swift:744` | main actor |
| 5 | `await config.fetchIfStale()` → **يعود فوراً** (`guard Store.shared.loginMode == .xtream else { return }`) | `HomeView.swift:136`، `Services.swift:~427` | main actor |
| 6 | `withTaskGroup` → `loadChannels` + `loadMovies` + `loadSeries` معاً | `HomeView.swift:137-141`، `:200-217` | main actor |
| 7 | الثلاثة → `ContentService.*` → **`PlaylistService.shared.load()`** (وحيدة الطيران) | `Core.swift:2398`, `2406`, `2414` → `Core.swift:1788-1795` | **actor executor (خارج main ✅)** |
| 8 | `_load(force:false)` → `Store.shared.m3uURL` (Keychain، لكن مُخزَّن من §3.3) | `Core.swift:1799-1802` | actor |
| 9 | **`CatalogDiskCache.read(scope:)`** | `Core.swift:1806` → `Core.swift:1744-1753` | actor |
| 9a | `Data(contentsOf:options:.mappedIfSafe)` — `mmap`، رخيص | `Core.swift:1748` | actor |
| 9b | **`JSONDecoder().decode(Envelope.self, from: data)` على الكتالوج كاملاً** | `Core.swift:1749` | actor |
| 9c | **`content(from: env)` — تمريرة ثانية كاملة تُخصّص كل `Channel`/`Movie`/`Series`/`Season`/`Episode`** | `Core.swift:1750` → `Core.swift:1681-1728` | actor |
| 10 | العودة للـ main actor: ثلاث إسنادات `@Published` كبيرة | `HomeView.swift:201`, `:207`, `:213` | main actor |
| 11 | `rebuildHero()` — ترتيبات على **الفهارس** (مكتوبة بشكل صحيح) + `s8kUniqueByID` + `prefetch` لثمانية خلفيات | `HomeView.swift:145` → `:74-118` | main actor |
| 12 | `showSkeleton` يصير `false` **فقط الآن** — شرطه `vm.isLoading && vm.heroItems.isEmpty && !vm.everLoaded` | `HomeView.swift:1005-1013` | main actor |

**الاستنتاج البنيوي الحاسم:**

> **لعرض أوّل بوستر، يجب فكّ ترميز الكتالوج كاملاً.** الشرط في `HomeView.swift:1013` يعلّق الهيكل العظمي حتى يمتلئ `heroItems`، و`heroItems` لا يُبنى إلا بعد أن يعود الكتالوج **بالكامل** من الخطوة 9.

نلاحظ أن الخطوتين 9b/9c تعملان **خارج الخيط الرئيسي** (على مُنفِّذ الـ actor)، وهذا صحيح هندسياً ويجنّبنا التجمّد. لكنّه لا يجعل الانتظار أقصر — لا شيء يُرسَم قبل انتهائهما.

### 5.2 كم يكلّف ذلك؟

**[مقيس]** — `Movie` (`Models.swift:224-245`) يحوي 13 حقل `String`/`String?` + `Bool` + مؤشّر تفاصيل ≈ 224 بايت لكل عنصر، كلّها حقول مُعاد عدّها (refcounted).

**تقدير سابق من هذا المستودع نفسه** — `PERF_LOGIN_LOAD.md:33` يقدّر الكتالوج بـ **≈ 42 MB** من JSON لخطّ 56k قناة / 30k فيلم / 10k مسلسل، و`PERF_LOGIN_LOAD.md:121` يقدّر مغلَّف الكاش المُرمَّز بـ **≈ 35 MB**. هذا **[تخمين]** موروث، ليس قياساً — لكنه من الفريق نفسه وعلى نفس البنية.

**ما هو موثَّق فعلاً عن `JSONDecoder`:**

- منتدى Swift الرسمي، «Improving JSONDecoder/Encoder performance for large apps» (أغسطس–سبتمبر 2025، بمشاركة Kevin Perry من Apple): قياسات إنتاجية تُظهر `JSONDecoder` عند **282–667 ms** (0.25–0.75 quantile)، وأن **`swift_conformsToProtocol` يستهلك 84٪ من زمن الفكّ**. والأخطر: هذه **تكلفة أوّل استخدام** — أي أنها تقع **بالضبط على مسار الإقلاع**.
  <https://forums.swift.org/t/improving-jsondecoder-encoder-performance-for-large-apps/81839>
- Apple تُدرج «معالجة كميّات كبيرة من البيانات، مثل ملفات JSON الكبيرة» ضمن أسباب إنهاء الـ watchdog.
  <https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations>

**[مستنتَج]** بتطبيق ذلك على مغلَّف بحجم ≈35 MB مع تمريرة تخصيص ثانية (`content(from:)`): **ثوانٍ، لا مليّ ثوانٍ. نضع نطاق 1.5–5 s** لخطّ كبير، وأقلّ بكثير لخطّ صغير. لن ندّعي دقّة أعلى من ذلك.

### 5.3 هل تقرأ القوائم من `CatalogDB`؟ — **لا. [مقيس]**

بحثنا عن كل استخدامات `CatalogDB` في المشروع. القراءات الموجودة **بأكملها**:

| الاستخدام | الموقع |
|---|---|
| بحث FTS5 | `ContentViews.swift:3234`, `3292`, `3297`, `3302` |
| بصمات `ThumbHash` للصور | `DesignSystem.swift:1436`, `1458`, `1461` |
| **قراءة قوائم** | **لا شيء.** |

والكتابات: `Core.swift:1854` و`Core.swift:1901` فقط — **كلتاهما على مسار الشبكة**، منفصلتان بـ `Task.detached(priority: .utility)`.

ورأس الملف نفسه يعترف بذلك — `CatalogDB.swift:13-16`:

> *"STEP 2 (isolated): schema + records + save / load / paging / search. **NO consumer yet — CatalogDiskCache stays the live path until the VMs are switched over (step 4).**"*

فالمخزن **مبنيّ بالكامل ومُعبَّأ ولا يُقرأ منه**. دوالّ الصفح `pageChannels` / `pageMovies` / `pageSeries` (`CatalogDB.swift:206-235`) مكتوبة وجاهزة ولا يناديها أحد.

### 5.4 ما الذي يوفّره التحوّل إلى قراءة SQLite مصفَّحة؟

**كم صفّاً تحتاج الشاشة الأولى فعلاً؟ [مقيس] من الكود:**

| المستهلك | العدد المطلوب | المصدر |
|---|---:|---|
| `heroItems` | ≤ 8 | `HomeView.swift:117` (`.prefix(8)`) |
| `topMovies` / `topSeries` | 10 + 10 | `HomeView.swift:92`, `:97` |
| `newMovies` / `newSeries` | 20 + 20 | `HomeView.swift:101`, `:105` |
| **مجموع شاشة Home الأولى** | **≤ 70 صفّاً** | |
| نافذة أي تبويب قوائم عند فتحه | **120 صفّاً** | `ContentViews.swift:560` (`S8KListWindow.initial = 120`) |

**المقارنة:**

| | اليوم | بعد الصفح |
|---|---|---|
| ما يُقرأ لعرض 8 بوسترات | **الكتالوج كاملاً (≈35 MB JSON)** | **≤ 70 صفّاً** |
| الآليّة | `JSONDecoder` + تمريرة تخصيص كاملة | `pageMovies(…, limit:)` على فهرس مُغطٍّ `movie_scope_pos` (`CatalogDB.swift:99`) |
| التقدير | **[مستنتَج] 1.5–5 s** | **[مستنتَج] < 10 ms** |

هذا يتطابق مع ما فعلته Apple نفسها في عرض WWDC19‑423 (تحميل ~20 صفّاً للخلايا المرئية فقط، والباقي كسولاً في الخلفية)، ومع إرشاد GRDB الرسمي: *"Cursors iterate database results in a lazy fashion, and don't consume much memory."* (<https://github.com/groue/GRDB.swift>).

### 5.5 المخاطر الدقيقة لهذا التحوّل — لا تبدأ قبل قراءتها

هذا **ليس تغييراً بسطر واحد**. أربع عقبات حقيقية، كلّها **[مقيسة]** من الكود:

**(أ) صفوف Hero و Top‑10 محسوبة من المصفوفات الكاملة.**
`rebuildHero()` (`HomeView.swift:88-105`) يحتاج أعلى تقييماً وأعلى `id` عبر **الكتالوج كلّه**. تحت الصفح يلزم SQL بديل: `ORDER BY CAST(rating AS REAL) DESC LIMIT 10` و`ORDER BY CAST(id AS INTEGER) DESC LIMIT 20`.
**لكن لا يوجد فهرس على `rating` ولا على `id` كعدد صحيح** — `CatalogDB.swift:99-100` و`:110-111` تفهرس فقط `(scope,pos)` و`(scope,categoryID,pos)`. بدون فهرسين جديدين يصير هذان مسحين كاملين في SQLite (أرخص بكثير من فكّ 35 MB، لكنه ليس مجّانياً). الحلّ: هجرة `v3` إضافية.

**(ب) البحث.** `LiveTVVM` / `MoviesVM` / `SeriesVM` تبني فهارس أسماء مطويّة في الذاكرة فوق المصفوفات الكاملة (`ContentViews.swift:45`, `:857`, `:2079`). تحت الصفح لا وجود لها — يجب أن يصير `CatalogDB.search` (`CatalogDB.swift:188-197`) **المسار الوحيد**، لا مجرّد مسار مفضّل. اليوم `SearchVM` يفضّله ثم يسقط إلى الذاكرة (`ContentViews.swift:3234`).

**(ج) التجميع وعدّادات المجلّدات.** `rebuildGroups()` يستخدم `Dictionary(grouping:)` على المصفوفة الكاملة (`ContentViews.swift:30`, `:848`, `:2070`)، و`folderList` يرشّح الفئات الفارغة. البديل هو `movieCategoryCounts(scope:)` — وهو **مكتوب بالفعل** (`CatalogDB.swift:273-280`) — **لكن نظيريه للقنوات والمسلسلات غير مكتوبين**. يجب كتابتهما.

**(د) فجوة التعبئة — أخطر بند.** `CatalogDB.save` (`CatalogDB.swift:305-341`) يُنادى **فقط** على مسار الشبكة، منفصلاً بأولويّة `.utility`، ويُدخل 20–50 ألف صفّ **صفّاً صفّاً داخل معاملة واحدة**. لو خرج المستخدم من التطبيق قبل انتهائها، تبقى القاعدة فارغة أو جزئية — وحينها واجهةٌ تقرأ بالصفح لا تجد شيئاً، بينما كاش JSON اليوم يجد. و`TECH_ADJUDICATION.md:59` يسجّل عَرَضاً قريباً من هذا لمسار FTS.
**الخطوة صفر لأي تحوّل: اجعل الكتابة إلى SQLite موثوقة وعلى كل مسار، ومقسَّمة إلى دفعات.**

---

## 6 — أفضل الممارسات 2025–2026 (بحث في مصادر أوّلية)

> **إفصاح عن المنهج:** ميزانية `WebSearch` كانت **مستنفدة بالكامل** لهذه الجلسة قبل بدء البحث. كل ما يلي جُمِع بـ `WebFetch` على مصادر أوّلية مباشرةً، بالإضافة إلى **تحليل ثنائي أجريناه بأنفسنا** لأرشيف MobileVLCKit الفعلي. موقع وثائق Apple تطبيق JS، فوصلنا إليه عبر خلفيّات DocC. **حيثما فشلنا في إيجاد مصدر، نقول ذلك صراحةً بدل تلفيقه.**

### 6.1 ميزانية الإقلاع وانضباط `init`

- **الهدف 400 ms، وهو هدف *أوّل إطار*.** WWDC19‑423: *"we need to hit the goal of rendering our first frame within 400 milliseconds. That's so that we have pixels displayed to the user during the launch animation."* — مقسومة تقريباً 100 ms للنظام + 300 ms لنا. <https://developer.apple.com/videos/play/wwdc2019/423/>
- **المراحل الست:** dyld → `libSystemInit` → مُهيّئات وقت التشغيل الساكنة → تهيئة UIKit → تهيئة التطبيق → رسم أوّل إطار.
- **نواهي الجلسة الحرفية:** *"You should be deferring any unrelated work… by either pushing it to the background queues or just doing it later entirely."* · *"You should avoid blocking the main thread, either with network I/O, file I/O, or more."* · *"In general, we don't recommend static initialization."*
- **وثيقة Apple الحالية «Reducing your app's launch time»** (© 2026): *"These methods execute synchronously on the main thread, and the launch cycle doesn't finish until both methods return successfully… Do only the work necessary to prepare your app's initial display; defer other tasks."* و*"Initialize nonview functionality, such as persistent storage and location services, on first use rather than on app launch. Retrieve only the data necessary to display your app's initial view."* <https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time>
- **[مستنتَج]** لم تنشر Apple قاعدة خاصّة بـ `App.init()` في SwiftUI. لكنه يشغل الخانة نفسها التي يشغلها `didFinishLaunching`: متزامن، خيط رئيسي، قبل أوّل إطار. فكل نصّ أعلاه ينطبق عليه حرفياً.

### 6.2 القياس — وتغيير API مهمّ لا يعرفه كثيرون

- **⚠️ `MXAppLaunchMetric` أُهمِل في iOS 27.** وثيقة Apple: *"Use `MetricResult` instead, and read the `TimeToFirstDrawMetric`, `OptimizedTimeToFirstDrawMetric`, `ApplicationResumeTimeMetric`, or `ExtendedLaunchMetric` cases instead."* <https://developer.apple.com/documentation/metrickit/mxapplaunchmetric>
- **`DYLD_PRINT_STATISTICS` ميت.** Apple DTS (سبتمبر 2021): *"iOS 15 and macOS Monterey have a new version of dyld… You should profile your app launches [with the Time Profiler instrument] instead."* <https://developer.apple.com/forums/thread/689581>
- **الأدوات الموصى بها اليوم:** Xcode Organizer → لوحة **Launch Time** (مليّ ثوانٍ من النقر حتى أوّل شاشة، بعد شاشة الإقلاع الساكنة، بمئويّات 50/90) → لوحة **Launches** (أطول الدوالّ ونسبتها) → قالب **App Launch** في Instruments (ملف زمني + تتبّع حالة الخيوط) → أداة **dyld Activity** (زمن المُهيّئات الساكنة) → **`os_signpost`** لما بعد أوّل إطار.
- **جديد في Xcode الحالي:** زرّ **«Generate Recommendations»** في لوحة Launches يمرّر كومة الاستدعاء ونسبة مساهمتها إلى مساعد الكود.
- **⚠️ التسخين المسبق (prewarming، iOS 15+) يشوّه كل قياس.** Apple: النظام *"may 'prewarm' your app… creates the process and loads linked libraries, then suspends it without running application code."* <https://developer.apple.com/documentation/uikit/about-the-app-launch-sequence>
  الحجم الواقعي: **Uber أبلغت عن «زيادة 130٪ في قياس الإقلاع الكلّي»** بسبب التسخين، فانتقلت إلى MetricKit + signposts مخصّصة. <https://www.uber.com/en-US/blog/measuring-performance-for-ios-apps-at-uber-scale/> (20 أبريل 2023)
- **تصحيح لازم:** الادّعاء الشائع بأن iOS 26 يجلب «إقلاعاً أسرع بـ 28٪» **لا مصدر رسمياً له** — أثره ينتهي إلى منشور Medium فقط. **لا تستشهد بهذا الرقم.**

### 6.3 شاشات الإقلاع والـ splash

مغطّى بالكامل في §4.2 أعلاه (HIG «Launching»، `UILaunchScreen`، عدّاد `scene-create`). ونضيف:

- **شاشة الإقلاع لا توقف العدّاد.** Apple: *"Drawing the `default.png` or launch-screen storyboard happens during this time, and its appearance doesn't end the launch-time counter."* العدّاد يتوقّف عند أوّل إطار حقيقي — أي عندنا **بعد** الـ 750 ms.
- **`UILaunchScreen` (iOS 14+)** يقبل `UIColorName` / `UIImageName` / `UIImageRespectsSafeAreaInsets` + عناصر نائبة لأشرطة التنقّل. <https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen>
- **استعادة الحالة إرشاد HIG لا تحسيناً:** *"Restore the previous state when your app restarts so people can continue where they left off."*

### 6.4 تأجيل العمل عن مسار الإقلاع

سلّم Apple المرتّب، من «Reducing your app's launch time»:
1. أزل عمل ما قبل `main` (مُنشئات C++ الساكنة، `+load`، `__attribute__((constructor))`).
2. **قلّل أُطُر الطرف الثالث الديناميكية** — *"Each additional third-party framework that your app loads adds to the launch time."*
3. استخدم **mergeable dynamic libraries** (Xcode 15+).
4. أخرج العمل الغالي من مُفوَّض التطبيق؛ هيّئ التخزين والخدمات **عند أوّل استخدام**.
5. قلّل تعقيد العرض الأوّل.

**ومثال Apple الحرفي لـ «أظهر هيكلاً ثم املأه»:** *"a photo gallery app might show a collection of image thumbnails by default… If the app is launching with no restored state, it only needs to show a placeholder for a screenful of thumbnails and fill them in with real image thumbnails once the app has finished launching."*
**وباركت صراحةً «القديم ثم التحديث»:** *"Defer synchronization of the data model with a network service until the app is running, if it makes sense to show stale content to the user while the content is being refreshed."*

**تحذير مهمّ:** WWDC19‑423 يحذّر من **انقلاب الأولويّات**: *"a symptom known as priority inversion, where a given thread is being blocked by a separate thread that has a lower QoS."* — أي أن `Task.detached(priority: .background)` صحيح لعمل «أطلق وانسَ» (تحليلات، تسخين كاش، prefetch)، وخطأ لأي شيء ينتظره الإطار الأوّل. لما يغذّي الشاشة الأولى استخدم `.task` (WWDC23‑10160: *"That way, the app is responsive when the expensive data loading operation occurs."*).

**رافعة إضافية حقيقية:** Sentry/Emerge فتحت مصدر **FaultOrdering** (18 يونيو 2025) الذي يولّد ملفّات ترتيب رموز تجمّع رموز الإقلاع الحرجة معاً وتقلّل أخطاء الصفحات؛ أرقامهم: *"we've seen apps have a 20% improvement in startup time."* يعمل داخل XCUITest فيُمكن أتمتته. <https://blog.sentry.io/open-source-tool-speed-up-ios-app-launch/>

### 6.5 Keychain و UserDefaults على الخيط الرئيسي

مغطّى في §3.3. ونضيف نقطتين:

- **[فجوة معلنة]** لم نجد رقماً مليّ‑ثانوياً موثوقاً لتكلفة رحلة Keychain واحدة على iOS الحديث. الموجود هو تحذير Apple الكيفي فقط. **عامِل أي رقم محدَّد على أنه غير موثَّق حتى تقيسه بنفسك.**
- **خطر ثانٍ أكّده Apple DTS (أكتوبر 2025):** قبل أوّل فتح للجهاز، العناصر بـ `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — **وهي بالضبط ما نستخدمه** (`Core.swift:795`) — تُرجع `errSecInteractionNotAllowed`. إرشادهم: *"design your app to gracefully handle scenarios where protected data is inaccessible."* والكود عندنا **يفعل ذلك بشكل صحيح**: `Core.swift:1040-1047` يرفض تخزين الـ `nil` مؤقتاً تحديداً لهذا السبب، والتعليق هناك يشرحه. **هذا بند مُصاب بشكل جيّد بالفعل — لا تلمسه.**
- **`UserDefaults`:** الكتابات تحدّث النسخة في الذاكرة فوراً وتذهب للقرص **لا تزامنياً**؛ النوع آمن للخيوط؛ و`synchronize()` **مُهمَل** (*"this method is unnecessary and shouldn't be used"*). قراءة `Bool` واحدة لن تكون عنق الزجاجة أبداً. <https://developer.apple.com/documentation/foundation/userdefaults>

### 6.6 الهياكل العظمية والشعور بالفوريّة

- **توصية Apple نفسها هي «هيكل ثم املأ»** — انظر اقتباس معرض الصور في §6.4.
- **نمط «الوظيفة الجزئية خير من الانتظار»:** *"Initialize a restricted subset of the app's behavior that's known to be viable on initial launch."*
- **`redacted(reason: .placeholder)`** (iOS 14+) و**`ContentUnavailableView`** (iOS 17+) هما الأداتان الرسميّتان.
- **تكاليف أوّل رسم في SwiftUI (WWDC23‑10160):** *"the row count resulting from a ForEach in a List is equal to the number of elements multiplied by the number of views produced for each element. You need to ensure the number of views per element is a constant."* — أي أن الشروط داخل `ForEach` و`AnyView` تكسر ذلك وتكلّف زمن تحميل.
- **العمل بعد أوّل إطار غير مرئي للمقياس ومرئي للمستخدم:** *"if your app renders a document after opening, the user will likely wait on the document to render and perceive it as part of your launch time, even though the system will end the launch measurement while you show a loading icon."* — **هذه بالضبط حالتنا: مقياس Apple سيقول إن إقلاعنا انتهى عند الهيكل العظمي، والمستخدم سيقول إنه لم يبدأ بعد.** ولهذا `os_signpost` ضروري.

**[فجوة معلنة]** لم نتمكّن من الوصول إلى منشور هندسي أوّلي من Netflix / Spotify / Disney+ / YouTube حول «استعادة لقطة آخر واجهة مرسومة عند الإقلاع». الادّعاء الشائع بأن هذه التطبيقات تحفظ وتعيد تشغيل لقطة الشاشة الأولى **لم نستطع توثيقه**، ونفضّل الإفصاح عن ذلك على تلبيسه بمدوّنة ثانوية. المصدر الوحيد الكبير الذي تحقّقنا منه هو منشور Uber، وهو عن **القياس** لا عن اللقطات.
**[مستنتَج]** لكنّنا لا نحتاج استشهاداً خارجياً أصلاً: «هيكل ثم املأ» من Apple + «استعد الحالة السابقة» من HIG يصفان النمط نفسه بسلطة أعلى.

### 6.7 SQLite/GRDB مقابل فكّ JSON ضخم

مغطّى في §5.2 و§5.4. ونضيف تحذيراً مباشراً:

- **أسوأ حالة هي خلط الاثنين.** GRDB issue #1365 (27 أبريل 2023): جلب ~100 ألف صفّ بأعمدة تحوي JSON يحتاج `JSONDecoder` — *"once it tries to decode a JSON column, the fetch total time is increased by 2000% compared with the fetch of primitive types."* <https://github.com/groue/GRDB.swift/issues/1365>
  **جدولنا آمن من هذا:** `CatalogDB.Chan/Mov/Ser` (`CatalogDB.swift:39-68`) كلّها أعمدة بدائيّة، بلا عمود JSON واحد. ✅
- **[مصدر ضعيف — نُعلمه ولا نؤكّده]** ادّعاء «GRDB أسرع 20× من SwiftData في الإدراج» من مدوّنة ثانوية؛ لم نتحقّق منه. ومقارنة Emerge Tools بين SwiftData و Realm (19 يونيو 2024) **لا تشمل GRDB ولا SQLite الخام** فلا تجيب سؤالنا؛ نقطتها المفيدة الوحيدة أن كلا المحرّكين **O(n) للمسح الكامل** — أي أن قراءة جدول كامل عند الإقلاع تتوسّع خطياً مهما كان المحرّك.

---

## 7 — التوصيات مرتَّبة بـ (الأثر المحسوس) ÷ (خطر كسر البناء)

| # | التوصية | الأثر المحسوس | خطر البناء | الجهد | الحكم |
|---:|---|---|---|---|---|
| **1** | **إلغاء التأخير الثابت + بدء تحميل الكتالوج أثناء الـ splash** | **عالٍ جداً — 500 ms مباشرة + إخفاء ثوانٍ من فكّ الترميز** | **ضئيل** | 20 دقيقة | ✅ **ابدأ من هنا** |
| **2** | **رسم أوّل سريع لـ Home من `CatalogDB` (إضافي، غير هادم)** | **عالٍ جداً — يحوّل ثوانٍ إلى ~10 ms لأوّل بوستر** | متوسّط | 1–2 يوم | ✅ الخطوة الكبرى الثانية |
| **3** | `UIUserInterfaceStyle = Dark` في `Info.plist` | متوسّط — يزيل وميضاً أبيض يراه كل مستخدم في الوضع الفاتح | ضئيل | دقيقتان | ✅ افعله مع #1 |
| **4** | حذف `setActive(true)` الزائدة عند الإقلاع | منخفض زمنياً (5–30 ms) · **عالٍ تجربةً — يتوقّف عن قطع موسيقى المستخدم** | منخفض (يلزم تغيير مقترن) | 10 دقائق | ✅ افعله — لسبب التجربة لا لسبب المللي ثانية |
| **5** | تخزين `DeviceIdentity.current` مؤقتاً | منخفض (10–50 ms) — **على الحدّ الأدنى للإحساس** | ضئيل | 10 دقائق | ✅ رخيص، وهو تصحيح لخلل يناقض تعليقه |
| **6** | تأجيل `Diagnostics.start()` و`DownloadService.shared` عن ما قبل أوّل إطار | منخفض (20–60 ms) — **[تخمين]، وغالباً غير محسوس** | منخفض | 20 دقيقة | 🟡 اختياري |
| **7** | التحوّل الكامل للقوائم إلى صفح SQLite | **الأكبر بنيوياً** | **عالٍ** | 4–7 أيام | 🟡 بعد #2 وبعد إصلاح فجوة التعبئة (§5.5‑د) |
| **8** | `use_frameworks! :linkage => :static` | **5–15 ms — لا يشعر به أحد** | **متوسّط‑عالٍ (لا بناء محلي)** | 5 دقائق + دورة CI | ⛔ **لا تفعل** |

---

## 8 — التغييرات الدقيقة (كود جاهز، لفريق لا يستطيع البناء محلياً)

### 8.1 [الأولوية 1] إلغاء الوقت الميت وبدء التحميل مبكّراً

**(أ) قلّص المؤقّتين.** في `BlankTV/AuthViews.swift:72-75`:

```swift
        // كان: .now() + 0.5  … ثم  .now() + 0.25   →  750 ms ميتة
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.20)) { logoOpacity = 0; textOpacity = 0; macOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { onComplete() }
        }
```

`750 ms → 250 ms`. **توفير صافٍ: 500 ms في كل إقلاع.** لمسة العلامة التجارية تبقى قائمة (شعار يظهر ثم يتلاشى)، لكنها تتوقّف عن كونها انتظاراً.

**(ب) — وهذا الجزء الأهمّ — ابدأ جلب الكتالوج أثناء الـ splash.** في `BlankTV/BlankTVApp.swift:194-196`:

```swift
        if !splashDone {
            SplashView { splashDone = true }
                // سخّن الكتالوج بينما الـ splash على الشاشة، بدل أن يبدأ بعده.
                // PlaylistService.load() وحيدة الطيران (Core.swift:1788-1795)، فنداء
                // HomeVM لاحقاً سينضمّ إلى هذا الجلب نفسه بدل أن يبدأ ثانياً.
                // لا نلمس أي حالة في HomeVM هنا عمداً — فلا rebuildHero مكرّر ولا
                // prefetch مزدوج.
                .task {
                    guard auth.loggedIn, !Store.shared.demoMode else { return }
                    _ = try? await PlaylistService.shared.load()
                }
        } else {
```

**لماذا هذا آمن بالضبط:** `PlaylistService.load()` (`Core.swift:1788-1795`) يحتفظ بـ `inFlight: Task` ويعيد `content` المخزَّن إن وُجد. فحين يصل `HomeVM.loadMovies()` لاحقاً إلى `ContentService.movies()`، يصطدم بـ `if let content, !force { return content }` (`Core.swift:1789`) ويعود **فوراً**. لا شبكة مضاعفة، ولا فكّ ترميز مضاعف، ولا حالة عرض ملموسة.

**الأثر المشترك:** بدل `750 ms انتظار → ثم 1.5–5 s فكّ ترميز` نحصل على `250 ms + (فكّ الترميز جارٍ منذ اللحظة صفر)`. أي أن الـ 250 ms صارت **تغطية لعمل حقيقي**، وهو بالضبط ما يفترض بالـ splash أن يكون.

### 8.2 [الأولوية 3] إزالة الوميض الأبيض

أضف إلى `BlankTV/Info.plist` داخل الـ `<dict>` الجذر:

```xml
	<key>UIUserInterfaceStyle</key>
	<string>Dark</string>
```

**لماذا هذا المفتاح لا `UILaunchScreen`:** المشروع يضع `INFOPLIST_KEY_UILaunchScreen_Generation = YES` (`project.pbxproj:300`, `:330`) مع `GENERATE_INFOPLIST_FILE = YES` **و** `INFOPLIST_FILE` مخصّصاً — فإضافة قاموس `UILaunchScreen` يدوياً قد تتصادم مع القاموس المولَّد. أمّا `UIUserInterfaceStyle` فليس ضمن المفاتيح المولَّدة، فلا تصادم ممكن. وهو يجعل `systemBackground` أسودَ فتصير شاشة الإقلاع مطابقة لـ `Color.s8kBlack` في `AuthViews.swift:21`.
**الخطر:** يفرض الوضع الداكن على مستوى UIKit — وهو ما يفرضه التطبيق أصلاً في `BlankTVApp.swift:176`. **متّسق، ولا انحدار ممكن.**

### 8.3 [الأولوية 4] حذف تفعيل جلسة الصوت الزائد

**تغييران مقترنان — يجب تطبيقهما معاً:**

**(أ)** في `BlankTV/BlankTVApp.swift:303-313`، احذف سطر التفعيل فقط:

```swift
    private func configureAudio() {
        do {
            // نضبط الفئة فقط. التفعيل (setActive) ينتمي إلى بدء التشغيل، لا إلى الإقلاع:
            // NowPlayingManager.configure() يفعله بالفعل من كلا المحرّكين
            // (PlayerEngine.swift:364 و VLCPlayer.swift:311). وتفعيله هنا كان يقاطع
            // صوت التطبيقات الأخرى في كل مرّة يُفتح فيها التطبيق، دون أي مقابل.
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
        } catch {
            print("Audio session: \(error)")
        }
    }
```

**(ب)** في `BlankTV/VLCPlayer.swift:751` — **إلزامي**، وإلا فقدنا خيارات AirPlay/Bluetooth لأن `configure()` يكتب فوق الفئة بخيارات أقلّ:

```swift
        try? session.setCategory(.playback, mode: .moviePlayback,
                                 options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP])
```

### 8.4 [الأولوية 5] تخزين هويّة الجهاز مؤقتاً

**تغييران مقترنان.**

**(أ)** `BlankTV/DeviceID.swift:15-21`:

```swift
    /// نسخة محفوظة في الذاكرة لعمر العملية. النمط `nonisolated(unsafe) static var`
    /// مستخدم بالفعل في هذا المشروع (Core.swift:36، Core.swift ~1940).
    private nonisolated(unsafe) static var cached: String?

    /// Cached, stable ID in the form `AA:BB:CC:DD:EE:FF` (uppercase).
    /// كان هذا `static var` محسوباً بلا تخزين رغم ما يقوله تعليقه: كل قراءة كانت
    /// رحلة SecItemCopyMatching كاملة + بناء NSRegularExpression جديداً. و SplashView
    /// يقرؤه من جسمه (AuthViews.swift:47) الذي يُعاد تقييمه مع كل قلبة @State في
    /// startAnimation()، بالإضافة إلى ActivationService.swift:108.
    static var current: String {
        if let cached { return cached }
        if let saved = Keychain.shared.deviceID, isValid(saved) { cached = saved; return saved }
        let generated = generate()
        Keychain.shared.deviceID = generated
        cached = generated
        return generated
    }

    /// يجب أن يناديها كل ما يمحو الهويّة المخزَّنة، وإلا سلّمنا قيمةً حُذفت للتوّ.
    static func invalidateCache() { cached = nil }
```

**(ب)** `BlankTV/Core.swift:781` — `Keychain.deleteDeviceID()` تُنادى من حذف الحساب (`Services.swift:341`)، فيجب أن تُبطل النسخة:

```swift
    func deleteDeviceID() { delete(.deviceID); DeviceIdentity.invalidateCache() }
```

### 8.5 [الأولوية 6 — اختياري] تأجيل العمل عبر الحدود العمليّاتية

**(أ)** `BlankTV/Diagnostics.swift:18-19` — اجعلها حصينة ضدّ النداء المتكرّر أوّلاً:

```swift
    private var started = false
    /// Register as a MetricKit subscriber (call once, early at launch).
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }
```

**(ب)** احذف `Diagnostics.shared.start()` من `BlankTVApp.swift:167`، ثم في `BlankTVApp.swift:94-106`:

```swift
    func applicationDidBecomeActive(_ application: UIApplication) {
        KeyboardDismisser.shared.install()
        // كل ما تحت هذا السطر عملُ إقلاعٍ لا يحتاجه الإطار الأوّل، وكلّه يعبر حدوداً
        // عمليّاتية: UNUserNotificationCenter يفتح XPC مع usernotificationd، وبناء
        // URLSession الخلفية يسجّل مع nsurlsessiond، و MXMetricManager يقرأ من القرص.
        // القفزة إلى الدورة التالية للـ runloop تدع الإطار الأوّل يُسلَّم أوّلاً.
        // DispatchQueue.main.async عمداً بدل Task {}: لا Sendable ولا عزل يتغيّر.
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().delegate = self
            Diagnostics.shared.start()
            // لمس هذا الـ singleton حمّال معنى — انظر التعليق الأصلي: init يعيد بناء
            // جلسة التنزيل الخلفية (وهو ما يعيد وصلنا بالنقل الجاري) ثم يشغّل
            // reconcileOnLaunch الذي يستأنف ما قتله الإغلاق القسري.
            _ = DownloadService.shared
        }
    }
```

**تحذير:** هذا أكثر تغييرات القسم عرضةً لخطأ ترجمة (التقاط `self` داخل مُغلِق من مُفوَّض التطبيق). المكسب **[تخمين] 20–60 ms، وغالباً غير محسوس**. **لا تُدرجه في نفس البناء مع #1 و#3** — أرسله في دورة CI لاحقة حتى لا يُعرّض المكسب الكبير لخطر بناء فاشل.

### 8.6 [الأولوية 2] رسم أوّل سريع من `CatalogDB` — الشكل المقترح

**المبدأ: إضافي بالكامل، غير هادم.** لا نغيّر أي مسار قائم. إن كانت القاعدة فارغة، لا يحدث شيء ويبقى سلوك اليوم كما هو.

الفكرة: `HomeVM` تحتاج **≤ 70 صفّاً** لترسم (§5.4). أضف مساراً يقرؤها من SQLite ويملأ `heroItems`/`topMovies`/`newMovies`/… فوراً، بينما `PlaylistService.load()` الكامل يعمل خلفه ويستبدل النتيجة عند وصولها.

**متطلّبات مسبقة إلزامية قبل كتابة سطر واحد:**
1. **هجرة `v3` تضيف فهرسين** إلى `CatalogDB.swift:75-143` — على `rating` كعدد حقيقي وعلى `id` كعدد صحيح، لكل من `movie` و`series`. بدونهما يصير Top‑10 و«الأحدث» مسحاً كاملاً.
2. **اجعل `CatalogDB.save` موثوقاً:** يُنادى اليوم من مسار الشبكة فقط (`Core.swift:1854`, `:1901`) ويدرج 20–50 ألف صفّ في معاملة واحدة. قسّمها إلى دفعات، وأضف علامة اكتمال، ولا تقرأ منها إلا بعد أن ترفع تلك العلامة. **هذه هي المخاطرة الحقيقية الوحيدة في البند كلّه.**
3. اكتب `channelCategoryCounts` و`seriesCategoryCounts` على غرار `movieCategoryCounts` الموجود (`CatalogDB.swift:273-280`).

لن نكتب الكود هنا: البند يحتاج قراراً من المالك أولاً (إنه يوم إلى يومين، وله متطلّب مسبق)، وقاعدتنا ألّا نقترح ما لم نتحقّق منه. لكن كل ما يلزم لتنفيذه محدَّد أعلاه بالسطر والملف.

---

## 9 — كيف نحوّل هذه الاستنتاجات إلى قياسات (لا نملك بناءً محلياً)

| السؤال المفتوح | القياس الحاسم |
|---|---|
| **ما هو الرقم الحقيقي لأوّل إطار؟** | Xcode Organizer → **Launch Time** بعد أوّل بناء TestFlight، عند المئويّتين 50 و90. هذا يقيس حتى أوّل إطار — أي **بعد** الـ 750 ms، فالتحسين سيظهر مباشرةً |
| **أين يذهب زمن ما قبل `main`؟** | Instruments → قالب **App Launch** + أداة **dyld Activity**. ستكشف حصّة `MobileVLCKit` من rebase/bind والمُهيّئات الأربعين |
| **كم يستغرق فكّ ترميز الكتالوج فعلاً؟** | ضع `os_signpost` حول `Core.swift:1749` (فكّ الترميز) و`Core.swift:1750` (`content(from:)`) وحول `HomeView.swift:145` (`rebuildHero`). **هذا القياس الأهمّ في التقرير كلّه** — كل تقديراتنا للثواني تعتمد عليه |
| **ما حجم ملف الكاش الحقيقي؟** | على جهاز حقيقي: `Caches/S8KCatalog/cat_*.json` (`Core.swift:1728`). رقم واحد يحسم النطاق `1.5–5 s` |
| **هل `CatalogDB` مُعبَّأ فعلاً بعد إقلاع بارد؟** | `CatalogDB.isPopulated(scope:)` (`CatalogDB.swift:170-177`) في مسار تشخيصي. `TECH_ADJUDICATION.md:59` يشكّ في ذلك — **تحقّق قبل بناء #2 عليه** |
| **كم تكلّف رحلة Keychain عندنا؟** | `signpost` حول `Core.swift:1043` (`Keychain.shared.m3uURL`). لا مصدر منشور يعطي رقماً — يجب أن نقيسه بأنفسنا |
| **هل يشوّه التسخين المسبق قياساتنا؟** | اقرأ متغيّر البيئة `ActivePrewarm` **قبل `main`** (UIApplication يمسحه قبل انتهاء `didFinishLaunching`)، وافصل عيّنات الإقلاع المُسخَّن كما فعلت Uber |

---

## 10 — ما لم نستطع إثباته، مذكوراً صراحةً

1. **لا رقم زمني واحد في هذا التقرير قيس على جهاز.** كلّها **[مستنتَج]** أو **[تخمين]**. المقيس هو البنية والثنائي فقط.
2. **لا رقم موثوق لتكلفة `SecItemCopyMatching`.** بحثنا ولم نجد؛ الموجود تحذير Apple الكيفي فقط.
3. **لم نوثّق أن Netflix/Spotify/Disney+ تستعيد «لقطة» عند الإقلاع.** الادّعاء شائع ولم نجد له مصدراً أوّلياً. لا تبنِ عليه.
4. **حجم الكتالوج (≈35–42 MB) موروث من `PERF_LOGIN_LOAD.md`**، وهو تقدير هندسي من الفريق لا قياس. النطاق `1.5–5 s` يرث هذا الشك بالكامل.
5. **`WebSearch` كانت مستنفدة** لهذه الجلسة؛ كل البحث تمّ عبر `WebFetch` على مصادر أوّلية. لم نتمكّن من الوصول إلى معايير أداء مستقلّة لعام 2025–2026 لتكلفة الـ dylib الواحدة على عتاد A17/A18.
6. **`MobileVLCKit 3.6.0` مبنيّ بأدوات قديمة** — `Info.plist` الخاصّ به (بإصدار 3.7.3 المنشور فبراير 2026 أيضاً) يعلن `DTXcode = 1330` (Xcode 13.3) و`DTSDKName = iphoneos15.4`. لم نتمكّن من التحقّق مما إذا كان هذا يسبّب احتكاكاً في مراجعة App Store اليوم. **يستحقّ متابعة منفصلة.**

---

## 11 — الخلاصة في سطرين

> **الوقت الميت الوحيد المؤكّد بدقّة في مسارنا هو `750 ms` من مؤقّت splash ثابت في `AuthViews.swift:72-75` — وهو أيضاً ما يؤخّر بدء العمل الحقيقي. إصلاحه بتغيير من عشرين دقيقة وبخطر يكاد يكون معدوماً.**
> **والعمل الحقيقي نفسه — فكّ ترميز الكتالوج كاملاً لعرض ثمانية بوسترات — يجلس فوق مخزن SQLite مبنيّ ومُعبَّأ وجاهز لا يقرأ منه أحد. هذه هي الثانية الكبرى، وهي تستحقّ يومين لا خمس دقائق.**
