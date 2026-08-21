# خطة الاكتمال من طرف إلى طرف — BLANK TV

**التاريخ:** 2026-08-20 · **الحالة عند الكتابة:** `main` @ `ddcdf50` · 26 ملف Swift · 22,630 سطر

## المنهجية — اقرأ هذا أولاً

هذه الخطة مبنية على شيئين فقط:

1. **تحليل ساكن للكود** — كل ادّعاء عن كودنا مربوط بـ `file:line` أو بأمر بحث قابل لإعادة التشغيل.
2. **تحقّق ويب من كل توصية** — لم تُكتب توصية واحدة من الذاكرة. المصادر في §7.

**ما لم يُفعل:** لم يُشغَّل التطبيق ولم يُعمل profiling على جهاز. كل رقم أداء هنا إمّا مشتقّ من بنية الكود، أو منقول من تقارير `PERF_*.md` السابقة مع التحقق من أنه ما زال صحيحاً. **الأرقام المطلقة (ms، MB) غير مقيسة ويجب قياسها قبل وبعد كل تغيير.**

---

## 0. تصحيحات ظهرت أثناء التحقق ⚠️

هذا القسم موجود لأن التحقق غيّر التوصيات فعلاً. لو حُفظت الخطة بلا تحقق لاحتوت خطأين:

### تصحيح 1 — VLCKit 4 **ألفا**، وليس مستقراً

**ما كان سيُكتب:** «رحّل إلى VLCKit 4 عبر SPM للحصول على PiP».

**الحقيقة المتحقَّق منها:** أحدث ما نُشر هو `4.0.0a19` / `a20` / `a21` — **إصدارات ألفا**. المستودع المجتمعي `virtualox/vlckit-spm` أُرشِف في 2026-07-31. VideoLAN دمجت دعم SPM الرسمي في 2026-07-20، لكن **الفرع نفسه ما زال ألفا**.

**القرار:** ❌ **لا تعتمد VLCKit 4 في الإنتاج الآن.** ابقَ على `MobileVLCKit 3.6.x`. راقب صدور 4.0.0 مستقراً.

### تصحيح 2 — `Font.system(size:relativeTo:)` **غير موجودة**

**ما كان سيُكتب:** «حوّل `S8KFont` إلى `.system(size:relativeTo:)`».

**الحقيقة المتحقَّق منها:** `relativeTo:` موجودة على `Font.custom(_:size:relativeTo:)` فقط (iOS 14+). **`Font.system` لا تملك هذه المعاملة إطلاقاً.**

**الطريق الصحيح لخطّ النظام:** انظر §م3.3.

---

## 1. تقييم البنية التحتية

| المحور | التقييم | الدليل |
|---|---|---|
| هندسة المشغّل | 🟢 ممتاز | `StreamRouter` + `EngineDecisionCache` + `EngineStats` + failover |
| ذاكرة الصور | 🟢 ممتاز | `DesignSystem.swift:1388-1560` — NSCache بحد تكلفة، URLCache قرص، downsample، `byPreparingForDisplay`، single-flight بـ token، ThumbHash |
| أمن البيانات | 🟢 جيد جداً | كل الاعتماديات في Keychain (`Core.swift:758`)، عزل لكل حساب، `deleteAccount` يمسح Keychain + القرص + SQLite |
| نظافة الكود | 🟢 جيد جداً | `try!`/`as!`: 1 · `ForEach(id:\.self)`: 0 · LazyStacks: 34 موضع |
| **الاختبارات** | 🔴 **معدومة** | `find . -iname "*test*"` → **صفر نتيجة** |
| **طبقة البيانات** | 🔴 **نصف موصولة** | §2.1 |
| المراقبة | 🔴 ضعيف | MetricKit فقط (`Diagnostics.swift:15`) |
| الشبكة | 🟠 ناقص | صفر `NWPathMonitor` / `import Network` |
| إمكانية الوصول | 🔴 ضعيف | 179 × `.system(size:` مقابل 0 × `@ScaledMetric` |
| التزامن | 🟠 متأخر | `SWIFT_VERSION = 5.0` (`project.pbxproj:314`) |
| الترجمة | 🟠 غير قياسي | قاموس Swift (396 مفتاح، `Core.swift:73`)، لا `.xcstrings` ولا `.lproj` |

---

## 2. الفجوات الحرجة

### 2.1 مخزن SQLite مبنيّ بالكامل ومهجور

`CatalogDB.swift` يحوي مخزن GRDB كاملاً: ترقيم keyset، فهارس مغطّية `(scope[,category],pos)`، فهرس FTS5.

| الدالة | السطر | مستهلكون |
|---|---|---|
| `pageChannels` / `pageMovies` / `pageSeries` | 206 / 216 / 226 | **صفر** |
| `load` / `isPopulated` | 147 / 170 | **صفر** |
| `countMovies` / `movieCategoryCounts` / `categories` | 264 / 273 / 281 | **صفر** |
| `search` + `*ByIds` | 188 / 238-254 | ✅ `SearchVM` فقط |
| `imageHash` / `saveImageHash` | 345 / 359 | ✅ ThumbHash |

**المسار الحيّ اليوم:** `CatalogDiskCache` (`Core.swift:1810`) → فكّ ترميز JSON كامل → `M3UContent` في الذاكرة → قواميس `grouped` في `LiveTVVM` + `MoviesVM` + `SeriesVM`.

التعليق في `CatalogDB.swift:12-17` يعترف: «STEP 2 (isolated) … NO consumer yet … until the VMs are switched over (step 4)». **الخطوة 4 لم تُنفَّذ.**

**الأثر:** على 50 ألف عنصر، فكّ ترميز الفهرس كاملاً في **كل إقلاع بارد**، والفهرس كله مقيم في RAM طوال عمر الجلسة.

### 2.2 `DatabaseQueue` بدل `DatabasePool`

`CatalogDB.swift:33` يفتح `DatabaseQueue` = اتصال واحد، كل شيء مسلسل. أثناء استيراد فهرس كبير **يتجمّد البحث و ThumbHash معاً**.

توثيق GRDB: `DatabasePool` مع WAL يسمح بقراءات متزامنة أثناء الكتابة، وهو المناسب لحمل «قراءة عالية / كتابة معتدلة». وينصّ أيضاً على أن `DatabaseQueue` هو الافتراضي الآمن — **لذا هذا تغيير مقصود لسبب مُقاس، لا ترقية تلقائية.** WAL يتطلّب قاعدة على القرص (متحقَّق: `catalog.sqlite` على القرص ✅).

### 2.3 صفر اختبارات

22,630 سطر بلا اختبار واحد، و`codemagic.yaml` فيه بناء ونشر فقط — **لا خطوة اختبار**.

منطق نقيّ قابل للاختبار فوراً بلا أي إعادة هيكلة:
`RailEngine.classify` / `cleanTitle` · `RegionClassifier.region` · `M3UParser.entries` / `build` · `StreamRouter.classify` / `defaultEngine` · `AuthService.normalizeXtreamHost` · `CatalogText.fold` · `Plate` (توليد حتمي) · `ActivationService.versionLessThan` · `DownloadByteText.string`.

### 2.4 التزامن متأخر جيلاً

`SWIFT_VERSION = 5.0`. Xcode 26 الافتراضي هو Swift 6.2 مع **Approachable Concurrency** و**`Default Actor Isolation = MainActor`**.

الدليل على الحاجة داخل الكود نفسه: `nonisolated(unsafe)` × 2 (`Core.swift:35`, `Core.swift:2177`)، `@unchecked Sendable` × 1 (`DesignSystem.swift:1388`)، `NSLock` يدوي × 3.

و`codemagic.yaml:16-19` يوثّق القنبلة صراحةً: «Xcode 26.4 كسر بناءً كان يمرّ — المصدر لم يتغيّر، الأدوات تغيّرت». **التثبيت على 26.3 تأجيل، لا حلّ.**

### 2.5 نظام backend ميت

`APIConfig.primary = "https://api.invalid/v1"` (`Core.swift:604`). النتائج المتسلسلة:

- `ConfigService.fetchIfStale` (`Services.swift:520`) يفشل دائماً بصمت → `FeaturesConfig` تبقى `.defaults` أبداً
- **7 من 8 أعلام الميزات لا يقرأها أحد** — فقط `hasParental` (`SettingsView.swift:236`)
- `AuthService.login` و`/auth/account` كود ميت
- التعليق نفسه: «الحل الصحيح هو حذف هذا النظام — ~15 موضع استدعاء يستحق commit خاصاً»

### 2.6 نواقص أخرى مؤكَّدة

| البند | الدليل |
|---|---|
| **PiP لا يعمل على VLC** | `VLCPlayer.swift` صفر ذكر لـ PiP · `BasePlayerVM.pipSupported = false` (`:287`) · متجاوَزة في `AVPlayerVM:322` فقط. و`StreamRouter` يوجّه كل VOD غير HLS إلى VLC → **معظم الأفلام بلا PiP** |
| **لا كشف اتصال** | صفر `NWPathMonitor` / `import Network` |
| **لا معالجة ضغط ذاكرة** | صفر `didReceiveMemoryWarning` |
| **`hashMisses` ينمو بلا حد** | `DesignSystem.swift:1543` — `Set<String>`، إدخال لكل بوستر بلا ThumbHash، لا يُفرَّغ أبداً |
| **لا Dynamic Type** | 179 × `.system(size:` · 0 × `@ScaledMetric` / `relativeTo:` |
| **لا crash reporting حيّ** | MetricKit فقط: مجمَّع، متأخر 24-48h، بلا تنبيهات |
| **`network-caching` ثابت** | `VLCPlayer.swift:273,286` — 1500/1000ms، غير تكيّفي |
| **لا ترجمات خارجية** | `addPlaybackSlave` غير مستخدم |
| **`@Observable` صفر** | كل شيء `ObservableObject` رغم أن الحدّ الأدنى iOS 17 |

---

## 3. مواعيد نهائية خارجية

| الموعد | ما يحدث | أثره علينا |
|---|---|---|
| ✅ 28 أبريل 2026 | بناء إلزامي بـ Xcode 26 / SDK iOS 26 | **مستوفى** — `codemagic.yaml` مثبَّت على Xcode 26.3 |
| ⏳ 1–7 نوفمبر 2026 | تجربة قراءة-فقط لسجلّ CocoaPods | تحذير: قد يفشل `pod install` في تلك النافذة |
| 🔴 **2 ديسمبر 2026** | **سجلّ CocoaPods للقراءة فقط نهائياً** | لا نسخ جديدة من `MobileVLCKit` أو `GRDB.swift`. البناء الحالي يستمر، لكن التحديث يتوقّف |
| ⏳ أكتوبر 2026 | Firebase يوقف دعم CocoaPods | يُرجّح Sentry على Crashlytics (§م3.2) |
| ⏳ غير محدّد | Accessibility Nutrition Labels تصبح إلزامية | اختيارية الآن، وApple صرّحت أنها ستُطلب لاحقاً |

---

## 4. الخطة

### قيود التسلسل — لا تُخرق

```
اختبارات     ──► [أي شيء آخر]     (بلا اختبار كل تغيير مقامرة)
Swift 6      ──► GRDB 7            (GRDB 7 يتطلب Swift 6.1+ / Xcode 16.3+)
SPM          ──► حذف CocoaPods     (الترتيب معكوس يكسر البناء)
DatabasePool ──► الخطوة 4          (وإلا الاستيراد يجمّد كل قراءة أثناء الاختبار)
```

---

### 🔴 المرحلة 1 — الأساس

**م1.1 — إنشاء target اختبارات + Swift Testing**

الإجماع الحالي (2026): **Swift Testing هو الافتراضي للاختبارات الجديدة**؛ XCTest يبقى لـ XCUITest و`XCTMetric` والكود Objective-C. الاثنان يتعايشان في نفس الـ target (ويفضَّل فصلهما بملفات).

ابدأ بالدوال النقية في §2.3 — يوم عمل، وبلا أي إعادة هيكلة.

**م1.2 — خطوة اختبار في CI**

أضف `xcode-project run-tests` في `codemagic.yaml` **قبل** `build-ipa`.

**م1.3 — `DatabaseQueue` → `DatabasePool` + WAL**

`CatalogDB.swift:28-36`. اجعل معاملات الكتابة قصيرة (استيراد على دفعات، لا معاملة واحدة عملاقة) — وإلا يظلّ القارئ محجوباً رغم الـ Pool.

**م1.4 — الخطوة 4 من `CatalogDB`**

وصّل `pageMovies`/`pageChannels`/`pageSeries` بالـ VMs الثلاثة، ثم احذف `CatalogDiskCache` بالكامل. الكود مكتوب ومختبَر بنيوياً — هذه عملية توصيل، لا بناء.

> **قِس قبل وبعد:** ذروة RAM، وزمن الإقلاع البارد، وزمن أول بوستر. `S8KPerf` (`Diagnostics.swift:73`) يعطي تقريراً نصياً جاهزاً.

---

### 🟠 المرحلة 2 — قبل 2 ديسمبر 2026

**م2.1 — ترحيل GRDB إلى SPM** — بسيط، `GRDB.swift` يدعم SPM أصلاً. **ابقَ على 6.x الآن** (7 يحتاج Swift 6 — انظر م2.3).

**م2.2 — ترحيل MobileVLCKit بعيداً عن CocoaPods**

⚠️ **لا ترقِّ إلى VLCKit 4** (ألفا — §0). الطريق: لفّ `MobileVLCKit 3.6.x` كـ `binaryTarget` XCFramework داخل حزمة Swift محلية. هذا نمط موثَّق ومستعمل على نطاق واسع للاعتماديات التي لا تنشر SPM رسمياً.

المكسب المباشر: **يختفي جحيم الـ 429** في `codemagic.yaml:39-63` (خمس محاولات + backoff) لأنه لا يبقى `pod install` أصلاً.

**م2.3 — Swift 6**

`SWIFT_VERSION = 6.0` + `SWIFT_APPROACHABLE_CONCURRENCY = YES` + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

عزل MainActor الافتراضي **يُسقط عدد الأخطاء بشدّة** لأن أغلب ما كان المدقّق يعلّمه هو كود main-thread أصلاً، فتبقى قائمة قصيرة من حدود حقيقية. مواضعنا الأربعة المعروفة (§2.4) هي تلك الحدود بالضبط.

ثم: **فُكّ التثبيت عن Xcode 26.3** في `codemagic.yaml`.

**م2.4 — GRDB 7** (بعد م2.3 حصراً)

7.x يتطلّب Swift 6.1+ / Xcode 16.3+. تغييرات كاسرة موثَّقة في `GRDB7MigrationGuide.md`؛ أبرزها: كل الكتابات صارت معاملات فورية افتراضياً، وإعادة تسمية `CSQLite` → `GRDBSQLite`.

---

### 🟡 المرحلة 3 — الجودة الملموسة

**م3.1 — `NWPathMonitor`**

كائن مراقبة واحد → `@Published var isOnline` → شريط "بلا اتصال" + إعادة محاولة تلقائية عند العودة. اليوم لا يوجد شيء من هذا إطلاقاً.

**م3.2 — مراقبة انهيارات حيّة**

MetricKit وحده لا يكفي لمنتج مباع: مجمَّع، متأخر 24-48 ساعة، بلا تنبيهات ولا تجميع دقيق.

**الترشيح: Sentry.** الأسباب: SPM أصلاً (وFirebase يُسقط CocoaPods في أكتوبر 2026)، وخيار الاستضافة الذاتية، وعدم إدخال SDK جوجل في تطبيق موقفه «مستقل». يتطلّب تحديث `PrivacyInfo.xcprivacy`.

**م3.3 — Dynamic Type** ⚠️ (انظر تصحيح §0-2)

`Font.system` **لا تقبل `relativeTo:`**. الطرق الصحيحة الثلاث:

1. **الأفضل:** أنماط دلالية — `.body` / `.headline` / `.caption` — تتكيّف مجاناً.
2. **لمقاس محدَّد:**
   ```swift
   @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
   Text(t).font(.system(size: titleSize, weight: .semibold))
   ```
3. **لخطّ مسمّى فقط:** `Font.custom("…", size: 15, relativeTo: .body)`.

أضف حدّاً أعلى (`.dynamicTypeSize(...DynamicTypeSize.accessibility3)`) على الشبكات كي لا ينفجر التخطيط.

**نصيحة موثَّقة:** اضبط حجم النص على الافتراضي (Large) وتأكّد أن الشاشة صحيحة، **ثم** حوّل الثوابت إلى `@ScaledMetric`. ووحّد التعريفات في امتداد على `Font` بدل تكرار المقاسات — نملك `S8KFont` بالفعل، فنقطة الدخول جاهزة.

**م3.4 — String Catalog (`.xcstrings`)** ⚠️ **بحذر**

القيد الحقيقي: التطبيق يبدّل اللغة **أثناء التشغيل** (`LocalizationManager`, `Core.swift:31`). `Text` و`String(localized:)` يقرآن من `Bundle.main` بلغة النظام، فالتبديل الفوري **لا يعمل تلقائياً**.

الطريق المتحقَّق منه: `LocalizedStringResource` + قيمة بيئة SwiftUI مركزية للّغة. **تحذير موثَّق:** بيئة SwiftUI لا تصل إلى UIKit ولا إلى الواجهات الخارجية — ولدينا `UIViewRepresentable` × 5 (`AirPlayButton`, `SystemVolumeHost`, `PlayerSurfaceView`, `VLCSurfaceView`, `S8KNoTouchDelay`). خطّط لها صراحةً.

**المكسب:** صفحة متجر متعدّدة اللغات، قواعد جمع، وأدوات ترجمة — وهذا مستحيل مع قاموس Swift.

**م3.5 — حذف `api.invalid`** — النظام كله (~15 موضع) + الأعلام السبعة الميتة.

**م3.6 — نظافة الذاكرة** — `didReceiveMemoryWarning` يفرّغ `hashMemory` و`hashMisses`؛ وسقف لـ `hashMisses` (أو تحويله إلى `NSCache`).

---

### 🟢 المرحلة 4 — توسيع المنتج

**م4.1 — توصيل ما هو مبنيّ** (أرخص مكسب في المشروع):

- رفوف `RailEngine` المنسّقة → `HomeView` (مبنية، غير معروضة)
- شاشة `WatchlistService` (خدمة كاملة بلا واجهة)

**م4.2 — Catch-up / Timeshift** — الآن صار قابلاً للتنفيذ بمواصفة دقيقة:

- **الكشف:** `get_live_streams` يُرجع `tv_archive` (0/1) و`tv_archive_duration` (بالأيام). أظهر الزرّ فقط عند `tv_archive == 1`.
- **الرابط:**
  ```
  http(s)://server:port/timeshift/USER/PASS/DURATION_MIN/YYYY-MM-DD:HH-MM/STREAM_ID.ts
  ```
  أو صيغة الاستعلام: `/streaming/timeshift.php?username=&password=&stream=&start=YYYY-MM-DD:HH-MM&duration=NN`
- ⚠️ **الطوابع بتوقيت UTC** — لا تحويل منطقة زمنية. عندنا `panelTimeZone` (`Core.swift:2177`)؛ يجب ألا يُطبَّق هنا.
- الامتداد `.ts` (الافتراضي) أو `.m3u8`. الأول يذهب إلى VLC عبر `StreamRouter` — وهذا صحيح.

**م4.3 — PiP لمحرك VLC** ⚠️ (انظر تصحيح §0-1)

لا تنتظر VLCKit 4. الطريق المدعوم من Apple لمشغّل مخصّص:

```swift
AVPictureInPictureController.ContentSource(
    sampleBufferDisplayLayer: layer,   // AVSampleBufferDisplayLayer
    playbackDelegate: self             // AVPictureInPictureSampleBufferPlaybackDelegate
)
```

يتطلّب `UIView` طبقتها `AVSampleBufferDisplayLayer`، وتنفيذ الـ delegate (المدى الزمني، حالة الإيقاف). **ملاحظة موثَّقة:** يعمل على iOS؛ على macOS يعمل `AVPlayerLayer` فقط.

**م4.4 — ترجمات `.srt` خارجية** — `addPlaybackSlave` في MobileVLCKit.

**م4.5 — `@Observable` تدريجياً** — القياسات المنشورة: انخفاض 20–30% في إعادة الرسم، والفرق يتضخّم في القوائم الطويلة لأن التتبّع يصير على مستوى الخاصية لا الكائن. ابدأ بالثلاثة الأثقل: `MoviesVM` / `SeriesVM` / `LiveTVVM`.

**م4.6 — لاحقاً:** tvOS · Widgets / Live Activities · Spotlight · تسجيل · Chromecast.

---

## 5. ما لا يجب فعله

| ❌ | لماذا |
|---|---|
| VLCKit 4 في الإنتاج | ألفا (`4.0.0a21`) |
| `Font.system(size:relativeTo:)` | **API غير موجودة** |
| GRDB 7 قبل Swift 6 | يتطلّب Swift 6.1+ / Xcode 16.3+ |
| `.xcstrings` بسذاجة | يكسر مبدّل اللغة الفوري — §م3.4 |
| Liquid Glass كأولوية | غير إلزامي؛ وشريط تبويبنا مخصّص فلن يرثه تلقائياً |
| لمس `S8KListWindow` | `PERF_CATALOG_SCALE.md §0-11`: «سليم ومصمَّم صح — لا تلمس» |
| ترقية Xcode قبل Swift 6 | 26.4 كسر البناء مرة — الترتيب م2.3 ثم فكّ التثبيت |

---

## 6. الخلاصة في سطر

**التطبيق ليس ناقص أفكار — هو ناقص توصيل وتحقّق.** أفضل ثلاث قطع فيه (مخزن SQLite، رفوف RailEngine، خدمة قائمة المشاهدة) مبنية بجودة عالية وغير موصولة، وأخطر نقص فيه ليس ميزة غائبة بل **غياب أي اختبار يثبت أن ما بُني ما زال يعمل**.

---

## 7. المصادر (كلها متحقَّق منها 2026-08-20)

**التزامن وSwift 6**
- https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/
- https://blakecrosley.com/blog/swift-6-2-concurrency-in-practice

**الاختبارات**
- https://blakecrosley.com/blog/swift-testing-vs-xctest
- https://www.codeanatomybyaher.com/articles/swift-unit-testing-xctest-swift-testing-compared

**GRDB**
- https://www.mintlify.com/groue/GRDB.swift/advanced/concurrency
- https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB7MigrationGuide.md

**VLCKit (تصحيح §0-1)**
- https://github.com/videolan/vlckit
- https://github.com/virtualox/vlckit-spm  (مؤرشف 2026-07-31، مبني من tag `4.0.0a21`)
- https://wiki.videolan.org/VLCKit/

**PiP مخصّص**
- https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource
- https://developer.apple.com/videos/play/wwdc2021/10290/
- https://artemnovichkov.com/blog/demystifying-picture-in-picture-on-ios

**CocoaPods → SPM**
- https://kitemetric.com/blogs/cocoapods-sunset-migrate-to-swift-package-manager-now
- https://flutter.dev/blog/saying-goodbye-to-cocoapods
- https://medium.com/@kusalprabathrajapaksha/using-a-cocoapod-as-an-xcframework-in-a-swift-package-07dd66679fa9

**Apple / المتجر**
- https://www.developer.apple.com/news/upcoming-requirements/
- https://developer.apple.com/app-store/review/guidelines/
- https://support.apple.com/en-us/123073

**Dynamic Type (تصحيح §0-2)**
- https://useyourloaf.com/blog/scaling-custom-swiftui-fonts-with-dynamic-type/
- https://sarunw.com/posts/swiftui-scale-custom-font-dynamic-type/

**الترجمة**
- https://techconcepts.org/blog/ios-localization-xcstrings
- https://www.sagarunagar.com/blog/swiftui-app-language-switching-without-restart

**Observation**
- https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/
- https://swiftcrafted.dev/article/swiftui-observable-macro-complete-guide-observation-framework

**Xtream Codes / Catch-up**
- https://deepwiki.com/northernpowerhouse/pvr.dispatcharr/6.1-xtream-codes-api
- https://mintlify.wiki/euzu/tuliprox/api/xtream
- https://forum.kodi.tv/showthread.php?tid=351431

**مراقبة الانهيارات**
- https://techconcepts.org/blog/sentry-vs-crashlytics-ios-crash-reporting
- https://www.drizz.dev/post/best-error-tracking-and-crash-reporting-tools-for-ios-apps
