# مقياس الفهرس: 20–50 ألف عنصر تبدو فورية

تقرير هندسي لمسار البيانات في التصفّح والبحث والتصفية والتمرير. كل ادّعاء عن كودنا مربوط بـ `file:line`.
كل ما يخص تسجيل الدخول والاستيراد الأول موجود في `PERF_LOGIN_LOAD.md` — هذا التقرير لا يكرّره، بل يبدأ من اللحظة التي صار فيها الفهرس في الذاكرة.

الترتيب في كل قسم: **(الأثر المحسوس) ÷ (المخاطرة)**، الأعلى أولاً.

---

## 0. الخلاصة — اثنا عشر سطراً

| # | البند | المكان | الأثر / المخاطرة |
|---|---|---|---|
| 1 | `MoviesVM.rebuildEditorial` و `SeriesVM.rebuildEditorial` ما زالتا تفرزان العناصر لا الفهارس — نفس العيب الذي أُصلح في `HomeVM` وحده | `ContentViews.swift:870-875`, `2092-2097` | ضخم / شبه معدوم |
| 2 | بحث التبويبات مسح خطّي على الذاكرة، وليس FTS5 — و FTS5 مكتوب وجاهز ويعمل في `SearchVM` فقط | `ContentViews.swift:51-58`, `860-866`, `2082-2088` مقابل `3234-3238` | ضخم / منخفض |
| 3 | `MoviePosterScreen.shown` و `ChannelListScreen.shown` تُطوى كل الأسماء عبر ICU في كل رسم إطار، بلا حفظ ولا debounce | `ContentViews.swift:2028-2030`, `805-807` | كبير / منخفض جداً |
| 4 | حقل البحث في واجهة iPad مربوط مباشرة بـ `vm.search` بلا أي debounce | `ContentViews.swift:1697`, `260` | كبير / منخفض جداً |
| 5 | `CatalogDB` يستعمل `DatabaseQueue`: استيراد واحد يحجب كل قراءة (بحث + ThumbHash) لعشرات الثواني | `CatalogDB.swift:28-36`, موثّق في `DesignSystem.swift:1571-1576` | كبير / متوسط |
| 6 | لا شيء يقرأ من SQLite في القوائم. `pageMovies`/`pageChannels`/`pageSeries`/`load`/`isPopulated`/`countMovies`/`movieCategoryCounts`/`categories` كود ميت بلا مستهلك | `CatalogDB.swift:147-287` | — (هذا هو الطريق) |
| 7 | `grouped` نسخة كاملة دائمة ثانية من الفهرس في كل واحد من ثلاثة VM | `ContentViews.swift:29-32`, `847-850`, `2069-2072` | متوسط / متوسط |
| 8 | `Movie` ≈ 424 بايت لأن `details` مضمّن (192 بايت) وهو `nil` في كل عناصر الفهرس | `Models.swift:224-270`, `192-221` | متوسط / منخفض |
| 9 | `favorites` و `folders` خاصيتان محسوبتان تمسحان الفهرس/تفرزان في كل تقييم `body` (تظهر على iPad خصوصاً) | `ContentViews.swift:1599`, `163`, `1575`, `136` | متوسط / منخفض |
| 10 | `filtered` / `applyFilter` / `filter()` / `selectCat` / `sortBy` — لا تقرؤها أي واجهة. كود ميت | `ContentViews.swift:17,81-94,833,897-910,2056,2117-2125` | صغير / معدوم |
| 11 | التمرير والنوافذ (`S8KListWindow`) سليمة ومصمَّمة صح — **لا تلمس** مفتاح إعادة الضبط `first?.id` | `ContentViews.swift:558-564`, `553`, `1974`, `2480` | لا تغيّرها |
| 12 | نسخ COW: الأربعة VM + `PlaylistService` يتشاركون **مخزناً واحداً** لا خمسة. النسخ الحقيقية أربع فقط، وكلها مسمّاة في §2 | §2 | — |

---

## 1. ما هو مسار البيانات فعلياً اليوم؟

### 1.1 الجواب المباشر

**لا شيء في التطبيق يقرأ قائمة من SQLite.** ولا قائمة واحدة.
كل شبكة وكل قائمة وكل رفّ تُغذّى من `M3UContent` واحدة في الذاكرة، تُبنى إمّا بفكّ ترميز JSON من `CatalogDiskCache` أو بتحليل شبكي كامل.

SQLite يُستعمل اليوم في مكانين اثنين فقط:

1. **البحث الشامل** — `SearchVM.ftsResults` (`ContentViews.swift:3290-3312`) عبر `CatalogDB.search` + `CatalogDB.moviesByIds/seriesByIds/channelsByIds`. هذا يعمل، وهو المسار الوحيد الصحيح في التطبيق.
2. **ThumbHash للصور** — `CatalogDB.imageHash` / `hasImageHash` / `saveImageHash` من `DesignSystem.swift:1436`, `1458`, `1461`.

كل ما عدا ذلك في `CatalogDB.swift` **مكتوب وغير مستهلَك**. تحققت بالبحث النصي على الشجرة كاملة:

| API | السطر | مستهلكون |
|---|---|---|
| `CatalogDB.load(scope:ttl:)` | `CatalogDB.swift:147` | **صفر** |
| `CatalogDB.isPopulated(scope:)` | `CatalogDB.swift:170` | **صفر** |
| `CatalogDB.pageChannels` | `CatalogDB.swift:206` | **صفر** |
| `CatalogDB.pageMovies` | `CatalogDB.swift:216` | **صفر** |
| `CatalogDB.pageSeries` | `CatalogDB.swift:226` | **صفر** |
| `CatalogDB.countMovies` | `CatalogDB.swift:264` | **صفر** |
| `CatalogDB.movieCategoryCounts` | `CatalogDB.swift:273` | **صفر** |
| `CatalogDB.categories(scope:kind:)` | `CatalogDB.swift:281` | **صفر** |

التعليق في رأس الملف صادق تماماً بهذا الخصوص: «STEP 2 (isolated): … NO consumer yet — CatalogDiskCache stays the live path until the VMs are switched over (step 4)» (`CatalogDB.swift:12-17`). الخطوة 4 لم تُنفَّذ. المخزن مبنيّ، والفهرس المقلوب مبنيّ، وترقيم keyset مبنيّ على فهارس مغطّية صحيحة — ولا أحد يستعملها.

### 1.2 المسار الكامل، بالترتيب

```
Store.shared.m3uURL  ──►  PlaylistService.load(force:)            Core.swift:1787
                            └─► _load(force:)                      Core.swift:1796
                                 ├─ (بارد، ضمن TTL) CatalogDiskCache.read(scope:)   Core.swift:1806
                                 │     ├─ Data(contentsOf:.mappedIfSafe)            Core.swift:1748
                                 │     ├─ JSONDecoder().decode(Envelope.self)       Core.swift:1749  ← تجسيد كامل ①
                                 │     └─ content(from: env)  .map ×3               Core.swift:1682-1710 ← تجسيد كامل ②
                                 ├─ (Xtream) loadXtreamDirect(xd)                   Core.swift:2123
                                 └─ (M3U خام) M3UParser.build(from: text)           Core.swift:1415
                                      ثم: Task.detached { CatalogDiskCache.save }   Core.swift:1850, 1899
                                          Task.detached { CatalogDB.save }          Core.swift:1854, 1901   ← كتابة ظلّ فقط
                            └─ يُحتفظ به في actor: `private var content: M3UContent?`  Core.swift:1763

ContentService.movies() / series() / liveStreams() / *Categories()  Core.swift:2394-2417
        كلها: `try await PlaylistService.shared.load().<field>`     ← لا نسخ (COW)

  ├─ HomeVM.movies / series / liveChannels        HomeView.swift:28-30, 184-204
  ├─ MoviesVM.movies                              ContentViews.swift:832, 886
  ├─ SeriesVM.series                              ContentViews.swift:2055, 2106
  └─ LiveTVVM.channels                            ContentViews.swift:16, 68
```

### 1.3 أين تعيش المصفوفات، وكم نسخة، وما المحتفَظ به

المحتفَظ به **بشكل دائم** طوال جلسة التطبيق:

| المالك | ما يملكه | مخزن مستقل؟ |
|---|---|---|
| `PlaylistService.content` (actor) | `M3UContent` كاملة | **نعم** — المخزن الأصلي |
| `HomeVM.movies/series/liveChannels` | نفس المصفوفات | لا — نفس المخزن (COW) |
| `MoviesVM.movies` | نفس المصفوفة | لا — نفس المخزن |
| `SeriesVM.series` | نفس المصفوفة | لا |
| `LiveTVVM.channels` | نفس المصفوفة | لا |
| `MoviesVM.filtered` / `SeriesVM.filtered` / `LiveTVVM.filtered` | نفس المصفوفة عند التحميل | لا — لكنها **كود ميت**، لا تقرؤها أي واجهة |
| `*VM.grouped` (`[String: [Movie]]` …) | كل عنصر منسوخ إلى مصفوفة قسمه | **نعم — نسخة كاملة ثانية دائمة** |
| `*VM.foldedNames` (`[String]`) | سلسلة مطويّة جديدة لكل اسم | **نعم** (لكنها رخيصة ومفيدة — أبقِها) |
| `HomeVM.topMovies/topSeries/newMovies/newSeries` | 10 + 10 + 20 + 20 عنصراً | محدود — سليم |
| `MoviesVM.topRanked/heroItems`, `SeriesVM.*` | 10 + 6 | محدود — سليم |

**النقطة المهمّة والصادقة:** الأربعة VM لا تصنع أربع نسخ. `ContentService.movies()` تُعيد حقلاً من بنية، وإسنادها إلى `@Published var movies` هو احتفاظ (retain) بنفس المخزن، لا نسخ. مصفوفات Swift هي COW، والنسخة تُفرض عند **الطفرة** لا عند الإسناد. لا أحد من الأربعة يطفر مصفوفته بعد التحميل. فالادّعاء الشائع «خمس نسخ من الفهرس» **غير صحيح في هذا الكود**.

النسخ الحقيقية معدودة، ومسمّاة في §2.

### 1.4 فخّ صحّة يجب معرفته قبل أي ترحيل

`_load` تعود مبكراً من مخبأ القرص (`Core.swift:1806-1827`) **بدون** أن تلمس SQLite. أي أن `CatalogDB.save` لا تُستدعى إلا على مسار شبكي حقيقي (`Core.swift:1854`, `1901`) وبشرط `!built.isPartial` (`Core.swift:1842`). النتيجة:

> يمكن أن يكون مخبأ JSON طازجاً بينما SQLite **فارغ تماماً** لهذا الخطّ — لمدة غير محدودة، إن كان المستخدم قد ثبّت النسخة قبل وجود المخزن، أو إن فشلت كتابة واحدة.

لهذا فإن أي قارئ مُرقَّم (paged) **يجب** أن يسأل عن الجاهزية أولاً ويتدهور بأمان. `CatalogDB.isPopulated` مكتوبة لهذا الغرض بالضبط وغير مستعملة. لكنها قراءة SQLite متزامنة — ويُمنع منعاً باتاً استدعاؤها من الـ main thread (السبب في §5 من `PERF_LOGIN_LOAD.md` وفي `DesignSystem.swift:1571-1576`). الحل الدقيق في §6، المرحلة 1.

---

## 2. الذاكرة والنسخ — بصدق، لخطّ 50 ألف عنصر

### 2.1 حجم البنى (محسوب من ترتيب التصريح؛ Swift لا يعيد ترتيب حقول البنى)

| النوع | التركيب | الحجم |
|---|---|---|
| `Channel` (`Models.swift:132-156`) | 5×16 (String/String?) + Bool + حشو + 16 (`directURL`) | **≈ 104 بايت** |
| `Series` (`Models.swift:273-299`) | 11×16 + Bool + حشو + 8 (`seasons`) | **≈ 192 بايت** |
| `Movie` (`Models.swift:224-270`) | 13×16 = 208، + Bool + حشو = 216، + 16 (`directURL`) = 232، + **192** (`details: S8KTitleDetails?`) | **≈ 424 بايت** |
| `S8KTitleDetails` (`Models.swift:192-221`) | 12 × `String?` × 16 | **192 بايت** |

> تحقّق على الجهاز بـ `print(MemoryLayout<Movie>.stride)` — الحساب أعلاه نظري ويجب تأكيده مرّة واحدة.

**الاكتشاف:** `Movie.details` قيمته `nil` في **كل** عنصر من عناصر الفهرس — لا يُملأ إلا في صفحة التفاصيل (`Models.swift:241-244`, يُقرأ في `ContentViews.swift:2599`, `2753`). ومع ذلك يدفع كل فيلم 192 بايت ثمنه. أي **45% من حجم `Movie` هو حقل فارغ دائماً في القوائم**. الملاحظة تكتسب وزناً أكبر لأن `Series` لا تحمل تفاصيلها إطلاقاً — بل تعيش في `PlaylistService.seriesDetailsCache` (`Core.swift:2369`). فـ `Movie` هو الشاذّ عن نمط المشروع نفسه.

### 2.2 مثال محسوب: 20,000 قناة + 25,000 فيلم + 5,000 مسلسل

مخزن المصفوفات وحده (بدون كومة السلاسل):

- القنوات: 20,000 × 104 = **2.1 م.ب**
- الأفلام: 25,000 × 424 = **10.6 م.ب**
- المسلسلات: 5,000 × 192 = **1.0 م.ب**
- **المجموع ≈ 13.7 م.ب** لكل نسخة كاملة.

كومة السلاسل: سلاسل Swift الأصلية ≤ 15 بايت UTF-8 تُخزَّن داخلياً (small-string). الاسم و`posterURL` و`directURL` تتجاوزها عادةً → ~3 تخصيصات كومة لكل عنصر × ~48 بايت ≈ 150 بايت للفيلم، و~200 بايت للقناة. الإجمالي المقيم للفهرس الحيّ ≈ **20–25 م.ب**. رقم معقول — لكن الأهم أن السلاسل **تُشارَك** عبر النسخ (احتفاظ لا نسخ)، فتكلفة كل نسخة إضافية هي مخزن المصفوفة (13.7 م.ب) **زائد ~200,000 عملية retain/release**.

### 2.3 أين تُفرض نسخة حقيقية — بالضبط

| # | الموضع | نوع الفرض | الحجم | دائم؟ |
|---|---|---|---|---|
| ① | `JSONDecoder().decode(Envelope.self)` `Core.swift:1749` | تجسيد DTO كامل | ≈ 13.5 م.ب + كل السلاسل | لا (يُحرَّر بعد ②) |
| ② | `content(from: e)` — ثلاث `.map` `Core.swift:1684-1705` | `map` = مصفوفة جديدة | ≈ 13.7 م.ب (السلاسل مشتركة) | **نعم** — هذا هو الفهرس الحيّ |
| ③ | `rebuildGroups()` — `Dictionary(grouping:)` `ContentViews.swift:30`, `848`, `2070` | نسخ كل عنصر إلى مصفوفة قسمه | **≈ 13.7 م.ب** | **نعم — دائم** |
| ④ | `rebuildSearchIndex()` — `.map { fold(name) }` `ContentViews.swift:45`, `857`, `2079` | سلسلة جديدة لكل اسم | ≈ 3 م.ب | نعم (ورخيص — أبقِه) |
| ⑤ | `MoviesVM.rebuildEditorial()` `ContentViews.swift:871-872` | **`sorted` ×2 + `filter` ×2** | **≈ 42 م.ب عابرة** | لا — لكن على **main actor** |
| ⑥ | `SeriesVM.rebuildEditorial()` `ContentViews.swift:2093-2094` | نفس النمط | ≈ 8 م.ب عابرة | لا — على main actor |
| ⑦ | `MoviesView.favorites` `ContentViews.swift:1599` | `filter` كامل | حسب المفضّلات | لكل تقييم `body` |
| ⑧ | `s8kFolderSearch` من `body` `ContentViews.swift:2029`, `806` | `filter` + طيّ ICU لكل اسم | حسب القسم | **لكل إطار** |

**المجموع الدائم بعد استقرار التحميل ≈ 31 م.ب** (② + ③ + ④) + كومة السلاسل. والذروة العابرة أثناء `load()` تصل إلى **≈ 70–80 م.ب** بسبب ⑤ و⑥.

### 2.4 العيب رقم واحد في هذا القسم — والأدلة عليه

`HomeVM.rebuildHero` (`HomeView.swift:75-120`) تحمل تعليقاً مكتوباً بدم:

> «SORT INDICES, NOT ELEMENTS. The old comparators parsed a String into a Double/Int on EVERY comparison — twice per compare, ~n·log n compares. On a 30–60k-title line that was **0.4–1.5s of BLOCKED MAIN THREAD** right after login…» (`HomeView.swift:79-86`)

وتنفّذ العلاج بشكل صحيح تماماً (`HomeView.swift:88-103`).

لكن `MoviesVM.rebuildEditorial` و `SeriesVM.rebuildEditorial` **لم تُصلَحا**، وما زالتا تحملان النمط الأصلي حرفياً:

```swift
// ContentViews.swift:870-875
private func rebuildEditorial() {
    topRanked = Array(s8kUniqueByID(movies.sorted { $0.ratingDouble > $1.ratingDouble }, { $0.id }).prefix(10))
    let newest = s8kUniqueByID(movies.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }, { $0.id })
    heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .movie($0)) }
    …
}
```

لخطّ فيه 25,000 فيلم، هذا السطران يكلّفان في نهاية `MoviesVM.load()` (`ContentViews.swift:887`)، **على الـ main actor**:

- `sorted` رقم 1: ~366,000 مقارنة، كل واحدة تنفّذ `Double(rating ?? "")` **مرّتين** → ~732,000 تحليل نصّي إلى `Double`، مع نقل بنية 424 بايت في كل تبديل.
- `s8kUniqueByID`: `filter` → نسخة كاملة ثانية.
- `sorted` رقم 2: ~366,000 مقارنة، `Int($0.id)` مرّتين → ~732,000 تحليل نصّي إلى `Int`، ونسخة كاملة ثالثة.
- `s8kUniqueByID` ثانية: نسخة كاملة رابعة.

**≈ 1.5 مليون تحليل سلسلة + أربع نسخ كاملة (≈42 م.ب) محجوزة على الـ main thread**، مرّتين (أفلام + مسلسلات)، في كل تحميل — لبناء 10 عناصر و6 عناصر.

هذا هو المرشّح الأول لعبارة «الصفحة تجمّدت لحظة بعد الدخول». الإصلاح مطابق حرفياً لما فعله `HomeVM` بالفعل، والكود الدقيق في §6 المرحلة 0-أ.

### 2.5 أين التصميم الحالي **سليم** — لا تعبث به

- **COW والمشاركة بين الـ VM**: صحيحة ولا تحتاج تغييراً. لا تُدخل `class` غلافاً حول `M3UContent` «لتوفير الذاكرة» — لا شيء يُوفَّر.
- **`foldedNames`**: 3 م.ب مقابل إلغاء مسح ICU لكل رسم إطار — صفقة ممتازة (`ContentViews.swift:34-47`).
- **الكتابة المؤجّلة `Task.detached`** لـ `CatalogDiskCache.save` و `CatalogDB.save` (`Core.swift:1850`, `1854`, `1899`, `1901`) — صحيحة، وقد أُصلحت لسبب موثّق. لا تُرجعها متزامنة.
- **`S8KImageCache`** (`DesignSystem.swift:1340-1465`): حدود مضبوطة، تفكيك ترميز خارج الـ main thread، دمج الطلبات المتزامنة، حراسة إعادة استعمال الخلية عبر `requestedURL`. من أنظف ما في الملف. **لا تلمسه.**
- **`MediaPrefetcher`** (`MediaPrefetcher.swift`): محدود بـ `cap = 2` وله حارس محرّك صحيح. سليم.
- **رفوف `HomeView`** (`HomeView.swift:1169-1465`): كلها محدودة (10/20 عنصراً) داخل `LazyHStack`. سليمة.
- **`RailEngine.build`**: مكلفة (`Dictionary(grouping:)` + فرز لكل قسم) لكنها **لا تُستدعى** — الاستدعاء أُلغي عمداً بتعليق موثّق (`HomeView.swift:145-149`). صحيح. لا تُعِدها.

---

## 3. البحث والتصفية

### 3.1 يوجد **نظاما بحث** في التطبيق، لا واحد

**النظام أ — البحث الشامل (`SearchVM`) — يستعمل FTS5 وهو صحيح.**

`ContentViews.swift:3218-3285`. عند كل تغيّر في النص:
1. `task?.cancel()` ثم `Task.sleep(350ms)` — debounce صحيح (`3226`).
2. `CatalogDB.isSearchable(scope:)` كبوّابة (`3234`).
3. `Task.detached(priority:.userInitiated)` — قراءات GRDB خارج الـ main actor (`3236-3238`). صحيح ومهم.
4. `CatalogDB.search` → `ORDER BY rank LIMIT ?` ثم `*ByIds` لحلّ المعرّفات مع الحفاظ على الترتيب (`CatalogDB.swift:188-197`, `238-261`).
5. تدهور آمن إلى المسح الخطّي حين لا يكون المخزن جاهزاً (`3239-3276`).

هذا هو النموذج الصحيح، وهو مكتوب ومُثبت داخل هذا المستودع.

**النظام ب — بحث التبويبات (مباشر / أفلام / مسلسلات) — مسح خطّي على الذاكرة.**

المسار: `AppRouter.searchText` → `.onChange` في `ContentViews.swift:201`, `1656`, `2208` → `vm.search = q` → قراءة `vm.searchResults` من الـ `body` → `searchMatches()`:

```swift
// ContentViews.swift:51-58 (وكذلك 860-866, 2082-2088)
fileprivate func searchMatches() -> [Channel] {
    let q = S8KSearch.fold(search)
    if lastQuery == q { return lastResults }
    let r: [Channel] = q.isEmpty ? [] : zip(foldedNames, channels).compactMap { $0.0.contains(q) ? $0.1 : nil }
    lastQuery = q; lastResults = r
    return r
}
```

هذا **محفوظ بشكل صحيح** (memo بمدخل واحد) — استعلام مكرّر يكلّف `O(1)`. لكن كل استعلام **جديد** يكلّف `O(n)` استدعاء `String.contains(String)`.

### 3.2 ما يحدث في كل ضغطة مفتاح، بدقّة

| المنصّة | المسار | debounce | الكلفة لكل ضغطة مُثبَّتة |
|---|---|---|---|
| iPhone — تبويب | `AppTabBar.searchField` → `commitSearch` `DesignSystem.swift:2210-2217` | **220 مللي ثانية** ✔ | انظر أدناه |
| iPad — شبكة الأفلام | `SearchField(text: $vm.search)` `ContentViews.swift:1697` | **لا يوجد** ✘ | كل حرف |
| iPad — قائمة القنوات | `SearchField(text: $vm.search)` `ContentViews.swift:260` | **لا يوجد** ✘ | كل حرف |
| شاشة قسم (أفلام) | `MoviePosterScreen` `ContentViews.swift:2025`, `2028-2030` | **لا يوجد** ✘ | **كل إطار** |
| شاشة قسم (قنوات) | `ChannelListScreen` `ContentViews.swift:802`, `805-807` | **لا يوجد** ✘ | **كل إطار** |
| بحث شامل / الرئيسية | `SearchVM` | 220 + 350 = **570 مللي ثانية** (مزدوج) | FTS5 ✔ |

**المضاعِف المخفي:** `AppRouter` هو `@ObservedObject` في `HomeView` و`LiveTVView` و`MoviesView` و`SeriesListView` معاً، وكلها أبناء `TabView` واحد يبقيها حيّة بعد أول زيارة (`BlankTVApp.swift:252-263`). لذا `.onChange(of: router.searchText)` يُطلق في **كل التبويبات المُركَّبة**، فتُسنَد `vm.search` في ثلاثة VM، وتُقيَّم أجسام ثلاث صفحات، وتُنفَّذ **ثلاثة مسوح خطّية** — على القنوات والأفلام والمسلسلات — مقابل ضغطة مفتاح واحدة في تبويب واحد.

لخطّ 50 ألف عنصر: ~50,000 استدعاء `contains` لكل ضغطة مثبَّتة، على الـ main actor.

**ملاحظة تقنية يجب حسمها على الجهاز:** `foldedNames[i].contains(q)` حيث `q: String` يمكن أن يُحلّ إلى واحد من زائدَين: زائدة Foundation `StringProtocol.contains<T: StringProtocol>` (التي تنفّذ `range(of:) != nil` — استدعاء ICU لكل اسم)، أو زائدة المكتبة القياسية `Collection.contains(_: some Collection)` المضافة في Swift 5.7. الأولى أبطأ بمرتبة. لا أستطيع الجزم من قراءة الكود؛ يُحسم بـ Time Profiler ورؤية أيّ رمز يظهر (`_stringCompareWithSmolCheck` مقابل `CFStringFindWithOptions`). في كلتا الحالتين الكلفة الدنيا هي `O(مجموع أحرف الفهرس)` لكل استعلام، أي ~1.2 مليون مقارنة محرف — والعلاج واحد.

### 3.3 الكلفة الخوارزمية والعلاج المسمّى

| اليوم | البديل |
|---|---|
| `O(n)` مسح خطّي، `n` = حجم الفهرس، على الـ main actor، ×3 تبويبات | `O(log n + k)` عبر FTS5، خارج الـ main actor، `k` = عدد النتائج المحدود |
| 50,000 استدعاء `contains` / ضغطة | استعلام SQL واحد بـ `LIMIT 60` + حلّ 60 معرّفاً |
| بلا ترتيب أهمّية (ترتيب المزوّد) | `ORDER BY rank` (bm25) |
| الاسم فقط | الاسم + النوع + الطاقم + القصّة + المخرج (الفهرس مبنيّ بالفعل — `CatalogDB.swift:124-130`) |

**العلاج الدقيق:** استبدال جسم `searchMatches()` في الـ VM الثلاثة باستدعاء FTS مُدَبْدَب (debounced) وخارج الـ main actor، بنفس بنية `SearchVM.ftsResults` المُثبتة (`ContentViews.swift:3290-3312`)، مع إبقاء المسح الخطّي كتدهور آمن حرفياً كما تفعل `SearchVM` اليوم (`ContentViews.swift:3239`). التفاصيل في §6 المرحلة 2.

### 3.4 ملاحظات على جودة فهرس FTS5 الحالي

سليم إجمالاً، وأفضل من المتوقّع:

- `tokenize = 'unicode61 remove_diacritics 2'` (`CatalogDB.swift:128`) — **صحيح ومعاصر**. الخيار `2` هو التصحيح الكامل؛ `1` القديم يترك حالات كثيرة، وهو ما يجعل البحث العربي بلا تشكيل يعمل.
- `scope`/`kind`/`itemId` مصرَّحة `UNINDEXED` (`CatalogDB.swift:127`) — صحيح؛ لا تُبنى فهارس نصية لأعمدة ترشيح.
- `actors` بدل `cast` لتفادي تصادم الكلمة المحجوزة `CAST` — انتباه جيّد (`CatalogDB.swift:126`).
- `ftsQuery` (`CatalogDB.swift:180-186`) تشقّ على `CharacterSet.alphanumerics.inverted` — الحروف العربية أبجدية-رقمية في Unicode فتنجو، والشقّ نفسه يزيل كل محارف FTS5 الخاصّة فلا حاجة لهروب إضافي ولا خطر حقن.

نقاط تحسين (ليست عيوباً):

1. **لا خيار `prefix=`.** كل استعلام هو `token*`، أي بحث بادئة في فهرس المصطلحات. إضافة `prefix='2 3'` إلى تعريف الجدول تجعل بادئات الحرفين والثلاثة — وهي **بالضبط** ما يُكتب أثناء الطباعة — قفزة فهرس مباشرة، مقابل زيادة حجم الفهرس. يحتاج ترحيلاً (إعادة بناء الجدول الافتراضي).
2. **الجدول يخزّن `plot` كاملاً.** لهذا يبلغ الاستيراد ~192,000 عبارة (`DesignSystem.swift:1573`). جعله `content=''` (contentless) أو external-content يقلّص الكتابة والحجم بنحو النصف، لأن `*ByIds` تجلب النصّ الحقيقي من الجداول الأصلية أصلاً ولا تحتاج FTS أن يحتفظ به.
3. **`bm25()` وأوزان الأعمدة**: `ORDER BY rank` يستعمل الأوزان الافتراضية المتساوية، فمطابقة في `plot` تنافس مطابقة في `name`. `ORDER BY bm25(catalog_fts, 0,0,0, 10.0, 2.0, 1.0, 0.5, 1.0)` يرفع الاسم فوق القصّة. تحسين جودة بحت، بلا ترحيل. (الصياغة موثَّقة في `sqlite.org/fts5.html`: أوزان حقيقية بترتيب الأعمدة.)
4. **`ftsQuery` يعيد اختراع واجهة موجودة**: GRDB يوفّر `FTS5Pattern(matchingAllPrefixesIn:)` — بنّاء رسمي **لا يرمي استثناءً** على مدخل المستخدم، وهو حرفياً دلالة `ftsQuery` عندنا (`CatalogDB.swift:180-186`). تنفيذنا صحيح ولا يقبل الحقن، لكن الانتقال إليه يقلّص سطح الصيانة. اختياري ومنخفض المخاطرة. انظر §5.7.
5. **قيد إصدار**: GRDB 7.9.0 (2025-12-13) أصلح «task cancellation issues with FTS5 full-text search». نحن على 6.24 لأن 7 على SPM فقط (`Podfile:8-11`) — فالإصلاح لا يشملنا. `SearchVM` يلغي مهامّه عند كل ضغطة (`ContentViews.swift:3219`)، فإن ظهرت أعطال إلغاء أثناء البحث فهذا أول مكان يُنظر فيه.

### 3.5 التصفية (بخلاف البحث)

`applyFilter()` (`ContentViews.swift:897-910`, `2117-2125`) و `filter()` (`81-92`) و `selectCat` (`94`) و `sortBy` (`838`, `904`) و `filtered` (`17`, `833`, `2056`) — **لا تقرأ أي واجهة أياً منها**. تحققت من الشجرة كاملة: `filtered` لا تُقرأ في أي `View`، و`selectCat` بلا مستدعٍ.

التصفية الفعلية تتمّ عبر `grouped` (قاموس محسوب مرّة عند التحميل) و`list(in:)` (`ContentViews.swift:137-139`, `1576-1578`, `2134-2136`) — وهذا **تصميم صحيح ورخيص**: بحث قاموس `O(1)` ثم احتفاظ بمصفوفة موجودة، بلا نسخ.

الحكم: التصفية ليست مشكلة أداء. المشكلة الوحيدة هي أن `applyFilter` تُستدعى في `load()` (`887`, `2107`) فتنشر `@Published` بلا فائدة. حذف الخمسة يقلّل الضوضاء ولا يقدّم أداءً محسوساً — **صنّفها تنظيفاً، لا تحسيناً**.

---

## 4. التمرير

### 4.1 النوافذ — مصمَّمة بشكل صحيح، ويجب عدم المساس بها

`S8KListWindow` (`ContentViews.swift:558-564`): `initial = 120`, `step = 180`.
النمط: `ForEach` على `prefix(shown)` + خفير (sentinel) بارتفاع 1 نقطة داخل الحاوية الكسولة، يزيد النافذة عند ظهوره.

المطبَّق في: `ChannelList` (`517-543`)، `PosterGrid` (`1953-1967`)، `SeriesGrid` (`2469-2512`)، ولوح iPad للقنوات (`160`, `269-279`).

**التحذير التاريخي — قرأت الكود و`git log`:**

الالتزام `d4fe249` («Perf: window the big lists and grids (P2)») يوثّق حرفياً:

> «The window reset is keyed on the HEAD ITEM, not the count… keyed on count, toggling one favourite in a >120 favourites list would collapse the content height and throw the scroll position; … inside the else branch, the modifier is destroyed on a 5000 → 0 transition (a search with no results) and never fires».

المفتاح الحالي `.onChange(of: channels.first?.id)` موضوع على `Group` يلفّ الفرعين (`ContentViews.swift:547-553`, `1973-1974`, `2479-2480`). **هذا صحيح. لا تحوّله إلى `count`، ولا تنقله داخل فرع `else`، ولا تضف `.id()` على الحاوية الكسولة نفسها.** أي تصميم ترقيم جديد يجب أن يُلحق الصفحات بذيل المصفوفة مع بقاء العنصر الأول كما هو — وهو بالضبط ما يفعله ترقيم keyset في `CatalogDB.page*` (تصاعدي على `pos`). التوافق هنا ليس مصادفة.

### 4.2 ما هو سليم فعلاً

- `LazyVGrid` / `LazyVStack` مع `ForEach(... id: \.element.id)` أو `Identifiable` — صحيح.
- `MoviePosterCell` / `SeriesGrid` تستعملان صندوق `Color.clear` بنسبة 2:3 مع `overlay` للصورة (`1992-1998`, `2492-2498`) — يمنع تسرّب عرض الملصق ويجعل الهيكل العظمي مطابقاً للمحمَّل. جيّد.
- `ChannelRow` تستقبل `isFav: Bool` مرّة من الأب بدل أن يحمل كل صفّ `@StateObject` على المفرد (`ContentViews.swift:519`, `566-574`) — إصلاح مهم ومُنفَّذ.
- `S8KImage.task(id: url)` + حراسة `requestedURL` (`DesignSystem.swift:1541`, `1580-1588`) — يمنع «الملصق الخطأ أثناء التمرير السريع».
- `BarVisibility.report(offsetY:)` (`DesignSystem.swift:2135-2143`) تُستدعى في كل إطار تمرير عبر `onScrollGeometryChange`، لكنها **محروسة بعتبة** ولا تنشر `@Published` إلا عند تبدّل الحالة. **لا إبطال لكل إطار.** سليم.
- `S8KImageCache.prefetch` مُستدعى على نوافذ محدودة (`prefix(40)` / `prefix(30)`) داخل `.onAppear` (`544`, `1970`, `2514`). سليم.

### 4.3 عيوب حقيقية في مسار التمرير

**(أ) إعادة حساب لكل إطار في شاشتَي القسم — الأعلى أثراً في هذا القسم.**

```swift
// ContentViews.swift:2028-2030
private var shown: [Movie] { s8kFolderSearch(movies, search) { $0.name } }
// ContentViews.swift:805-807 — نفس الشيء للقنوات
```

`s8kFolderSearch` (`ContentViews.swift:116-122`) تنفّذ `S8KSearch.fold($0.name)` — أي `String.folding(options:locale:)`، استدعاء ICU مخصِّص — **لكل اسم، في كل تقييم `body`**، بلا حفظ وبلا debounce، بينما `SearchField` (`1442-1468`) لا تحمل أي تأخير.

هذا هو بالضبط النمط الذي أُنشئت `foldedNames` لقتله (التعليق في `ContentViews.swift:34-40`)، والشاشتان الورقيتان لم تُحوَّلا. في قسم فيه 5,000 فيلم: 5,000 طيّة ICU لكل حرف، وأكثر من مرّة لكل إطار أثناء الرسم. (لصالحها: `q.isEmpty` يعيد `items` مباشرة `120`، فالكلفة صفر ما لم يكن هناك استعلام — لكن لحظة الطباعة هي بالضبط اللحظة المحسوسة.)

**(ب) نافذة لوح iPad لا تُعاد ضبطها عند تغيّر الاستعلام.**

`padShown` تُعاد إلى `initial` عند تبدّل القسم فقط (`ContentViews.swift:233`). لكن `channelScroll` يبدّل المصدر بين `chans` و`vm.searchResults` (`257`) — تتغيّر هوية القائمة كلياً بينما `padShown` تبقى حيث نمت (قد تكون 2,000). النتيجة: `ForEach` يمشي على 2,000 هوية لقائمة نتائج فيها 12 عنصراً، والخفير يصبح فوق الطيّة. عيب صغير لكنه حقيقي. الإصلاح: إضافة `.onChange(of: vm.search) { _, _ in padShown = S8KListWindow.initial }` على `padBrowser` (بجانب السطر 233).

**(ج) `ForEach(Array(visible.enumerated()), id: \.element.id)`** (`ContentViews.swift:530`, `269`) ما زالت تُجسّد صفّاً من الصفوف عند كل إبطال. مع النافذة هذا محدود بـ `shown` (120 → بضعة آلاف بعد تمرير طويل)، لا 56,000. مقبول. لا تغيّره الآن؛ إن أُزيل لاحقاً فليكن بتمرير `index` عبر `enumerated()` كسول أو بحقل ترتيب من SQL (`pos` موجود أصلاً).

**(د) خطر هويّة مكرَّرة في `SeriesGrid`.**

`HomeView.swift:8-13` يوثّق أن معرّفات مسلسلات M3U مُشتقّة من **الاسم** (`M3UParser` `Core.swift:1495`: `stableID("series", name)`)، فالمسلسلات المتشابهة العنوان (منتشرة في قوائم IPTV) تتصادم على نفس المعرّف — وأن `ForEach` + `scrollPosition` **ينهار** على ذلك. الحلّ `s8kUniqueByID` مطبَّق على البطل والعشرة الأوائل — لكن **ليس** على `SeriesGrid` (`ContentViews.swift:2485`: `ForEach(series.prefix(shown))`). شبكة المسلسلات لا تستعمل `scrollPosition` فلن تنهار، لكن `ForEach` بهويات مكرّرة سلوكه غير معرَّف (صفوف مفقودة أو مكرَّرة). عيب كامن — والترقيم من SQL يحلّه مجاناً لأن المفتاح الأساسي `(scope, id)` يجعل التكرار مستحيلاً في المخزن.

**(هـ) خاصيّات محسوبة تمسح الفهرس داخل `body`.**

- `MoviesView.favorites` (`ContentViews.swift:1599`) = `vm.movies.filter { … }` — مسح كامل. تُستدعى في `padBrowser` عبر `favoritesCount: favorites.count` (`1674`) في **كل** تقييم `body` على iPad.
- `LiveTVView.favorites` (`163`) — نفسه عبر `222`.
- `vm.folders` (`136`, `1575`, `2133`) = `Store.orderedCategories` (`Core.swift:1182-1191`) — تبني قاموس رتب + مرشِّحين + فرز في كل قراءة، ومرّتين لكل `body` في `MoviesView` (`1866`, `1869`).

كلاهما `O(n)` أو `O(cats·log cats)` لكل إطار. على iPad مع 25,000 فيلم، `favorites` وحدها مسح كامل لكل رسم.

**العلاج:** تحويلهما إلى قيم مخزّنة تُحدَّث عند تغيّر `favs.movies` (`.onChange`) بدل خاصيّة محسوبة، أو الأفضل — عدّ من SQL (`CatalogDB.countMovies` مكتوبة أصلاً وغير مستعملة).

### 4.4 ما لا يوجد اليوم ولا أنصح بإضافته الآن

لا `List`، ولا `scrollPosition(id:)` على القوائم الطويلة، ولا `onScrollVisibilityChange`، ولا استرجاع موضع تمرير. البطل وحده يستعمل `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` (`HomeView.swift:298-299`) وهو محدود بـ 8 عناصر.

هذا **مناسب، والبحث في §5 يؤيّده صراحةً**:

- `List` كان سيجمع **كل** المعرّفات فوراً — «all the IDs of List and Table are gathered eagerly» (WWDC23 10160). خمسون ألف معرّف عند فتح التبويب. النافذة تجعلها 120. **لا تستبدل `LazyVGrid` بـ `List`.**
- `scrollPosition(id:)` أداة منع القفزة الرسمية، لكن ضمان Apple موصوف لحالة **إعادة ترتيب** البيانات أو تغيّر الحجم. ترقيمنا يُلحق بالذيل فلا يعيد ترتيب شيء. **لا تُضِفها استباقياً؛ احتفظ بها كخطّة طوارئ إن أظهر اختبار جهاز قفزة فعلية** (§5.5).
- `onScrollVisibilityChange(threshold:)` (iOS 18) هو المشغّل الأصحّ لتحميل الملصقات — أدقّ من `onAppear` الذي يتبع بناء العرض لا رؤيته. تحسين مستقبلي مشروع، خلف `#available`، لكنه ليس أولوية أمام §6.

القاعدة العامّة المستخلصة: إدخال `List` أو `scrollPosition` على شبكة ذات نافذة يفتح بالضبط فئة الأخطاء التي كلّفت هذا المشروع «انهيار التمرير» من قبل. أرجئ كليهما إلى ما بعد استقرار الترقيم.

---

## 5. أفضل ممارسة حالية (2025–2026) — بحث موثَّق

> **حدّ منهجي يجب ذكره:** حصّة WebSearch كانت مستنفدة (200/200) قبل بدء هذا البحث. كل ما يلي جُلب **مباشرةً** من مصادر أوّلية: ملفات GitHub الخام، و`api.github.com`، ونقاط توثيق Apple (`developer.apple.com/tutorials/data/documentation/*.json`)، و`sqlite.org`. لا اكتشاف بكلمات مفتاحية، لذا «لم أجد» أدناه تعني «لم أجده بالجلب المباشر»، لا «غير موجود». ما لم يُتحقّق منه مذكور صراحةً في §5.8.

### 5.1 GRDB: `ValueObservation` مقابل الترقيم اليدوي

الإصدار الحالي **GRDB 7.11.1 (2026-06-18)**؛ نحن مثبَّتون على **6.24** عبر CocoaPods لأن 7 متاح على SPM فقط (`Podfile:8-11`).
https://raw.githubusercontent.com/groue/GRDB.swift/master/CHANGELOG.md

**الحكم الحاسم لحالتنا** — من توثيق `trackingConstantRegion` حرفياً:

> «Observations that do not track a constant database region **must not** use this method, because some changes may not be notified to the application.»
> والشرط المسبق: «The `fetch` function must perform requests that fetch from a single and **constant** database region.»

https://raw.githubusercontent.com/groue/GRDB.swift/master/GRDB/ValueObservation/ValueObservation.swift

استعلام `LIMIT`/`OFFSET` أو keyset يتغيّر مؤشّره **ليس منطقة ثابتة**. النتيجة:

- `trackingConstantRegion` — **غير آمن** لصفحة (قد تضيع تنبيهات).
- `tracking { }` العادي — آمن لكنه **يعيد جلب الصفحة كاملة عند أي كتابة** في المنطقة المتتبَّعة، وكتابتنا هي استيراد الفهرس بأكمله.

البديل الصحيح إن احتجنا إبطالاً: `DatabaseRegionObservation` — يخبرك أن شيئاً تغيّر ويسلّمك `Database` **بلا جلب**، فتقرّر أنت أي صفحة تعيد قراءتها:

```swift
let observation = DatabaseRegionObservation(tracking: Player.all())
let cancellable = try observation.start(in: dbQueue) { error in
} onChange: { (db: Database) in /* أعد قراءة الصفحة المرئية فقط */ }
```
https://raw.githubusercontent.com/groue/GRDB.swift/master/GRDB/Documentation.docc/Extension/DatabaseRegionObservation.md

إرشادات الأداء الرسمية لـ `ValueObservation` (نفس المستودع، `Documentation.docc/Extension/ValueObservation.md`): «Avoid observing list elements individually; observe the entire collection»، وأوقف المراقبة في دورة حياة العرض، وشاركها عبر `shared(in:scheduling:extent:)`، وعالج القيم عبر `map` **خارج** المعاملة. كما أن المراقبة قد تدمج التغييرات وقد تُبلّغ بقيم متطابقة متتالية → `removeDuplicates()`.

كذلك `try db.registerAccess(to: Player.all())` يُبلّغ المنطقة بلا جلب — تحسين اختياري.

**`GRDBQuery` (`@Query`) — الإصدار 0.11.0 (2025-03-15):** ما زال مبنيّاً على `ObservableObject` وأغلفة الخصائص؛ **لا دعم لإطار `Observation`** في توثيق فرع `main` الذي جلبته. والافتراضي أن الجلب **متزامن** (يحجب خيط الواجهة عند أول جلب) ما لم تمرّر `.async`. وقيده الصلب حرفياً: «Changes in the `request` state have no effect» ما لم تستعمل `Binding` أو `Query(constant:)`.
https://raw.githubusercontent.com/groue/GRDBQuery/main/Sources/GRDBQuery/Documentation.docc/QueryableParameters.md

**تطبيق GRDB التجريبي الوحيد الباقي** هو `Documentation/DemoApps/GRDBDemo` (اختفى `GRDBCombineDemo` و`GRDBAsyncDemo`)، ونموذجه `PlayerListModel` صنف `@Observable` يراقب القاعدة — لكنه **نمط القائمة الصغيرة فقط. لا يوجد مثال ترقيم رسمي في GRDB إطلاقاً.**

مشكلات GRDB ذات صلة مباشرة:
- **#1647** «Long write operation locks reads in ValueObservation» (2024-10-01، مغلقة): مع `DatabasePool` وعدد قرّاء محدود، كتابة طويلة تحجب قارئاً إضافياً بلا حدّ. https://github.com/groue/GRDB.swift/issues/1647
- **#1790** حول `cache_size` المنخفض على iOS (2025-07-10) — انظر §5.7.
- GRDB **7.9.0** (2025-12-13) أصلح «task cancellation issues with FTS5 full-text search». نحن على 6.24 ولا يشملنا الإصلاح.

**لم أجد** أي مشكلة أو نقاش في GRDB يخصّ تحديداً 20–50 ألف صفّ. نقاشات GitHub غير متاحة عبر واجهة البحث بلا مصادقة.

**الخلاصة لنا:** الترقيم اليدوي بـ keyset (`CatalogPager` في §6) هو الخيار الصحيح والموثَّق، لا `ValueObservation`. وهذا يطابق ما بُني في `CatalogDB` أصلاً.

### 5.2 `@Observable` مقابل `ObservableObject` — لا تهاجر، لن ينفعك

WWDC23 جلسة 10149 «Discover Observation in SwiftUI» تَعِد بدقّة على مستوى الحقل، وتذكر المصفوفات صراحةً: «you can use arrays, optionals, or… any type that contains your observable models».
https://developer.apple.com/videos/play/wwdc2023/10149/

لكن **WWDC25 جلسة 306 «Optimize SwiftUI performance with Instruments»** (يونيو 2025) عرضها بالضبط كخطأ، حرفياً:

> «Because each view accessed the favorites array, even though it was indirectly, the `@Observable` macro has created a dependency for each view on the **whole array** of favorites.»
> والحل المقترح: «Create granular data dependencies using Observable view models **per landmark** instead of depending on the entire array.»

https://developer.apple.com/videos/play/wwdc2025/306/

**المعنى المباشر لنا:** طالما أن النموذج يعرض `var movies: [Movie]` وتقرأ الواجهة المصفوفة، فإن الترحيل من `ObservableObject` إلى `@Observable` **لا يمنح دقّة على مستوى العنصر**؛ كل إلحاق صفحة سيُبطل كل مستهلك للمصفوفة، تماماً كاليوم. الدقّة الحقيقية تتطلّب أن يكون كل صفّ نوعاً مرجعياً `@Observable` مستقلاً، أو أن يستقبل عرض الصفّ **قيمة** لا المصفوفة — وهو ما نفعله بالفعل (`ChannelRow(channel:index:isFav:…)` يستقبل قيماً، `ContentViews.swift:566-574`).

**الحكم: ترحيل الـ VM إلى `@Observable` عمل بلا مكسب في هذه الحالة. أرجئه.** (الجلسة نفسها تحذّر أيضاً من تخزين قيم سريعة التغيّر — هندسة أو مؤقّتات — في `Environment`، لأن قراءة `@Environment` تُنشئ تبعية على `EnvironmentValues` كاملة. نحن نضع `s8kMetrics` هناك وهي مستقرّة — سليم.)

`Observations` (تسلسل غير متزامن للتغييرات المعامَلاتية) متاح **iOS 26.0+ فقط** — خارج نطاقنا (`Podfile:2` يستهدف iOS 17). https://developer.apple.com/documentation/observation/observations

### 5.3 `List` مقابل `LazyVStack` — ولماذا نافذتنا صحيحة

**WWDC23 جلسة 10160 «Demystify SwiftUI performance»**، حرفياً:

> «List and Table use identifiers to know what changes occurred to the data. **For consistency, all the IDs of List and Table are gathered eagerly.**»
> «**You need to ensure the number of views per element is a constant**, or SwiftUI has to build the views in addition to the identifiers.»

https://developer.apple.com/videos/play/wwdc2023/10160/

**هذه أقوى حجّة في التقرير على أن النافذة صحيحة:** لو سلّمنا `List` خمسين ألف صفّ لجمع **كل** المعرّفات فوراً. النافذة تجعل الرقم 120.

Apple نفسها في «Creating Performant Scrollable Stacks»:
> «Lazy stacks trade some degree of layout correctness for performance… always start with a standard stack view and only switch to a lazy stack if profiling your code shows a worthwhile performance improvement.»
> «**Never profile your code using the iOS simulator. Always use real devices.**»

https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks

**fatbobman, «List or LazyVStack» (2024-07-10)** — https://fatbobman.com/en/posts/list-or-lazyvstack/
- `List` مدعوم بـ `UICollectionView` منذ iOS 16؛ `LazyVStack` سويفت-يوآي خالص **بلا إعادة استعمال خلايا**.
- «with the same amount of data, `List` typically demonstrates higher efficiency than `LazyVStack`».
- في القفز السريع: `List` يختار الأعراض اللازمة فقط، بينما `LazyVStack` «requires instantiating and calculating the height of all subviews prior to that position»، ومع تفاوت الارتفاعات «may cause a white screen phenomenon».
- ⚠️ المقال **بلا أرقام قياس**.

**fatbobman, «Tips and Considerations for Using Lazy Containers» (2024-03-14)** — https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/
- **`.id()` على صفّ داخل `ForEach` يقتل الكسل**: «As a result, the List instantiates all the child views immediately.»
- **`if`/`switch` في أعلى جسم الصفّ يكسر الكسل** (`_ConditionalContent`). الحل تغليفه بحاوية تخطيط حقيقية (`VStack`) — و`Group` **لا يكفي**.
- الذاكرة لا تُستردّ إذا احتفظ الصفّ بـ `UIImage` في حالته؛ خزّنها `Optional<Data>` لتُستردّ عند `nil`.

**fatbobman, «Demystifying SwiftUI List Responsiveness» (2022-04-19)** — أرقام حقيقية على **40,000 سجلّ Core Data**: مع `.id(item.objectID)` على الصفّ ← تأخير يتجاوز الثانية عند الدخول و**إنشاء 40,000 صفّ**؛ بدونه ← بلا تأخير و**10–20 صفّاً فقط**.
https://fatbobman.com/en/posts/optimize_the_response_efficiency_of_list/

**خطأ Apple مفتوح ذو صلة:** feedback-assistant/reports **#651** (فُتح 2025-05-01، **ما زال مفتوحاً**): تمرير `List` بأكثر من 1000 عنصر يصبح «very janky and jumpy» عند عكس الاتجاه بعد تمرير سريع. https://github.com/feedback-assistant/reports/issues/651

**الحكم لنا:** لا تستبدل `LazyVGrid`/`LazyVStack` بـ `List`. شبكة الملصقات تحتاج شبكة، والنافذة تحلّ ما كان `List` سيحلّه. **ولا تضع `.id()` على أي صفّ داخل `ForEach`** — انظر التحفّظ المضاف على الكود في §6 المرحلة 1-ج.

> **ملاحظة:** لا توجد جلسة WWDC باسم «Explore SwiftUI performance». جلستا الأداء هما 10160 (2023) و306 (2025).

### 5.4 الترقيم والجلب المسبق — واجهات iOS 17/18 المؤكَّدة

| الواجهة | التوفّر | ملاحظة |
|---|---|---|
| `scrollTargetBehavior(_:)` | **iOS 17.0+** | التقاط (snap)، **وليس** ترقيم بيانات |
| `scrollTargetLayout(isEnabled:)` | iOS 17.0+ | شرط لعمل `scrollPosition(id:)` |
| `scrollPosition(id:anchor:)` | **iOS 17.0+** | آلية منع القفزة — انظر §5.5 |
| `defaultScrollAnchor(_:)` | iOS 17.0+ | يتحكّم بسلوك تغيّر حجم المحتوى |
| `onScrollGeometryChange(for:of:action:)` | **iOS 18.0+** | مشغّل «اقتربنا من النهاية» الحديث |
| `onScrollVisibilityChange(threshold:_:)` | **iOS 18.0+** | مشغّل تحميل صور الصفّ |
| `onScrollTargetVisibilityChange(idType:…)` | iOS 18.0+ | مجموعة المعرّفات المرئية → نافذة جلب مسبق |
| `ScrollPosition` (النوع) | iOS 18.0+ | يضيف `isPositionedByUser` |

كلام Apple على `onScrollGeometryChange`، حرفياً:
> «The geometry of a scroll view changes frequently while scrolling. **You should avoid updating large parts of your app whenever the scroll geometry changes.** To aid in this, you provide two closures: transform … action …»
> ⚠️ «If multiple scroll views are found within the view hierarchy, **only the first one** will invoke the closure you provide and a runtime issue will be logged.»

https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)

هذا هو بديل 2025 لـ «`onAppear` على الصفّ رقم N من النهاية»: تُختزل `ScrollGeometry` إلى `Bool` واحد (مثل `contentOffset.y > contentSize.height - containerSize.height * 2`) فيُطلق الفعل مرّة عند عبور العتبة لا في كل إطار، لأن `T: Equatable`.

`onScrollVisibilityChange(threshold:)` هو المشغّل الصحيح لتحميل/إيقاف الملصقات — أدقّ من `onAppear`/`onDisappear` اللذين يتبعان بناء العرض لا رؤيته فعلياً.
https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:)

**تحذير خاص بمشروعنا:** `reportsScrollToTabBar` (`DesignSystem.swift:2171-2183`) يستعمل `onScrollGeometryChange` بالفعل على `ScrollView` كل صفحة. تحذير Apple أعلاه («أول `ScrollView` فقط») يعني أن إضافة مشغّل ترقيم ثانٍ بالطريقة نفسها **على عرض متداخل** قد يلتقط الـ `ScrollView` الخارجي نفسه ويُسجَّل تحذير زمن تشغيل. لهذا السبب تحديداً بقي مشغّل الترقيم في §6 قائماً على الخفير (sentinel) لا على `onScrollGeometryChange`.

### 5.5 الهويّة المستقرّة ومنع قفزة التمرير — أهمّ اقتباس في القسم

من توثيق `scrollPosition(id:anchor:)`، حرفياً:

> «SwiftUI will attempt to keep the view with the identity specified in the provided binding visible when events occur that might cause it to be scrolled out of view by the system, including:
> — **The data backing the content of a scroll view is re-ordered**
> — The size of the scroll view changes…
> — The scroll view initially lays out its content defaulting to the top-most view, but the binding has a different view's identity»

https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)

```swift
ScrollView {
    LazyVStack { ForEach(items) { ItemView($0) } }
        .scrollTargetLayout()
}
.scrollPosition(id: $scrolledID)
```

**هذه هي الآلية المعتمَدة رسمياً ضد القفزة، وتعمل من iOS 17.** وعلى iOS 18 يحلّ محلّها نوع `ScrollPosition` مع `isPositionedByUser` (لكبح التصحيح البرمجي أثناء سحب المستخدم).
https://developer.apple.com/documentation/swiftui/scrollposition

**لكن انتبه لصياغة Apple:** الضمان مذكور لإعادة **الترتيب** وتغيّر الحجم. ترقيمنا **يُلحق بالذيل** ولا يعيد ترتيب شيء، فلا يُتوقّع قفز أصلاً. لذلك: **لا تُضِف `scrollPosition(id:)` في المرحلة 1.** أضفها فقط إن أظهر اختبار جهاز قفزة فعلية — وحينها هي الأداة الصحيحة، لا حلّ ملفّق.

**لم أجد** أي تقرير خطأ من Apple يقول صراحةً «تغيير هويّة المصفوفة يصفّر إزاحة التمرير». أقرب ما وُجد هو #651 أعلاه، و#806 (مغلقة 2026-06-16: نقر شريط الحالة للصعود لا يحدّث ربط `scrollPosition` على iOS 18). لذا فإن ما وثّقه التزامنا `d4fe249` عن انهيار التمرير يبقى **ملاحظة ميدانية داخلية**، وليست له وثيقة خارجية مطابقة — وهذا سبب إضافي لعدم العبث بها.

### 5.6 ماذا تفعل التطبيقات الحقيقية ذات الفهارس الضخمة

| المستودع | النجوم | الصلة |
|---|---|---|
| [signalapp/Signal-iOS](https://github.com/signalapp/Signal-iOS) | — | **GRDB في الإنتاج على أضخم نطاق رسائل على iOS.** مؤكَّد من `Podfile`: `pod 'GRDB.swift/SQLCipher'`. |
| [kushalpandya/Petrichor](https://github.com/kushalpandya/Petrichor) | 1,571 | **أقرب نظير وجدته لحالتنا.** مشغّل موسيقى SwiftUI/macOS: «Tracks searching is handled by SQLite FTS5»، جدول `tracks_fts` مخصّص، GRDB. مشكلاته الحقيقية على المكتبات الكبيرة: [#273](https://github.com/kushalpandya/Petrichor/issues/273) انهيار عند تحميل مجلد كبير («crashes after reaching 1144 songs» على مكتبة ~15,000)، [#233](https://github.com/kushalpandya/Petrichor/pull/233) «~50% faster scan» عبر **حجم دفعة تكيّفي**، [#269](https://github.com/kushalpandya/Petrichor/pull/269) إعادة كتابة `EntityGridView` للذاكرة + مخبأ أعمال فنية مشترك، [#243](https://github.com/kushalpandya/Petrichor/pull/243) تحسين تمرير الشريط الجانبي. |
| [pointfreeco/sqlite-data](https://github.com/pointfreeco/sqlite-data) | 1,869 | نشط (آخر دفع 2026-07-28). طبقة `@FetchAll`/`@FetchOne`/`@Fetch` فوق GRDB، **وواعية بإطار `Observation`** بخلاف GRDBQuery. أسرع من فكّ ترميز `Codable`. |
| [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) | 10,238 | SQLite عبر FMDB لا GRDB؛ عشرات آلاف المقالات، وحدات `ArticlesDatabase`/`SearchTable`. لم أستطع استخراج مخطط FTS منه. |
| [IceCubesApp](https://github.com/Dimillian/IceCubesApp) | 7,031 | مرقَّم شبكياً لا من SQLite، لكنه **كتالوج ممتاز لأعطال تجربة الترقيم**: PR #2297 تحميل ثنائي الاتجاه، PR #2389 تحميل تلقائي حين تُزيل المرشِّحات كل المرئي، والعطل المفتوح #2339 «Timeline skips». |

**نتيجة سلبية صادقة: لم أجد أي تطبيق IPTV مفتوح المصدر على iOS يرقّم من SQLite على نطاق 50 ألفاً.** بحث المستودعات عن `iptv + ios + swift` يعيد مجمّعات قوائم و«awesome lists» فقط. بحث الكود على GitHub يتطلّب مصادقة (401).

### 5.7 FTS5 — ما نفعله صح، وما يمكن تحسينه

من `https://sqlite.org/fts5.html` حرفياً:

- **فهارس البادئات:** `CREATE VIRTUAL TABLE ft USING fts5(a, b, prefix='2 3');`
- **`remove_diacritics`:** `"0"` يُبقيها، `"1"` **الافتراضي** يزيلها من اللاتينية «except combined diacritics»، `"2"` = «Diacritics correctly removed from all Latin characters».
  → **`remove_diacritics 2` عندنا (`CatalogDB.swift:128`) هو الخيار الصحيح، لا الافتراضي.** ✔
- **خيارات المحتوى:** `content=''` (بلا محتوى) أو `content='t1', content_rowid='a'` (محتوى خارجي).
- **الترتيب:** `ORDER BY bm25(email, 10.0, 5.0)` — أوزان حقيقية لكل عمود بترتيب الأعمدة.
- **حجم الفهرس:** `columnsize=0` يحذف عدّادات الرموز لكل عمود؛ `detail=column` يُسقط الإزاحات (**يعطّل NEAR والعبارات**)، و`detail=none` يبقي rowid فقط (**يعطّل ترشيح الأعمدة وNEAR**).

**التوصية المشتقّة لفهرسنا:** `prefix='2 3'` + `columnsize=0` تعطي بادئات الحرفين والثلاثة — أي بالضبط ما يُكتب أثناء الطباعة — قفزة فهرس بدل مسح بادئة. أمّا `detail=none` فلا تتخذها إلا إن قبلنا فقدان بحث العبارات. وتخزين `plot` كاملاً في FTS هو سبب الـ ~192,000 عبارة في الاستيراد؛ المحتوى الخارجي يزيله لأن `*ByIds` تجلب النص من الجداول الأصلية أصلاً.

**غلاف GRDB لـ FTS5** — https://raw.githubusercontent.com/groue/GRDB.swift/master/Documentation/FullTextSearch.md

يوفّر بنّائي أنماط آمنة **لا ترمي استثناءً** على مدخلات المستخدم:

```swift
FTS5Pattern(matchingAllPrefixesIn: query)   // ← نمط البحث أثناء الطباعة
FTS5Pattern(matchingAnyTokenIn: query)
FTS5Pattern(matchingAllTokensIn: query)
FTS5Pattern(matchingPhrase: query)
```

`ftsQuery` عندنا (`CatalogDB.swift:180-186`) يعيد اختراع `matchingAllPrefixesIn` يدوياً. تنفيذنا صحيح (الشقّ على `alphanumerics.inverted` يزيل كل محارف FTS5 الخاصّة فلا حقن)، لكن استبداله بالبنّاء الرسمي يقلّص السطح ويستفيد من إصلاحات المكتبة تلقائياً. تغيير اختياري، منخفض المخاطرة.

**عن الـ debounce — كن صادقاً:** لم أجد **أي** مصدر مؤرَّخ وموثوق يصف قيمة بالمللي ثانية. توجيه Apple كيفيّ فقط، حرفياً: «If the cost is high… **consider prefetching and caching data or reducing the frequency of updates**. Alternatively, you can wait until someone submits the query.» (https://developer.apple.com/documentation/swiftui/performing-a-search-operation). والواجهة الرسمية هي `AsyncSequence.debounce(for:tolerance:)` من `apple/swift-async-algorithms`. قيمنا الحالية (220 و350 مللي ثانية) **اجتهاد لا مرجع له** — عايِرها على جهاز ولا تستشهد بـ«300 مللي ثانية معيار» من أحد.

> مفارقة تستحق الذكر: مثال Apple نفسه في «Adding a search interface» هو `products.filter { $0.name.lowercased().contains(searchText.lowercased()) }` — أي بالضبط النمط `O(n)` لكل ضغطة الذي يجب ألا يُستعمل على 50 ألفاً. توثيق Apple هنا ليس مرجع أداء.

### 5.8 SQLite على iOS: WAL، وPool مقابل Queue، وضبط PRAGMA

موقف GRDB الرسمي (`DatabaseConnections.md`, `Concurrency.md`):

- «**If you are not sure, choose `DatabaseQueue`.**» ويمكن التحوّل إلى `DatabasePool` لاحقاً بلا قيود.
- `DatabasePool`: «Unless `Configuration.readonly`, the database is set to the **WAL mode**», ما «makes it possible for reads and writes to proceed concurrently». المعمارية: كاتب واحد على طابور تسلسلي + N قارئاً للقراءة فقط. «**writes are still serialized**».
- «Reads are generally non-blocking, unless the maximum number of concurrent reads has been reached.»
- `DatabaseQueue` يدعم قواعد في الذاكرة؛ `DatabasePool` لا.

القيم الافتراضية الفعلية (من `GRDB/Core/Configuration.swift`):

```swift
public var maximumReaderCount: Int = 5
public var busyMode: Database.BusyMode = .immediateError
public var journalMode = JournalModeConfiguration.default   // Pool يضبط WAL
public mutating func prepareDatabase(_ setup: @escaping @Sendable (Database) throws -> Void)
```

**نتيجة سلبية مؤكَّدة: `Configuration.swift` لا يذكر `cache_size` ولا `mmap_size` ولا `temp_store` ولا `synchronous` إطلاقاً. GRDB لا يضبطها لك.**

المشكلة **#1790** (2025-07-10) تفيد أن حجم مخبأ الصفحات الافتراضي **على iOS ≈ 512 كيلوبايت مقابل ≈ 8 ميغابايت على macOS**، وتقترح:

```sql
PRAGMA journal_mode = WAL;
PRAGMA cache_size  = -32768;   -- 32 م.ب (القيمة السالبة = كيبيبايت)
PRAGMA temp_store  = MEMORY;
```

⚠️ **تحفّظ صريح:** هذه اقتراحات **المُبلِّغ**، لا توصية رسمية من GRDB؛ لم يظهر تأييد صيانة في الصفحة المجلوبة. تعامل معها كخيط قوي **للقياس**، لا كحقيقة. وانتبه: 32 م.ب لكل اتصال قارئ × 5 قرّاء = 160 م.ب مخبأ محتمل — حدّد الرقم بوعي.

وقيد مهم على خطّتنا: المشكلة **#1647** تُظهر أن كتابة طويلة مع `DatabasePool` قد تُجوّع قارئاً إضافياً بعد استنفاد `maximumReaderCount`. الاستيراد عندنا **هو** الكتابة الطويلة. فالانتقال إلى `DatabasePool` (§6 المرحلة 0-ج) يحسّن الوضع كثيراً لكنه **لا يجعله مثالياً** — والحلّ الجذري هو تقسيم الاستيراد إلى دفعات معامَلاتية (وهو بالضبط ما فعله Petrichor في PR #233 بـ«adaptive batch sizing»).

### 5.9 خلاصة البحث — تسع نقاط قابلة للتنفيذ

1. **لا تسلّم SwiftUI خمسين ألف صفّ.** `List`/`Table` تجمعان كل المعرّفات فوراً (WWDC23 10160). نافذتنا صحيحة.
2. **لا تُبنَ الترقيم على `ValueObservation`.** مؤشّر متغيّر ليس منطقة ثابتة. استعمل `DatabaseRegionObservation` للإبطال فقط.
3. **`DatabasePool` + WAL**، مع الوعي بـ #1647 وبضرورة تقسيم الاستيراد إلى دفعات.
4. **`.scrollPosition(id:)` + `.scrollTargetLayout()`** هي أداة منع القفزة الرسمية (iOS 17+) — احتفظ بها كخطّة طوارئ، لا كإضافة استباقية.
5. **`onScrollGeometryChange`** (iOS 18) للمشغّل، و**`onScrollVisibilityChange`** لتحميل الصور — مع الانتباه لقيد «أول ScrollView فقط» الذي يصطدم بـ `reportsScrollToTabBar` عندنا.
6. **`List` أفضل من `LazyVStack` للقوائم الرأسية الطويلة** — لكن ليس لشبكة ملصقات، فابقَ على `LazyVGrid`.
7. **لا `.id()` على صفّ داخل `ForEach`، ولا `if`/`switch` عارٍ في أعلى جسم الصفّ.**
8. **FTS5:** `prefix='2 3'`، و`remove_diacritics 2` (عندنا ✔)، وأوزان `bm25()` تفضّل الاسم، و`FTS5Pattern(matchingAllPrefixesIn:)`.
9. **`@Observable` لن ينقذك** ما دام النموذج يعرض مصفوفة — عرض WWDC25 306 كامله هو هذا الخطأ بعينه.

### 5.10 ما لم يُتحقَّق منه (يجب ذكره)

- **WebSearch غير متاح** (الحصّة مستنفدة) — لا اكتشاف بكلمات مفتاحية، جلب مباشر فقط.
- **`gh` غير مثبَّت** → بحث كود GitHub ونقاشاته غير متاحين (401). **لا نقاش GRDB عن عشرات الآلاف من الصفوف عُثر عليه — وغيابه هنا ليس دليل عدم وجوده.**
- **لا مثال ترقيم رسمي في GRDB.** وصفة §6 مركَّبة من أوّليات، لا منقولة.
- **لا تقرير خطأ معترَف به من Apple** يربط تغيّر هويّة المصفوفة بتصفير إزاحة التمرير.
- **لا قيمة debounce موثَّقة.** لا تستشهد بـ«300 مللي ثانية».
- مقال fatbobman عن List/LazyVStack **بلا أرقام**؛ الأرقام الوحيدة الصلبة هي قياس 40,000 صفّ Core Data من مقال 2022-04-19.
- تعذّر جلب: توثيق `task(id:priority:_:)` (404)، وصفحات Swift Package Index (403)، ومنتديات Apple (JS).

---

## 6. خطة الترحيل إلى قراءات SQLite مرقَّمة

### 6.1 المبدأ الحاكم — قُلها بصراحة قبل أي كود

**الترقيم وحده لا يوفّر بايتاً واحداً ما دام `MoviesVM.movies` موجوداً.**
الذاكرة لا تنخفض إلا عندما تتوقّف الـ VM عن الاحتفاظ بالمصفوفات كاملة، وذلك يتطلّب أن تأتي الأقسام والعدّادات والرفوف التحريرية من SQL أيضاً. لذلك الترتيب أدناه **ليس** «ابدأ بالترقيم» — بل «اقطف المكاسب المجانية أولاً، ثم ابنِ الترقيم، ثم اسحب المصفوفات من تحته».

كل مرحلة تُشحن وحدها وتُرجَع وحدها.

---

### المرحلة 0 — مكاسب مجانية، لا علاقة لها بـ SQLite (اشحنها أولاً)

#### 0-أ · فرز الفهارس لا العناصر — **الأعلى أثراً في التقرير كلّه**

الأثر: يزيل ~1.5 مليون تحليل سلسلة و~42 م.ب تخصيص عابر من الـ main actor في كل تحميل.
المخاطرة: شبه معدومة — نسخة حرفية من علاج مُثبت في `HomeVM.rebuildHero`.

**استبدل `ContentViews.swift:870-875` كاملةً بـ:**

```swift
    // Editorial rows: Top-10 by rating + a newest-movies hero.
    //
    // SORT INDICES, NOT ELEMENTS — the same fix HomeVM.rebuildHero already carries
    // (HomeView.swift:78-90) and that this function was left out of. `movies.sorted { … }`
    // moved a ~424-byte struct with 14 refcounted String fields on every swap AND
    // re-parsed `rating` / `id` out of a String on EVERY comparison, twice per compare,
    // ~n·log n compares. On a 25k-title line that is ~1.5M string parses and four
    // full-catalogue arrays, on the MAIN ACTOR, at the end of every load — to produce
    // ten items and six. Each key is parsed ONCE here, only Ints move during the sort,
    // and `.prefix(n)` materialises tens of structs instead of tens of thousands.
    // The prefix headroom absorbs the duplicate ids that `s8kUniqueByID` then removes.
    private func rebuildEditorial() {
        let rate = movies.map(\.ratingDouble)
        let byRate: [Int] = movies.indices.sorted { rate[$0] > rate[$1] }
        topRanked = Array(s8kUniqueByID(byRate.prefix(40).map { movies[$0] }, { $0.id }).prefix(10))

        let ids = movies.map { Int($0.id) ?? 0 }
        let byID: [Int] = movies.indices.sorted { ids[$0] > ids[$1] }
        let newest = s8kUniqueByID(byID.prefix(24).map { movies[$0] }, { $0.id })
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .movie($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }
```

**واستبدل `ContentViews.swift:2092-2097` كاملةً بـ:**

```swift
    // Editorial rows for series — see the note on MoviesVM.rebuildEditorial. `Series`
    // has no `ratingDouble` helper, so the key is parsed once with `s8kRating`, which
    // is already NaN-safe (a NaN in a `>` comparator traps `sorted` at runtime).
    private func rebuildEditorial() {
        let rate = series.map { s8kRating($0.rating) }
        let byRate: [Int] = series.indices.sorted { rate[$0] > rate[$1] }
        topRanked = Array(s8kUniqueByID(byRate.prefix(40).map { series[$0] }, { $0.id }).prefix(10))

        let ids = series.map { Int($0.id) ?? 0 }
        let byID: [Int] = series.indices.sorted { ids[$0] > ids[$1] }
        let newest = s8kUniqueByID(byID.prefix(24).map { series[$0] }, { $0.id })
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .series($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }
```

ملاحظات صحّة (كلاهما فُحص قبل الكتابة):
- `movies.indices` هو `Range<Int>`، و`.sorted(by:)` عليه يُعيد `[Int]`. ✔
- `byRate.prefix(40)` هو `ArraySlice<Int>`، و`.map { movies[$0] }` يُعيد `[Movie]`. ✔
- `s8kUniqueByID<T>(_ items: [T], _ id: (T) -> String) -> [T]` (`HomeView.swift:14-17`) — التوقيع مطابق. ✔
- `Movie.ratingDouble` (`Models.swift:246`) و `s8kRating` (`HomeView.swift:20-23`) كلاهما يحرس `isFinite` — لا انهيار strict-weak-ordering. ✔
- تغيّر سلوكي وحيد ومقصود: إزالة التكرار تجري الآن على أفضل 40 / أحدث 24 بدل الفهرس كاملاً — مطابق حرفياً لما يفعله `HomeVM` (`HomeView.swift:90`, `94`). لا فرق مرئي ما لم يوجد أكثر من 30 معرّفاً مكرَّراً داخل الأربعين الأوائل.

#### 0-ب · debounce + حفظ لشاشتَي القسم

الأثر: يزيل مسح ICU لكل إطار أثناء الطباعة داخل قسم.
المخاطرة: منخفضة جداً.

في `MoviePosterScreen` (`ContentViews.swift:2020-2046`) وبالمثل في `ChannelListScreen` (`797-823`) و`SeriesPosterScreen`:

```swift
    @State private var search  = ""
    /// The query the grid actually filters by. `search` drives the field; this trails it
    /// by one debounce. `shown` is read from `body`, so filtering on `search` directly
    /// ran a full ICU `folding` sweep of the category on EVERY frame, not every keystroke.
    @State private var applied = ""

    private var shown: [Movie] { s8kFolderSearch(movies, applied) { $0.name } }
```

وأضف على الـ `ZStack` في `body`:

```swift
        // `.task(id:)` cancels the previous run on each change — a clean debounce with
        // no Task bookkeeping. An empty query applies instantly (clearing must feel free).
        .task(id: search) {
            if search.isEmpty { applied = ""; return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            applied = search
        }
```

هذا لا يزيل إعادة الحساب لكل إطار كلياً (ما زالت `shown` محسوبة)، لكنه يقصرها على الإطارات التي تلي تغيّر `applied` فعلياً بدل كل ضغطة وكل إطار. الإزالة الكاملة تأتي في المرحلة 2 حين يصبح البحث داخل القسم استعلام FTS محدوداً بـ `categoryID`.

#### 0-ج · `DatabaseQueue` → `DatabasePool`

الأثر: القراءات (بحث FTS + ThumbHash) تتوقّف عن الانحجاز خلف معاملة الاستيراد الواحدة ذات الـ ~192,000 عبارة — وهي مشكلة موثَّقة في هذا المستودع نصّاً (`DesignSystem.swift:1571-1576`).
المخاطرة: متوسطة — يحوّل الملف إلى WAL. يحتاج اختبار جهاز.

في `CatalogDB.swift:28-36`:

```swift
    // DatabasePool, not DatabaseQueue: a queue serialises EVERYTHING, and the catalogue
    // import is one write transaction of ~192,000 statements. Behind a queue, every FTS
    // search and every ThumbHash lookup in the app waits out that whole import (see the
    // note in DesignSystem.swift:1571-1576). A pool runs SQLite in WAL mode, so readers
    // proceed against the last committed snapshot while the writer works. GRDB enables
    // WAL automatically when the pool opens the file; an existing rollback-journal
    // database is converted in place on first open.
    static let dbQueue: DatabasePool? = {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
            let q = try DatabasePool(path: dir.appendingPathComponent("catalog.sqlite").path)
            try migrator.migrate(q)
            return q
        } catch { print("CatalogDB init failed:", error); return nil }
    }()
```

الاسم `dbQueue` يبقى كما هو حتى لا يتغيّر أي موقع نداء. كل `q.read { … }` و`q.write { … }` في الملف يبقى صالحاً حرفياً — `DatabasePool` و`DatabaseQueue` يشتركان في `DatabaseReader`/`DatabaseWriter`.

**يجب اختباره على جهاز:** أول إقلاع على قاعدة موجودة (تحويل WAL)، ثم إجبار إعادة تحميل الفهرس والبحث أثناء جريان الاستيراد، ثم إنهاء التطبيق قسراً أثناء الاستيراد والتأكّد من عدم تلف الملف (ملفّا `-wal` و`-shm` سيظهران بجانب `catalog.sqlite`).

> **حدّ هذا الإصلاح، بصراحة (من §5.8).** `DatabasePool` يجعل الكتابات ما زالت **متسلسلة** ويحدّد القرّاء المتزامنين بـ `maximumReaderCount = 5` افتراضياً. ومشكلة GRDB **#1647** (2024-10-01) توثّق أن كتابة طويلة يمكن أن تُجوّع قارئاً إضافياً بعد استنفاد العدد. الاستيراد عندنا **هو** الكتابة الطويلة (~192,000 عبارة في معاملة واحدة). فالانتقال يحسّن الوضع كثيراً ولا يجعله مثالياً.
>
> **الحلّ الجذري المكمِّل — المرحلة 0-د:** تقسيم `CatalogDB.save` إلى دفعات معامَلاتية (مثلاً 2,000 صفّ لكل `q.write`) بدل معاملة واحدة عملاقة، فيحصل القرّاء على نوافذ بين الدفعات. هذا بالضبط ما فعله Petrichor في PR #233 («~50% faster scan» عبر حجم دفعة تكيّفي — §5.6). الثمن أن الفشل في المنتصف يترك الفهرس جزئياً، فيلزم إمّا كتابة `catalog_meta.savedAt` في النهاية فقط (وهو ما يفعله الكود اليوم أصلاً، `CatalogDB.swift:337-338` — فبوّابة الطزاجة تحمينا) أو حذف النطاق أولاً في دفعة منفصلة.

---

### المرحلة 1 — سقالة الترقيم + أول شاشة (**الكود الدقيق**)

الهدف: مسار قراءة مرقَّم حقيقي، يعمل، يُشحن وحده، ولا يغيّر سلوك أي شاشة أخرى.
ما لا يفعله بصراحة: **لا يوفّر ذاكرة** — `vm.movies` ما زالت موجودة. هذه سقالة وإثبات.

#### 1-أ · بوّابة جاهزية آمنة للـ main thread

قاعدة غير قابلة للتفاوض: **الواجهة لا تسأل قاعدة البيانات سؤالاً على الـ main thread**، لأن الاستيراد قد يحجزها لعشرات الثواني. `isPopulated` قراءة متزامنة، فلا يجوز استدعاؤها من `init` أي `View`.

**أضف إلى `CatalogDB.swift` قبل `// MARK: - FTS search`:**

```swift
    // MARK: - Readiness gate (main-thread safe)
    // A view must NEVER ask SQLite a question on the main thread: the catalogue import
    // is one write transaction of ~192,000 statements, and even with a DatabasePool a
    // cold page-in can take milliseconds the main thread does not have. The question
    // "can this scope be paged?" is answered ONCE per scope, off-main, and cached in
    // memory behind a lock. Everything else reads the cached answer for free.
    private static let readyLock = NSLock()
    nonisolated(unsafe) private static var readyScopes: Set<String> = []

    /// Free, main-thread-safe: is this scope known to be paged-readable right now?
    static func isReady(scope: String) -> Bool {
        readyLock.lock(); defer { readyLock.unlock() }
        return readyScopes.contains(scope)
    }
    static func markReady(scope: String) {
        readyLock.lock(); readyScopes.insert(scope); readyLock.unlock()
    }
    /// Account deletion / playlist switch — the next probe has to ask again.
    static func forgetReady() {
        readyLock.lock(); readyScopes.removeAll(); readyLock.unlock()
    }
    /// One-shot background probe. Idempotent and safe to call from anywhere, any number
    /// of times, including from the main actor — it never touches the database inline.
    /// Needed because `_load` returns early from the JSON disk cache (Core.swift:1806)
    /// WITHOUT writing SQLite, so a warm start would otherwise never learn that the
    /// store is populated from an earlier session.
    static func probeReady(scope: String) {
        if isReady(scope: scope) { return }
        Task.detached(priority: .utility) {
            if isPopulated(scope: scope) { markReady(scope: scope) }
        }
    }
```

**وفي `CatalogDB.save(_:scope:)`، بعد نجاح المعاملة** — أي بين `}` المغلقة لـ `try q.write { … }` وبين `} catch { … }` في `CatalogDB.swift:339-340`:

```swift
            }
            markReady(scope: scope)      // the store now definitively has this line
        } catch { print("CatalogDB save failed:", error) }
```

**وفي `CatalogDB.deleteEverything()`**، بعد كتلة `try? q.write { … }` (`CatalogDB.swift:301`):

```swift
        }
        forgetReady()
    }
```

**وفي `Core.swift`، داخل فرع مخبأ القرص في `_load`** — أضف سطراً واحداً بعد `content = cached.content` (`Core.swift:1807`):

```swift
            content = cached.content
            // The SQLite store is written only on a NETWORK parse (line 1854 / 1901), so a
            // warm start that is served from JSON never learns whether an earlier session
            // already populated it. Probe once, off-main; the paged readers consult the
            // cached answer and fall back to these in-memory arrays until it flips.
            CatalogDB.probeReady(scope: urlString)
```

#### 1-ب · مصدر بيانات مرقَّم عام

**ملف جديد `BlankTV/CatalogPaging.swift`** (يجب إضافته إلى `project.pbxproj` — انظر §8):

```swift
// ============================================================
// BLANK TV — CatalogPaging.swift
// A keyset-paged, SQLite-backed data source for ONE list. The view holds only the
// rows the user has actually scrolled past, at any catalogue size, because the
// covering indexes in CatalogDB (scope[,category],pos) make "the next 180 rows
// after cursor" the same cost at row 50 and at row 50,000.
//
// It degrades to a caller-supplied in-memory array whenever the store cannot serve
// this line — demo mode, no saved playlist scope, a first run where the import has
// not finished, or GRDB failing to open at all. In that case behaviour is IDENTICAL
// to today's, byte for byte, because the fallback IS today's array.
//
// Nothing here touches SQLite on the main actor.
// ============================================================

import Foundation

@MainActor
final class CatalogPager<Item: Identifiable & Sendable>: ObservableObject {
    /// Rows loaded so far, in provider order (`pos` ascending). Only ever APPENDED —
    /// the head item never changes, which is what keeps the list windows in
    /// ContentViews from resetting and throwing the scroll position (see the
    /// `.onChange(of: movies.first?.id)` note there, and commit d4fe249).
    @Published private(set) var items: [Item] = []
    /// A page fetch is in flight. Doubles as the re-entrancy guard — it is read and
    /// written only on the main actor, so the check and the set are one step.
    @Published private(set) var loading = false
    /// The store said there is nothing after the last cursor.
    @Published private(set) var reachedEnd = false

    private let pageSize: Int
    private let usesStore: Bool
    private let page: @Sendable (_ after: Int?, _ limit: Int) -> (items: [Item], nextCursor: Int?)
    private var cursor: Int? = nil
    private var started = false

    /// - Parameters:
    ///   - usesStore: resolved by the caller from `CatalogDB.isReady(scope:)`, which is a
    ///     free in-memory read. Never pass a value obtained by querying SQLite on main.
    ///   - fallback: what to show when `usesStore` is false. Shown immediately and never
    ///     replaced, so the user can never see the list swap under their finger.
    init(pageSize: Int = S8KListWindow.step,
         usesStore: Bool,
         fallback: [Item],
         page: @escaping @Sendable (_ after: Int?, _ limit: Int) -> (items: [Item], nextCursor: Int?)) {
        self.pageSize  = pageSize
        self.usesStore = usesStore
        self.page      = page
        if !usesStore {
            items = fallback
            reachedEnd = true
        }
    }

    /// First page. Idempotent — safe to call from `.task` / `.onAppear`.
    func start() {
        guard usesStore, !started else { return }
        started = true
        loadNext()
    }

    /// Next page. Called by the list's end sentinel; a no-op while one is in flight.
    func loadNext() {
        guard usesStore, !loading, !reachedEnd else { return }
        loading = true
        let after = cursor, limit = pageSize, fetch = page
        Task { [weak self] in
            // GRDB reads are synchronous; they run on a detached task so a page fetch
            // can never sit on the main thread behind a running import.
            let r = await Task.detached(priority: .userInitiated) { fetch(after, limit) }.value
            guard let self else { return }
            self.items.append(contentsOf: r.items)
            self.cursor = r.nextCursor
            self.reachedEnd = (r.nextCursor == nil)
            self.loading = false
        }
    }
}

extension CatalogPager where Item == Movie {
    /// Movies in one provider category (nil = the whole line), paged from SQLite.
    static func movies(category: String?, fallback: [Movie]) -> CatalogPager<Movie> {
        let scope = Store.shared.demoMode ? nil : Store.shared.m3uURL
        let ok = scope.map { CatalogDB.isReady(scope: $0) } ?? false
        return CatalogPager<Movie>(usesStore: ok, fallback: fallback) { after, limit in
            guard let s = scope else { return ([], nil) }
            return CatalogDB.pageMovies(scope: s, category: category, after: after, limit: limit)
        }
    }
}

extension CatalogPager where Item == Channel {
    /// Channels in one provider group (nil = the whole line), paged from SQLite.
    /// NOTE the asymmetry, and it is not a mistake: `CatalogDB.pageChannels` filters on
    /// `groupTitle`, because a Channel carries its category NAME, not its id — exactly
    /// what `LiveTVVM.list(in:)` does with `grouped[cat.name]`.
    static func channels(group: String?, fallback: [Channel]) -> CatalogPager<Channel> {
        let scope = Store.shared.demoMode ? nil : Store.shared.m3uURL
        let ok = scope.map { CatalogDB.isReady(scope: $0) } ?? false
        return CatalogPager<Channel>(usesStore: ok, fallback: fallback) { after, limit in
            guard let s = scope else { return ([], nil) }
            return CatalogDB.pageChannels(scope: s, category: group, after: after, limit: limit)
        }
    }
}
```

#### 1-ج · خفير نهاية اختياري في `PosterGrid`

**في `ContentViews.swift:1942-1946`، أضف معاملاً واحداً — قبل `onSelect` وليس بعده**، حتى تبقى كل مواقع النداء الحالية بإغلاق زائل (trailing closure) صالحة كما هي:

```swift
struct PosterGrid: View {
    let movies: [Movie]
    var empty: String = L("grid.empty")
    /// Fired once the local window has caught up with everything the caller has loaded.
    /// Paged screens use it to ask the store for the next page. `nil` for every in-memory
    /// caller (favourites, history, Home rails), whose behaviour is therefore unchanged.
    var onReachEnd: (() -> Void)? = nil
    let onSelect: (Movie) -> Void
```

**واستبدل كتلة الخفير (`ContentViews.swift:1962-1966`) بـ:**

```swift
                    // Sentinel: reaching it means the user scrolled past the window.
                    if shown < movies.count {
                        Color.clear.frame(height: 1)
                            .onAppear { shown = min(shown + S8KListWindow.step, movies.count) }
                    } else if let onReachEnd {
                        // The window has consumed everything loaded — ask for more rows.
                        // `.id(movies.count)` is on this ONE-POINT SPACER only, so each
                        // landed page gives a fresh sentinel whose `onAppear` fires again
                        // (an `onAppear` fires once per view identity). This is NOT the
                        // banned pattern: the banned pattern was keying the WINDOW RESET
                        // on `count`, which collapsed the content height and threw the
                        // scroll position (commit d4fe249). Nothing here re-keys the
                        // ForEach, the window, or the container.
                        Color.clear.frame(height: 1)
                            .id(movies.count)
                            .onAppear(perform: onReachEnd)
                    }
```

لماذا يتصالح هذا مع النافذة القائمة: الصفحات تُلحق بالذيل، فـ `movies.first?.id` لا يتغيّر، فمعالج `.onChange` في `ContentViews.swift:1974` **لا يُطلق** والنافذة لا تُعاد. ثم يعود `shown < movies.count` صحيحاً فتنمو النافذة بخطواتها المعتادة. الحلقة ذاتية التصحيح: نافذة → خفير → صفحة → نافذة.

`pageSize` الافتراضي هو `S8KListWindow.step` (180) وهو **أكبر** من `S8KListWindow.initial` (120)، فالصفحة الأولى تملأ النافذة الأولى دائماً ولا يوجد وضع ارتجاف.

> ⚠️ **تحفّظ صريح على `.id(movies.count)` — أخذاً ببحث §5.3.**
> القاعدة الموثَّقة هي أن `.id()` **على صفّ داخل `ForEach`** يقتل كسل الحاوية ويجبرها على إنشاء كل الأبناء فوراً — مقيسة على 40,000 سجلّ: تأخير يتجاوز الثانية وإنشاء 40,000 عرض بدل 10–20 (fatbobman، 2022-04-19 و2024-03-14).
> الخفير هنا **ليس داخل `ForEach`**؛ هو شقيق مفرد للـ `ForEach` داخل `LazyVGrid`، ولا يحمل `.id()` أي صفّ. نظرياً لا ينطبق التحذير. عملياً هذا **الافتراض الوحيد غير المؤكَّد في المرحلة 1، ويجب أن يُختبر على جهاز** (انظر §8): افتح قسماً فيه >5,000 عنصر، ومرّر، وراقب ذاكرة العملية وعدّاد إنشاء الخلايا. إن ظهر إنشاء متلهّف، البديل الآمن بلا `.id()` هو ربط المشغّل بحالة بدل هوية العرض:
> ```swift
> } else if let onReachEnd {
>     Color.clear.frame(height: 1)
>         .onAppear(perform: onReachEnd)
>         .onChange(of: movies.count) { _, _ in onReachEnd() }   // بلا هوية جديدة
> }
> ```
> **ما يجب ألّا يُجرَّب إطلاقاً كبديل:** `onScrollGeometryChange` (وهو المشغّل «الحديث» لهذا الغرض في iOS 18) — لأن Apple تنصّ على أن أول `ScrollView` فقط في الشجرة ينفّذ الإغلاق ويُسجَّل تحذير زمن تشغيل لغيره، و`reportsScrollToTabBar` (`DesignSystem.swift:2171-2183`) يحتلّ ذلك الموقع بالفعل في كل صفحة.

#### 1-د · توصيل `MoviePosterScreen`

**استبدل `ContentViews.swift:2020-2030` بـ:**

```swift
struct MoviePosterScreen: View {
    @Environment(\.s8kMetrics) private var metrics
    let title: String
    /// Provider category id — the SQL filter for the paged read. nil = the whole line.
    let category: String?
    /// What to show when the SQLite store cannot serve this line (demo, first run, an
    /// import still in flight). Identical to today's behaviour in that case.
    let movies: [Movie]
    let onSelect: (Movie) -> Void
    @State private var search  = ""
    @State private var applied = ""
    @StateObject private var pager: CatalogPager<Movie>
    @Environment(\.dismiss) var dismiss

    init(title: String, category: String? = nil, movies: [Movie],
         onSelect: @escaping (Movie) -> Void) {
        self.title = title
        self.category = category
        self.movies = movies
        self.onSelect = onSelect
        _pager = StateObject(wrappedValue: CatalogPager.movies(category: category, fallback: movies))
    }

    /// Browsing reads the paged rows; searching still reads the in-memory array, because
    /// a folder search must cover the WHOLE folder, not just the pages loaded so far.
    /// Stage 3 replaces this branch with a category-scoped FTS query.
    private var shown: [Movie] {
        applied.isEmpty ? pager.items : s8kFolderSearch(movies, applied) { $0.name }
    }
```

**واستبدل `PosterGrid(movies: shown) { onSelect($0) }` (`ContentViews.swift:2039`) بـ:**

```swift
                    PosterGrid(movies: shown,
                               onReachEnd: applied.isEmpty ? { pager.loadNext() } : nil) { onSelect($0) }
```

**وأضف على الـ `ZStack` في `body`، بجوار `.navigationBarHidden(true)`:**

```swift
        .task { pager.start() }
        .task(id: search) {
            if search.isEmpty { applied = ""; return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            applied = search
        }
```

**وأخيراً موقع النداء — `ContentViews.swift:1647-1651` يصبح:**

```swift
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .movie, categoryID: cat.id) {
                    MoviePosterScreen(title: cat.name, category: cat.id,
                                      movies: vm.list(in: cat)) { selected = $0 }
                }
            }
```

`movies.count` في العنوان الفرعي (`ContentViews.swift:2036`) يبقى صحيحاً لأن المصفوفة ما زالت مُمرَّرة. عند المرحلة 4 يُستبدل بـ `CatalogDB.countMovies(scope:category:)` المكتوبة أصلاً وغير المستعملة.

#### 1-هـ · ما يثبته هذا وما لا يثبته

يثبت: keyset يعمل، الترتيب مطابق لترتيب المزوّد، الخفير لا يكسر النافذة، التدهور صامت وسليم، ولا قراءة SQLite على الـ main thread.
لا يثبت: أي توفير ذاكرة. صفر. `MoviesVM.movies` و`grouped` ما زالتا كاملتين.

---

### المرحلة 2 — بحث التبويبات إلى FTS5

الأثر: يزيل ~50,000 استدعاء `contains` لكل ضغطة مفتاح مثبَّتة، عبر ثلاثة VM، من الـ main actor.
المخاطرة: منخفضة — البنية منسوخة من `SearchVM.ftsResults` المُثبتة.

الشكل: يصبح `searchResults` قيمة `@Published` مخزّنة لا خاصيّة محسوبة، تُحدَّث من `.onChange(of: search)` بمهمّة مُدَبْدَبة تستدعي `CatalogDB.search(_:kind:scope:limit:)` ثم `*ByIds` داخل `Task.detached`، مع الإبقاء على `searchMatches()` الحالية كتدهور حين `!CatalogDB.isReady(scope:)` — حرفياً كما تفعل `SearchVM` اليوم (`ContentViews.swift:3234-3239`).

نظّف معها:
- أزل `debounce` المزدوج في مسار الرئيسية: إمّا اخفض `Task.sleep` في `SearchVM.search()` (`ContentViews.swift:3226`) إلى ~120 مللي ثانية لأن `commitSearch` دبدب 220 قبله (`DesignSystem.swift:2213`)، أو أزل أحدهما. اليوم الكلفة 570 مللي ثانية محسوسة.
- أضف debounce إلى حقلَي iPad (`ContentViews.swift:1697`, `260`) أو مرّرهما عبر `AppRouter.searchText` مثل iPhone.
- أضف `.onChange(of: vm.search) { _, _ in padShown = S8KListWindow.initial }` بجانب `ContentViews.swift:233`.

### المرحلة 3 — الأقسام والعدّادات وبحث القسم من SQL

الأثر: يحذف `grouped` — النسخة الكاملة الدائمة الثانية (≈13.7 م.ب) — من الـ VM الثلاثة.
المخاطرة: متوسطة. `folders` و`list(in:)` و`CategoryRow(count:)` و`CategorySidebar` كلها تعتمد عليها.

- `folderList` ← `CatalogDB.categories(scope:kind:)` + `movieCategoryCounts(scope:)` (كلاهما مكتوب وغير مستعمل).
- `list(in:)` تختفي: كل مستهلك يصبح `CatalogPager`.
- بحث داخل القسم ← استعلام FTS مقيَّد بالقسم. يحتاج إضافة عمود `categoryID` (UNINDEXED) إلى `catalog_fts` أو `JOIN` على جدول المصدر — والثاني أبسط ولا يحتاج ترحيلاً.
- `favorites` تصبح استعلاماً بمعرّفات المفضّلات لا مسحاً للفهرس.

### المرحلة 4 — التبويبات تتوقّف عن الاحتفاظ بالفهرس

الأثر: **هنا فقط** تسقط الذاكرة — من ≈31 م.ب دائمة (+ السلاسل) إلى حجم ما هو معروض فعلاً.
المخاطرة: الأعلى في الخطة. اشحنها وحدها وخلف مفتاح إيقاف.

- `MoviesVM.movies` / `SeriesVM.series` / `LiveTVVM.channels` تُحذف. يبقى فقط `topRanked` و`heroItems` (عشرات العناصر).
- الصفوف التحريرية تأتي من SQL: `ORDER BY CAST(rating AS REAL) DESC LIMIT 40` و`ORDER BY pos DESC LIMIT 24` — الفرز على 25 ألف صف داخل SQLite أرخص بمرتبة من فرزها كبنى Swift، ويخرج من الـ main actor كلياً.
- `PlaylistService.content` يجب أن يتوقّف عن الاحتفاظ بالنتيجة (`Core.swift:1763`) وإلا بقيت النسخة الأصلية حيّة والتوفير صفر. هذه أدقّ نقطة في المرحلة: `movieInfo` و`seasons` و`shortEPG` تعتمد على الـ actor، لكن ليس على `content` كاملة.
- `MoviesVM.filtered` / `applyFilter` / `selectCat` / `sortBy` — احذفها هنا، فلا قارئ لها أصلاً.
- (اختياري، رخيص) صندقة `Movie.details` في `final class` غير قابلة للتغيير ومطابِقة لـ `Sendable`، أو نقلها إلى مخبأ جانبي على غرار `PlaylistService.seriesDetailsCache` (`Core.swift:2369`) — وهو الاتساق مع `Series`. يُنقص `Movie` من ≈424 إلى ≈240 بايت (−43%).

### المرحلة 5 — تقاعُد `CatalogDiskCache`

الأثر: يزيل التجسيدين الكاملين ① و② من الإقلاع البارد، وكتابة JSON بعشرات الميغابايت.
المخاطرة: عالية — هذا هو مسار الإقلاع الوحيد اليوم. **افعلها أخيراً، خلف مفتاح إيقاف بعيد**، وبعد أن يكون `CatalogDB` قد أثبت نفسه في الإنتاج لدورة كاملة.

---

## 7. ما هو سليم — والتغيير فيه عبث

مذكور صراحةً حتى لا يُهدَر عليه وقت:

1. **مشاركة COW بين الـ VM.** لا يوجد «خمس نسخ». لا تُدخل مرجعاً أو غلافاً.
2. **`S8KListWindow` ومفتاح `first?.id`.** صحيح، ومدفوع ثمنه مرّة. لا تلمسه.
3. **`S8KImageCache` و`S8KImage`.** حدود مضبوطة، فكّ ترميز خارج main، دمج طلبات، حراسة إعادة الاستعمال. أنظف جزء في الملف.
4. **`foldedNames`.** 3 م.ب ثمن ممتاز.
5. **`SearchVM` بمسار FTS.** هو النموذج — انسخه، لا تعِد اختراعه.
6. **الكتابات المؤجّلة `Task.detached` للمخبأين.** أُصلحت لسبب موثَّق.
7. **`RailEngine` غير المستدعاة.** الإلغاء مقصود وموثَّق (`HomeView.swift:145-149`). لا تُعِدها «لإثراء الرئيسية» قبل المرحلة 4.
8. **رفوف الرئيسية المحدودة (10/20).** سليمة.
9. **`BarVisibility.report`.** محروسة بعتبة، بلا إبطال لكل إطار.
10. **`MediaPrefetcher`** بحدّ 2 وحارس المحرّك. سليم.
11. **`ObservableObject` بدل `@Observable`.** لا تهاجر. عرض WWDC25 306 كامله هو أن `@Observable` **لا** يمنح دقّة على مستوى العنصر ما دام النموذج يعرض مصفوفة تقرؤها الواجهة — وهو حالنا بالضبط (§5.2). الترحيل عمل كامل بمكسب صفر. وصفوفنا تستقبل قيماً لا مصفوفات أصلاً (`ChannelRow`, `MoviePosterCell`)، وهو الجزء الذي يهمّ فعلاً.
12. **لا `GRDBQuery` / `@Query`.** ما زال مبنيّاً على `ObservableObject`، وجلبه الافتراضي **متزامن** يحجب خيط الواجهة، و«Changes in the request state have no effect» ما لم تُستعمل `Binding` (§5.1). لا يشتري لنا شيئاً فوق `CatalogPager`.
13. **لا `ValueObservation` للترقيم.** المؤشّر المتغيّر ليس منطقة ثابتة؛ `trackingConstantRegion` **غير آمن** هنا بنصّ التوثيق، و`tracking` العادي يعيد جلب الصفحة عند أي كتابة (§5.1).

---

## 8. ما يحتاج اختبار جهاز (لا يمكن حسمه بالقراءة، ولا نبني محلياً)

| البند | الاختبار | المعيار |
|---|---|---|
| `MemoryLayout<Movie>.stride` | طباعة واحدة عند الإقلاع | تأكيد ≈424 وإلا أُعيد حساب §2 |
| زائدة `String.contains` | Time Profiler أثناء الطباعة | ظهور `CFStringFindWithOptions` يعني مسار ICU (الأسوأ) |
| `DatabasePool` (0-ج) | أول إقلاع على قاعدة موجودة | لا فقدان بيانات؛ ظهور `-wal` و`-shm` |
| `DatabasePool` تحت الحمل | بحث + تمرير أثناء استيراد جارٍ | لا تجمّد؛ ظهور الملصقات أثناء الاستيراد |
| `DatabasePool` وإنهاء قسري | إنهاء أثناء الاستيراد ثم إعادة فتح | لا تلف؛ الفهرس يُعاد بناؤه |
| ترقيم keyset (1-ب) | فتح قسم فيه >5,000 فيلم والتمرير حتى القاع | لا تكرار، لا فجوات، لا قفزة تمرير عند وصول صفحة |
| الخفير `.id(movies.count)` | تمرير سريع متواصل في قسم >5,000 | لا توقّف عند نهاية صفحة؛ لا استدعاء متكرر لا نهائي |
| **الخفير — كسل الحاوية** | قسم >5,000، مراقبة الذاكرة وعدّاد إنشاء الخلايا | **الحرج**: لا إنشاء متلهّف لكل الشبكة. إن حدث → البديل بلا `.id()` في §6 المرحلة 1-ج |
| `DatabasePool` واستنفاد القرّاء | بحث + تمرير + ThumbHash معاً أثناء استيراد | لا تجويع (GRDB #1647). إن ظهر → المرحلة 0-د (دفعات) |
| `PRAGMA cache_size` | قياس قبل/بعد `-32768` عبر `prepareDatabase` | خيط غير مؤكَّد (§5.8) — قِس، ولا تشحنه بلا قياس |
| التدهور (1-أ) | تشغيل بوضع Demo، ثم بحساب جديد قبل اكتمال الاستيراد | الشاشة تعرض المصفوفة الحالية بلا فراغ |
| `pos` كمفتاح keyset | مقارنة ترتيب القسم بين المسارين | ترتيب مطابق لترتيب المزوّد تماماً |
| 0-أ بعد التطبيق | Time Profiler على `MoviesVM.load` | اختفاء `Movie.sorted` من الحمل على main |
| ذاكرة الذروة | Memory graph بعد الدخول على خطّ 50 ألف | مقارنة قبل/بعد المرحلة 0 ثم المرحلة 4 |
| الأقسام العربية | بحث بكلمة عربية بلا تشكيل | `remove_diacritics 2` يطابق كما هو متوقّع |

**ملاحظة على `Item: Sendable` في `CatalogPager`:** `Movie` و`Channel` و`Series` بنى داخلية كل حقولها `Sendable`، فالمطابقة مستنتَجة ضمنياً. الدليل العملي أن هذا يترجم اليوم: `SearchVM.ftsResults` تعبر حدود ممثّل (`Task.detached`) وهي تُعيد `[SearchResult]` الحاوي على `Movie` و`Series` و`Channel` (`ContentViews.swift:3236-3238`, `3185-3202`). إن ظهر خطأ مطابقة رغم ذلك، الحل الأدنى هو حذف القيد `& Sendable` من تعريف `CatalogPager` والاكتفاء بـ `Identifiable` — الإغلاق يبقى `@Sendable` والالتقاط قيمي.

**قيود العملية** (من `MEMORY.md`): لا بناء محلي. البوّابات المتاحة هي `chk.py` (توازن أقواس + كشف ملف مبتور) و`scopechk.py` و`brandlint.py` ثم `Codemagic`. لا شيء منها يتحقّق من الأنواع — لذا كل كود أعلاه كُتب بعد فحص التواقيع الفعلية في الملفات (`s8kUniqueByID`, `s8kRating`, `ratingDouble`, `CatalogDB.page*`, `S8KListWindow`, `Store.m3uURL`, `Store.demoMode`) لا من الذاكرة.

**تنبيه ملف جديد:** `CatalogPaging.swift` يجب إضافته إلى `BlankTV.xcodeproj/project.pbxproj` (`PBXBuildFile` + `PBXFileReference` + عضوية `PBXSourcesBuildPhase` + `PBXGroup`) وإلا ترجم Codemagic بنجاح مع أخطاء «رمز غير معرَّف» عند الربط — وهي القاعدة المسجَّلة في ذاكرة المشروع.
