# صيد تقني — الجولة الثانية
**بحث هندسي مستقل · 2026-07-28 · Blank Prime (SwiftUI · iOS 17.0 كحدّ أدنى · Xcode 26.3 · CocoaPods)**

> **القاعدة الحاكمة (بكلمات المالك):** لا تتبنَّ تقنية من المرجع على الثقة. ابحث عن أحدث ما وصلت إليه
> الصناعة، ودَع **الأحدث والأفضل** يفوز — ولو كان ذلك يعني تجاهل المرجع كلّياً.

> **القيود التي التزمتُ بها حرفياً:** `C:\Users\user\Strong8K-App\Strong8K\iOS\` **للقراءة فقط** — لم
> يُنشأ فيه ولم يُعدَّل ولم يُحذف شيء، ولم يُنفَّذ فيه أي أمر git مُغيِّر. ولم يُعدَّل أي ملف مصدري في
> `blankstor`. الملف الوحيد المكتوب هو هذا الملف.

> **علاقته بـ `TECH_ADJUDICATION.md`:** تلك الجولة حكمت على ثمانية بنود (FTS من الكاش، جاهزية المشغّل،
> `saveProgress` عند `load`، تحصين سجلّ التنزيلات، رايات AirPlay، `DatabasePool`، الـ Keychain، طبقة
> QoE) وثلاث إضافات. **لا يُعاد أيٌّ منها هنا.** هذه الجولة تفتّش في أماكن أخرى: الذاكرة، والقراءة من
> المخزن، ونموذج المراقبة (Observation)، وقوائم العرض الضخمة، وسلوك الخلفية.

---

## 0. جدول الأحكام

| # | البند | الحكم | الفائدة ÷ الخطر | جهد |
|---|-------|-------|------------------|-----|
| **1** | تفعيل القراءة المُصفَّحة من `CatalogDB` (`loadPaged`/`loadMore`) — وطيّ نسخ `filtered` الميتة معها | **ADOPT MODIFIED** | **الأعلى** — أكبر مكسب ذاكرة في التطبيق، والنصف الصعب مدفوع سلفاً | 6–10 س |
| **2** | الهجرة من `ObservableObject` إلى `@Observable` | **REPLACE WITH SOMETHING NEWER** 🔴 | عالية — يُغلق صنفاً كاملاً من العيوب كنّا نسدّده حالةً حالة | 4–6 س (على مراحل) |
| **3** | ميزانية ذاكرة الصور تُشتقّ من الجهاز + مسار واحد للاستجابة لضغط الذاكرة | **REPLACE WITH SOMETHING NEWER** 🔴 | عالية · خطر منخفض جداً | 2–3 س |
| **4** | `PosterCollectionView` (UICollectionView + `UIHostingConfiguration` + prefetch) | **REJECT (الآن)** | منخفضة عندنا — والمرجع نفسه لم يُشغّله | — |
| **5** | تسليم تنزيل Turbo إلى جلسة الخلفية عند `scenePhase == .background` | **REJECT (الآن) — مع قرار مطلوب** | صفر اليوم: `runTurbo` عندنا **شيفرة ميتة لا يمكن الوصول إليها** | — |
| **ج-أ** | *لا يملكه أيٌّ من التطبيقين* — التكيّف مع الحالة الحرارية ووضع الطاقة المنخفضة | **ابنِه — لكن بعد البنود 1 و3** | متوسطة | 2 س |

**السطر الواحد:** **ثلاثة بنود تستحقّ التبنّي** (1، 2، 3) — واحد منها فقط تقنيةٌ يملكها المرجع فعلاً،
واثنان **يتفوّقان على المرجع** بواجهات أحدث. وبندان يُرفضان بعد الفحص، أحدهما لأن المرجع نفسه لم
يُشغّله قط، والآخر لأن الشيفرة المقابلة عندنا **ميتة أصلاً**. ولا شيء في المرجع في مجالات التشغيل أو
الشبكة أو الصور بقي غير مأخوذ — تلك المساحات استُنزفت في الجولة الأولى.

---

## 0.1 تحذير عن المصادر — اقرأه قبل أن تثق بأي سطر

- كل ادّعاء عن شيفرتنا أو عن المرجع **مُتحقَّق منه بالقراءة المباشرة**، ومعه `file:line`. هذه أقوى
  أجزاء التقرير، ولا تعتمد على أي مصدر خارجي.
- كل ادّعاء عن «ما هو الأحدث في 2026» مشفوع برابط. حيث لم أجد **توثيق Apple رسمياً** أقول ذلك
  صراحةً بعبارة **«غير متحقَّق منه لدى Apple»** بدل ملء الفراغ بادّعاء مدوّنة.
- `RESEARCH.md §6` كان قد أوصى سلفاً بـ `@Observable` وبمَخرج `UICollectionView`. **كلاهما لم يُنفَّذ
  حتى اليوم.** إسهام هذا التقرير ليس اكتشافهما، بل **تحكيمهما**: أحدهما يُتبنّى الآن، والآخر يُرفض
  لسبب قِيسَ لا خُمِّن.
- هدف النشر `iOS 17.0` (`Podfile:2` + `project.pbxproj:254`). كل ما هو iOS 18+ فما فوق يجب أن يُسيَّج
  بـ `if #available` مع مسار عامل لـ iOS 17.

---

# البند 1 — تفعيل القراءة المُصفَّحة من `CatalogDB`

## الحكم: **ADOPT MODIFIED** — أسلوب المرجع صحيح، والنصف الصعب مدفوع عندنا سلفاً وغير مستعمل

## ما يفعله المرجع
`MoviesVM.load` (`Strong8K/iOS/Strong8K/ContentViews.swift:1004–1022`) يسأل المخزن أولاً، ثم يتفرّع:

```swift
paged = s0.isEmpty ? false
      : await Task.detached(priority: .userInitiated) { CatalogDB.isPopulated(scope: s0) }.value
if paged { await loadPaged() } else { await loadFallback() }
```

و`loadPaged()` (`:1025–1048`) يقرأ **صفحة واحدة فقط** بـ keyset، خارج الخيط الرئيسي:

```swift
let (cats, counts, first, total) = await Task.detached(priority: .userInitiated) {
    (CatalogDB.categories(scope: s, kind: "movie"),
     CatalogDB.movieCategoryCounts(scope: s),
     CatalogDB.pageMovies(scope: s, category: nil, after: nil, limit: ps),   // ps = 150
     CatalogDB.countMovies(scope: s, category: nil))
}.value
```

و`loadMore()` (`:1051–1065`) يُلحق الصفحة التالية عند اقتراب الشبكة من نهايتها. حالة التصفيح كلها
أربعة حقول: `paged` / `cursor` / `reachedEnd` / `pageSize` (`:983–988`).

## ما نفعله اليوم
**نملك المخزن كاملاً ولا نقرأ منه شيئاً من هذا.**

- `BlankTV/CatalogDB.swift:206–292` يحتوي `pageChannels` و`pageMovies` و`pageSeries` (keyset على عمود
  `pos`، مع `nextCursor`) و`countMovies` و`movieCategoryCounts` و`categories` و`isPopulated`
  (`:170`). **كلها مطابقة لما يحتاجه `loadPaged` — وكلها بلا مستهلك واحد.**
- المستهلكون الوحيدون لـ `CatalogDB` في التطبيق كلّه هم البحث (`ContentViews.swift:3220, 3278–3288`)
  وبصمات الصور (`DesignSystem.swift:1372, 1394, 1397`) والحذف (`Services.swift:342`). **لا شيء
  يستدعي `pageMovies` أو `pageChannels` أو `pageSeries` أو `countMovies` أو `movieCategoryCounts`
  أو `isPopulated`.**
- وبدلاً من ذلك `MoviesVM.load` (`ContentViews.swift:869–884`) يجلب **الكتالوج كاملاً إلى الذاكرة**
  ويبني فوقه أربع بِنى مشتقّة.

### حساب الذاكرة — وهو المبرِّر الحقيقي للبند
`MoviesVM` (`ContentViews.swift:818–853`) يحتفظ في آنٍ واحد بـ:

| الحقل | ما هو | السطر |
|---|---|---|
| `movies: [Movie]` | الكتالوج كاملاً | `:821` |
| `filtered: [Movie]` | **نسخة كاملة ثانية** | `:822` |
| `grouped: [String: [Movie]]` | **نسخة كاملة ثالثة**، موزّعة على قواميس | `:834` |
| `foldedNames: [String]` | سلسلة مطويّة لكل عنصر | `:842` |
| `lastResults: [Movie]` | نتائج آخر استعلام | `:844` |

`Movie` (`Models.swift`) بنية ذات **13 حقلاً نصّياً** — أي ~208 بايت تخزين داخلي لكل عنصر قبل
محتوى السلاسل نفسها. على كتالوج بحجم 176 ألف عنوان (وهو الحجم الذي يقيس عليه المرجع صراحةً في
`ContentViews.swift:1012`) فذلك **~37 ميغابايت لكل نسخة كاملة**. ونحن نحتفظ بثلاث. ونفس النمط
مكرَّر حرفياً في `SeriesVM` (`:2038–2055`) و`LiveTVVM` (`:13–30`).

### 🔴 المكسب الفوري المجّاني: `filtered` عندنا **حقل ميّت**
بحثتُ عن كل قارئ لـ `filtered` في `BlankTV/` كلّها. النتيجة: **يُكتب ولا يُقرأ أبداً**.

- `LiveTVVM.filtered` — يُكتب في `:69` و`:91`، لا قارئ.
- `MoviesVM.filtered` — يُكتب في `:898`، لا قارئ.
- `SeriesVM.filtered` — يُكتب في `:2110`، لا قارئ.

العروض تقرأ `vm.movies` أو `vm.searchResults` (`:1565`) أو `vm.grouped` — لا `filtered`.
**في المرجع هذا الحقل حيّ** (`loadPaged` يضبط `filtered = first.items`، و`loadMore` يضبط
`filtered = movies`، `ContentViews.swift:1038, 1060, 1088`) — أي أنه جزء من آلة التصفيح. عندنا
وُرِث الحقل وبقيت آلته خلفه، فصار **نسخة كاملة من الكتالوج تعيش في الذاكرة بلا غرض**، ومعها
`@Published` تبثّ تغيّراً في كل مرة.

> **افعل هذا أولاً، قبل أي شيء آخر في هذا التقرير:** احذف الحقول الثلاثة (أو اجعلها نافذة التصفيح
> كما في المرجع). **~37 ميغابايت لكل تبويب، بلا أي مخاطرة، في ثلاثة أسطر.**

## هل هناك ما هو أحدث من keyset paging في 2026؟
**لا، والبديل الشائع أسوأ.** التصفيح بـ `LIMIT/OFFSET` يجعل SQLite تمسح وتتخطّى كل صفٍّ قبل
الإزاحة، فتصير الصفحة رقم 1000 أبطأ بألف مرّة من الأولى — بينما `WHERE pos > ? ORDER BY pos LIMIT n`
تصيب الفهرس مباشرة. هذا سلوك مُوثَّق في محرّك SQLite نفسه ([sqlite.org/optoverview.html](https://sqlite.org/optoverview.html))
وليس رأياً. وشيفرتنا في `CatalogDB.swift:216–225` **تنفّذ الشكل الصحيح أصلاً**.

- **هل تُغني `ValueObservation` من GRDB عن هذا؟** لا. `ValueObservation` تُبقي العرض متزامناً مع
  قاعدة البيانات، لكنها **لا تحدّ حجم ما يُحمَّل**؛ ملاحظةٌ على استعلام يعيد 176 ألف صف تعيدها كلها
  في كل تغيير. الملاحظة تحلّ مشكلة الاتّساق، والتصفيح يحلّ مشكلة الذاكرة — وهما مشكلتان مختلفتان.
  ([GRDB ValueObservation](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb/valueobservation))
- **هل SwiftData/`@Query` أنسب؟** لا. أُجيب على هذا في `TECH_ADJUDICATION` البند 6 ولا أعيده؛
  والأهم أن التبديل يعني مكدّس تخزين ثانياً إلى جانب GRDB.

> **الخلاصة:** أسلوب المرجع هو الصحيح في 2026. التعديل المطلوب ليس في الطريقة بل في **الاكتمال**.

## التعديلات الأربعة على نسخة المرجع

1. **الحارس يجب أن يعمل على الحالة الجزئية.** `isPopulated` (`CatalogDB.swift:170`) يُشغّل ثلاث
   عمليات `COUNT` مُصفّاة — على 176 ألف صف. المرجع نفسه انتبه لهذا ونقلها خارج الخيط الرئيسي
   (`ContentViews.swift:1011–1013`). **انقلها كما نقلها**، ولا تستدعِها من `body` أبداً.
2. **`P7` لم يُلغَ.** كتالوج مُعلَّم `isPartial` (انظر `PROJECT_HANDOFF §9`) **لا يُصفَّح** — لأنه
   لم يُكتب إلى `CatalogDB` أصلاً. اجعل الشرط `isPopulated && !lastLoadWasPartial`، وإلا صفّحتَ فوق
   كتالوج قديم بينما الذاكرة تحمل واحداً أحدث وأصدق.
3. **ينقصنا ثلاث دوال عدّ.** نملك `countMovies` و`movieCategoryCounts` فقط
   (`CatalogDB.swift:264–280`). التصفيح لـ `SeriesVM` و`LiveTVVM` يحتاج نظيرَيهما. ~24 سطراً،
   نسخٌ حرفيّ لنمطٍ موجود.
4. **لا تصفّح البحث.** `SearchVM` عندنا يمرّ على FTS5 ثم `moviesByIds` (`:3278`) — وهذا المسار
   **أفضل من مسار المرجع**. لا تلمسه. التصفيح خاصّ بالتصفّح لا بالبحث، ونفس القاعدة عند المرجع
   (`loadMore` يخرج فوراً إذا `!search.isEmpty`، `ContentViews.swift:1052`).

## الفائدة، وكيف تُقاس (لا «يبدو أسرع»)
| ما يُقاس | الأداة | الرقم |
|---|---|---|
| ذاكرة مقيمة بعد فتح «أفلام» ثم التمرير 2000 صفّاً | Instruments → Allocations → *Persistent Bytes* | متوقَّع: من ~110–150 م.ب إلى ~15–25 م.ب |
| ذروة الذاكرة على الأسطول | **MetricKit — نملكه أصلاً** (`Diagnostics.swift`): `MXMemoryMetric.peakMemoryUsage` | يُقارن قبل/بعد بلا شيفرة جديدة |
| زمن أول رسم لتبويب «أفلام» | `MXAppLaunchMetric` + Instruments → *Time Profiler* على `load()` | القراءة تصير 150 صفاً بدل 176 ألفاً |
| توقّفات الإطارات أثناء التمرير | Instruments → *Animation Hitches* → نسبة زمن التلعثم (م.ث/ث) | يجب أن تنخفض، لأن `ForEach` يمشي على مجموعة أصغر |

**استعمل MetricKit.** هذه أرخص نقطة قياس في التقرير كلّه: `Diagnostics.shared.start()` مُستدعىً
بالفعل من `BlankTVApp.swift:159`، والحمولات تُحفَظ في `Caches/Diagnostics/`. القياس متاح **بلا سطر
واحد جديد**.

## الخطر والجهد
- **الجهد:** 6–10 ساعات (ثلاثة نماذج عرض + ثلاث دوال عدّ + وصلة `onNearEnd`).
- **الخطر:** **متوسط** — مسار ساخن يمسّ ثلاثة تبويبات. **ينصّ `PROJECT_HANDOFF §6` البند 6 على أن
  هذا يحتاج موافقة المالك أولاً؛ احترم ذلك.**
- **قاعدة إلزامية:** المسار الاحتياطي في الذاكرة **يبقى**. مستخدم لم تُملأ قاعدة بياناته بعد (أو
  مسار Xtream-credentials الخالص الذي لا يُعبّئ المخزن حتى اليوم — `PROJECT_HANDOFF §6` البند 5)
  يجب أن يرى نفس التطبيق تماماً.

## سكتش التنفيذ — `BlankTV/ContentViews.swift`، داخل `MoviesVM`

```swift
// ── حالة التصفيح (مطابقة لمرجعنا: ContentViews.swift:983–988) ──
private(set) var paged = false
private var cursor: Int? = nil
private var reachedEnd = false
private let pageSize = 150
private var loadingPage = false

func load(force: Bool = false) async {
    if loaded && !force { return }
    isLoading = true; error = nil
    let s = Store.shared.m3uURL ?? ""
    // isPopulated = ثلاث COUNT مُصفّاة على 176k صفّاً — لا تلمس الخيط الرئيسي.
    // ‏!lastLoadWasPartial: كتالوج P7 الجزئي لا يُكتب إلى CatalogDB، فتصفيحه
    // يعني تقديم بيانات أقدم من التي في الذاكرة.
    paged = s.isEmpty ? false
          : await Task.detached(priority: .userInitiated) { CatalogDB.isPopulated(scope: s) }.value
    if paged { await loadPaged(scope: s) } else { await loadFallback() }
    isLoading = false
}

private func loadPaged(scope s: String) async {
    let ps = pageSize
    let (cats, counts, first, total) = await Task.detached(priority: .userInitiated) {
        (CatalogDB.categories(scope: s, kind: "movie"),
         CatalogDB.movieCategoryCounts(scope: s),
         CatalogDB.pageMovies(scope: s, category: nil, after: nil, limit: ps),
         CatalogDB.countMovies(scope: s, category: nil))
    }.value
    categories   = [.all] + cats
    folderCounts = counts
    movies       = first.items                  // النافذة، لا الكتالوج
    cursor       = first.nextCursor
    reachedEnd   = first.nextCursor == nil
    totalCount   = total
    loaded       = true
    // في وضع التصفيح لا يوجد `grouped` ولا `foldedNames`: الفئة استعلام،
    // والبحث يمرّ على FTS5. هذا هو موضع مكسب الذاكرة الحقيقي.
}

func loadMore() {
    guard paged, !loadingPage, !reachedEnd, selected == "all", search.isEmpty else { return }
    loadingPage = true
    let s = Store.shared.m3uURL ?? "", after = cursor, ps = pageSize
    Task { @MainActor [weak self] in
        let pg = await Task.detached(priority: .userInitiated) {
            CatalogDB.pageMovies(scope: s, category: nil, after: after, limit: ps)
        }.value
        guard let self else { return }
        self.movies.append(contentsOf: pg.items)
        self.cursor = pg.nextCursor
        self.reachedEnd = pg.nextCursor == nil
        self.loadingPage = false
    }
}
```

**الوصلة في العرض** — `PosterGrid` عندنا (`ContentViews.swift:1946–1955`) يملك سلفاً حارس النافذة
الذي يحتاجه هذا البند:

```swift
if shown < movies.count {
    Color.clear.frame(height: 1)
        .onAppear { shown = min(shown + S8KListWindow.step, movies.count) }
} else if let onNearEnd {                 // ← جديد: النافذة استُنفدت ⇒ اطلب صفحة
    Color.clear.frame(height: 1).onAppear { onNearEnd() }
}
```

⚠ **لا تحذف نافذة `shown`.** هي تحلّ مشكلة مختلفة (P2: `ForEach` يمشي على المجموعة كاملة لبناء
خريطة الهوية في كل إبطال)، والتصفيح لا يُغني عنها — بل يعملان معاً: التصفيح يحدّ ما في الذاكرة،
والنافذة تحدّ ما يمشي عليه `ForEach`.

---

# البند 2 — الهجرة من `ObservableObject` إلى `@Observable`

## الحكم: **REPLACE WITH SOMETHING NEWER** 🔴 — المرجع على النموذج القديم، والأحدث يتفوّق عليه بنيوياً

## ما يفعله المرجع، وما نفعله — النموذج نفسه في التطبيقين
- المرجع: 18 صنفاً على `ObservableObject`.
- نحن: **19 صنفاً على `ObservableObject` و128 خاصية `@Published`**، وصفر استعمال لـ `@Observable`
  في التطبيقين معاً.

أثقل الحالات عندنا:

| الصنف | عدد `@Published` | الموضع |
|---|---|---|
| `HomeVM` | **18** | `HomeView.swift:26–44` |
| `MoviesVM` | 10 | `ContentViews.swift:818–830` |
| `SeriesVM` | 10 | `ContentViews.swift:2038–2049` |
| `LiveTVVM` | 7 | `ContentViews.swift:13–21` |
| `SearchVM` | 6 | `ContentViews.swift:3132–3138` |

و`HomeView` (`HomeView.swift:1–15`) يراقب **سبعة** من هذه الأشياء في آنٍ واحد
(`vm`, `config`, `theme`, `auth`, `activation`, `bars`, `router`, `searchVM`).

## المشكلة البنيوية — وهي مُثبَتة في تاريخ مستودعنا نفسه
مع `ObservableObject`، أي تغيير على **أي** خاصية `@Published` يبثّ `objectWillChange`، فيُبطَل
**كل** عرض يراقب الكائن — لا العروض التي تقرأ الخاصية المتغيّرة فقط.

هذا ليس تنظيراً. **دفعناه ثلاث مرات، وأصلحناه ثلاث مرات يدوياً:**

1. **`heroIndex`** — مؤقّت يزيده كل 5 ثوانٍ (`HomeView.swift:229–245`). التعليق عند `:253–260`
   يوثّق النتيجة حرفياً: *«كل نبضة تُعيد تقييم كل الأقسام (أشرطة الترتيب، الأفلام، المسلسلات،
   المباشر) — مصدر رئيسي للتلعثم المُبلَّغ عنه»*. الحلّ كان **استخراج `HeroCarouselView` يدوياً**.
2. **المفضّلات (P8)** — `PROJECT_HANDOFF §9`: *«كل `ChannelRow` كان يحمل `@StateObject` خاصاً به على
   الـ singleton — صندوق حالة واشتراك Combine لكل صفّ مرئي»*. الحلّ كان **رفعها يدوياً**.
3. **بحث مطويّ (P5)** — `searchResults` كانت خاصية محسوبة تُقرأ من `body`، فتُمسح كل الكتالوج مع
   كل إعادة رسم. الحلّ كان **فهرساً مطويّاً + مذكِّرة يدوية**.

**ثلاثة إصلاحات، ثلاث حالات، ونمط واحد.** `@Observable` يغلق النمط كلّه بدل الحالات واحدةً واحدة.

**وحالة رابعة لا تزال حيّة:** `MoviesView.favorites` (`ContentViews.swift:1586`) خاصية محسوبة
`vm.movies.filter { favs.movies.contains($0.id) }` — تصفية O(n) على الكتالوج كاملاً، تُعاد في كل
تقييم للجسم يشمل فرع المفضّلات، أي مع كل ضغطة مفتاح بحث ومع كل تغيير في أيٍّ من الأشياء السبعة.

## البحث — هل `@Observable` هو الأحدث فعلاً في 2026؟
- `@Observable` أُدخل مع إطار Observation في iOS 17، وهو **بالضبط حدّنا الأدنى** — لا حاجة إلى
  `if #available` ولا مسار احتياطي.
  ([Observation](https://developer.apple.com/documentation/observation) ·
  [`@Observable`](https://developer.apple.com/documentation/observation/observable()))
- Apple تنشر دليل ترحيل مخصّصاً لهذه العملية بالذات:
  [Migrating from the Observable Object protocol to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).
  **وجود دليل ترحيل رسمي من Apple هو الجواب على سؤال «هل هذا هو الاتجاه؟»** — لا يُكتب دليل ترحيل
  إلا في اتجاه واحد.
- الأساس المعياري: [SE-0395 Observability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md).
- جلسة الإطلاق: [WWDC23 · Discover Observation in SwiftUI (10149)](https://developer.apple.com/videos/play/wwdc2023/10149/).
- ⚠ **غير متحقَّق منه لدى Apple:** لم أجد وثيقة من Apple تنشر **رقماً** لمقدار التحسّن. الادّعاء
  الموثَّق هو **الدلالة** (إبطال على مستوى الخاصية بدل بثّ على مستوى الكائن)، لا نسبة مئوية. أي
  رقم تراه في مدوّنة عن «‏@Observable أسرع بـ X%» عامله كقياسٍ لحالة ذلك الكاتب لا كحقيقة.

## ثلاثة مصائد يجب توثيقها قبل السطر الأول
1. **مِلكية الحالة تنقلب.** مع `@Observable` يصير `@StateObject` خطأ ترجمة و`@ObservedObject` كذلك:
   الملكية تصير `@State` (لما يملكه العرض) أو `let`/`@Bindable` (لما يُمرَّر إليه). أشياؤنا كلها
   **singletons** (`MoviesVM.shared`…) فالنمط الصحيح لها هو `private let vm = MoviesVM.shared`
   **لا** `@State` — لأن العرض لا يملكها. راجع دليل الترحيل أعلاه؛ هذه أكثر نقطة يُخطئ فيها الناس.
2. **الإبطال يتبع القراءة، فاحذر الخصائص المحسوبة.** `@Observable` يُبطل العرض الذي **قرأ** الخاصية.
   خاصية محسوبة مثل `favorites` تقرأ `vm.movies` — فتبقى مرتبطة بالمصفوفة كاملها. **الهجرة وحدها لا
   تُصلح هذه؛** يجب مع الهجرة تحويل `favorites` إلى قيمة تُبنى عند التغيير لا عند القراءة.
3. **`@ObservationIgnored` للتخزين غير المعروض.** حقول مثل `foldedNames` و`lastResults` و`grouped`
   لا يقرأها أي عرض مباشرة؛ وسمها بـ `@ObservationIgnored` كي لا تدخل في التتبّع أصلاً.

## الفائدة، وكيف تُقاس
- **العدّاد الصحيح ليس زمناً بل عدد إعادات التقييم.** ضع `let _ = Self._printChanges()` في أول
  `body` لـ `HomeView` و`MoviesView`، ثم نفّذ سيناريو ثابتاً (افتح الرئيسية، انتظر ثلاث نبضات
  للـ hero، اكتب خمسة أحرف في البحث). **قِس العدد قبل وبعد.** هذا رقم قابل للتكرار، بخلاف
  «يبدو أنعم».
- **ثم** Instruments → قالب SwiftUI → *Long View Body Updates* (الأحمر = تلعثم) و
  *Animation Hitches*. القياس على **بناء Release وجهاز حقيقي فقط**.

## الخطر والجهد
- **الجهد:** 4–6 ساعات، **على مراحل**. ابدأ بـ `AppTheme` و`LocalizationManager` و`BarVisibility`
  (صغيرة، سطحها ضيّق) للتحقّق من نمط الملكية على الجهاز، ثم `HomeVM` (أكبر عائد)، ثم الثلاثة الكبار.
- **الخطر:** **متوسط** — ليس لأن التقنية صعبة، بل لأن `@StateObject` → `let` يمسّ **كل ملف عرض**،
  و`TabView` يُقيّم أجسام كل التبويبات عند الإقلاع (`PROJECT_HANDOFF §3`): خطأ زمن-تشغيل في أي جسم
  = انهيار عند الإقلاع. **لا تهاجر أكثر من صنف واحد في بناء واحد.**

## سكتش التنفيذ — `BlankTV/HomeView.swift`

```swift
import Observation

@MainActor @Observable
final class HomeVM {
    static let shared = HomeVM()
    var liveChannels: [Channel] = []
    var movies: [Movie] = []
    …
    var heroIndex: Int = 0          // ← الآن يُبطل فقط ما يقرأ heroIndex
    @ObservationIgnored private var heroTimer: Timer?   // ليس حالة عرض
    @ObservationIgnored private var loaded = false
}

struct HomeView: View {
    // لا @StateObject: العرض لا يملك singleton. مِلكيةٌ خاطئة تعني
    // دورة حياة خاطئة، لا مجرّد أسلوب مختلف.
    private let vm = HomeVM.shared
    …
}
```

---

# البند 3 — ميزانية ذاكرة الصور ومسار الاستجابة لضغط الذاكرة

## الحكم: **REPLACE WITH SOMETHING NEWER** 🔴 — المرجع ضبط رقماً ثابتاً بعد قياس؛ الصواب ألّا يكون ثابتاً

## ما يفعله المرجع
`Strong8K/iOS/Strong8K/DesignSystem.swift:544–557` — وهذا أفضل جزء في تعليقه، لأنه يعترف بأن الرقم
قياسٌ لا مبدأ:

```swift
memory.countLimit = 260
memory.totalCostLimit = 64 * 1024 * 1024   // ~64 MB … (was 96MB —
// lowered with the 500px grid downsample … Data: 176k-movie catalog,
// 928 fetches/session, thermal 'serious'.)
```

أي أن المرجع **قاس ضغطاً حرارياً حقيقياً على كتالوج بحجمنا**، وردّ عليه بخفض حدّ التكلفة وخفض
حجم فكّ الترميز إلى 500 بكسل.

## ما نفعله اليوم
`BlankTV/DesignSystem.swift:1286–1298`:

```swift
memory.countLimit = 240
memory.totalCostLimit = 96 * 1024 * 1024   // ~96 MB of decoded bitmaps
hashMemory.countLimit = 512
hashMemory.totalCostLimit = 8 * 1024 * 1024
```

### ⚠ ولا تنسخ رقم المرجع — تصميمنا مختلف، وهذه نقطة مهمّة
أغرى في الوهلة الأولى أن أوصي بخفض `maxPixel` من 800 إلى 500 كما فعل المرجع. **فحصتُ، والتوصية
خاطئة عندنا:**

- ملصق المرجع بارتفاع ثابت 150 نقطة (`ContentViews.swift:2055`) ⇒ ~450 بكسل عند 3x ⇒ **500 صحيح**.
- ملصقنا **نسبة 2:3 في عمود تكيّفي بحدّ أدنى 116/168 نقطة** (`ContentViews.swift:1934, 1978–1980`).
  على iPhone بعرض 390: بعد الهوامش ~358، فعمودان بعرض ~172 نقطة، وارتفاع 258 نقطة ⇒ **~774 بكسل
  عند 3x**. أي أن **800 هو الرقم الصحيح لتصميمنا**، وخفضه إلى 500 كان سيُنتج ملصقات ضبابية على
  أكبر شاشة في المصفوفة.

> **الدرس:** المرجع لم يُعطِنا رقماً، أعطانا **طريقة**. وطريقته هي: طابِق الفكّ بالحجم المعروض
> فعلاً. نحن نطبّقها بالفعل — لكن على مقاسات أكبر.

### 🔴 وهنا تظهر المشكلة الحقيقية: الميزانية لا تتّسع لتصميمنا
ملصق واحد عندنا بعد فكّ الترميز = 533 × 800 × 4 ≈ **1.7 ميغابايت**. مع سقف 96 ميغابايت، الذاكرة
تتّسع لـ **~56 ملصقاً فقط** — بينما `countLimit` مضبوط على 240، أي أن **حدّ التكلفة هو المُلزِم
دائماً و`countLimit` زينة**. والشبكة تعرض ~8 ملصقات في الشاشة و`prefetch` يُسخّن 30
(`ContentViews.swift:1956`). أي أن تمريرة واحدة بطول 60 عنواناً تُخلي الذاكرة بالكامل، والعودة إلى
الأعلى **تعيد التنزيل وفكّ الترميز**.

وتعليقنا نفسه في `DesignSystem.swift:1446–1447` يوثّق هذا العَرَض حرفياً:
*«أفسد ذاكرة الصور (~38 صورة عند 800 بكسل) وسبّب وميض إعادة فكّ الترميز أثناء التمرير»*.

### 🔴 وأسوأ: لا شيء في التطبيق يستجيب لضغط الذاكرة إطلاقاً
- **صفر** نتيجة لـ `didReceiveMemoryWarning` أو `memoryWarningNotification` في **التطبيقين معاً**.
- `MediaPrefetcher.clear()` (`MediaPrefetcher.swift:56–59`) موثَّق حرفياً بأنه *«للحالات مثل تحذير
  الذاكرة»* — و**لا يستدعيه أحد**. تحقّقتُ: المستدعيان الوحيدان لـ `MediaPrefetcher.shared` هما
  `prefetch` (`ContentViews.swift:2579`) و`take` (`PlayerEngine.swift:330`). أي أن **مشغّلَين
  دافئَين يبقيان يخزّنان فيديو VOD تحت ضغط الذاكرة حتى يقتلنا النظام**.

## البحث — ما هو الأحدث؟
- `NSCache` **يستجيب فعلاً لضغط الذاكرة تلقائياً** — توثيق Apple ينصّ على أنه *«يُخلي محتوياته
  تلقائياً عندما تكون موارد الذاكرة شحيحة»*
  ([NSCache](https://developer.apple.com/documentation/foundation/nscache)). فالمشكلة ليست في
  `NSCache` بل في **ما ليس داخل `NSCache`**: المشغّلات الدافئة.
- الرقم الثابت هو الخلل الجوهري: 96 ميغابايت رقمٌ واحد لجهاز بذاكرة 3 غ.ب وآخر بـ 8 غ.ب. الواجهة
  المُوثَّقة لمعرفة ما تبقّى **لهذه العملية** هي `os_proc_available_memory()` (iOS 13+، من
  `<os/proc.h>`) ([os_proc_available_memory](https://developer.apple.com/documentation/os/os_proc_available_memory())).
- والبديل/المكمّل للتحذير: `DispatchSource.makeMemoryPressureSource(eventMask:queue:)` — مصدر
  GCD يُطلق عند `.warning` و`.critical`، ويعمل خارج دورة حياة UIKit
  ([DispatchSource](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:))).
- ⚠ **غير متحقَّق منه لدى Apple:** لم أجد توثيقاً رسمياً يقول «اشتقّ `totalCostLimit` من
  `os_proc_available_memory()`». الواجهتان موثَّقتان كلٌّ على حدة؛ **الربط بينهما اجتهادٌ هندسي
  مني، لا توصية من Apple.** عامله كذلك، وقِس النتيجة.
- ⚠ **وحذارِ من الصياغة الخاطئة الشائعة:** `ProcessInfo.processInfo.physicalMemory` يعطي ذاكرة
  **الجهاز**، لا حصّة التطبيق. الاشتقاق منه يعطي أرقاماً متفائلة تنتهي بالقتل (jetsam). استعمل
  `os_proc_available_memory()`.

## الفائدة، وكيف تُقاس
| ما يُقاس | كيف | ما نتوقّعه |
|---|---|---|
| نسبة إصابة ذاكرة الصور | أضِف عدّادَين ذرّيَّين في `S8KImageCache.load` (إصابة/إخفاق) واعرضهما في لوحة التشخيص القائمة (`EngineStatsView`) | ترتفع بوضوح عند العودة بالتمرير |
| عدد التنزيلات لكل جلسة تصفّح | العدّاد نفسه | ينخفض — وهو **بطارية وبيانات**، لا سرعة فقط |
| ذروة الذاكرة | `MXMemoryMetric.peakMemoryUsage` عبر MetricKit القائم | يجب ألّا ترتفع رغم زيادة السقف على الأجهزة الكبيرة |
| عمليات القتل بسبب الذاكرة | `MXAppExitMetric` (`cumulativeMemoryResourceLimitExitCount`) | يجب أن تصير صفراً |

## الخطر والجهد
- **الجهد:** 2–3 ساعات. **الخطر:** منخفض — لا يمسّ أي منطق عرض.
- **قيد إلزامي:** لا تجعل الحدّ يعتمد على قياس يُجرى **مرّة واحدة عند الإقلاع** فقط؛ الذاكرة
  المتاحة تتغيّر. أعِد التقييم عند العودة إلى المقدّمة.

## سكتش التنفيذ

**`BlankTV/DesignSystem.swift` — داخل `S8KImageCache.init()`:**

```swift
import os          // os_proc_available_memory()

/// ميزانية النقوش المفكوكة، مشتقّة من الذاكرة المتبقّية لهذه العملية.
/// الرقم الثابت (96 م.ب) كان يعني شيئين مختلفين تماماً على جهاز 3 غ.ب وجهاز 8 غ.ب:
/// إفراطاً يقود إلى القتل على الأول، وإهداراً يقود إلى إعادة تنزيل على الثاني.
/// ملصقنا 2:3 عند 800 بكسل = ~1.7 م.ب، فسقف 96 م.ب يسع ~56 ملصقاً — أقلّ من
/// شاشتين — وهو سبب "وميض إعادة الفكّ" الموثَّق عند :1446.
private static func imageBudget() -> Int {
    let available = Int(os_proc_available_memory())        // بايت متبقّية لهذه العملية
    guard available > 0 else { return 96 * 1024 * 1024 }   // احتياطي: السلوك الحالي
    // الخُمس، ضمن حدَّين. ليست توصية من Apple — اجتهاد يُقاس، انظر التقرير.
    return min(max(available / 5, 48 * 1024 * 1024), 220 * 1024 * 1024)
}

init() {
    memory.totalCostLimit = Self.imageBudget()
    memory.countLimit = 0          // 0 = بلا حدّ عددي. الحدّ المُلزِم هو التكلفة،
                                   // وكان 240 رقماً لا يُبلَغ أبداً (التكلفة تسبقه دائماً).
    …
}

/// أفرغ ما يمكن إفراغه فوراً. تُستدعى من مصدر ضغط الذاكرة.
func purge() {
    memory.removeAllObjects()      // الصور الكاملة أولاً — أغلى ما نملك
    // لا تُفرغ hashMemory: بصمات ThumbHash ~32 بكسل، ووجودها هو ما يمنع
    // الشاشة الرمادية بعد الإفراغ. إفراغها يجعل الاسترداد يبدو كعطل.
}
```

**`BlankTV/BlankTVApp.swift` — داخل `AppDelegate` (وهو موجود عند `:72`):**

```swift
private var memoryPressure: DispatchSourceMemoryPressure?

func application(_ app: UIApplication,
                 didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // مسار واحد للاستجابة لضغط الذاكرة. لم يكن في التطبيق أيّ مسار من قبل —
    // ولا حتى في المرجع — فكان النظام يقتلنا بدل أن نتراجع.
    let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                      queue: .main)
    src.setEventHandler {
        // المشغّلات الدافئة أولاً: مشغّلا AVPlayer يخزّنان فيديو VOD، وهما
        // أغلى ما نملك وأسهل ما يُعاد بناؤه (يُعاد التسخين عند فتح الصفحة).
        // clear() موجودة منذ اليوم الأول وموثَّقة "مثلاً عند تحذير الذاكرة" —
        // ولم يستدعِها أحد قط.
        MediaPrefetcher.shared.clear()
        S8KImageCache.shared.purge()
    }
    src.resume()
    memoryPressure = src
    return true
}
```

⚠ **تحفّظ صادق:** `NSCache` يُخلي تلقائياً تحت الضغط، فجزء `S8KImageCache.purge()` قد يكون
مكرِّراً لعمل النظام. **الجزء الذي لا بديل عنه هو `MediaPrefetcher.shared.clear()`** — لأن
`AVPlayer` ليس `NSCache` ولا يُخلي نفسه. إن أردت أقلّ تغيير بأكبر أثر، **نفّذ ذلك السطر وحده.**

---

# البند 4 — `PosterCollectionView` (UICollectionView + `UIHostingConfiguration`)

## الحكم: **REJECT (الآن)** — والسبب الأقوى هو أن **المرجع نفسه لم يُشغّله**

## ما يفعله المرجع
`Strong8K/iOS/Strong8K/ContentViews.swift:1963–2040` — بنية `UIViewRepresentable` كاملة:
`UICollectionViewCompositionalLayout` + `UICollectionViewDiffableDataSource` +
`UIHostingConfiguration` تستضيف `MoviePosterCell` حرفياً + `UICollectionViewDataSourcePrefetching`
يغذّي `S8KImageCache.prefetch` ويُطلق `onNearEnd` للتصفيح.

وتعليقه (`:1955–1962`) يشرح الحجّة بدقّة: *«LazyVGrid لا تُعيد استعمال الخلايا حقاً ⇒ عند 100 ألف
عنصر تُبدّد التمريرات السريعة مخزن العروض وتتجاوز ميزانية 8.33 م.ث»*.

## لماذا الرفض — أربعة أسباب، مرتَّبة بقوّتها

**١. المرجع أبقاه مطفأً.** موضع الاستدعاء (`ContentViews.swift:1795`) مسوَّر بـ
`if Store.shared.gridEngine == "uikit"`، وتعليقه يقول حرفياً **«Dark-launch»**، والفرع الآخر
*«المسار LazyVGrid غير المتغيّر»*. ولا يظهر إلا في **جزء iPad** (`padGrid`) — لا على iPhone.
**المرجع لم يشحن هذه التقنية؛ شحن مفتاحاً لها ولم يقلبه.** تبنّي شيء لم يثبت في الميدان عند مصدره
هو بالضبط ما تمنعه القاعدة الحاكمة.

**٢. المشكلة التي يحلّها حلَلناها بطريقة أرخص.** حجّته هي «100 ألف عنصر في `ForEach` واحدة».
عندنا `S8KListWindow` (`ContentViews.swift:555–561`) يحدّ ما تمشي عليه `ForEach` بـ 120 صفاً + 180
لكل خطوة، وهو الإصلاح P2 المُقاس. **والبند 1 من هذا التقرير يحدّ الذاكرة أيضاً.** بعد البند 1 لن
تحمل الشبكة 176 ألف عنصر أصلاً، بل 150 وتنمو — فالفرضية التي بُني عليها البند تسقط.

**٣. ثمنه المعماري مرتفع عندنا تحديداً.** تعليق المرجع نفسه يحذّر: *«⚠️ هذا **يملك** تمريره — يجب
ألّا يُعشِّشه المستدعي داخل ScrollView»*. وصفحاتنا **ليست شبكة عارية**: `MoviesView` بُني على نمط
الرئيسية — بطل مُمتدّ كامل العرض + أشرطة تحريرية + شبكة، كلّها داخل `ScrollView` واحد
(`PROJECT_HANDOFF §5f`). إدخال عرض يملك تمريره يعني **تفكيك الصفحة** التي بُنيت لأجل حجّة التمايز
عن Strong8K. الثمن ليس «ساعات»، بل تراجع عن قرار تصميمي مُوقَّع.

**٤. ومفارقة التمايز.** `UIHostingConfiguration` تستضيف `MoviePosterCell` **حرفياً**. نقل هذه
البنية يعني إعادة إدخال ملف عرضٍ مطابق للمرجع سطراً بسطر إلى ثنائيّتنا — بعد أن قضينا جولة كاملة
(`DIFFERENTIATION_REPORT.md`، `PROJECT_HANDOFF §5f`) في تفكيك تطابقٍ من هذا النوع بالضبط. حتى لو
كان الأداء رابحاً، **هذا وحده يكفي لتأجيله.**

## ما يبقى صحيحاً منه ويستحقّ الأخذ — بلا UIKit
الفكرة الجيّدة الوحيدة القابلة للفصل هي **إطلاق `prefetch` عند نموّ النافذة، لا عند `onAppear`
مرّة واحدة**. اليوم نُسخّن أول 30 ملصقاً فقط (`ContentViews.swift:1956`) ولا نُسخّن شيئاً بعدها
أبداً، مهما طال التمرير. سطر واحد، بلا `UIViewRepresentable`:

```swift
if shown < movies.count {
    Color.clear.frame(height: 1)
        .onAppear {
            let next = min(shown + S8KListWindow.step, movies.count)
            // سخّن الخطوة التي نحن على وشك عرضها. اليوم يقع التسخين مرّة واحدة
            // عند onAppear لأول 30، فكل ما بعد الشاشة الأولى يُنزَّل عند ظهوره.
            S8KImageCache.shared.prefetch(
                movies[shown..<next].compactMap { $0.posterURL }, maxPixel: 800)
            shown = next
        }
}
```

**الجهد:** ~8 أسطر. **الخطر:** منخفض. **الفائدة:** يقلّ ظهور الهيكل الرمادي أثناء التمرير المتواصل.
**قِسها** بعدّاد إصابة/إخفاق الذاكرة من البند 3، لا بالنظر.

⚠ **وملاحظة يجب ألّا تُنسى إن عاد أحدٌ يوماً إلى `PosterCollectionView`:** المرجع ينفّذ
`prefetchItemsAt` (`:2034`) ولا ينفّذ `cancelPrefetchingForItemsAt` إطلاقاً. أي أن تمريرة سريعة
تُطلق تنزيلات لعشرات الملصقات التي تجاوزها المستخدم فعلاً، بلا إلغاء. البروتوكول يعرّف الدالتين
معاً لسبب ([UICollectionViewDataSourcePrefetching](https://developer.apple.com/documentation/uikit/uicollectionviewdatasourceprefetching)).

---

# البند 5 — تسليم تنزيل Turbo إلى جلسة الخلفية

## الحكم: **REJECT (الآن)** — لأن الشيفرة التي يُصلحها **ميتة عندنا**، ويلزم قرار من المالك

## ما يفعله المرجع
`Strong8K/iOS/Strong8K/Downloads.swift:235–241`:

```swift
func handoffActiveTurboToBackground() {
    for it in items where it.state == .downloading && turboTasks[it.id] != nil {
        guard let urlStr = it.remoteURL, let url = URL(string: urlStr) else { continue }
        turboTasks[it.id]?.cancel(); turboTasks[it.id] = nil
        launchBackground(it.id, url: url, ext: extFor(it.id))
    }
}
```

مُستدعىً من `Strong8KApp.swift:165–171` في فرع `scenePhase == .background`. وتعليقه يذكر شكوى
مستخدم حقيقية عالجها: *«"لا عدّاد عند العودة"»*. والمنطق سليم تماماً: تنزيل Turbo يعيش على `Task`
+ جلسة عادية، والنظام يعلّقه ثم يقتله عند التخلّف؛ بينما جلسة `URLSessionConfiguration.background`
هي **الآلية الوحيدة** التي يواصل النظام تنفيذها خارج العملية.

## لماذا لا ننقله — الفحص الذي قلب الحكم
كنتُ سأضع هذا البند في المرتبة الأولى. ثم فحصتُ ما إذا كان `runTurbo` قابلاً للوصول عندنا أصلاً:

```
BlankTV/Core.swift:850   var turboDownloads: Bool {
BlankTV/Core.swift:851       get { ud.bool(forKey: "s8k.turboDownloads") }   // ← الافتراضي false
BlankTV/Downloads.swift:194  if Store.shared.turboDownloads {
```

- `ud.bool(forKey:)` يعيد `false` لمفتاح غير مضبوط ⇒ **Turbo مطفأ افتراضياً**.
- بحثتُ عن أي `setter` أو مفتاح في الواجهة: **لا يوجد**. لا شيء في `SettingsView.swift` يضبط
  `turboDownloads`، ولا مفتاح ترجمة له، ولا تحكّم عن بُعد.

> **النتيجة:** `runTurbo` (`Downloads.swift:248–355`) — ~110 سطراً — **شيفرة لا يمكن لأي مستخدم
> بلوغها**. وبناء التسليم إليها يعني كتابة إصلاحٍ لمسارٍ لا يُنفَّذ.
>
> **والخبر الجيّد:** مسارنا الفعلي (`launchBackground`, `Downloads.swift:202–223`) هو **جلسة خلفية
> حقيقية** منذ البداية، و`AppDelegate.handleEventsForBackgroundURLSession`
> (`BlankTVApp.swift:85–92`) موصول بشكل صحيح، وبيانات الاستئناف تُحترم (`:206`). **تنزيلاتنا
> موثوقة في الخلفية اليوم.**

## القرار المطلوب من المالك (وليس بنداً هندسياً)
1. **إمّا احذف `runTurbo` و`turboTasks` و`turboDownloads`** — ~120 سطراً من شيفرة ميتة تُصعّب كل
   قراءة لاحقة لـ `Downloads.swift`، وتُغري كل مراجع بأن يُصلح فيها ما لا يعمل أصلاً.
2. **وإمّا أَظهِر المفتاح في الإعدادات — وعندها التسليم إلى الخلفية إلزاميّ لا اختياري**، وإلا شحنّا
   بالضبط الخلل الذي اشتكى منه مستخدمو المرجع. نفّذ الاثنين في **بناءٍ واحد**، لا أحدهما.

⚠ **وإن نُفِّذ يوماً، انتبه لهذا في نسخة المرجع:** `handoff` يستدعي `launchBackground` **فوراً بعد**
`turboTasks[id]?.cancel()`. والإلغاء في Swift **تعاوني**: لا يوقف `runTurbo` لحظياً، بل يضع رايةً
تُفحص عند نقاط التعليق. المرجع نفسه يعرف ذلك ويحرس ضدّه بفحصين للإلغاء (`Downloads.swift:287–300`
مع تعليق صريح: *«التسليم يفوز؛ نحن ننسحب»*). **انقل الحارسَين معه، وإلا فتحتَ نافذة يعمل فيها
تحويلان على خطّ Xtream يقبل اتصالاً واحداً، فيُرفض الثاني.**

---

# قسم إضافي — تقنية لا يملكها أيٌّ من التطبيقين

## ج-أ · التكيّف مع الحالة الحرارية ووضع الطاقة المنخفضة

**الحكم: ابنِه — لكن بعد البندين 1 و3، لا قبلهما.**

**الدليل على أن المشكلة حقيقية يأتي من المرجع نفسه:** تعليق ذاكرة الصور عنده
(`DesignSystem.swift:548–552`) يسجّل بيانات ميدانية: *«كتالوج 176 ألف فيلم، 928 جلبة/جلسة، حراري
'serious'»*. أي أن هذا الصنف من التطبيقات **يبلغ `.serious` فعلاً** على أجهزة حقيقية.

**وما يفعله أيٌّ من التطبيقين حيال ذلك: لا شيء.** المرجع **يقيس** الحالة الحرارية
(`Telemetry.swift:206`) ولا يتصرّف بناءً عليها. ونحن لا نقيسها ولا نتصرّف.

**ما تقوله Apple:** `ProcessInfo.thermalState` مع `thermalStateDidChangeNotification`
([thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate)) —
والتوثيق واضح في أن على التطبيق **تقليل العمل** عند `.serious` و`.critical`. ونظيرها للبطارية
`isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`
([isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)).

**أين يقع الأثر عندنا بالضبط، وهو مكان واحد:**

```swift
// BlankTV/DesignSystem.swift — S8KImageCache
/// حجم التسخين المسموح به الآن. التسخين عملٌ اختياري بالكامل — لا شيء على
/// الشاشة ينتظره — فهو أول ما يجب أن يتراجع تحت الضغط، وآخر ما ينبغي أن
/// نُبقيه يعمل بينما النظام يخفض تردّد المعالج ويستنزف البطارية.
private var prefetchAllowance: Int {
    if ProcessInfo.processInfo.isLowPowerModeEnabled { return 0 }
    switch ProcessInfo.processInfo.thermalState {
    case .critical: return 0
    case .serious:  return 8
    case .fair:     return 20
    default:        return .max
    }
}

func prefetch(_ urls: [String], maxPixel: CGFloat) {
    let budget = prefetchAllowance
    guard budget > 0 else { return }
    for u in urls.prefix(budget) { … }
}
```

**كيف تُقاس:** MetricKit مرة أخرى — `MXCPUMetric.cumulativeCPUTime` و`MXCellularConditionMetric`،
ولوحة `EngineStatsView` القائمة لعرض عدد الجلبات لكل جلسة. والقياس المباشر: `xcrun devicectl` +
Instruments → *Energy Log*، أو ببساطة قِس `thermalState` قبل/بعد في نفس سيناريو التمرير.

**الجهد:** ساعتان. **الخطر:** منخفض. ⚠ **لكن رتّبه بعد البندين 1 و3**: البند 1 يقلّل ما يُحمَّل،
والبند 3 يقلّل ما يُعاد تنزيله. خنق التسخين **قبلهما** يعالج عَرَضاً بينما السببان قائمان، ويجعل
التمرير يبدو أبطأ بلا داعٍ.

## واجهات فحصتُها ولم أجد فيها ما يُضاف — نتائج سلبية مؤكَّدة
- **`NWPathMonitor` / كشف الاتصال:** المرجع يستعمله في `Telemetry.swift:31` فقط (وقد رُفض
  `Telemetry` كلّه في الجولة الأولى). **ولا أوصي بنقله:** توجيه Apple منذ سنوات هو **ألّا** تُستعمل
  فحوص الوصول المسبقة، بل يُحاول الطلب ويُترك النظام يقرّر، مع
  `URLSessionConfiguration.waitsForConnectivity` حيث يكون الانتظار مقبولاً — وهو **مضبوط عندنا
  بالفعل حيث يلزم** (`Downloads.swift:79, 253`).
  ([waitsForConnectivity](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity))
- **`HostFailover`** (`ActivationService.swift:469–559`): **لا ينطبق علينا.** يقرأ
  `Store.shared.resellerHosts`، ونحن أزلنا مسار رمز الموزّع كلّه في جولة الاستعداد للمتجر
  (`PROJECT_HANDOFF §11`, البند 2.1). فالقائمة عندنا فارغة دائماً و`canFailover` دائماً `false`.
  وهو **حتى في المرجع غير موصول** بإقراره الخاص (`:465–467`).
- **مشغّل الوسائط الدافئ** (`MediaPrefetcher`): طابقتُ الملفين سطراً بسطر — **متطابقان**. منقول
  بالكامل. لا شيء متبقٍّ.
- **ذاكرة الصور**: بنيتنا (`DesignSystem.swift:1281–1433`) **أحدث من المرجع** — نملك مذكِّرة سالبة
  لبصمات ThumbHash (`:1356, 1371`) لا يملكها، وفحص `hasImageHash` نُقل داخل المهمّة الخلفية
  (`:1391–1394`) بينما هو عنده على مسار العودة. **لا شيء يُؤخذ في الاتجاه الآخر.**
- **توجيه المحرّكات**: `StreamRouter` + `EngineDecisionCache` عندنا **أحدث** — ذاكرة قرار لكل
  محتوى، بينما المرجع يتذكّر لكل قناة مباشرة فقط (`PlayerEngine.swift:930–935`). ومسار HLS-VOD عنده
  (`vodHLSRoutingEnabled`) مربوط بخادمه وبمِسبار `HLSProbe` داخل `Telemetry` المرفوض.

---

# ما يجب ألّا نُنسخ من المرجع — مهما بدا مفيداً

**١. 🔴 مفتاح سرّي مكتوب في الشيفرة.**
```
Strong8K/iOS/Strong8K/ActivationService.swift:16
static let appKey = "s8k_1ba20e7bead5716bb9e9b871fb71f3f304919f125dd62e91"
```
هذا ينتهك قيداً غير قابل للتفاوض في `PROJECT_HANDOFF §3` («لا مفاتيح API مكتوبة في الشيفرة»).
**تطبيقنا نظيف اليوم — تحقّقتُ.** أبقِه كذلك.

**٢. 🔴 `Diagnostics.uploadStored()`** (`Strong8K/iOS/Strong8K/Diagnostics.swift:36–60`). نسختنا
(`BlankTV/Diagnostics.swift`) تحفظ حمولات MetricKit محلّياً فقط، ونسخته **ترفعها إلى خادمه** مع
`DeviceIdentity.current`، مصادَقةً بالمفتاح المكتوب في الشيفرة أعلاه. لا تنقلها: (أ) تعتمد على
البند ١، (ب) ترفع حمولات انهيار تحمل مسارات ورموزاً، (ج) تفتح التزامات في
`PrivacyInfo.xcprivacy` أُغلقت بالفعل، (د) قطعنا الاتصال بـ `/v2` عمداً
(`ActivationService.swift:5`). **الاحتفاظ المحلّي هو القرار الصحيح — لا تتراجع عنه.**

**٣. `Telemetry.swift` كاملاً** — مرفوض في الجولة الأولى (`TECH_ADJUDICATION` البند 8)، ولا يزال
مرفوضاً؛ و`accessLog()`/`errorLog()` اللتان يقوم عليهما مهجورتان.

**٤. نمط `HostFailover.apply()`** (`ActivationService.swift:537–545`) — يعيد بناء رابط Xtream يحمل
**اسم المستخدم وكلمة المرور** ويكتبه في `Store.shared.m3uURL`، أي في `UserDefaults` بلا تشفير. هذا
هو بالضبط الخلل المفتوح عندنا في `PROJECT_HANDOFF §13` البند 4. **لا تُضِف موضع كتابة خامساً لهذا
السرّ.**

**٥. تخصيص `Dictionary(uniqueKeysWithValues:)`** في `PosterCollectionView.apply`
(`ContentViews.swift:2027`) — يتوقّف (trap) على مفتاح مكرّر. المرجع ينجو لأنه يُزيل التكرار في
السطر السابق. **إن نُقل هذا الملف يوماً، فالسطران لا ينفصلان.** (ونفس الحذر عندنا: `CatalogDB`
يستعمل `uniquingKeysWith:` وهو الشكل الآمن — `CatalogDB.swift:243, 251, 259`.)

**ولا شيء آخر.** فحصتُ `try!`/`as!` و`Data(contentsOf:)` على الخيط الرئيسي وأنماط التخطيط المحظورة
في ملفات المرجع الساخنة: `layer as! AVPlayerLayer` (`PlayerEngine.swift:844`) هو نمط Apple القياسي
مع تجاوز `layerClass` وآمن؛ وقراءات `Data(contentsOf:)` كلها على مسارات مُفصَّلة عن الخيط الرئيسي
أو صغيرة بما يكفي. **لا توجد قنابل أخرى في المرجع في المساحات التي فحصتها.**

---

# ترتيب التنفيذ الموصى به

| ترتيب | العمل | لماذا هنا | جهد |
|---|---|---|---|
| **0** | احذف `filtered` من `LiveTVVM`/`MoviesVM`/`SeriesVM` (البند 1) | مكسب ذاكرة فوري، ثلاثة أسطر، خطر صفر | 15 د |
| **1** | `MediaPrefetcher.shared.clear()` من مصدر ضغط الذاكرة (البند 3) | أعلى أثر لكل سطر في التقرير | 30 د |
| **2** | تسخين الملصقات عند نموّ النافذة (ما بقي من البند 4) | معزول تماماً، ويُهيّئ عدّادات القياس | 30 د |
| **3** | ميزانية الصور من `os_proc_available_memory()` (البند 3) | يحتاج العدّادات من الخطوة 2 ليُقاس | 2 س |
| **4** | التصفيح — ابدأ بـ `MoviesVM` وحدها (البند 1) | **موافقة المالك أولاً** (`PROJECT_HANDOFF §6.6`) | 4 س |
| **5** | التصفيح — `SeriesVM` ثم `LiveTVVM` | بعد تحقّق البناء 4 على الجهاز | 4 س |
| **6** | `@Observable` — الأصناف الصغيرة أولاً (البند 2) | التحقّق من نمط الملكية على شيء لا يُسقط الإقلاع | 2 س |
| **7** | `@Observable` — `HomeVM` ثم الثلاثة الكبار | أكبر عائد، وأكبر نصف قطر انفجار | 4 س |
| **8** | التكيّف الحراري (ج-أ) | بعد أن تُعالَج الأسباب لا الأعراض | 2 س |
| **—** | **قرار المالك:** احذف Turbo أو أَظهِره ومعه التسليم (البند 5) | ليس عملاً هندسياً بل قراراً | — |

**قاعدة واحدة تحكم الجدول كلّه:** بندٌ واحد لكل بناء، ومراجعة خصومية قبل كلٍّ منها. سجّل
`PROJECT_HANDOFF §11` أن المراجعة الخصومية **وجدت عيباً حقيقياً في كل جولة بلا استثناء**. ولا يوجد
في هذا التقرير بندٌ يستحقّ أن يكون الاستثناء الأول.

---

## ملحق — المصادر المُستشهَد بها

**توثيق Apple**
- Observation — https://developer.apple.com/documentation/observation
- `@Observable` — https://developer.apple.com/documentation/observation/observable()
- دليل الترحيل من `ObservableObject` — https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
- `NSCache` — https://developer.apple.com/documentation/foundation/nscache
- `os_proc_available_memory()` — https://developer.apple.com/documentation/os/os_proc_available_memory()
- `DispatchSource.makeMemoryPressureSource` — https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)
- `ProcessInfo.thermalState` — https://developer.apple.com/documentation/foundation/processinfo/thermalstate
- `ProcessInfo.isLowPowerModeEnabled` — https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- `URLSessionConfiguration.waitsForConnectivity` — https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity
- `URLSessionConfiguration.background(withIdentifier:)` — https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
- `UICollectionViewDataSourcePrefetching` — https://developer.apple.com/documentation/uikit/uicollectionviewdatasourceprefetching
- `UIHostingConfiguration` — https://developer.apple.com/documentation/swiftui/uihostingconfiguration
- MetricKit — https://developer.apple.com/documentation/metrickit

**جلسات WWDC**
- WWDC23 · Discover Observation in SwiftUI (10149) — https://developer.apple.com/videos/play/wwdc2023/10149/
- WWDC22 · Use SwiftUI with UIKit (10072) — https://developer.apple.com/videos/play/wwdc2022/10072/
- WWDC18 · iOS Memory Deep Dive (416) — https://developer.apple.com/videos/play/wwdc2018/416/

**غير Apple**
- SE-0395 Observability — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md
- SQLite Query Optimizer Overview — https://sqlite.org/optoverview.html
- GRDB · ValueObservation — https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb/valueobservation

**مصادر داخلية (وهي الأقوى في هذا التقرير)**
- `TECH_ADJUDICATION.md` — البنود الثمانية السابقة، لا تُعاد
- `PROJECT_HANDOFF.md` §3 (القيود) · §5f (التمايز) · §6.6 (التصفيح مؤجَّل بموافقة) · §9 (P2–P8) · §11 (المراجعة الخصومية) · §13 (المفتوح)
- `RESEARCH.md` §6 — أوصى بـ `@Observable` وبمَخرج UIKit؛ هذا التقرير يحكم عليهما
- `DEVICE_MATRIX.md` — مقاسات الشاشات التي بُني عليها حساب 800 بكسل في البند 3
