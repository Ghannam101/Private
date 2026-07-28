# تدقيق طبقة اللمس — BLANK TV

مراجعة كاملة لكل عنصر تفاعلي في `BlankTV/` (SwiftUI · iOS 17+ · iPhone + iPad).
التقرير يسرد **العيوب فقط** — أي عنصر سليم لا يُذكر إلا في القسم الأخير (ما تم التحقق منه).

**قاعدة القياس المستخدمة**: مساحة اللمس لأي `Button` = مجموع المحتوى **المعتم** داخل الـ label
(التعبئات `fill` والخلفيات `background` تُحتسب؛ `Spacer` و`padding` الفارغ و`.frame` الفارغ **لا** تُحتسب)
ما لم يوجد `.contentShape(...)` صريح. الحد الأدنى من Apple HIG = **44×44 pt**.
أصغر عرض مدعوم في المشروع = **320pt** (لوح iPad Slide Over، `.compactNarrow`)، ثم 375pt (iPhone SE).

---

## الملخص التنفيذي

| التصنيف | العدد |
|---|---|
| **BROKEN** (لا يمكن لمسه، أو ينفّذ الفعل الخاطئ) | **9** |
| **أهداف لمس أقل من 44×44 pt** | **62** |
| **AWKWARD** (يعمل، لكن الهدف صغير أو مُزاح) | 8 مجموعات |
| **RISK** (هشّ — قد ينكسر مع تغيّر حالة) | 11 |
| عناصر أيقونية بلا `.accessibilityLabel` | **26** |

حقائق بنيوية مقلقة تكرّرت عبر التدقيق:

- في **كامل الـ codebase** يوجد **إعلان أولوية إيماءات واحد فقط**: `.simultaneousGesture` في
  `PlayerView.swift:572`. لا يوجد `.highPriorityGesture` ولا `.exclusively(before:)` ولا
  `.simultaneously(with:)` في أي ملف — بينما طبقة تحكّم المشغّل تكدّس أربع إيماءات على نفس العنصر.
- توجد **11 عبارة `.accessibilityLabel` فقط** في التطبيق كله، مقابل ~37 عنصر أيقوني بلا نص.
- إصلاح `delaysContentTouches = false` (`GWNoTouchDelay`) مطبَّق على **صفحة الدخول وحدها**
  (`GatewayView.swift:283`)؛ كل زر آخر في التطبيق داخل `ScrollView` ما يزال يدفع تأخير ~150ms.

---

## أولاً: BROKEN

### B1 — طبقة تحكّم المشغّل تبتلع كل إيماءات الشاشة
**`PlayerView.swift:820-827` مقابل `PlayerView.swift:366-371` و `450-452`**

`controlsOverlay` مركّب دائماً ويُرسم **بعد** مناطق الإيماءات في الـ ZStack. تدرّجه العلوي:

```swift
LinearGradient(...)
    .ignoresSafeArea()
    .contentShape(Rectangle())     // ← يجعل كامل الشاشة قابلة للإصابة
    .onTapGesture { toggleControls() }
```

**لماذا يفشل**: التدرّج يملأ الـ ZStack كاملاً وهو أعلى من `gestureZone(isVolume:)`. لحظة ظهور
الأزرار (`showControls == true`) تتوقف — بصمت — كل هذه الوظائف:

- النقر المزدوج للتقديم/التأخير ±10 ثوانٍ (`handleTap` / `doubleTapSeek`، سطر 649-682)
- سحب عمودي للصوت (يسار) والسطوع (يمين) (`handleDrag`، سطر 597)
- السحب الأفقي لتبديل القنوات في البث المباشر (`endDrag` / `zap`، سطر 621-630)
- الضغط المطوّل لسرعة 2× (`startBoost`، سطر 584)

المستخدم يرى الأزرار ظاهرة فيظن الشاشة "نشطة"، وهي فعلياً الحالة الوحيدة التي تكون فيها
كل الإيماءات ميتة. التعليق في السطر 823-825 يعترف بالتغطية لكنه لم يُعِد الإيماءات الأخرى.

**الإصلاح الأدنى**: احذف `.contentShape(Rectangle()).onTapGesture` من التدرّج وأضف
`.allowsHitTesting(false)` عليه، ودع `gestureZone` يتولّى الإخفاء (`handleTap` يستدعي
`toggleControls()` أصلاً). الأزرار نفسها داخل `VStack` تبقى فوق مناطق الإيماءات وتأخذ نقراتها.

---

### B2 — إيماءات المشغّل بلا أي أولوية معلنة → تحرير الـ 2× يقلب الأزرار
**`PlayerView.swift:564-581`**

```swift
Color.clear
    .contentShape(Rectangle())
    .onTapGesture { handleTap(isVolume: isVolume) }
    .simultaneousGesture(DragGesture(minimumDistance: 14) ...)
    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 14, ...)
```

**لماذا يفشل**:
1. `TapGesture` في SwiftUI لا يملك حدّاً أعلى للمدة. بعد الضغط المطوّل 0.45s وتفعيل 2×، لحظة
   رفع الإصبع يبقى الـ tap مؤهلاً ويُنفَّذ `handleTap` → تنقلب طبقة الأزرار في **كل مرة**
   ينتهي فيها التسريع. لا يوجد `.exclusively(before:)` يمنع ذلك.
2. `maximumDistance: 14` للضغط المطوّل و`minimumDistance: 14` للسحب متطابقان. سحب صوت بطيء
   (أقل من 14pt خلال أول 0.45s) يشعل شارة الـ 2× قبل أن يبدأ السحب.
3. الحالة أسوأ لأن `handleTap` هو أيضاً كاشف النقر المزدوج: نقرة زائفة بعد تحرير الـ 2×
   تسجَّل في `lastTapTime`، فالنقرة الحقيقية التالية خلال 0.32s تُقرأ نقراً مزدوجاً وتقفز 10 ثوانٍ.

**الإصلاح الأدنى**:
```swift
.highPriorityGesture(
    LongPressGesture(minimumDuration: 0.45, maximumDistance: 10)
        .onEnded { _ in startBoost() }
        .exclusively(before: TapGesture().onEnded { handleTap(isVolume: isVolume) })
)
```
مع رفع `minimumDistance` للسحب إلى 20 لفصل النطاقين.

---

### B3 — «انقر المشغّل للتوسّع» غير موجود أصلاً (البث المباشر)
**`ContentViews.swift:342-344` (التوثيق) مقابل `677-713` (الكود)**

التعليق يقول حرفياً: *«Tapping a row swaps the preview channel; tapping the player expands to
fullscreen»*. لكن `InlineLiveEngineView.body` لا يحمل أي `onTapGesture` ولا `Button` على سطح
الفيديو — الطريقة الوحيدة للتوسّع هي زر زاوية **34×34** (سطر 701-707)، وهو نفسه دون 44pt.
`PlayerSurfaceView` (`PlayerEngine.swift:709-713`) هو `UIView` عادي بلا أي مستقبِل نقر.

هذا يُصيب المسارَين: الـ mini-player اللاصق على iPhone (`browser`, سطر 354) ولوح iPad
الأيمن (`padPlayerPane`, سطر 291).

**الإصلاح الأدنى**: على الـ `ZStack` في السطر 678 (تحت زر الزاوية في ترتيب الطبقات):
```swift
.contentShape(Rectangle())
.onTapGesture { onExpand() }
```

---

### B4 — بوّابة التحديث الإجباري تحبس المستخدم خلف زر مُعطَّل
**`ActivationView.swift:109-146`، تحديداً `131-136`**

```swift
GoldButton(title: L("update.button"), ...) { ... }
    .opacity((urlString?.isEmpty == false) ? 1 : 0.5)
    .disabled(urlString?.isEmpty != false)
```

`UpdateRequiredView` تُرسَم فوق كل المحتوى في `ActivationGate` (`ActivationView.swift:44-50`)
وهي **الشاشة الوحيدة**: لا زر إعادة فحص، لا زر إغلاق، ولا `dismiss`. إذا أرسل الخادم
`updateRequired = true` بدون `updateURL` (حقل اختياري) فالزر الوحيد على الشاشة معطَّل
والمستخدم محبوس نهائياً — إعادة التشغيل تعيد نفس الحالة، لأن `act.check()` لا يُستدعى من هنا.
`MaintenanceView` المجاورة (سطر 94) فيها زر Retry؛ هذه لا.

**الإصلاح الأدنى**: أضف `OutlineButton(title: L("common.retry")) { Task { await act.check() } }`
تحت الزر الأساسي، تماماً كما في `MaintenanceView`.

---

### B5 — `DownloadControl`: الإطار مطبَّق **خارج** الـ Button
**`ContentViews.swift:2735-2739` (صفحة الفيلم) و `ContentViews.swift:3075-3076` (صف الحلقة)**

```swift
DownloadControl(target: .movie(m), size: 18, showPercent: false)
    .frame(width: 48, height: 48)                       // ← خارج الـ Button
    .background(Circle().fill(Color.white.opacity(0.07)))
    .overlay(Circle().strokeBorder(...).allowsHitTesting(false))
```

**لماذا يفشل**: داخل `Downloads.swift:623-633` الـ Button مبنيّ هكذا:
```swift
Button(action: tap) { HStack { ... stateIcon(...) } }   // بلا frame وبلا contentShape
```
فمساحة اللمس الحقيقية هي **الأيقونة 18pt فقط**. الإطار 48pt والدائرة المضافين من الخارج
لا يوسّعان الإيماءة — يوسّعان خلية التخطيط فقط. وهذه بالضبط الحالة التي وثّقها المشروع
بنفسه في `DesignSystem.swift:2277-2283`
(*«Applied outside the Button they only widened the LAYOUT cell: the gesture stayed on the 44pt image»*).

أسوأ من ذلك: `Circle().fill(...)` في `.background` **قابل للإصابة** ويقع خلف الزر، فالنقرة على
الحلقة المحيطة تُبتلع ولا يحدث شيء — الزر يبدو "ميتاً" وليس "صغيراً".

وفي `episodeRow` النتيجة **فعل خاطئ**: الـ `DownloadControl` شقيق لزر الصف (سطر 3040-3069)،
فالنقرة القريبة تسقط على زر الصف و**تشغّل الحلقة** بدل تنزيلها.

**الإصلاح الأدنى**: انقل الإطار والخلفية والـ `contentShape` إلى داخل الـ label في
`DownloadControl`:
```swift
Button(action: tap) {
    HStack(spacing: 5) { ... }
        .frame(width: 48, height: 48)
        .contentShape(Circle())
}
```
واحذف المُعدِّلات من موقعَي الاستدعاء.

---

### B6 — `onLongPressGesture` و `contextMenu` على نفس الزر (بطاقة «تابع المشاهدة»)
**`HomeView.swift:1256-1268`**

```swift
Button(action: { ... }) { watchCardBody(item) }
    .buttonStyle(S8KButtonStyle())
    .onLongPressGesture { withAnimation { editingHistory = true } }
    .contextMenu { Button(role: .destructive) { removeHistory(item) } ... }
```

**لماذا يفشل**: `.contextMenu` يركّب `UIContextMenuInteraction` وهو مبنيّ على ضغط مطوّل،
و`.onLongPressGesture` يركّب ضغطاً مطوّلاً ثانياً على نفس العنصر بلا أي إعلان أولوية.
ضغطة مطوّلة واحدة تُشعل الاثنين: يدخل الصف وضع التحرير (تظهر ✕ الحمراء) **و** تنفتح القائمة
السياقية فوقه في اللحظة نفسها. أي مسار يختار المستخدم يترك الآخر في حالة معلّقة.

**الإصلاح الأدنى**: احذف `.onLongPressGesture` واترك `.contextMenu` وحده (فيه أصلاً خيار الحذف)،
أو انقل «وضع التحرير» إلى زر صريح في رأس القسم.

---

### B7 — بطاقات التأكيد `S8KConfirm` ليست modal — شريط التبويب العائم فوقها
**`BlankTVApp.swift:245-246` مقابل `HomeView.swift:733-746`، `SettingsView.swift:173-181`، `SettingsView.swift:516-524`**

```swift
// BlankTVApp.swift
ZStack(alignment: .bottom) {
    TabView(selection: $router.tab) { HomeView() ... SettingsProV2() ... }
    AppTabBar(selected: $router.tab)
        .zIndex(1)   // ← أعلى من كل صفحات التبويب
}
```

`S8KConfirm` (تسجيل الخروج، حذف الحساب، إعادة تحميل المحتوى) يُعرَض عبر `.overlay` **داخل**
صفحة التبويب. مهما بلغ `zIndex` المحلّي (20 في Home، 10 في Settings) فهو محصور داخل الـ TabView،
و`AppTabBar` شقيق لاحق بـ `zIndex(1)` **خارجه**. النتيجة: البُك الدائري 58pt أسفل اليمين
(`DesignSystem.swift:2127-2144`) يُرسَم **فوق** الحاجب الأسود ويبقى قابلاً للنقر، ويمكنه فتح
شريط التنقّل الكامل فوق نافذة تأكيد حذف الحساب.

**الإصلاح الأدنى**: انقل عرض `S8KConfirm` إلى `BlankTVApp.tabView` (نفس المكان الذي استُضيفت
فيه `router.homeSheet`) عبر حالة في `AppRouter`، أو أضِف `.zIndex(2)` للحاجب هناك.

---

### B8 — رأس `CategoryRow` ميّت في وسطه (المدخل الرئيسي لكل تصنيف)
**`ContentViews.swift:1339-1364`**

```swift
NavigationLink(value: category) {
    HStack(spacing: 8) {
        RoundedRectangle(...).frame(width: 3, height: 18)
        Text(category.name) ...
        if count > 0 { Text("\(count)") ... }
        Spacer()                                   // ← منطقة ميّتة
        HStack(spacing: 3) { Text(L("common.all")); Image("chevron.left") }
    }
    .padding(.horizontal, S8KSpace.xl)
}                                                  // ← لا contentShape
```

**لماذا يفشل**: لا يوجد `.contentShape(Rectangle())` ولا خلفية معتمة، فمساحة اللمس هي المحتوى
المرسوم فقط. الـ `Spacer` — وهو غالبية عرض الصف على أي هاتف — غير قابل للإصابة إطلاقاً.
المستخدم ينقر منتصف عنوان القسم فلا يحدث شيء. هذا هو الصف المستخدم في Home وMovies وSeries
وLive (`ContentViews.swift:479`, `1849`, `2378`) — أي على كل صفحة محتوى في التطبيق.

**الإصلاح الأدنى**: أضف `.contentShape(Rectangle())` بعد `.padding(.horizontal, S8KSpace.xl)`
داخل الـ label.

---

### B9 — قائمة `ellipsis` داخل صف يحمل `onTapGesture` يبدّل الحساب
**`SettingsView.swift:786-796` مقابل `803-804`**

```swift
Menu { Button(L("common.activate")) { switchTo(p) }
       Button(L("common.delete"), role: .destructive) { ... } }
label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }   // بلا خلفية/contentShape
...
.contentShape(Rectangle())
.onTapGesture { if !isActive { switchTo(p) } }                          // على كامل الصف
```

**لماذا يفشل**: الـ Menu label أيقونة `ellipsis` (~17pt) داخل إطار 30×30 فارغ. الزجاج الميّت
حول النقاط الثلاث يقع داخل مستطيل الـ `onTapGesture` للصف، فالنقرة القريبة **تبدّل قائمة التشغيل**
— وهي عملية ثقيلة تُعيد بناء الكتالوج كاملاً (`switchPlaylist` → `contentGen`) — بدل فتح القائمة.
لا سبيل للتراجع، والفعل غير مقصود.

**الإصلاح الأدنى**: داخل الـ label: `.frame(width: 44, height: 44).contentShape(Rectangle())`،
وحوّل نقرة الصف إلى `Button` صريح بدل `onTapGesture` على المستطيل الكامل.

---

## ثانياً: أهداف لمس أقل من 44×44 pt (62 موقعاً)

الأرقام هي المساحة **الفعلية** القابلة للإصابة بعد تطبيق قاعدة القياس أعلاه.
عمود «عند 320pt» يذكر ما يُرسَم به العنصر على أضيق عرض مدعوم.

| # | العنصر | file:line | المقاس الفعلي | عند 320pt |
|---|---|---|---|---|
| 1 | `SectionHeader` — «الكل» | `DesignSystem.swift:1196` | ~46×**13** | نفسه (ثابت) |
| 2 | «تابع المشاهدة» — عرض الكل | `HomeView.swift:1226` | ~60×**13** | نفسه |
| 3 | «تابع المشاهدة» — مسح الكل | `HomeView.swift:1217` | ~70×**14** | نفسه |
| 4 | «تابع المشاهدة» — تم | `HomeView.swift:1222` | ~28×**13** | نفسه |
| 5 | `AllHistoryView` — مسح الكل | `HomeView.swift:1584` | ~70×**14** | نفسه |
| 6 | `AllHistoryView` — إغلاق | `HomeView.swift:1592` | ~44×**17** | نفسه |
| 7 | `LockedCategoriesView` — قفل الكل | `SettingsView.swift:1296` | ~72×**14** | نفسه |
| 8 | `LockedCategoriesView` — فتح الكل | `SettingsView.swift:1301` | ~72×**14** | نفسه |
| 9 | `ParentalControlView` — نسخ رمز الاسترجاع | `SettingsView.swift:1216` | ~80×**17** | نفسه |
| 10 | `AccountSwitcherView` — إعادة تسمية | `SettingsView.swift:667` | ~60×**18** | نفسه |
| 11 | `AccountSwitcherView` — إغلاق | `SettingsView.swift:610` | **38×38** | نفسه |
| 12 | `PINEntryView` — نسيت الرمز | `SettingsView.swift:970` | ~50×**14** | نفسه |
| 13 | `PINEntryView` — إلغاء | `SettingsView.swift:973` | ~44×**17** | نفسه |
| 14 | `PlaylistsView` — قائمة `ellipsis` | `SettingsView.swift:793` | إطار 30×30، جليف ~17 | نفسه |
| 15 | `SettingsProV2` — إغلاق | `SettingsView.swift:292` | **38×38** | خامل (onClose = nil) |
| 16 | `SearchField` — مسح ⊗ | `ContentViews.swift:1438` | ~**17×17** | نفسه |
| 17 | `SearchView` — مسح ⊗ | `ContentViews.swift:3381` | ~**17×17** | نفسه |
| 18 | `SearchView` — إغلاق | `ContentViews.swift:3349` | ~44×**17** | نفسه |
| 19 | `SearchView` — رقائق النطاق (×4) | `ContentViews.swift:3398` | ارتفاع ~**33** | العرض/4 ≈ 62 |
| 20 | `ContentTitleBar` — رجوع | `ContentViews.swift:957` | **38×38** | نفسه |
| 21 | `ContentTitleBar` — ترتيب | `ContentViews.swift:934` | ~90×**38** | نفسه |
| 22 | `CategorySidebar` — ترتيب | `ContentViews.swift:1498` | **34×34** | لا يظهر (<720) |
| 23 | `ChannelRow` — مفضّلة | `ContentViews.swift:602` | جليف 15، إطار 30×30 فارغ | نفسه |
| 24 | `ChannelRow` — تشغيل | `ContentViews.swift:610` | **32×32** | نفسه |
| 25 | `miniInfoBar` — مفضّلة | `ContentViews.swift:442` | ~**16×16** | نفسه |
| 26 | `miniInfoBar` — ملء الشاشة | `ContentViews.swift:448` | **34×34** | نفسه |
| 27 | `channelInfoPane` — مفضّلة | `ContentViews.swift:312` | ~**17×17** | لا يظهر (<720) |
| 28 | `channelInfoPane` — ملء الشاشة | `ContentViews.swift:317` | ارتفاع ~**29** | لا يظهر |
| 29 | `InlineLiveEngineView` — توسّع | `ContentViews.swift:701` | **34×34** | نفسه |
| 30 | `InlineLiveEngineView` — إعادة محاولة | `ContentViews.swift:693` | ~70×**14** | نفسه |
| 31 | `AppTabBar` — مسح البحث ⊗ | `DesignSystem.swift:2083` | ~**16×16** | نفسه |
| 32 | `FilterPill` (مقاس الترجمة في المشغّل) | `DesignSystem.swift:1146` | ارتفاع ~**29** | نفسه |
| 33 | `GatewayModeSwitcher` — Xtream / M3U | `GatewayView.swift:192` | ارتفاع ~**38** | نفسه |
| 34 | `GatewayView` — بلاطة حساب | `GatewayView.swift:448` | **34×34** | نفسه |
| 35 | `GatewayView` — شيفرون اختيار الحساب | `GatewayView.swift:419` | **32×32** | نفسه |
| 36 | `GatewayView` — إغلاق علوي | `GatewayView.swift:374` | **40×40** | خامل (onClose = nil) |
| 37 | `GatewayView` — تجربة (Demo) | `GatewayView.swift:640` | ارتفاع ~**17** | نفسه |
| 38 | `GatewayView` — تحتاج مساعدة؟ | `GatewayView.swift:650` | ارتفاع ~**14** | نفسه |
| 39 | `GatewayView` — الشروط | `GatewayView.swift:658` | ارتفاع ~**13** | نفسه |
| 40 | `GatewayView` — الخصوصية | `GatewayView.swift:660` | ارتفاع ~**13** | نفسه |
| 41 | `LoginView` — الخصوصية | `AuthViews.swift:269` | ارتفاع ~**13** | نفسه |
| 42 | `LoginView` — الشروط | `AuthViews.swift:272` | ارتفاع ~**13** | نفسه |
| 43 | مشغّل — رجوع (`chevron.down`) | `PlayerView.swift:832` → `1003` | **38×38** | نفسه |
| 44 | مشغّل — PiP | `PlayerView.swift:849` → `1003` | **38×38** | نفسه |
| 45 | مشغّل — قفل الشاشة | `PlayerView.swift:852` → `1003` | **38×38** | نفسه |
| 46 | مشغّل — تدوير | `PlayerView.swift:855` → `1003` | **38×38** | نفسه |
| 47 | مشغّل — AirPlay | `PlayerView.swift:844` | **38×38** | نفسه |
| 48 | مشغّل — الحلقة/القناة السابقة | `PlayerView.swift:867` / `871` → `1011` | جليف ~**22×20** | نفسه |
| 49 | مشغّل — ‑10 ثوانٍ | `PlayerView.swift:874` → `1011` | جليف ~**28×25** | نفسه |
| 50 | مشغّل — +10 ثوانٍ | `PlayerView.swift:888` → `1011` | جليف ~**28×25** | نفسه |
| 51 | مشغّل — الحلقة/القناة التالية | `PlayerView.swift:891` / `895` → `1011` | جليف ~**22×20** | نفسه |
| 52 | مشغّل — إلغاء القفل | `PlayerView.swift:728` | ارتفاع ~**35** | نفسه |
| 53 | مشغّل — تخطّي المقدّمة | `PlayerView.swift:746` | ارتفاع ~**33** | نفسه |
| 54 | مشغّل — إلغاء الحلقة التالية | `PlayerView.swift:790` | ارتفاع ~**24** | نفسه |
| 55 | مشغّل — تشغيل الحلقة التالية | `PlayerView.swift:797` | ارتفاع ~**24** | نفسه |
| 56 | مشغّل — رجوع في شاشة الخطأ | `PlayerView.swift:483` → `1003` | **38×38** | نفسه |
| 57 | `DownloadControl` (كل المواضع) | `Downloads.swift:623` | جليف **18–22** | نفسه |
| 58 | `DownloadsView` — زر الحالة | `Downloads.swift:789` | جليف **28–30** | نفسه |
| 59 | `DownloadsView` — حذف (سلّة) | `Downloads.swift:779` | جليف ~**16** | نفسه |
| 60 | `HomeView` — ✕ حذف من السجل | `HomeView.swift:1272` | **24×24** | نفسه |
| 61 | `ChannelInfoSheet` — إغلاق | `HomeView.swift:1687` | ~44×**17** | نفسه |
| 62 | `Toggle` في الإعدادات (×6) | `SettingsView.swift:93` و `1365` | 51×**31** (مفتاح النظام) | نفسه |

**ملاحظات على الجدول**

- الأسوأ إطلاقاً هي الصفوف 1–13 و16–17 و30 و37–42: أزرار نصّية بلا `padding` وبلا `frame`
  وبلا `contentShape`، فارتفاعها هو ارتفاع سطر الخط (13–18pt) — أقل من **نصف** حدّ الـ HIG.
  الصف 1 (`SectionHeader` «الكل») هو المدخل الوحيد من الرئيسية إلى أقسام Movies/Series/Live.
- الصفوف 43–56 هي **طبقة تحكّم المشغّل بأكملها**: ولا زرّ واحد فيها يبلغ 44pt، وهي الشاشة
  التي يُستعمل فيها اللمس الأعمى أكثر من أي شاشة أخرى.
- الصف 62 مفتاح نظام قياسي من Apple (31pt) — لا يُعدّ عيباً، لكنه مذكور لاكتمال الجرد؛
  الصف كله في `SetUI.toggleRow` غير قابل للنقر (لا `contentShape` على الصف)، فالمستخدم مضطر
  لإصابة المفتاح نفسه بدل نقر الصف كما هو معتاد في iOS Settings.

---

## ثالثاً: AWKWARD

### A1 — حقل بحث شريط التبويب بلا نقرة عريضة للتركيز
**`DesignSystem.swift:2079-2108`**

الكبسولة تحمل `.padding(.horizontal, 14).padding(.vertical, 12)` و`.s8kGlass(Capsule)`، لكن لا
`contentShape` ولا `onTapGesture` يمنح التركيز. النقر على حشوة الكبسولة يصيب خلفية الـ material
(وهي قابلة للإصابة) ولا يفعل شيئاً؛ التركيز يتطلّب إصابة صندوق النص الضيّق نفسه. المشروع أصلح
هذا بالضبط لـ `S8KTextField` (`DesignSystem.swift:1123-1130`) ولم ينقله هنا.
**الإصلاح**: `.contentShape(Capsule()).onTapGesture { searchFocused = true }` على الكبسولة.

### A2 — صفّ إجراءات المشغّل يفيض عند 320pt
**`PlayerView.swift:974-995` و `1017-1043`**

6 رقائق × مربّع ثابت **48pt** + `spacing: 6` × 5 + `padding(.horizontal, S8KSpace.xl)` × 2
= 288 + 30 + 40 = **358pt**. عند 320pt (لوح Slide Over) كل خلية تحصل على
(320−40−30)/6 ≈ **41.7pt** بينما `RoundedRectangle().frame(width: 48, height: 48)` ثابت —
فالرقيقتان الطرفيتان (كتم الصوت، مؤقّت النوم) تُقصّان جزئياً عند الحافة وتفقدان جزءاً من هدفهما.
على iPhone SE (375pt) الحساب يعطي 50.8pt وهو يمرّ بالكاد (كما يوثّق التعليق في السطر 973).
**الإصلاح**: عند `.compactNarrow` انزل بالمربّع إلى 40pt أو لفّ الصف في `ScrollView(.horizontal)`.

### A3 — قائمة المواسم مُعطَّلة بلا إشارة بصرية
**`ContentViews.swift:2976-3003`**

`.disabled(vm.seasons.count < 2)` على `Menu` يحمل `Image(systemName: "chevron.down")` —
شيفرون يَعِد بمُنتقٍ. في مسلسل بموسم واحد يبقى الشيفرون ظاهراً بنفس اللون والحدود، والنقر
لا يفعل شيئاً. الحالة الوحيدة التي يفهم منها المستخدم «معطّل» هي غياب أي فرق.
**الإصلاح**: أخفِ الشيفرون كلياً عندما `vm.seasons.count < 2` (`if vm.seasons.count > 1 { Image(...) }`).

### A4 — نصّ التلميح يَعِد بسحبة لا تعمل (إعادة الترتيب)
**`ContentViews.swift:1145` مقابل `1174-1177` و `1181`**

`Text(L("reorder.drag_hint"))` يقول «اسحب لإعادة الترتيب، مرّر للإزالة»، بينما
`.environment(\.editMode, .constant(.active))` يُثبّت وضع التحرير دائماً — وفي هذا الوضع تعرض
القائمة زرّ ⊖ الأحمر وتصبح سحبة الحذف الجانبية غير مضمونة عبر إصدارات iOS.
**الإصلاح**: عدّل نصّ التلميح ليذكر زرّ ⊖ الأحمر، أو أزل `editMode` الثابت واستعمل
`.moveDisabled(false)` مع مقبض سحب صريح.

### A5 — تسلسل رقائق الترتيب داخل القائمة المحدودة الارتفاع
**`ContentViews.swift:1156-1182`**

قائمة «ترتيبك» محصورة بـ `arrangedHeight(geo.size.height)` (أقصاه 42% من الارتفاع). سحب عنصر
إلى ما بعد آخر صفّ مرئي لا يجد منطقة تمرير تلقائي كافية داخل قائمة ثابتة الارتفاع مُدرَجة داخل
`VStack` تحتها `ScrollView` منفصل — إعادة ترتيب قائمة من 30 تصنيفاً تصبح متعبة.

### A6 — `GatewayModeSwitcher` بارتفاع 38pt
**`GatewayView.swift:198-220`** — `padding(.vertical, 11)` + سطر `subhead` (13pt) ≈ 38pt.
الـ `contentShape(Rectangle())` صحيح (يُصلح الزوايا الميّتة للكبسولة) لكن الارتفاع دون الحدّ.
**الإصلاح**: `padding(.vertical, 14)`.

### A7 — صفوف `SetUI.toggleRow` غير قابلة للنقر ككل
**`SettingsView.swift:91-99`** — الصف لا يحمل `contentShape` ولا `onTapGesture`، بخلاف
`navRow` و`proRow` (السطران 75 و57) اللذين يحملانه. عدم اتساق: نصف صفوف الإعدادات قابل للنقر
بكامله والنصف الآخر لا.

### A8 — تأخير لمس الـ ScrollView مطبَّق على صفحة واحدة فقط
**`GatewayView.swift:120-137`، مستعمَل في `283` فقط**

`GWNoTouchDelay` يُطفئ `delaysContentTouches` على أقرب `UIScrollView`. كل زرّ آخر في التطبيق
داخل `ScrollView` (رقائق `toolRow`، بطاقات البوسترات، صفوف القنوات، صفوف الإعدادات، رقائق
`RankRail`، بطاقات الأبطال) ما يزال يدفع ~150ms قبل أن يُسلَّم اللمس — وهو بالضبط الإحساس
الذي وصفه المالك بـ «الأزرار ثقيلة». الحلّ موجود ومختبَر في الـ codebase وغير معمَّم.
**الإصلاح**: `.background(GWNoTouchDelay().frame(width: 0, height: 0))` داخل كل `ScrollView`
رئيسي، أو حوّله إلى `ViewModifier` مثل `.s8kInstantTouch()`.

---

## رابعاً: RISK

### R1 — عروض متعدّدة (`.sheet` / `.fullScreenCover`) على نفس العرض — 11 موقعاً
المشروع يوثّق القاعدة بنفسه في `HomeView.swift:651-656`:
*«SwiftUI only honors one .sheet / one .fullScreenCover per view reliably … Mixing .sheet +
.fullScreenCover on one view made SwiftUI silently swallow the sheet (the bell never opened)»*.
والقاعدة مخروقة في:

| العرض | المواقع |
|---|---|
| `LiveTVView` | `ContentViews.swift:203` (cover) + `204` + `208` (sheet ×2) |
| `MoviesView` | `ContentViews.swift:1638` + `1639` + `1643` |
| `SeriesListView` | `ContentViews.swift:2189` + `2190` + `2194` |
| `MovieDetailView` | `ContentViews.swift:2575` (cover) + `2576` (sheet) |
| `SeriesDetailView` | `ContentViews.swift:2827` + `2828` |
| `SearchView` | `ContentViews.swift:3335-3337` — **ثلاثة** `fullScreenCover` |
| `SettingsProV2` | `SettingsView.swift:183-185` — **ثلاثة** `fullScreenCover` |
| `SetAboutPage` | `SettingsView.swift:513-515` — ثلاثة `sheet` |
| `SetConnectionPage` | `SettingsView.swift:393-394` |
| `GatewayView` | `GatewayView.swift:328-330` — ثلاثة `sheet` |
| `SetAppPage` + `DownloadsView` | `SettingsView.swift:481` ثم `Downloads.swift:740` (cover داخل sheet) |

الأثر المحتمل: زرّ «التفاصيل»، أو «التصنيفات»، أو «الترتيب» يُنقر ولا ينفتح شيء — وهو عرَض
سبق أن ظهر في هذا المشروع (الجرس).

### R2 — `S8KSatellite` بلا `label` يمسح تسمية VoiceOver
**`DesignSystem.swift:401-418`** — `var label: String = ""` ثم `.accessibilityLabel(label)`.
تمرير سلسلة فارغة **يُلغي** التسمية المستنتَجة بدل أن يتركها. كل مواقع الاستدعاء الحالية
(`ContentViews.swift:2609, 2726, 2732, 2857, 2960, 2965`) تمرّر تسمية، لكن أول استدعاء ينسى
المعامل يُنتج زرّاً صامتاً تماماً في VoiceOver.
**الإصلاح**: `.accessibilityLabel(label.isEmpty ? Text(icon) : Text(label))` أو اجعل `label` إلزامياً.

### R3 — `S8KDetailsSheet` قد يُعرَض فوق `details` = nil → ورقة فارغة بلا مخرج
**`ContentViews.swift:2576-2581` و `2828-2833`**
```swift
.sheet(isPresented: $showDetails) { if let d = m.details { S8KDetailsSheet(...) } }
```
لو صار `details` = nil بينما الورقة مفتوحة (إعادة تحميل `SeriesDetailVM.load` تُسند `details`
بعد `seasons`)، فالورقة تصبح `EmptyView`: بلا محتوى، بلا `presentationDragIndicator`
(فهو داخل `S8KDetailsSheet`)، وبلا أي زرّ إغلاق. السحب للأسفل يبقى ممكناً لكن بلا أي مؤشّر بصري.
**الإصلاح**: بدّل إلى `.sheet(item:)` مربوطاً بـ `details` نفسه.

### R4 — مسبار الهندسة في `GatewayView` بلا `allowsHitTesting(false)`
**`GatewayView.swift:316-320`** — `GeometryReader { Color.clear ... }` داخل `.background`.
`Color.clear` **قابل للإصابة** في SwiftUI. هنا هو في الخلفية فلا يسرق شيئاً عملياً، لكن
`S8KMetricsRoot` يلفّ مسباريه بـ `.allowsHitTesting(false)` (`DesignSystem.swift:243`) — عدم
الاتساق يجعل نسخ النمط خطراً. نفس الملاحظة على `PlayerView.orientationReader`
(`PlayerView.swift:507`, `1049-1055`).

### R5 — `stopBoost` قد لا يُستدعى عند إلغاء الإيماءة
**`PlayerView.swift:578-580`** — `pressing: { if !pressing { stopBoost() } }`. إذا أُلغيت
الإيماءة (تقديم `fullScreenCover`، مكالمة واردة، تدوير) قد لا تصل `pressing = false`، فيبقى
`vm.boostSpeed(true)` نشطاً والمشغّل عالقاً على 2× بلا شارة.
**الإصلاح**: `stopBoost()` أيضاً في `.onDisappear` وفي `onChange(of: currentItem.id)`.

### R6 — الرجوع بالسحب معطَّل/متناقض على شاشات التصنيف
`ChannelListScreen` (`ContentViews.swift:809`)، `MoviePosterScreen` (`2023`)،
`SeriesPosterScreen` (`2520`) تستعمل `.navigationBarHidden(true)`، و`LiveTVView`/`MoviesView`/
`SeriesListView` تستعمل `.toolbar(.hidden, for: .navigationBar)`. إخفاء شريط التنقّل يُعطّل
تاريخياً `interactivePopGestureRecognizer`، ولا يوجد بديل مُعرَّف. المخرج الوحيد زرّ
`chevron.right` بمقاس 38×38 (الصف 20 في الجدول).

### R7 — الشيفرون الاتجاهي مثبَّت على `chevron.left` في كل مكان
`SetUI.navRow:65`، `FolderCard:1469`، `CategoryRow:1358`، `liveRow:3531`،
`sectionRowLabel:253`، `actionCard:1181`، `SectionHeader:1199`، `HomeView:1229`،
`row(_:)` في السجل، `notifHint:844`، `supportButtons:1426`، أوراق المشغّل `1205`.
صحيح للعربية (الأمام = يسار)، لكن `AppLang.allCases` يضمّ لغات LTR — وفيها تشير **كل** أسهم
الاستكشاف في التطبيق إلى الخلف. لا يوجد أي `s8kChevronForward` مقابل `s8kIsRTL`.

### R8 — كود ميّت يحمل عناصر تفاعلية (خطر إعادة إحياء بعيوبه)
`HomeView.navBar` (`HomeView.swift:890-937`، وبداخله `navBtn` بـ 40×40)،
`HomeView.announcementBar` (`1038`)، `HomeView.bannerSection` (`1060`، وفيه `onTapGesture`
على حاوية داخل `ScrollView`)، `HomeView.railsSection` (`1146`)،
`MoviesView.featuredBanner` (`ContentViews.swift:1785`)، `SeriesListView.featuredBanner` (`2316`)،
`ContentTabBar` (`1290`)، `SubscriptionsGateView` (`AuthViews.swift:458`).
لا شيء منها مُشار إليه من أي مكان.

### R9 — `heroContent` في الإعدادات إيماءة نقر بدل زر
**`SettingsView.swift:221-222`** — `.contentShape(Rectangle()).onTapGesture { showAccounts = true }`
على كتلة كاملة (الصورة الرمزية + الاسم + الخطّة + كبسولة «تبديل الحساب»). تعمل، لكن بلا سمة
`.isButton`، بلا ردّ فعل ضغط (`S8KButtonStyle`)، وبلا `.accessibilityLabel` — VoiceOver لا يعلن
أنها قابلة للتفعيل.

### R10 — طبقة قفل الشاشة تحجب فعلاً، لكن التوثيق يصف سلوكاً غير موجود
**`PlayerView.swift:454`** يقول *«tap anywhere reveals a single unlock button»*. الحقيقة:
عند `gestureLocked` تُحذف مناطق الإيماءات (`366`)، وتُعطَّل الأزرار (`452`)، وتُخفى بطاقات
التخطّي/الحلقة التالية (`458`, `463`) — فالحجب **صحيح وكامل**، لكن زرّ إلغاء القفل ظاهر دائماً
(لا كشف بالنقر ولا إخفاء تلقائي)، وهو **المخرج الوحيد من المشغّل** بارتفاع ~35pt.

### R11 — حاجب `S8KConfirm` يبتلع نقرات الحافة
**`DesignSystem.swift:2354-2361`** — البطاقة تُغلَّف بـ `.padding(28)` **بعد** الخلفية،
فالـ 28pt المحيطة شفافة وتقع على الحاجب → نقرة قريبة من حافة البطاقة تُلغي الحوار.
مقبول في «إعادة التحميل»، محفوف في «حذف الحساب».

---

## خامساً: إمكانية الوصول — 26 عنصراً أيقونياً بلا `.accessibilityLabel`

التطبيق كله يحتوي **11** عبارة `.accessibilityLabel` (تحقّق: `grep -rn accessibilityLabel *.swift`).
العناصر الأيقونية التالية بلا أي نص مرئي وبلا تسمية — VoiceOver سيقرؤها باسم رمز SF Symbol
أو لن يقرأ شيئاً:

| # | العنصر | file:line |
|---|---|---|
| 1 | مشغّل — رجوع (`chevron.down`) | `PlayerView.swift:832` |
| 2 | مشغّل — PiP | `PlayerView.swift:849` |
| 3 | مشغّل — قفل الشاشة | `PlayerView.swift:852` |
| 4 | مشغّل — تدوير | `PlayerView.swift:855` |
| 5 | مشغّل — رجوع في شاشة الخطأ | `PlayerView.swift:483` |
| 6 | مشغّل — تشغيل/إيقاف مؤقت | `PlayerView.swift:876` |
| 7 | مشغّل — السابق (حلقة/قناة) | `PlayerView.swift:867` / `871` |
| 8 | مشغّل — ‑10 ثوانٍ | `PlayerView.swift:874` |
| 9 | مشغّل — +10 ثوانٍ | `PlayerView.swift:888` |
| 10 | مشغّل — التالي (حلقة/قناة) | `PlayerView.swift:891` / `895` |
| 11 | مشغّل — `Slider` التقديم | `PlayerView.swift:915` (بلا `accessibilityValue` بالوقت) |
| 12 | `ChannelRow` — مفضّلة | `ContentViews.swift:602` |
| 13 | `ChannelRow` — تشغيل | `ContentViews.swift:610` |
| 14 | `SearchField` — مسح | `ContentViews.swift:1438` |
| 15 | `SearchView` — مسح | `ContentViews.swift:3381` |
| 16 | `ContentTitleBar` — رجوع | `ContentViews.swift:957` |
| 17 | `CategorySidebar` — ترتيب | `ContentViews.swift:1498` |
| 18 | `miniInfoBar` — مفضّلة | `ContentViews.swift:442` |
| 19 | `miniInfoBar` — ملء الشاشة | `ContentViews.swift:448` |
| 20 | `channelInfoPane` — مفضّلة | `ContentViews.swift:312` |
| 21 | `InlineLiveEngineView` — توسّع | `ContentViews.swift:701` |
| 22 | `AppTabBar` — مسح البحث | `DesignSystem.swift:2083` |
| 23 | `HomeView` — ✕ حذف من السجل | `HomeView.swift:1272` |
| 24 | `HeroCarouselView` — مفضّلة | `HomeView.swift:390` |
| 25 | `HeroCarouselView` — تشغيل | `HomeView.swift:404` |
| 26 | `DownloadControl` (الحالة كاملة) | `Downloads.swift:623` |

إضافات: `DownloadsView` — زر الحالة (`Downloads.swift:789`) والسلّة (`779`)،
`AccountSwitcherView` — إغلاق (`SettingsView.swift:610`)، `SettingsProV2` — إغلاق (`292`)،
`PlaylistsView` — `ellipsis` و`+` و`arrow.clockwise` (`793`, `754`, `748`).

**ملاحظة خاصة على `DownloadControl`**: أيقونته تتغيّر عبر خمس حالات
(`arrow.down.circle` / `hourglass` / حلقة تقدّم / `play.fill` / `exclamationmark…`) بلا أي
تسمية ولا `accessibilityValue` بالنسبة المئوية — مستخدم VoiceOver لا يمكنه معرفة حالة التنزيل إطلاقاً.

---

## سادساً: RTL و iPad

### RTL — الطبقة اللمسية
التطبيق يفرض `.environment(\.layoutDirection, .leftToRight)` عالمياً (`BlankTVApp.swift:166`)
ويعكس يدوياً عبر `s8kIsRTL` / `s8kTextAlign` / `s8kFrameAlign`.

**سليم** (المرسوم = المُصاب): `closeBar` في صفحتَي الفيلم/المسلسل (`ContentViews.swift:2607-2611`,
`2855-2859`)، `actionRow` (`2702-2710`, `2951-2969`)، `seasonBar` (`2978-3007`)،
`episodeRow` (`3039-3064`)، `AppTabBar` (يفرض LTR صراحةً في `DesignSystem.swift:2050` فيبقى
البُك في الزاوية اليمنى السفلية في كل اللغات).

**عيوب**:
1. **زرّ إظهار كلمة المرور خارج نطاق قلب الاتجاه** — `DesignSystem.swift:1059-1100`.
   `.environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)` مطبَّق على `Group` النص
   وحده (سطر 1071)، بينما زرّ العين شقيق خارجه. في العربية يبقى الزرّ على اليمين الفيزيائي —
   أي عند **بداية** النص لا نهايته. الإطار يطابق الرسم (لا خطأ إصابة) لكن الموضع خاطئ لغوياً.
2. **تعارض اتجاه الرجوع** — نظام iOS يضع إيماءة الـ pop على الحافة **اليسرى** الفيزيائية لأن
   `layoutDirection` مفروض LTR، بينما زرّ الرجوع الخاص بالتطبيق (`chevron.right`) على الحافة
   **اليمنى** (`ContentViews.swift:919`). المستخدم العربي يتلقّى إشارتَي رجوع متناقضتين.
3. **الشيفرون الأمامي مثبَّت `chevron.left`** — راجع R7.
4. **اتجاه التقديم في المشغّل صحيح**: `play.fill` و`forward/backward` لا تنعكس (تعليق مقصود في
   `DesignSystem.swift:371`)، والنقر المزدوج يمين = تقديم (`handleTap:650`) — وهذا هو العرف
   الصحيح لأدوات النقل الإعلامي حتى في RTL. لا تغيير مطلوب.

### iPad و Split View
- `useSplit(width) = isPad && width >= 720` (`ContentViews.swift:173`, `1583`, `2140`) —
  يسقط إلى تخطيط الهاتف تحت 720pt، فلا تنزلق عناصر تحت الشريط الجانبي. **سليم**.
- `ExpandedNavBar` عند 320pt: 6 دوائر ×44 + `spacing 2`×5 + `padding 6`×2 = **286pt** من
  **288pt** متاحة (`320 − S8KSpace.lg × 2`). يمرّ بـ 2pt فقط — أي عنصر سابع يقصّ الشريط.
  موثّق في `DesignSystem.swift:2228-2231`. **RISK مقبول لكنه هشّ**.
- **صفّ إجراءات المشغّل يفيض عند 320pt** — راجع A2. هذا العيب الوحيد المؤكّد في هذا المحور.
- `MovieDetailView.actionRow` يتكدّس عند `.compactNarrow` (`ContentViews.swift:2692-2711`)
  ليتجنّب قصّ `DownloadControl`. **سليم ومقصود**.
- `padPlayerPane` بلا `bottomClearance` (`ContentViews.swift:288-307`) — لا يوجد محتوى تحت
  الشريط العائم فيه، فلا مشكلة.

---

## سابعاً: ما تم التحقق منه وهو سليم (لا يحتاج تعديلاً)

هذه بنود طُلب فحصها صراحةً وخرجت نظيفة:

1. **حرّاس الحاويات الكسولة (النقطة 11)** — `Color.clear.frame(height: 1).onAppear`:
   `ContentViews.swift:276-279` (قنوات iPad)، `535-538` (`ChannelList`)،
   `1942-1945` (`PosterGrid`)، `2486-2489` (`SeriesGrid`).
   `Color.clear` قابل للإصابة في SwiftUI، لكن ارتفاعه **1pt** فلا يعترض أي لمسة فعلية،
   ولا يُدخل نفسه بين عنصرين قابلين للنقر. في `LazyVGrid` يستهلك **خلية شبكة واحدة** في الصف
   الأخير (بوستر أقل في آخر صف) — أثر بصري لا لمسي.
2. **الأوراق والأغطية (النقطة 10)** — لا يوجد `.interactiveDismissDisabled` في أي ملف
   (تحقّق بالبحث الشامل). كل ورقة تحمل زرّ Close في `toolbar` أو `presentationDragIndicator`.
   `S8KDetailsSheet` (`DesignSystem.swift:628-632`) يحمل مؤشّر السحب و`.presentationDetents`
   يشمل `.large` كاحتياط، ومحتواه داخل `ScrollView` فلا يخرج زرّ الإعلان الترويجي عن المتناول.
   الاستثناء الوحيد هو R3 أعلاه.
3. **طبقة الخطأ القاتل في المشغّل** — `PlayerView.swift:473-505` مُرسَمة **آخر** عنصر في الـ ZStack
   مع `Color.black.opacity(0.9).contentShape(Rectangle())` تمتصّ اللمس، وزرّ Retry وزرّ الرجوع
   فوقها. الإصلاح الموثّق في السطر 355-357 صحيح ومُطبَّق.
4. **الطبقات الزخرفية تحمل `allowsHitTesting(false)`** حيثما يجب:
   `S8KPinnedPageBar` التدرّج (`DesignSystem.swift:700`)، `S8KSectionBar` كاملاً (`672`)،
   `S8KWatermark` (`1621`)، `S8KShimmer` (`1510`)، حدود `s8kGlass` الاحتياطية (`2412`, `2419`)،
   مسبارا `S8KMetricsRoot` (`243`)، ضباب الشريط العلوي للرئيسية (`HomeView.swift:1010`)،
   شارة الإشعارات (`HomeView.swift:929`, `DesignSystem.swift:2168`)، لوحة صفحات التفاصيل
   (`ContentViews.swift:2601`, `2850`)، تدرّج بطاقة البطل (`HomeView.swift:355`)،
   شريط تقدّم `S8KPlayCapsule` (`DesignSystem.swift:390`)، حدود `S8KTextField` (`1121`).
5. **`S8KTextField`** — الحلّ الصحيح المرجعي في المشروع: زرّ العين **44×44** مع `contentShape`
   (`DesignSystem.swift:1091-1099`)، و`contentShape(Rectangle()) + onTapGesture` على الصفّ كاملاً
   بعد الخلفية وقبل الإيماءة (`1129-1130`)، وحدّ زخرفي غير قابل للإصابة. **هذا هو النمط الذي
   يجب تعميمه على كل عناصر الجدول في القسم الثاني**.
6. **`ExpandedNavBar.navCircle`** — `frame(maxWidth: .infinity) + contentShape(Rectangle())`
   **داخل** الـ label (`DesignSystem.swift:2282-2283`) مع تعليق يشرح السبب، وبلا `offset`
   أثناء الظهور المتدرّج (`2287-2289`). سليم تماماً.
7. **`KeyboardDismisser`** (`BlankTVApp.swift:109-132`) — `cancelsTouchesInView = false`
   و`shouldRecognizeSimultaneouslyWith → true`، فلا يبتلع أي زر. سليم.
8. **`toolButton`** في Live/Movies/Series (`ContentViews.swift:423-435`, `1768-1780`, `2300-2312`)
   — 44×44 + خلفية دائرة + `contentShape(Circle())` + `accessibilityLabel`. مطابق للمعيار.
9. **`collapsedPuck`** (`DesignSystem.swift:2127-2147`) — 58×58 + `contentShape(Circle())`
   + `accessibilityLabel`. سليم.
10. **`S8KPlayCapsule`** (`DesignSystem.swift:363-397`) — `minHeight: 54` + `contentShape(Capsule)`
    وشريط التقدّم `allowsHitTesting(false)`. سليم.
11. **`PINEntryView.pinPad`** (`SettingsView.swift:987-1005`) — مفاتيح بارتفاع 62pt وخلفية
    معتمة و`frame(maxWidth: .infinity)`. سليم.
12. **قفل الشاشة يحجب فعلاً** — راجع R10: الحجب كامل وصحيح، الملاحظة على حجم زرّ الفكّ فقط.

---

## الأولويات المقترحة للإصلاح

| الترتيب | البند | الجهد |
|---|---|---|
| 1 | **B1** — `allowsHitTesting(false)` على تدرّج طبقة التحكّم | سطر واحد |
| 2 | **B5** — نقل الإطار داخل `DownloadControl` | ~5 أسطر |
| 3 | **B8** — `contentShape(Rectangle())` على رأس `CategoryRow` | سطر واحد |
| 4 | **B4** — زرّ إعادة فحص في `UpdateRequiredView` | ~4 أسطر |
| 5 | **B2** — `highPriorityGesture(longPress.exclusively(before: tap))` | ~6 أسطر |
| 6 | **B6** — حذف `onLongPressGesture` المكرّر | سطر واحد |
| 7 | **B9** + **B3** — `contentShape`/`frame(44)` + نقرة توسيع المشغّل | ~4 أسطر |
| 8 | **B7** — نقل `S8KConfirm` إلى `BlankTVApp.tabView` | ~20 سطراً |
| 9 | الجدول (62 هدفاً) — تعميم نمط `S8KTextField`/`toolButton` | متوسط |
| 10 | 26 `accessibilityLabel` | آلي تقريباً |
| 11 | **A8** — تعميم `GWNoTouchDelay` كـ `ViewModifier` | صغير، أثر كبير |
