# خطة التنظيف — تدقيق مستقلّ للشيفرة الميّتة، وآثار العلامة، وما تبقّى من عمل التمايز

**تدقيق للقراءة فقط · 2026-07-29 · اللقطة: `HEAD = 64c1ab2` + شجرة عمل غير مثبّتة الساعة 05:11**

> **قيد مطلق التُزم به:** شجرة التطبيق المرجعي `C:\Users\user\Strong8K-App\Strong8K\iOS\Strong8K\` **للقراءة فقط**.
> لم يُكتب فيها ولم يُعدَّل ولم يُنشأ شيء. **الملف الوحيد المكتوب في هذه الجلسة هو هذا الملف.** لم أحذف ولم أعدّل سطراً واحداً في `BlankTV/`.

---

## 0. تحذيران قبل القراءة

### 0.1 الشجرة تتغيّر أثناء التدقيق

أثناء عمل هذا التدقيق كانت جلسة أخرى تكتب في المستودع فعلياً:

| الملف | حالة git | ما يجري |
|---|---|---|
| `BlankTV/AuthViews.swift` | `M` (124 سطراً) | **`SplashView` يُعاد بناؤها الآن** — انظر §0.2 |
| `BlankTV/Core.swift` | `M` (سطر واحد) | — |
| `DIFFERENTIATION_REPORT.md` | `M` (753 سطراً) | التقرير نفسه يُعاد كتابته |
| `TECH_HUNT_V2.md` | `M` (1451 سطراً) | — |

**نتيجة عملية:** كل رقم سطر في هذا الملف هو **لقطة**. قبل تنفيذ أي حذف، أعِد تحديد الموضع **بالاسم لا بالرقم**
(`grep -n "struct SearchView" BlankTV/ContentViews.swift`). كل نطاق أدناه محسوب بمطابقة أقواس آلية على الشجرة كما هي الساعة 05:11.

### 0.2 نتيجة قديمة سقطت أثناء الكتابة

`SplashView` — أخطر دليل مفرد في `DIFFERENTIATION_REPORT.md` («فرقها صفر سطر») — **لم تعد كذلك في شجرة العمل**:

| القياس | القيمة |
|---|---|
| عند `HEAD` (`AuthViews.swift:10–77` مقابل `ref AuthViews.swift:10–77`) | **68/68 سطراً متطابقة — `diff` = 0** ✅ تأكّد الادّعاء |
| في شجرة العمل الآن (`AuthViews.swift:10–111`) | **16 من 74 سطراً مجرّداً = 21.6 % متطابقة فقط** |

الشيفرة الجديدة تحذف `scaleEffect(0.88)` والدوّارة الدائرية، وتضع الـ lockup أفقياً على حافة القراءة، وتضيف `RadialGradient` bloom.
**هذا العمل جارٍ وغير مثبّت.** لا تكرّره، ولا تستشهد بالرقم القديم بعد اليوم.

---

## 1. الشيفرة الميّتة التي هي أيضاً استنساخ

### 1.1 منهج إثبات الموت

لكل نوع، تُنفَّذ **خمس** عمليات مسح على `BlankTV/` كاملةً، لا مسحاً واحداً:

1. `grep` على اسم النوع/العضو في كل ملفات `*.swift` — بما فيها التعليقات (تُعزل يدوياً).
2. تنقّل نصّي/انعكاسي: `NSClassFromString` · `#selector` · `value(forKey:)` · `perform(` →
   **النتائج الثلاث الوحيدة في الشجرة كلّها** هي `BlankTVApp.swift:132`, `:140` (لوحة المفاتيح) و`VLCPlayer.swift:578` (حجم خط الترجمة). **لا تنقّل بالسلاسل في هذا التطبيق.**
3. `AnyView` → **ثلاث مواضع فقط**، كلّها في `HomeView.swift:487–489` وكلّها `ShapeStyle` لا عرض. لا تغليف عروض.
4. معاينات وشيفرة تصحيح: **`#Preview` = صفر · `PreviewProvider` = صفر · `#if DEBUG` = صفر** في الشجرة كلّها.
   (`#if targetEnvironment(simulator)` واحد في `Core.swift:1247` داخل `SecurityCheck`، لا علاقة له بالعروض.)
5. **سلسلة الموت**: إن كان الاستدعاء الوحيد داخل نوع/عضو ميّت، فالنوع ميّت — وتُعرض السلسلة كاملة.

### 1.2 حكم مستقلّ على «الستّة» التي سمّاها `DIFFERENTIATION_REPORT.md §3.2`

التقرير يقول: «ستّ بنى عرض **منقولة من المرجع** ولا تُرسم أبداً — احذفها». **ثلاث من الستّ فقط منقولة.**

| # | ما سمّاه التقرير | ميّت؟ | مستنسخ؟ | التشابه المقيس | الحكم |
|---|---|---|---|---|---|
| 1 | `HomeView.navBar` | ✅ نعم | ✅ **نعم** | **60 من 65 سطراً** = 92.3 % مقابل `ref HomeView.swift:243–305` | التقرير **مُصيب** |
| 2 | `HomeView.announcementBar` | ✅ نعم | ✅ **نعم** | **21/21 سطراً — `diff` = 0** مقابل `ref :308–328` | التقرير **مُصيب** |
| 3 | `HomeView.bannerSection` | ✅ نعم | ✅ **نعم** | **24/24 سطراً — `diff` = 0** مقابل `ref :330–353` | التقرير **مُصيب** |
| 4 | `HomeView.railsSection` | ✅ نعم | ❌ **لا** | **لا مقابل له في المرجع إطلاقاً** | التقرير **مخطئ** — §1.5 |
| 5 | `featuredBanner` ×2 | ✅ نعم | ❌ **لا** | **لا مقابل له في المرجع إطلاقاً** | التقرير **مخطئ** — §1.5 |
| 6 | `ContentTabBar` | ✅ نعم | ❌ **لا** | **24 من 36 سطراً = 66.7 %** — أُعيد بناؤه | التقرير **مخطئ** — §1.5 |

**الأهمّ:** الستّة ليست القائمة الكاملة. **التدقيق وجد عشرة أنواع إضافية ميّتة ومستنسخة، منها شاشتان كاملتان وعائلة شاشات التفعيل بأسرها.**

### 1.3 الجدول القاطع — ميّت **و** مستنسخ · يُحذف

مرتّب بـ (حجم الدليل × تطابقه).

| # | النوع / العضو | الملف والنطاق **الدقيق للحذف** | أسطر | التطابق مع المرجع | موضع المرجع |
|---|---|---|---:|---:|---|
| A1 | `SearchView` | `ContentViews.swift:3409–3669` | **261** | **205 من 227 مجرّداً = 90.3 %** | `ref ContentViews.swift` |
| A2 | `ActivationRequiredView` | `ActivationView.swift:166–347` | **182** | **140 من 148 = 94.6 %** | `ref ActivationView.swift:129+` |
| A3 | `AlertsView` | `HomeView.swift:1539–1630` | **92** | **85 من 87 = 97.7 %** | `ref HomeView.swift` |
| A4 | `HomeView.navBar` + `navBtn` | `HomeView.swift:924–989` | **66** | **60 من 65 = 92.3 %** | `ref HomeView.swift:243–305` |
| A5 | `UpdateRequiredView` | `ActivationView.swift:115–163` | **49** | 24 من 37 = 64.9 % | `ref ActivationView.swift` |
| A6 | `MaintenanceView` | `ActivationView.swift:76–112` | **37** | 19 من 28 = 67.9 % | `ref ActivationView.swift` |
| A7 | `LoadingView` | `DesignSystem.swift:1910–1939` | **30** | **26/26 = 100 %** | `ref DesignSystem.swift:951–981` |
| A8 | `TrialBanner` | `ActivationView.swift:349–377` | **29** | **27/27 = 100 % — `diff` = 0** | `ref ActivationView.swift:355–382` |
| A9 | `HomeView.bannerSection` | `HomeView.swift:1094–1117` | **24** | **24/24 = 100 % — `diff` = 0** | `ref HomeView.swift:330–353` |
| A10 | `HomeView.announcementBar` | `HomeView.swift:1072–1092` | **21** | **21/21 = 100 % — `diff` = 0** | `ref HomeView.swift:308–328` |
| A11 | `LoadingDots` | `ActivationView.swift:379–397` | **19** | **18/18 = 100 %** | `ref ActivationView.swift` |
| A12 | `ActivationCheckingView` | `ActivationView.swift:59–73` | **15** | **14/14 = 100 %** | `ref ActivationView.swift` |
| A13 | `VLCVideoView` | `VLCPlayer.swift:729–740` | **12** | **12/12 = 100 % — `diff` = 0** | `ref VLCPlayer.swift:676–687` |
| A14 | `S8KGlassGroup` | `DesignSystem.swift:2652–2663` | **12** | **11/11 = 100 % — `diff` = 0** | `ref DesignSystem.swift:1371–1382` |
| A15 | `S8KLogoMark` | `AuthViews.swift:113–124` | **12** | **11 من 12** (الفرق الوحيد `Image(S8KBrand.logoAsset)` بدل `Image("Logo")`) | `ref AuthViews.swift:79–91` |
| A16 | `ShareActivityView` | `VLCPlayer.swift:742–749` | **8** | **8/8 = 100 % — `diff` = 0** | `ref VLCPlayer.swift:689–696` |
| | **المجموع** | | **868 سطراً** | **≈ 90 % منها متطابق حرفياً** | |

### 1.4 إثبات عدم البلوغ — السلاسل كاملةً

#### السلسلة 1 — `navBar` وكل ما يتدلّى منها (A4, A9, A10 + أثر جانبي)

`HomeView.body` (`HomeView.swift:707`) يرسم **حصراً**:

```
body (707)
 └─ ZStack
     ├─ showSkeleton (1005) ? homeSkeleton (846) : mainScroll (800)
     └─ .overlay(.top) → S8KPinnedPageBar { homeTopBar (1015) }
```

و`mainScroll` (`:800`) يبني `VStack` بأبنائه المسمّاة صراحةً في `:807–818`:

```
heroSection · contentErrorBanner · continueWatching · quickNav ·
moviesSection · seriesSection · liveSection · supportButtons · Color.clear
```

**`navBar` · `announcementBar` · `bannerSection` · `railsSection` ليست بينها، ولا في `homeSkeleton`، ولا في `homeTopBar`.**
و`navBtn` (`:974`) يُستدعى من `:941, :943, :947, :951` — **الأربعة داخل `navBar`**. سلسلة مغلقة.

> **⚠ أثر جانبي إلزامي — لا تحذف `navBar` قبل قراءة هذا.**
> `showRefreshConfirm` (`:691`) يُكتب في موضع واحد فقط: `:941` داخل `navBar`.
> فحذف `navBar` يُميت أيضاً كتلة `S8KConfirm` في `:763–777` و`@State refreshing` (`:690`)،
> **ومعها يفقد التطبيق مدخل «تحديث المحتوى» الوحيد** (`auth.refreshContent()`).
> `.refreshable` في `:834` **ليس بديلاً** — فهو يستدعي `vm.load(force: true)`، وهو مسار مختلف.
> `PROJECT_HANDOFF.md:408` سجّل هذه النقطة سلفاً: «wire it or …».
> **القرار قرار المالك**: إما وصل زرّ التحديث في `ExpandedNavBar` (`DesignSystem.swift:2390+`)، أو قبول أن `pull-to-refresh` هو المسار الوحيد.

#### السلسلة 2 — `SearchView` (A1) · **أكبر مكتشَف في هذا التدقيق**

```
BlankTVApp.swift:309   .fullScreenCover(item: $router.homeSheet)
BlankTVApp.swift:311     case .search: SearchView()
```

`homeSheet` يظهر في الشجرة كلّها في **سبعة** مواضع فقط:

| السطر | ماذا |
|---|---|
| `BlankTVApp.swift:46` | التعريف |
| `BlankTVApp.swift:309` | المستهلك |
| `DesignSystem.swift:2436` | `= .alerts` (حيّ شكلاً — انظر السلسلة 3) |
| `HomeView.swift:944` | **`= .search`** ← **داخل `navBar` الميّت** |
| `HomeView.swift:948` | `= .downloads` ← داخل `navBar` الميّت |
| `HomeView.swift:952` | `= .alerts` ← داخل `navBar` الميّت |
| `HomeView.swift:1141` | قراءة فقط (إيقاف دوران البطل) |

**لا كاتب حيّ لـ `.search`.** والبحث الفعلي في التطبيق مسار مختلف تماماً وملكيّ:

```
DesignSystem.swift:2424   AppRouter.shared.searchActive = true      (ExpandedNavBar)
HomeView.swift:789        HomeSearchResults(...)                    (HomeView.swift:597 — لا مقابل له في المرجع)
ContentViews.swift:202 / :1725 / :2296   .onChange(of: router.searchActive) → ترشيح موضعي
```

⇒ **`SearchView` — 261 سطراً، 90.3 % منها متطابقة مع صفحة بحث المرجع — لا يمكن أن تُعرض على أي جهاز.**
`DIFFERENTIATION_REPORT.md` لم يذكرها إطلاقاً.

> `DownloadsView` **لا تموت** بحذف `navBar`: لها مدخل ثانٍ حيّ في `SettingsView.swift:487`.

#### السلسلة 3 — `AlertsView` (A3)

المدخل الحيّ الوحيد ظاهرياً هو `DesignSystem.swift:2436`، لكنه محاط بـ:

```swift
DesignSystem.swift:2432    if alerts.unreadCount > 0 {
```

و`unreadCount` (`ActivationService.swift:97–100`) يحسب على `notifications`، و`notifications` (`ActivationService.swift:61`):

```swift
@Published var notifications: [AppNotification] = []
```

**مسحُ الشجرة كلّها على `notifications` يعطي 5 مواضع في `ActivationService.swift` — التعريف، تعليقان، وقراءتان.
لا يُلحَق بها عنصر واحد في أي مكان.** التعليق في `:24–25` يقرّ بذلك: «لم تعد تُسلَّم من الخادم — تبقى فارغة».

⇒ `unreadCount` صفر دائماً ⇒ دائرة الجرس لا تُرسم أبداً ⇒ **`AlertsView` (97.7 % متطابقة، 91 سطراً) لا يمكن بلوغها.**
والكاتب الثاني (`HomeView.swift:952`) داخل `navBar` الميّت.

#### السلسلة 4 — عائلة شاشات التفعيل بأسرها (A2, A5, A6, A8, A11, A12)

`ActivationService` صار كعباً محلّياً بعد `M0a` (تعليق `ActivationService.swift:3–17`). والقيم **ثوابت هيكلية**:

| الحقل | التعريف | كل الكتّاب في الشجرة |
|---|---|---|
| `gate` | `ActivationService.swift:51` = `.allowed` | `:45` (init) و`:118` (`check()`) — **كلاهما `.allowed`. لا ثالث.** |
| `maintenance` | `:66` = `false` | **لا كاتب.** (`Services.swift:422` يكتب على `ConfigService.maintenance` — نوع آخر تماماً) |
| `updateRequired` | `:74` = `{ false }` | **محسوب ثابت، غير قابل للكتابة** |
| `isTrial` | `:111` = `{ false }` | **محسوب ثابت** |

وجسم `ActivationGate` (`ActivationView.swift:32–52`):

```swift
if Store.shared.demoMode || act.gate == .allowed { content() }   // ← الفرع الوحيد القابل للتنفيذ
else if act.gate == .checking { ActivationCheckingView() }        // ← ميّت
else { ActivationRequiredView() }                                 // ← ميّت
if !Store.shared.demoMode {
    if act.maintenance { MaintenanceView(...) }                   // ← ميّت
    else if act.updateRequired { UpdateRequiredView(...) }        // ← ميّت
}
```

- `LoadingDots` مستدعىً من موضع واحد: `ActivationView.swift:67` **داخل `ActivationCheckingView` الميّت** ⇒ ميّت بالسلسلة.
- `TrialBanner` **صفر مواضع استدعاء أصلاً** (والمرجع يستدعيه في `ref HomeView.swift:201`) ⇒ ميّت مرّتين.

⇒ **من `ActivationView.swift` البالغ 398 سطراً، الحيّ هو `ActivationGate` (`:20–57`) وحده — وهو الآن مجرّد ممرّ.**
> هذا يصحّح `DIFFERENTIATION_REPORT.md` في موضعين: «رأس `ActivationRequiredView` متطابق … **هذه شاشة يراها المراجع على جهاز غير مفعّل**» — لا، **لا يراها أحد**؛ والتطابق ليس رأساً بل **148 سطراً بنسبة 94.6 %**.

#### السلسلة 5 — أنواع بصفر مواضع استدعاء (A7, A13, A14, A15, A16)

مسح آلي على كل `struct` في `BlankTV/` مع استبعاد أسطر التعليق أعطى قائمة الأنواع ذات المرجع الواحد (= التصريح فقط):

```
BlankTVApp (@main — سليم) · ContentTabBar · LoadingView · S8KGlassGroup ·
S8KLogoMark · ShareActivityView · SubscriptionsGateView · TrialBanner · VLCVideoView
```

خمسة منها مستنسخة (A7, A13, A14, A15, A16). البقيّة في §1.5.

### 1.5 ميّت لكن **ليس** استنساخاً — هنا أخطأ `DIFFERENTIATION_REPORT.md`

| النوع / العضو | الملف والنطاق | حالة المرجع | الحكم |
|---|---|---|---|
| `railsSection` + `railRow` + `railHeader` | `HomeView.swift:1187–1254` | **لا مقابل. `RailEngine.swift` (207 سطراً) ملك خالص لنا** | **لا تحذفه** — §1.6 |
| `MoviesView.featuredBanner` | `ContentViews.swift:1871–1907` | **لا مقابل** (`grep` على `featured` في `ref ContentViews.swift` يعطي `ActorWorksView` فقط) | حذفه مسموح، ومكسبه على 4.3 = **صفر** |
| `SeriesListView.featuredBanner` | `ContentViews.swift:2423–2458` | **لا مقابل** | نفسه |
| `ContentTabBar` | `ContentViews.swift:1362–1399` | موجود عند المرجع (`ref ContentViews.swift:1370`) **وحيّ فيه في 3 مواضع** — لكن **أُعيد بناؤه عندنا**: خطّ سفلي تحت المقطع النشط بدل كبسولة ذهبية ممتلئة؛ `spacing 24` بدل `8`؛ `S8KFont.subhead` بدل `caption1`؛ لا `Capsule` ولا `LinearGradient` ولا `strokeBorder` | **24 من 36 = 66.7 %.** حذفه آمن لكنه **ليس** تنظيف استنساخ. **`enum ContentTab` (`:1340–1359`) حيّ — لا تلمسه** (`ContentViews.swift:397, 1795, 2347`) |
| `SubscriptionsGateView` | `AuthViews.swift:477–688` (**212 سطراً**) | **ملك خالص لنا** | ميّت: صفر استدعاء. المرجعان الآخران تعليقان يقولان «retired» (`BlankTVApp.swift:241`, `GatewayView.swift:629`) |
| `LoginView.langMenu` | `AuthViews.swift:313` | — | عضو ميّت داخل بنية **حيّة**: `LoginView` تُستدعى من `SettingsView.swift:639`، لكن `langMenu` الخاصّ بها لا يُستدعى (النداء في `:508` يخصّ `langMenu` الآخر في `:659` داخل `SubscriptionsGateView`) |

### 1.6 لماذا **لا** تُحذف `railsSection`

`RailEngine.swift` (207 سطراً) و`HomeRail` **لا مقابل لهما عند المرجع** — وهما مذكوران في `DIFFERENTIATION_REPORT.md §2.1` و§5 ضمن «عندنا ولا يملكه». مستهلكهما الوحيد:

```
HomeView.swift:1193/1195   vm.rails  →  railRow (1202)  →  railHeader (1229) + ContentCard
```

وقد أُوقف عمداً — `HomeView.swift:146–149`:
> «`rebuildRails()` intentionally NOT called: … `railsSection` is not currently shown on Home (owner kept the movies/series/live layout) … Re-enable this call if `railsSection` is added back.»

**حذف `railsSection` يقتل `RailEngine.swift` بالكامل — أي يحذف ميزة ملكية ويخفض البُعد 5.** الخياران الصحيحان:
1. **الأفضل:** إعادة تفعيلها (إضافة `rebuildRails()` في `load()` و`bootLoad()` وإدراج `railsSection` في `mainScroll`) — تصبح ميزة حيّة تُذكر أمام App Review.
2. أو تركها كما هي بتعليقها الحالي الذي يشرح السبب.

**القرار للمالك** (شكل الرئيسية معتمد منه).

### 1.7 تصحيحان إضافيان لـ `DIFFERENTIATION_REPORT.md`

1. **`ContentCard` «حيّة في 4 مواضع» — بل في اثنين.**
   `HomeView.swift:1210` و`:1215` **داخل `railRow` الميّت**. الحيّان هما `HomeView.swift:1435` (`moviesSection`) و`:1456` (`seriesSection`) فقط.
   هذا **يقلّل** كلفة استبدالها ويرفع أولويّتها (§3).

2. **`SubscriptionsGateView` مذكورة في §2.1 و§5 كدليل تمايز.** وهي **ميّتة**. الاستشهاد بها في ردّ على App Review غير قابل للدفاع — شيفرة لا تُرسم لا تُقدَّم كميزة. القاعدة نفسها تنطبق على `HeroCarouselView`؟ لا — تلك حيّة (`HomeView.swift:1139`, `ContentViews.swift:1920`, `:2468`).

### 1.8 الحكم النهائي على السلامة، وأمر الحذف

**آمن للحذف بلا شرط (16 بنداً · 868 سطراً):** كل ما في §1.3.

**ترتيب التنفيذ الملزم** (لأن بعضها يُميت بعضاً):

```
الخطوة 1 — ملفات مستقلّة تماماً (لا تبعات):
  BlankTV/VLCPlayer.swift        742–749   ShareActivityView
  BlankTV/VLCPlayer.swift        729–740   VLCVideoView
  BlankTV/DesignSystem.swift    2652–2663  S8KGlassGroup
  BlankTV/DesignSystem.swift    1910–1939  LoadingView
  BlankTV/AuthViews.swift        113–124   S8KLogoMark

الخطوة 2 — عائلة التفعيل (احذف من الأسفل للأعلى حفاظاً على الأرقام):
  BlankTV/ActivationView.swift   379–397   LoadingDots
  BlankTV/ActivationView.swift   349–377   TrialBanner
  BlankTV/ActivationView.swift   166–347   ActivationRequiredView
  BlankTV/ActivationView.swift   115–163   UpdateRequiredView
  BlankTV/ActivationView.swift    76–112   MaintenanceView
  BlankTV/ActivationView.swift    59– 73   ActivationCheckingView
  ثم في ActivationView.swift:33–51 → بسّط ActivationGate إلى `content()` مباشرةً،
  أو احذف ActivationGate كلياً وعدّل BlankTVApp.swift:221.

الخطوة 3 — HomeView (من الأسفل للأعلى):
  BlankTV/HomeView.swift        1539–1630  AlertsView
  BlankTV/HomeView.swift        1094–1117  bannerSection
  BlankTV/HomeView.swift        1072–1092  announcementBar
  BlankTV/HomeView.swift         924– 989  navBar + navBtn (+ MARK)
  ثم: احذف @State refreshing (:690) و showRefreshConfirm (:691)
      واحذف كتلة S8KConfirm (:763–777)  ← بعد قرار المالك في §1.4/السلسلة 1

الخطوة 4 — SearchView (بعد الخطوة 3، لأن موتها يعتمد على موت navBar):
  BlankTV/ContentViews.swift    3409–3669  SearchView
  ثم: BlankTVApp.swift:311  احذف `case .search: SearchView()`
      BlankTVApp.swift:60   احذف `search` من `enum HomeSheet`
      BlankTVApp.swift:49   `searchScope` صار بلا قارئ — تحقّق واحذف إن صحّ
  ملاحظة: SearchVM (ContentViews.swift) يبقى — HomeSearchResults تستهلكه.

اختياري (ميّت لكن غير مستنسخ — مكسبه على 4.3 صفر):
  BlankTV/AuthViews.swift        477– 688  SubscriptionsGateView (212 سطراً)
  BlankTV/ContentViews.swift    1361–1399  ContentTabBar  (لا تلمس enum ContentTab :1340–1359)
  BlankTV/ContentViews.swift    2423–2458  SeriesListView.featuredBanner
  BlankTV/ContentViews.swift    1871–1907  MoviesView.featuredBanner
  BlankTV/AuthViews.swift        313–…     LoginView.langMenu

لا تُحذف:
  BlankTV/HomeView.swift        1187–1254  railsSection/railRow/railHeader — انظر §1.6
```

**بعد كل خطوة:** `python chk.py` ثم بناء على Codemagic. لا مترجم محلياً (`build-verify-constraints`).

---

## 2. آثار العلامة والهوية المتبقّية

### 2.1 ما تحقّقتُ من نزوله فعلاً (الادّعاءات في المهمّة)

| الادّعاء | الحالة | الدليل |
|---|---|---|
| `strong8k.app` أُزيل من `APIConfig` | ✅ **نزل** | `Core.swift:538–539` = `"https://api.invalid/v1"` (RFC 2606، لا تُحلّ أبداً). الدفعة `f55fc08`. |
| نصّ إذن الشبكة المحلية أُعيد كتابته | ✅ **نزل** | `Info.plist` صار «يستخدم التطبيق الشبكة المحلية للعثور على شاشات AirPlay القريبة وبثّ ما تشاهده إليها. لا يُجمع أي شيء عن شبكتك.» مقابل نصّ المرجع «للتواصل مع أجهزة AirPlay على نفس الشبكة». |
| عنوان بلاغات 4.7.1 انتقل إلى `S8KBrand` | ✅ **نزل** … | `DesignSystem.swift:1802` داخل `enum S8KBrand`، و`ActivationView.swift:15` صار `static var reportEmail: String { S8KBrand.reportEmail }`. |
| … لكن قيمته | ❌ **لا تزال نطاق المرجع** | `DesignSystem.swift:1802` → `"report@strong8k.app"` |

**كذلك سقط ادّعاء ثالث في `DIFFERENTIATION_REPORT.md`:** «`Info.plist` لا يزال متطابقاً بالبايت» — **لم يعد**. الآن فيه مفتاح إضافي (`UIUserInterfaceStyle = Dark`) ونصّ إذن مختلف.

### 2.2 ما بقي — بترتيب الخطورة على مراجع Apple

#### 🔴 خ1 — `report@strong8k.app` · **آخر سلسلة نصّية تحمل نطاق المرجع في الثنائي**

`BlankTV/DesignSystem.swift:1802`

```swift
static let reportEmail = "report@strong8k.app"
```

- **مسحُ الشجرة كلّها** على كل عنوان بريد أو `URL` أعطى: روابط المحتوى التجريبي (`archive.org`, `commons.wikimedia.org`, `test-streams.mux.dev`)، و`api.invalid`، و`youtube.com/watch`، و`wa.me`، وأمثلة `http://host:8080`. **`strong8k.app` هو الوحيد الباقي.**
- إنّه ثابت **ميّت** (`ActivationView.swift:15` بلا قارئ) — لكن `strings` على الـ IPA سيُظهره، وهو **بالضبط** نوع الأثر الذي يُثبّت رفضاً تحت Guideline 4.3.
- **وله وجه ثانٍ أخطر:** إن كان ميّتاً فلا يوجد في التطبيق **أي مسار للإبلاغ عن محتوى** — وهذا مطلب **Guideline 1.2 / 4.7.1** لتطبيق يعرض محتوى من طرف ثالث.
- **الإصلاح:** نطاق المالك، وربط الثابت بواجهة إبلاغ حقيقية في `SetAboutPage`. **يحتاج المالك** (§4).

#### 🟠 خ2 — تعليقات النسب في المصدر

سبعة تعليقات تسمّي التطبيق المرجعي بالاسم أو بالنطاق. لا يراها مراجع App Store، **لكنها قاتلة في أي تدقيق مصدري** (نزاع، شراء، تدقيق قانوني):

| الملف والسطر | النصّ |
|---|---|
| `ActivationService.swift:5` | `(strong8k.app: /v2/device/check + /v2/device/resolve) has been SEVERED.` |
| `CatalogDB.swift:9` | `Adapted from the proven Strong8K store …` |
| `Core.swift:531–532` | ``It used to read `https://strong8k.app/api/v1` … showed the REFERENCE app's live domain`` |
| `Core.swift:2624` | `The old XtreamService proxy fallback (→ strong8k.app) has been …` |
| `GatewayView.swift:3` | `… distinct from the Strong8K …` |
| `MediaPrefetcher.swift:7` | `Ported from the proven Strong8K …` |
| `ThumbHash.swift:7` | `… it must stay byte-identical to the reference to stay correct.` |

وأربعة تعليقات تقول «the reference» بلا اسم: `AuthViews.swift:243`, `:441` · `ContentViews.swift:2756`, `:3094` · `DesignSystem.swift:1278` · `HomeView.swift:848` · `SettingsView.swift:1139`.
**التوصية:** أعِد صياغتها بلغة محايدة («ported from our shared playback engine»). `ThumbHash.swift:7` استثناء مشروع — الخوارزمية MIT عامّة ويجب أن تبقى حرفية؛ لكن أعِد صياغة الجملة إلى «must stay byte-identical to the published ThumbHash reference implementation».

#### 🟠 خ3 — 17 مفتاح `UserDefaults` ببادئة `s8k.` · **مطابقة حرفياً لمفاتيح المرجع**

قِيست: مفاتيحنا الـ17 كلّها موجودة **بالاسم نفسه** في مفاتيح المرجع الـ24.

```
s8k.lang · s8k.theme.cache · s8k.engine · s8k.subFontSize · s8k.downloadWifiOnly ·
s8k.kc.accessibility.v2 · s8k.migrated.scopedV2 · s8k.history · s8k.watchlist ·
s8k.fav.movies · s8k.fav.series · s8k.fav.channels ·
s8k.catorder2.movies · s8k.catorder2.series · s8k.catorder2.live ·
s8k.search.recent · s8k.notif.lastSeen
```

المواضع: `Core.swift:38, 41, 765, 874–875, 883–884, 902–903, 1141–1167, 1199, 1218–1219` · `DesignSystem.swift:1007, 1046` · `ContentViews.swift:3260, 3370, 3372` · `ActivationService.swift:98, 103`.
لا يراها مراجع App Store، لكنها تظهر في `com.blanktv.player.plist` عند أي فحص وقت-تشغيل.
**الإصلاح:** بادئة `blank.` + **ترحيل صامت لمرّة واحدة** (اقرأ القديم إن غاب الجديد، اكتب الجديد، احذف القديم) — وإلّا فقد كل مستخدم حالي مفضّلاته وسجلّه وترتيب أقسامه.

#### 🟡 خ4 — 39 معرّف نوع ببادئة `S8K` + الرمز `S8KBrand`

`S8KFont`, `S8KSpace`, `S8KRadius`, `S8KGradient`, `S8KImage`, `S8KPlinth`, `S8KBrand` … أسماء الرموز تظهر في الثنائي.
**غير مرئية لمراجع App Store، ولا تُصنَّف دليلاً تحت 4.3.** أولويّة منخفضة جداً — وإعادة تسميتها تلمس كل ملف. **لا أوصي بها الآن.**

#### 🟡 خ5 — ملف مؤقّت داخل مجلّد المصدر

`BlankTV/out1.txt` — 916 بايت، محتواه **Python traceback**، تاريخه 2026-07-27.
**ليس** في `BlankTV.xcodeproj/project.pbxproj` (فلا يُشحن في الحزمة)، وليس في `git status` (فهو متجاهَل أو غير مضاف). لكنه **قذارة داخل مجلّد يفحصه أي مدقّق**. احذفه.

#### 🟢 ما فحصتُه ووجدته **نظيفاً** (تأكيد إيجابي)

| البند | الحالة |
|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.blanktv.player` (`project.pbxproj:307, 337`) ✅ |
| `INFOPLIST_KEY_CFBundleDisplayName` | `"Blank Prime"` (`:297, 327`) ✅ |
| خدمة الـ Keychain | `"com.blanktv.app"` (`Core.swift:695`) ✅ |
| جلسة التنزيل الخلفية | `"com.blanktv.player.downloads"` (`Downloads.swift:62`) ✅ |
| طابور الإبقاء | `"com.blanktv.downloads.persist"` (`Downloads.swift:484`) ✅ |
| بديل معرّف الحزمة | `"com.blanktv.player"` (`DeviceID.swift:42`) ✅ |
| **URL schemes** | **`CFBundleURLSchemes` = غير موجود إطلاقاً** ✅ |
| **App Groups** | غير موجودة ✅ |
| **ملفّات `.entitlements`** | **صفر في المستودع كلّه** ✅ |
| `User-Agent` | `VLC/3.0.20 LibVLC/3.0.20`, `okhttp/4.12.0`, `IPTVSmartersPlayer` — **سلاسل توافق مع خوادم IPTV، ليست هوية**. لا تُغيَّر (تكسر التشغيل). ✅ |
| `Logo.imageset` | `d3bbcee39f · cb12d0e5e7 · 715a14ccf6` مقابل `88d3bbdc4e · 89a60a6116 · 65be53e672` — **مختلفة** ✅ |
| أصول ملكية | `gwposter1…6.imageset` — لا مقابل لها ✅ |
| `PrivacyInfo.xcprivacy` | `NSPrivacyCollectedDataTypes` **فارغة عندنا** مقابل **أربع كتل** عند المرجع (DeviceID · CrashData · PerformanceData · ProductInteraction) — **فرق حقيقي وصحيح**، لأن طبقة `Telemetry` غير موجودة عندنا. كتلة `NSPrivacyAccessedAPITypes` متطابقة، لكنها **قوالب Apple الحرفية** (`CA92.1`, `3B52.1`, `85F4.1`, `E174.1`) ولا يمكن أن تختلف. ✅ |
| `Info.plist` | لم يعد متطابقاً بالبايت ✅ |

---

## 3. أعلى ما تبقّى قيمةً — مرتّباً بـ (نقاط 4.3 ÷ ساعات الهندسة)

### 3.0 تصحيح خطّ الأساس أولاً

`DIFFERENTIATION_REPORT.md` يعطي «≈ 55 %» ويجعل **الخطر رقم 3 = الفرنسية/التركية/الإسبانية عند 79.6 % تطابق**. **هذا لم يعد صحيحاً.** الدفعة `eccd4ed` («Live-first fetch, and the fr/tr/es rewrite») نفّذته. أعدتُ القياس على `L10n.table` مباشرةً (372 مفتاحاً عندنا · 402 عند المرجع · 298 مشتركاً):

| اللغة | متطابقة من المفاتيح الـ298 المشتركة | من 372 مفتاحاً عندنا | ما قاله التقرير |
|---|---:|---:|---:|
| العربية | 208 = 69.8 % | **55.9 %** | 55.9 % ✅ |
| الإنجليزية | 212 = 71.1 % | **57.0 %** | 56.7 % ✅ |
| الفرنسية | 149 = 50.0 % | **40.1 %** | 79.6 % ❌ |
| التركية | 157 = 52.7 % | **42.2 %** | 79.3 % ❌ |
| الإسبانية | 150 = 50.3 % | **40.3 %** | 79.6 % ❌ |

**النصوص الطويلة (>30 حرفاً) المتطابقة حرفياً:** ar **27** · en **30** · fr **4** · tr **2** · es **2**.

⇒ **انقلبت الصورة: العربية والإنجليزية صارتا الأسوأ، لا الأفضل.** البند «2️⃣» في خطّة التقرير أُنجز، والعمل النصّي المتبقّي هو `.ar` و`.en` في المفاتيح الطويلة —
`alert.delete.msg` · `alert.logout.msg` · `alerts.empty.sub` · `downloads.empty.sub` · `downloads.low_warning` · `downloads.notif.denied` · `downloads.space_low.msg` · `error.account_expired` · `error.account_suspended` · `error.invalid_credentials` · `error.invalid_server` …

**البُعد 6 ينتقل من 45 % إلى ≈ 53 %.** ومع إعادة بناء `SplashView` الجارية (§0.2) يرتفع البُعد 4 من 68 % إلى ≈ 76 %.
**خطّ الأساس الحقيقي اليوم ≈ 57 %، لا 55 %.**

### 3.1 الترتيب

الأثر مقدَّر على سلّم `DIFFERENTIATION_REPORT.md §4` نفسه (100 نقطة موزونة).

| # | العمل | الملف | النقاط | الساعات | **النسبة** | موافقة؟ |
|---|---|---|---:|---:|---:|---|
| 1 | إزاحة سلّمي الطباعة والمسافات | `DesignSystem.swift:937–954` + `:957–966` | **+3.0** | 1.5 | **2.00** | 🔴 **المالك** |
| 2 | تبديل رموز التبويبات الخمسة | `DesignSystem.swift:2108–2121` | **+0.5** | 0.3 | **1.67** | 🟢 هندسي |
| 3 | إعادة كتابة `.ar`/`.en` الطويلة | `Core.swift` — `L10n.table` | **+1.5** | 2.0 | **0.75** | 🟢 هندسي |
| 4 | حزمة «الذرّات» البصرية (4 مكوّنات) | `DesignSystem.swift` + `ContentViews.swift` | **+3.0** | 4.0 | **0.75** | 🟢 هندسي |
| 5 | إعادة تصميم طبقة عرض المشغّل | `PlayerView.swift:878–1130` وما بعدها | **+7.0** | 12.0 | **0.58** | 🔴 **المالك** |
| 6 | تنظيف آثار العلامة (§2.2) | 5 ملفات | **+0.5** | 1.0 | **0.50** | 🟡 جزئي |
| 7 | سبع شاشات ثانوية على `SetScaffold` | `SettingsView.swift` + `Downloads.swift` | **+2.5** | 6.0 | **0.42** | 🟢 هندسي |
| 8 | حذف الشيفرة الميّتة (§1) | 6 ملفات | **≈ +0.2** | 2.0 | **0.10** | 🟡 قرار واحد |

---

### 1️⃣ إزاحة سلّمي الطباعة والمسافات — **+3.0 نقطة · 1.5 ساعة · النسبة 2.00** 🔴

**تحقّقتُ من الادّعاء بنفسي — وهو صحيح 100 %.**

`DesignSystem.swift:937–954` مقابل `ref DesignSystem.swift:238–254`: **13 رمزاً، قيمة بقيمة ووزناً بوزن.**

```
display 34/black · title1 28/heavy · title2 22/bold · title3 18/bold ·
headline 15/semibold · body 15/regular · callout 14/regular · subhead 13/semibold ·
footnote 12/regular · caption1 11/medium · caption2 10/semibold · caption3 9/bold ·
mono 12/medium/monospaced
```

الإضافة الوحيدة عندنا `field = 16/regular` (`:945`) — وهي إضافة، لا إزاحة.

`DesignSystem.swift:957–966` مقابل `ref :256–265`: **8 قيم — `4/8/12/16/20/24/32/48` — متطابقة حرفياً**، بالأسماء نفسها `xs/sm/md/lg/xl/xxl/h/hh`.

**ماذا تفعل بالضبط:** عدّل **تعريفين فقط**. كل الشيفرة تقرأ الرموز لا الأرقام (أتمّت ذلك الدفعة `c7e3c34`)، فالتغيير يمتدّ إلى كل شاشة بلا لمس أي شاشة.

```swift
// DesignSystem.swift:937–954
display 40/black · title1 30/black · title2 24/heavy · title3 19/bold ·
headline 16/semibold · body 15 · field 16 · callout 13.5 · subhead 13/bold ·
footnote 12 · caption1 11.5/medium · caption2 10.5 · caption3 9 · mono 12/medium/monospaced

// DesignSystem.swift:957–966
xs 5 · sm 9 · md 13 · lg 18 · xl 22 · xxl 28 · h 36 · hh 56
```

**لماذا الأول:** الإيقاع الطباعي أوّل ما تقرؤه العين، قبل اللون. ولأنه ملف واحد وتعريفان، فهو أعلى (أثر ÷ جهد) في القائمة كلّها بفارق واضح.
**🔴 يحتاج المالك:** يمسّ مظهراً معتمداً ويغيّر ارتفاعات كل صفّ. **نفّذه في بناء منفرد** واختبره وفق `DEVICE_MATRIX.md §6`.

---

### 2️⃣ رموز التبويبات — **+0.5 نقطة · 20 دقيقة · النسبة 1.67** 🟢

`DesignSystem.swift:2108–2121`. **الخمسة متطابقة مع `ref DesignSystem.swift:1159–1172`:**

```
home → "house" / "house.fill"          movies → "film" / "film.fill"
live → "dot.radiowaves.left.and.right"  series → "tv"
settings → "gearshape" / "gearshape.fill"
```

**البديل — بلا أي أصل جديد، رموز نظام موجودة:**

| التبويب | بدلاً من | استعمل |
|---|---|---|
| `live` | `dot.radiowaves.left.and.right` | `waveform` أو `antenna.radiowaves.left.and.right` |
| `movies` | `film` | `popcorn` أو `movieclapper` |
| `series` | `tv` | `rectangle.stack` أو `sparkles.tv` |
| `settings` | `gearshape` | `slider.horizontal.3` |
| `home` | `house` | `square.grid.2x2` |

هذه الرموز تُرسم في **`ExpandedNavBar` (`DesignSystem.swift:2440+`)** — أي على كل شاشة، طوال الوقت. أرخص تغيير مرئي في التقرير كلّه.
**🟢 هندسي بحت.**

---

### 3️⃣ إعادة كتابة `.ar` و`.en` الطويلة — **+1.5 نقطة · ساعتان · النسبة 0.75** 🟢

**الملف:** `BlankTV/Core.swift` — `L10n.table` (`:53–516`).
**النطاق المحدَّد:** **27 نصّاً عربياً و30 إنجليزياً** طولها > 30 حرفاً ولا تزال متطابقة حرفياً. ابدأ بالمفاتيح المذكورة في §3.0 — كلّها تظهر في مسارات يسلكها المراجع (حذف الحساب · الخروج · فشل التنزيل · انتهاء الاشتراك · بيانات دخول خاطئة).
**لا تلمس `.fr`/`.tr`/`.es`** — أُنجزت (`eccd4ed`)، وإعادة لمسها إهدار.
**🟢 هندسي بحت** — صوت تحريري مختلف، لا معنى مختلف.

---

### 4️⃣ حزمة «الذرّات» البصرية — **+3.0 نقطة · 4 ساعات · النسبة 0.75** 🟢

أربعة مكوّنات صغيرة تتكرّر أكثر من أي شاشة، وكلّها لا تزال شبه متطابقة. تُنفَّذ كدفعة واحدة.

| المكوّن | الملف | التطابق | أين يُرسم |
|---|---|---:|---|
| `ContentCard` | `DesignSystem.swift:1986–2048` | **49 من 53 = 92.5 %** | `HomeView.swift:1435, 1456` — **موضعان حيّان لا أربعة** (§1.7) |
| `CategoryRow` | `ContentViews.swift:1402–…` | **43 من 45 = 95.6 %** | رأس كل قسم في الأفلام والمسلسلات والمباشر — 4 صفحات |
| `ChannelChip` | `DesignSystem.swift:2051–2089` | **32 من 36 = 88.9 %** | `HomeView.liveSection` + صفحة المباشر |
| `S8KConfirm` | `DesignSystem.swift:2522–…` | **50 من 57 = 87.7 %** | كل تنبيه تأكيد في التطبيق |

**`ContentCard` بالتفصيل** — نفس `118×166` ونفس `S8KRadius.md` ونفس `strokeBorder(.s8kBorder)` ونفس الشارة (`caption3` أسود على `goldFlat` بـ `S8KRadius.xs` و`padding(7)`) ونفس `spacing: 7` ونفس `caption1.semibold`/`caption2` — **وخمسة تعليقات حرفية نفسها**: `// Image container` · `// Badge` · `// Progress bar` · `// Title` · `// Subtitle`. الفارقان الوحيدان: `S8KProgressBar` بدل `GeometryReader` داخلي، و`Button` بدل `.onTapGesture`.

**ماذا تفعل — بمفردات BLANK الموجودة أصلاً:**
- غادر `118×166` (نسبة 1:1.41 = مقاس المرجع) إلى نسبة الملصق الحقيقية `2:3` → `112×168`، بـ `S8KRadius.sm`.
- **انقل العنوان خارج البطاقة** بمحاذاة حافة القراءة، بدل أسفلها بمحاذاة `trailing`.
- اجعل الشارة **نصّاً مسطّحاً على أرضية معتمة** لا مستطيلاً بتدرّج ذهبي.
- اجعل شريط التقدّم **خطّاً عند الحافة السفلية للملصق نفسه** بلا حاوية.
- **احذف التعليقات الخمسة المنسوخة.**

**🟢 هندسي بحت** — لا فنّ جديد؛ المفردات (`S8KProgressBar`, `S8KRadius`, `BrandTheme`) مبنيّة عندك.

---

### 5️⃣ طبقة عرض المشغّل — **+7.0 نقطة · 12 ساعة · النسبة 0.58** 🔴

**تحقّقتُ من الادّعاء بنفسي — وهو صحيح.**

`PlayerView.swift:878–1130` مقابل `ref PlayerView.swift:827–1054`:
**173 من 205 سطراً مجرّداً متطابقة = 84.4 %** (التقرير قال 85.9 % — الفرق ضمن اختلاف المجرِّد). **أطول كتلة متّصلة متطابقة = 67 سطراً.**

و**عناوين `// MARK:` الخمسة عشر بنفس الأسماء وبنفس الترتيب** — دليل نسب مستقلّ عن البكسلات تماماً:

| عندنا | عند المرجع |
|---|---|
| `:242` Episode context (auto-next + skip-intro) | `ref :238` |
| `:303` Live channel zapping (next / previous) | `ref :290` |
| `:609` Gesture zones (volume / brightness / seek) + tap-to-toggle | `ref :573` |
| `:629` Hold-to-2x speed boost | `ref :593` (بـ `(#package)`) |
| `:720` Double-tap seek (±10s, accumulating) + Netflix ripple | `ref :678` |
| `:736` Side HUD views | `ref :694` |
| `:776` Screen-lock overlay (gesture lock) | `ref :734` |
| `:800` Skip-intro + auto-next overlays | `ref :754` |
| `:878` Controls overlay (cinematic, over the video) | `ref :827` |
| `:1131` Orientation | `ref :1055` |
| `:1159` Controls auto-hide | `ref :1083` |
| `:1200` Sleep timer | `ref :1127` |
| `:1312` Subtitle sheet | `ref :1234` |
| `:1383` Playback speed sheet | `ref :1305` |
| `:1421` Audio track sheet (audio selection + remember) | `ref :1343` |

(✅ وسوم `#package` الستّة حُذفت فعلاً — تأكّد.)

**ماذا تفعل — ولا تلمس المحرّك:** المنطق والإيماءات هندسة، تبقى كما هي. غيّر **ما يُرسم** فقط:
- **طبقة التحكّم** (`:878–1130`): انقل الصفّ السفلي الكلاسيكي إلى مفردات BLANK المستعملة في صفحة التفاصيل — **كبسولة `S8KPlayCapsule` بحجم المحتوى + أقمار `S8KSatellite` دائرية 48pt**.
- **شريط التقدّم**: قاعدة رفيعة بلغة `S8KPlayCapsule` بدل `Slider` المعياري بلونه `.s8kGoldHigh` وفقاعة وقته العائمة عند `y: -32`.
- **HUD الصوت والسطوع** (`:736`): المرجع عمود عمودي `5×110` في الوسط بحشو `.horizontal, 30` ← اجعلها **شارة أفقية صغيرة أعلى الحافة**.
- **الصفائح الأربع** (`:1312`, `:1383`, `:1421` + النوم `:1200`): أعِد بناءها على **`SetScaffold` الموجود عندك في `SettingsView.swift`**.
- **أعِد صياغة عناوين `// MARK:` الخمسة عشر** — الترتيب الحرفي نفسه دليل قائم بذاته.

**لماذا هو الخامس لا الأول:** أعلى أثر مفرد في القائمة كلّها، لكنه أغلاها وأخطرها (المشغّل على المسار الحرج، ولا تحقّق بصري إلا على جهاز). **نفّذه على مراحل، طبقة لكل بناء**، بنمط «العرض المعزول» الذي نجح مع `GatewayView`.
**🔴 يحتاج المالك:** موافقة على الاتجاه (كبسولة + أقمار مثل صفحة التفاصيل) **قبل كتابة أي سطر**.

---

### 6️⃣ تنظيف آثار العلامة — **+0.5 نقطة · ساعة · النسبة 0.50** 🟡

بالترتيب:
1. `DesignSystem.swift:1802` → استبدل `"report@strong8k.app"`. **🔴 يحتاج المالك** (نطاق + قرار واجهة الإبلاغ).
2. `BlankTV/out1.txt` → احذفه. 🟢
3. تعليقات النسب السبعة (§2.2/خ2) → أعِد صياغتها. 🟢
4. البادئة `s8k.` → `blank.` مع **ترحيل صامت لمرّة واحدة**. 🟢 (ساعتان، ليست ضمن الساعة أعلاه)

---

### 7️⃣ الشاشات الثانوية على `SetScaffold` — **+2.5 نقطة · 6 ساعات · النسبة 0.42** 🟢

كلّها **حيّة** وكلّها على بُعد نقرة واحدة من الإعدادات — أي في مسار مراجعة تفصيلية معتادة. قِيست كلّها في هذه الجلسة:

| الشاشة | الملف والنطاق | التطابق | المدخل الحيّ |
|---|---|---:|---|
| `ParentalGate` | `SettingsView.swift:1056–1087` | **31/31 = 100 %** | `ContentViews.swift:194, 248, 1716` + 3 |
| `LockedCategoriesView` | `SettingsView.swift:1283–1413` | **106 من 112 = 94.6 %** | `SettingsView.swift:1137` |
| `PlaylistsView` | `SettingsView.swift:723–836` | **104 من 111 = 93.7 %** | `SettingsView.swift:398` |
| `AboutView` | `SettingsView.swift:889–936` | **43 من 47 = 91.5 %** | `SettingsView.swift:519` |
| `DownloadsView` | `Downloads.swift:744–910` | **139 من 154 = 90.3 %** | `SettingsView.swift:487` + `BlankTVApp.swift:313` |
| `PINEntryView` | `SettingsView.swift:945–1053` | **81 من 97 = 83.5 %** | `SettingsView.swift:1077, 1113, 1118` |
| `AddPlaylistView` | `SettingsView.swift:838–886` | **38 من 46 = 82.6 %** | `SettingsView.swift:776` |

**ماذا تفعل:** كلّها قوائم ونماذج. أعِد بناءها على `SetScaffold` الذي تملكه (`SettingsView.swift`) — رأس موحّد + صفوف بلغة BLANK.
**🟢 هندسي بحت** — إعادة استعمال مكوّن قائم، لا تصميم جديد.

> **تصحيح لأرقام `DIFFERENTIATION_REPORT.md`:** `LockedCategoriesView` = 94.6 % لا 96.4 % · `DownloadsView` = 90.3 % لا 91.4 % · `PINEntryView` = 83.5 % لا 89.2 %. الاتجاه واحد، والأرقام أدقّ هنا.

---

### 8️⃣ حذف الشيفرة الميّتة — **≈ +0.2 نقطة · ساعتان · النسبة 0.10** 🟡

**أخالف `DIFFERENTIATION_REPORT.md` هنا صراحةً.** التقرير أعطى البند «+1 نقطة» ووضعه خامساً. **مكسبه على البند 4.3 كما تطبّقه Apple فعلياً ≈ صفر** — لأن 4.3 يقاس على **ما يُرى**، والشيفرة الميّتة **لا تُرى بحكم التعريف** (وهذا ما يقوله التقرير نفسه في ملاحظته «(ب) لا تستشهد بهذه البنى … فهي لا تُرسم»).

**لكنه يبقى واجباً، ولسبب مختلف تماماً:**
- **868 سطراً** يُشحن منها ما نسبته ≈ 90 % متطابق حرفياً مع المرجع — دليل نسب مباشر في **أي تدقيق مصدري** (نزاع، شراء، فحص قانوني).
- يمنع أن يُستشهد بميزة ميّتة (`SubscriptionsGateView`) في ردّ على App Review — وهو خطأ **يجعل الردّ نفسه دليل إدانة**.
- يزيل شاشتين كاملتين (`SearchView` 90.3 % · `AlertsView` 97.7 %) وعائلة شاشات التفعيل بأسرها من الثنائي.

**نفّذه — لكن لا تحتسبه في الرقم، ولا تجعله يسبق البنود 1 و2 و4.**

---

## 4. «يحتاج المالك» — ما لا يُغلق بالهندسة وحدها

| البند | لماذا | المطلوب منك بالضبط |
|---|---|---|
| **إزاحة سلّم الطباعة/المسافات** (3.1/1) | يغيّر مظهراً **معتمداً** على كل شاشة ويغيّر ارتفاعات كل صفّ | موافقة صريحة + جولة نظر على الجهاز بعد البناء، في بناء منفرد |
| **اتجاه إعادة تصميم المشغّل** (3.1/5) | قرار تصميم لا تنظيف | موافقة على «كبسولة + أقمار مثل صفحة التفاصيل» **قبل** أول سطر |
| **بريد بلاغات 4.7.1** | `report@strong8k.app` هو آخر نطاق المرجع في الثنائي — **و**لا يوجد مسار إبلاغ فعّال أصلاً | عنواناً على نطاقك، أو قرار بحذف الثابت + قرار بشأن التزام 1.2/4.7.1 |
| **زرّ «تحديث المحتوى»** (§1.4/السلسلة 1) | حذف `navBar` يزيل المدخل الوحيد لـ `auth.refreshContent()` | إمّا «صِله في `ExpandedNavBar`» أو «`pull-to-refresh` يكفي — احذفه» |
| **مصير `railsSection` / `RailEngine`** (§1.6) | إعادة تفعيلها تغيّر شكل الرئيسية المعتمَد منك | «فعّلها» أو «اتركها معطّلة» — لكن **لا تحذفها** |
| **بادئة `s8k.` → `blank.`** | الترحيل يمسّ بيانات مستخدمين حاليين | موافقة على تنفيذ الترحيل الصامت (وإلّا يُؤجَّل) |
| **لقطات App Store** | لا شيء في الشيفرة يضبطها | **لا تصوّر:** المشغّل، ولا التنزيلات، ولا «حول»، ولا الرقابة الأبوية. **صوّر:** البوّابة · الرئيسية بالبطل و Top-10 · صفحة التفاصيل · مركز الإعدادات · مبدّل الحسابات |

**لا يحتاج المالك:** رموز التبويبات · إعادة كتابة `.ar`/`.en` · حزمة الذرّات · الشاشات الثانوية على `SetScaffold` · تعليقات النسب · `out1.txt` · حذف الشيفرة الميّتة (عدا قرار زرّ التحديث ومصير `railsSection`).
**ولا يحتاج أيٌّ منها فنّاً جديداً ولا هوية جديدة** — `S8KPlinth` و`S8KPlayCapsule` و`S8KSatellite` و`SetScaffold` و`S8KWordmark` و`BrandTheme` و`S8KProgressBar` مبنيّة عندك أصلاً وغير مستعملة في هذه المواضع.

---

## 5. الأثر المتوقّع

| بعد تنفيذ | النسبة |
|---|---|
| خطّ الأساس الحقيقي اليوم (بعد `eccd4ed` و`SplashView` الجارية) | **≈ 57 %** |
| + البنود 2 و3 و6 (يوم عمل، صفر موافقة تصميم) | **≈ 60 %** |
| + البند 1 (سلّم الطباعة — **موافقتك**) | **≈ 63 %** |
| + البندان 4 و7 | **≈ 68 %** |
| + البند 5 (المشغّل — **موافقتك**) | **≈ 75 %** |

---

## 6. ملاحظة منهجية

كل رقم تشابه في هذا الملف حُسِب آلياً على شجرتين حيّتين: تُجرَّد الأسطر الفارغة والتعليقات، وتُطبَّع المسافات، ثم `difflib.SequenceMatcher` يعطي مجموع الكتل المتطابقة ÷ عدد أسطرنا المجرّدة. حالات «`diff` = 0» فُحصت بـ `diff` مباشر على النصّ الخام.

**لم تُنفَّذ أي كتابة على `C:\Users\user\Strong8K-App\Strong8K\iOS\Strong8K\`، ولا أي تعديل على `BlankTV/`.**

_انتهى._
