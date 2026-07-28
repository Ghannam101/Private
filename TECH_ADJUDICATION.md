# تحكيم تقني — ما نتبنّاه من التطبيق المرجعي وما نستبدله بالأحدث
**مراجعة هندسية مستقلة · 2026-07-27 · Blank Prime (SwiftUI · iOS 17.0 minimum · Xcode 26 · CocoaPods)**

> **القاعدة الحاكمة (بكلمات المالك):** لكل تقنية فكّرنا في نقلها من التطبيق المرجعي — ابحث عن أحدث ما وصلت إليه الصناعة **بالتوازي**. إن كان أسلوب المرجع هو الأفضل فعلاً، تبنَّه. وإن وُجد أحدث وأفضل، **تجاهل المرجع ونفّذ الأحدث**.
>
> **قيود التزمتُ بها:** مصدر `Strong8K/iOS` للقراءة فقط — لم يُكتب فيه شيء. ولم يُعدَّل أي ملف مصدري في `blankstor`. الملف الوحيد المكتوب هو هذا الملف.

---

## 0. جدول الأحكام

| # | البند | الحكم | لماذا باختصار | جهد | خطر |
|---|---|---|---|---|---|
| **1** | إعادة بناء فهرس FTS عند القراءة من ذاكرة القرص | **ADOPT MODIFIED** | الفكرة صحيحة، لكن التنفيذ الصحيح ليس أمر `rebuild` في FTS5 بل إعادة تعبئة `CatalogDB` من الكاش، خارج الخيط الرئيسي، بحارس `isSearchable` لا `isPopulated` | ~12 سطراً · 30 د | منخفض |
| **2** | معالجة `.readyToPlay` / جاهزية المشغّل | **ADOPT AS-IS** ✅ | KVO مع `[.initial, .new]` **هو** الممارسة الحديثة في 2026؛ لا توجد `AsyncSequence` لـ `AVPlayerItem.status`، و`Observation` غير قابل للتطبيق أصلاً على أنواع ObjC. ما نُفّذ صحيح — مع تحفّظين موثَّقين | 0 (مُنفَّذ) | — |
| **3** | `saveProgress()` عند `load()` | **ADOPT AS-IS** ✅ | إصلاح تدفّق بيانات لا علاقة له بأي API؛ لا شيء أحدث يتفوّق عليه. راجعتُ التنفيذ: آمن (يلتقط القيم في متغيّرات محلّية قبل `Task`) | 0 (مُنفَّذ) | — |
| **4** | تحصين سجلّ التنزيلات بـ `FailableItem` | **ADOPT MODIFIED** ⚠ | الغلاف نفسه **إلزامي وليس اختياراً** (`UnkeyedDecodingContainer` لا يتقدّم عند الفشل)، ولا بديل أوّلياً في Foundation. **لكن ما نُفّذ ناقص**: لا مغلّف نسخة، ولا عزل للملف التالف — و`persist()` لا تزال تكتب `[]` فوق مكتبة المستخدم | +45 سطراً · ساعتان | منخفض |
| **5** | رايتا AirPlay + حارس الفيديو | **ADOPT MODIFIED** | الخصائص الثلاث لا تزال حيّة وغير مهجورة في 2026، فتبنَّها. **لكن الرايات وحدها لا تكفي**: بدون `AVAudioSession.RouteSharingPolicy.longFormVideo` توثّق Apple أن الفيديو **يبقى محلّياً** ولا يذهب إلى AirPlay أصلاً | ~20 سطراً · ساعتان | منخفض |
| **6** | `DatabasePool` بدل `DatabaseQueue` | **ADOPT MODIFIED** ⚠ | توثيق GRDB يصف حالتنا حرفياً. **لكن: قِس أولاً** — معيار GRDB الرسمي يُدخل 50 ألف صف في ~0.06 ث، و`Codable` يضاعفها ستّاً؛ قد يكون الاختناق في الترميز لا في الاتصال. وثلاثة شروط مسبقة إلزامية، أحدها (`0xdead10cc`) **يقتل التطبيق** | ~35 سطراً · 3–5 ساعات | **متوسط** |
| **7** | نقل رابط القائمة إلى الـ Keychain | **ADOPT MODIFIED** | لا توجد أي API حديثة تلغي `SecItem` (تحقّقتُ من 4 مصادر Apple). **لكن اقسِم الرابط** بدل نقله كاملاً، والخلل الأكبر ليس `m3uURL` بل أن `Keychain` عندنا يثبّت `WhenUnlockedThisDeviceOnly` لكل المفاتيح | ~60 سطراً · 3 ساعات | متوسط |
| **8** | طبقة قياس جودة التشغيل (QoE) | **REPLACE WITH NEWER** 🔴 | **لا تنقل `Telemetry.swift`.** Apple شحنت `AVMetrics` (WWDC 2024 · جلسة 10113) — `AsyncSequence` بأحداث مُصنَّفة تحسب لك ما كان المرجع يجمّعه يدوياً. والأهم: `accessLog()`/`errorLog()` — أساس نهج المرجع — **مهجورتان اعتباراً من 27.0** | ~130 سطراً · 4 ساعات | منخفض |
| **ج-أ** | *جديد* — فخّ `automaticallyWaitsToMinimizeStalling` على البث المباشر | **خلل حيّ — أصلحه** 🔴 | Apple توثّق أن `false` تعني: عند نفاد المخزن ينزل المعدّل إلى 0 **ولا يستأنف ذاتياً**. مخرجنا الوحيد اليوم هو مراقب 30 ثانية ثم انتقال إلى VLC | ~8 أسطر · ساعة | منخفض |
| **ج-ب** | *جديد* — دورة حياة `AVAudioSession` | **ابنِه** | مقاطعة/تغيير مسار/إعادة تهيئة خدمات الوسائط — لا يعالجها أي من التطبيقين. أعلى أثر ملموس للمستخدم لكل سطر | ~80 سطراً · 3 ساعات | منخفض |
| **ج-ج** | *جديد* — `longFormVideo` route-sharing policy | **ابنِه** | مذكور في البند 5، وهو **الشرط** الذي بدونه لا تعمل رايات AirPlay | ~6 أسطر · 30 د | منخفض |

**السطر الواحد:** من البنود الثمانية — **بندان صحيحان كما نُفّذا** (2 و3)، **أربعة تُتبنّى معدَّلة** (1 و4 و5 و7)، **واحد له شروط مسبقة إلزامية** (6)، **وواحد يُستبدل بالكامل بواجهة Apple أحدث** (8). ولا يوجد بند واحد ينبغي رفضه كلّياً.

---

## 0.1 تحذير عن المصادر — اقرأه قبل أن تثق بأي سطر أدناه

- **ميزانية البحث النصّي على الويب نفدت في هذه الجلسة.** كل ما يلي مأخوذ **مباشرةً** من مصادر أوّلية عبر جلب الصفحات: واجهة توثيق Apple بصيغة JSON (`developer.apple.com/tutorials/data/...`)، وصفحات جلسات WWDC، ومستودعات GitHub الخام (`swiftlang/swift-foundation`, `groue/GRDB.swift`)، وواجهات GitHub/CocoaPods البرمجية.
- **النتيجة:** التغطية من **توثيق Apple الرسمي ممتازة**، ومن **مدوّنات الهندسة المستقلّة شبه معدومة**. حيث لم أجد توثيقاً رسمياً، أقول ذلك صراحةً بعبارة **«غير متحقَّق منه»** بدل أن أملأ الفراغ.
- **اكتشاف يغيّر إطار الحديث كلّه:** توثيق Apple الحالي يعرض رموزاً موسومة **«Beta, iOS 27.0+»**، وعدداً من رموز AVFoundation **مهجورة اعتباراً من 27.0**. أي أن **WWDC 2026 وقع وiOS 27 هو الـ SDK الحالي**، بينما `PROJECT_HANDOFF.md` و`codemagic.yaml` يفترضان Xcode 26 / iOS 26 SDK. **تحقّق من إصدار Xcode المثبَّت في `codemagic.yaml` قبل تنفيذ البند 8.**
- **هدف النشر عندنا `iOS 17.0`** (`Podfile:2`, `post_install`). كل ما هو iOS 18+ فما فوق يجب أن يُسيَّج بـ `if #available`, ويجب أن يبقى للـ iOS 17 مسار عامل.

---

# البند 1 — إعادة بناء فهرس FTS عند القراءة من ذاكرة القرص

## الحكم: **ADOPT MODIFIED**

## المشكلة المتحقَّق منها في شيفرتنا
`PlaylistService._load` (`BlankTV/Core.swift:1736–1742`) يعود من ذاكرة القرص فوراً:

```swift
if !force, let cached = CatalogDiskCache.load(scope: urlString) {
    content = cached
    if let xd = XtreamDirect.parse(urlString) { xtream = xd }
    return cached                    // ← لا شيء يلمس CatalogDB هنا
}
```

بينما التعبئة الوحيدة للـ SQLite تقع في المسار **الشبكي** فقط (`Core.swift:1762`):
```swift
Task.detached(priority: .utility) { CatalogDB.save(built, scope: urlString) }
```

فبعد أي إقلاع بارد داخل نافذة الـ 12 ساعة، يعود `CatalogDB.isSearchable(scope:)` (`CatalogDB.swift:198`) بـ `false`، ويسقط `SearchVM` إلى المسار الاحتياطي في الذاكرة على الكتالوج كاملاً. الفهرس الذي بنيناه معطَّل في **أكثر الحالات شيوعاً**.

## هل هناك ما هو أحدث؟
**نعم، وهو فخّ — تجنّبه.** SQLite تقدّم أمراً أصيلاً لإعادة بناء فهرس FTS5:
```sql
INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild');
```
توثيق SQLite (§6.12) حرفياً: *«This command first deletes the entire full-text index, then rebuilds it based on the contents of the table or content table. **It is not available with contentless tables.**»* ([sqlite.org/fts5.html](https://sqlite.org/fts5.html))

**وهو *متاح* لنا لكنه *عديم الجدوى* هنا، ولسبب دقيق:** جدولنا `catalog_fts` (`CatalogDB.swift:124–130`) جدول FTS5 **عاديّ يخزّن محتواه بنفسه** — ليس `contentless` (فالأمر متاح إذن) وليس `content=` خارجي المحتوى. أي أن `rebuild` سيعيد بناء الفهرس **من صفوف الجدول نفسه**. وفي سيناريو الإقلاع البارد من الكاش تلك الصفوف **غير موجودة أصلاً** — لم يكتبها أحد. النتيجة: عملية مسحٍ باهظة تنتهي إلى فهرس فارغ.

كذلك: `rebuild` **لا يغيّر المُجزِّئ (tokenizer)**. لو أردنا يوماً تعديل `unicode61 remove_diacritics 2`، فالسبيل هو `DROP` + `CREATE` + إعادة تعبئة، لا `rebuild`. (وGRDB نفسها **لا توثّق `rebuild` إطلاقاً** — بحثتُ كامل `Documentation/` و`Documentation.docc/`: صفر ذكر. المصدر هنا SQLite لا GRDB.)

> **الخلاصة:** لا يوجد API أحدث يتفوّق هنا. المطلوب ليس «إعادة بناء فهرس»، بل **إعادة تعبئة المخزن من الكاش**. أسلوب المرجع صحيح في الجوهر، ويحتاج ثلاثة تعديلات.

## التعديلات الثلاثة
1. **الحارس هو `isSearchable` لا `isPopulated`.** `isPopulated` (`CatalogDB.swift:170`) يفحص جداول `Chan/Mov/Ser` فقط. `save()` تكتب الصفوف **ثم** الفهرس في نفس المعاملة (`CatalogDB.swift:293–324`)، فمعاملة أُجهضت (انقطاع، قتل النظام للتطبيق) قد تترك حالة تجتاز `isPopulated` وتفشل في البحث. `isSearchable` (`:198`) يستعلم عن `catalog_fts` مباشرة — وهو السؤال الصحيح.
2. **خارج الخيط الرئيسي وخارج المُمثِّل**، بنفس نمط السطر 1762 تماماً (`Task.detached(priority: .utility)`)، حتى لا يتأخّر عودة `_load` ولا يُحجز `PlaylistService`.
3. **لا تكتب كتالوجاً جزئياً.** نفس القاعدة التي تعلّمناها في P7 (`PROJECT_HANDOFF.md §9`): إن حمل الكاش راية `isPartial` فلا يُسجَّل كحقيقة.

## سكتش التنفيذ — `BlankTV/Core.swift`، داخل `PlaylistService._load(force:)`

```swift
if !force, let cached = CatalogDiskCache.load(scope: urlString) {
    content = cached
    if let xd = XtreamDirect.parse(urlString) { xtream = xd }
    // The SQLite store + FTS5 index are only ever written on a NETWORK fetch, so a
    // cold start served from the 12-hour disk cache leaves isSearchable() == false
    // and drops SearchVM onto the whole-catalogue in-memory fallback — exactly what
    // the index exists to eliminate. Repopulate off-actor; the operation is
    // idempotent and never blocks this return.
    if !cached.isPartial, !CatalogDB.isSearchable(scope: urlString) {
        Task.detached(priority: .utility) { CatalogDB.save(cached, scope: urlString) }
    }
    return cached
}
```

**تعارض يجب الانتباه له:** هذا البند يزيد عدد استدعاءات `CatalogDB.save()` — وهي معاملة واحدة ضخمة تُدخل 20–50 ألف صف. **نفّذ هذا البند بعد أو مع البند 6 (تقطيع المعاملة)**، وإلا صار كل إقلاع بارد يحمل معاملة كتابة عملاقة، وهو بالضبط ملف الخطر في `0xdead10cc`.

- **الجهد:** ~12 سطراً · 30 دقيقة. **الخطر:** منخفض. **المصادر:** [SQLite FTS5](https://sqlite.org/fts5.html)

---

# البند 2 — معالجة `.readyToPlay` / جاهزية المشغّل

## الحكم: **ADOPT AS-IS** ✅ — ما نُفّذ **هو** الممارسة الحديثة

## ما نُفّذ عندنا فعلاً (`BlankTV/PlayerEngine.swift:436–476`)
```swift
statusObs = pItem.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
    let status = it.status
    let dur = it.duration.seconds
    Task { @MainActor in
        guard let self else { return }
        switch status {
        case .readyToPlay:
            self.isLoading = false
            …
            self.avPlayer.playImmediately(atRate: 1.0)
```
وكذلك `bufferEmptyObs` و`likelyKeepUpObs` بنفس `[.initial, .new]`.

## البحث — هل هناك أحدث؟ ثلاثة أسئلة، ثلاث إجابات قاطعة

**أ) هل توجد `AsyncSequence` لحالة `AVPlayerItem`؟ — لا.**
بروتوكول [`AVAsynchronousKeyValueLoading`](https://developer.apple.com/documentation/avfoundation/avasynchronouskeyvalueloading) (أي `await asset.load(.isPlayable)`) مطبَّق على **الأصول والمسارات فقط**: `AVAsset`, `AVURLAsset`, `AVAssetTrack`, `AVComposition`, `AVMetadataItem`. **`AVPlayerItem` ليس من المطبِّقين.** فـ `load(_:)` أداة ممتازة للتحقّق المسبق من الأصل، لكنها **لا تستطيع** أن تحلّ محلّ جاهزية عنصر المشغّل. لا يوجد أي مسار async/await لـ `AVPlayerItem.status` حتى iOS 27.

**ب) هل يصلح `Observation` / `@Observable`؟ — لا، وبشكل بنيوي لا يقبل الالتفاف.**
`@Observable` [ماكرو مُلحَق بالنوع](https://developer.apple.com/documentation/observation/observable()) — يجب أن يُكتب **على تصريح النوع نفسه**. `AVPlayerItem` مصرَّح بـ Objective-C داخل AVFoundation. و`withObservationTracking` لا يتتبّع إلا خصائص تمرّ عبر `ObservationRegistrar` مُولَّد، ولا يملكه أي نوع في AVFoundation. و[SE-0395](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md) يعرّف Observation كبديل لـ KVO **في أنواع Swift الجديدة**، ولا يقدّم أي مسار تحديث للأصناف ObjC القائمة.
**العمارة الصحيحة هي بالضبط ما نفعله:** KVO على AVFoundation ← نموذج عرضنا ← SwiftUI.

**ج) هل `Publisher.values` (جسر Combine) أفضل؟ — لا، مكافئ سطحياً.**
`NSObject.publisher(for:options:).values` ([iOS 15+](https://developer.apple.com/documentation/combine/publisher/values-1dm9r)) يعطي `AsyncPublisher`، لكنه **KVO تحته** بنفس الدلالات تماماً. يشتري صياغة أجمل ولا شيء غير ذلك، ويضيف تبعية على Combine في مسار حرج.

## هل `.initial` هو الحلّ الصحيح لمشكلة «العنصر جاهز قبل أن نراقبه»؟ — نعم، بنصّ Apple
توثيق [`NSKeyValueObservingOptions.initial`](https://developer.apple.com/documentation/foundation/nskeyvalueobservingoptions/initial) حرفياً: الإشعار *«should be sent to the observer **immediately, before the observer registration method even returns**»*.
وسابقة Apple نفسها تستعمل النمط ذاته في شيفرتها المرجعية الحالية: في [Adopting Picture in Picture in a Custom Player](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player) تكتب Apple حرفياً `pipController.observe(\.isPictureInPicturePossible, options: [.initial, .new])`.

## تحفّظان يجب توثيقهما في الشيفرة (لا تغييرَ مطلوباً الآن)

**التحفّظ 1 — خطر إعادة الدخول (re-entrancy)، ونحن ناجون منه بالمصادفة.**
لأن `.initial` يُطلَق **قبل عودة `observe(...)`**، فإن `self.statusObs` لا يزال `nil` داخل ذلك النداء الأول. شيفرتنا تنجو لأن المعالج يقفز فوراً إلى `Task { @MainActor in … }`. **لكن هذا هشّ:** أي تعديل مستقبلي يقرأ أو يُبطل `statusObs` **من داخل** المعالج سيعمل «أحياناً». أضِف تعليقاً صريحاً عند `PlayerEngine.swift:443`:
> `// .initial fires SYNCHRONOUSLY before observe() returns → statusObs is still nil inside this first callback. Never read or invalidate statusObs from here.`

وملاحظة ثانية: `.initial` يُطلَق **على الخيط الذي تسجّل منه**. `observe(pItem)` تُستدعى من `setup()` — تأكّد أنها دائماً على `@MainActor`.

**التحفّظ 2 — `playImmediately(atRate:)` يفتح ثقباً في القياس، وهذا يمسّ البند 8 مباشرة.**
توثيق [`playImmediately(atRate:)`](https://developer.apple.com/documentation/avfoundation/avplayer/playimmediately(atrate:)) حرفياً: إن كان المخزن غير كافٍ، *«the player will behave as if it has encountered a stall during playback, **except that no `playbackStalledNotification` will be posted**»*.
أي أن قرارنا «البدء الفوري» **يخفي التوقّفات المبكّرة عن أي طبقة قياس**. قبل أن تثق بـ `stallCount` في البند 8، تحقّق على الجهاز هل `AVMetricPlayerItemStallEvent` يُكبَت هو الآخر. (**غير موثَّق لدى Apple — يجب قياسه ميدانياً.**)

**وملاحظة صغيرة:** السطر يمرّر `atRate: 1.0` ثابتاً ويتجاهل `self.rate` (تفضيل سرعة المستخدم). غيّره إلى `self.rate` — سطر واحد.

## ماذا عن `preroll(atRate:)`؟ — لا تستعمله كبديل، إنه **يشترط** فحصنا
توثيق [`preroll(atRate:completionHandler:)`](https://developer.apple.com/documentation/avfoundation/avplayer/preroll(atrate:completionhandler:)) ينصّ على شرطين صارمين: *«If the player object is not ready to play (its `status` property is not `readyToPlay`), this method **throws an exception**»* — أي **انهيار**، لا خطأ يُعاد. و*«The current rate for the playback item should always be 0 prior to calling this method.»*
فالترتيب إلزامي: `readyToPlay` ← `preroll` ← ضبط المعدّل. `preroll` ليست بديلاً عن فحص الجاهزية، بل **مستهلكة له**.

- **الجهد:** 0 (مُنفَّذ) + سطران توثيق + سطر `self.rate`. **الخطر:** لا شيء.

---

# البند 3 — `saveProgress()` عند `load()`

## الحكم: **ADOPT AS-IS** ✅

## ما نُفّذ (`BlankTV/PlayerEngine.swift:363–368`)
```swift
// Save the OUTGOING item first. cleanup() saves on teardown, but load() is the
// zap / next-episode path and never calls it …
saveProgress()
setItem(newItem)
```

## التحكيم
هذا **ليس سؤال API على الإطلاق**. لا توجد واجهة في iOS 17/18/26/27 تحفظ موضع المشاهدة نيابةً عنك؛ هذا منطق تطبيقٍ خالص وإصلاح تدفّق بيانات. لا يوجد شيء «أحدث» يمكن أن يتفوّق عليه. أسلوب المرجع صحيح ونقطة.

## تدقيق سلامة التنفيذ (وهو ما يستحق الوقت هنا)
راجعتُ `saveProgress()` عند `PlayerEngine.swift:203–207`:
```swift
func saveProgress() {
    guard duration > 1 else { return }
    let p = progress, dur = duration, it = item      // ← لقطة محلّية
    Task { @MainActor in … }
}
```
**التقاط القيم في متغيّرات محلّية *قبل* `Task` هو الجزء الحرج، وهو صحيح عندنا.** لو قرأ الإغلاق `self.progress` و`self.item` داخل `Task` لكان قد قرأهما **بعد** أن نفّذ `load()` سطر `setItem(newItem)` — فيحفظ موضع الحلقة الخارجة تحت هوية الحلقة الداخلة. وهذا هو بالضبط الخطأ الذي يقع فيه أغلب من ينفّذ هذا الإصلاح. **لا تُعِد ترتيب هذه الأسطر أبداً.**

**نقطة يقظة واحدة:** الحارس `duration > 1` يعني أن الانتقال إلى الحلقة التالية **قبل** أن يُعرَف طول الحلقة الحالية لا يحفظ شيئاً. هذا سلوك صحيح (لا نريد كتابة موضع على مدّة صفرية)، لكنه يعني أن «انتقالاً سريعاً جداً» لا يزال يفقد الموضع. مقبول.

- **الجهد:** 0 (مُنفَّذ). **الخطر:** لا شيء. **لا تغيير مطلوب.**

---

# البند 4 — تحصين سجلّ التنزيلات (`FailableItem`)

## الحكم: **ADOPT MODIFIED** ⚠ — الغلاف صحيح وإلزامي، لكن ما نُفّذ **ناقص وما زال يمكنه محو مكتبة المستخدم**

## ما نُفّذ (`BlankTV/Downloads.swift:473–483`)
```swift
private struct FailableItem: Decodable {
    let value: DownloadItem?
    init(from decoder: Decoder) throws { value = try? DownloadItem(from: decoder) }
}
private static func loadItems() -> [DownloadItem] {
    guard let url = storeURL(), let data = try? Data(contentsOf: url) else { return [] }
    if let arr = try? JSONDecoder().decode([FailableItem].self, from: data) {
        return arr.compactMap(\.value)
    }
    return []
}
```

## التحكيم — الجزء الجيّد أولاً: الغلاف **ليس اختياراً أسلوبياً، بل شرطٌ بنيوي**

هذا أهم اكتشاف في البند، وهو موثَّق من Apple نصّاً ومن الشيفرة المُنفَّذة:

**توثيق Apple** لـ [`UnkeyedDecodingContainer.currentIndex`](https://developer.apple.com/documentation/swift/unkeyeddecodingcontainer/currentindex) حرفياً: *«The current decoding index of the container … **Incremented after every successful decode call.**»*

**وشيفرة `swift-foundation` الحالية** (`main`, 2026) تؤكّدها بنيوياً:
```swift
mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let value = try self.peekNextValue(ofType: type)
    let result = try impl.unwrap(value, as: type, for: codingPathNode, currentIndexKey)
    advanceToNextValue()      // ← بعد الـ unwrap القابل للرمي
    return result
}
```
إن رمى `unwrap`، لا يُبلَغ `advanceToNextValue()` أبداً و`currentIndex` لا يتحرّك. أي أن حلقة `while !container.isAtEnd { do { … } catch { continue } }` **تدور إلى الأبد** — تعليق، لا انهيار، وهو أصعب في التشخيص بمراتب.

و**لا توجد أي API للتخطّي**: عدّدتُ كامل أعضاء `UnkeyedDecodingContainer` — لا `skip()` ولا `moveNext()`. اقتُرحت `skip()` على منتديات Swift في 2019 (PR ‏#1012 + swift#23707)، وأيّدها Itai Ferber من Apple نصّاً، **ولم تُشحن قط**. وطلب «الفكّ المتساهل» ([SR-5953 / swift-corelibs-foundation#4414](https://github.com/swiftlang/swift-corelibs-foundation/issues/4414)) مفتوح **منذ 2017 بلا حراك**.

**هل يوجد بديل أوّليّ؟ — لا. قُرئت شيفرة `swift-foundation` على `main` مباشرةً:** لا توجد أي راية `lossy`/`partial`/«تخطَّ عند الخطأ» في `JSONDecoder.swift`؛ استراتيجياته الوحيدة هي `Date`/`Data`/`NonConformingFloat`/`Key`. ولا شيء في Swift 6.4 يمسّ Codable. `BetterCodable` (`@LossyArray`) مهجورة عملياً (آخر دفعة نوفمبر 2023، 54 مسألة مفتوحة). **الغلاف اليدوي، بـ ~15 سطراً، هو الجواب الصحيح في 2026.**

✅ **إذن: `FailableItem` عندنا صحيح، وتنفيذه بـ `try? DownloadItem(from: decoder)` مكافئ لصيغة `singleValueContainer().decode(_:)` الشائعة، و — الأهم — `init` لا يرمي أبداً، فالحاوية تتقدّم. الجزء الصعب أُصيب.**

## الجزء الناقص — وهو خطير

**أ) لا يزال بإمكان `persist()` أن تمحو مكتبة المستخدم بالكامل.**
`loadItems()` تعود بـ `[]` عند فشل الفكّ **الكلّي** (ملف مبتور بسبب كتابة انقطعت، JSON مشوّه، ملف بحجم صفر). عندها:
- `init()` (`Downloads.swift:83–88`) يضبط `items = []`؛
- `reconcileOnLaunch()` تخرج فوراً (حارسها لا يجد عناصر)؛
- ثم **أوّل** `persist()` — من `enqueue` (`:173`) أو `remove` (`:376`) أو `setState` (`:423`) — تكتب `[]` فوق الملف نهائياً.
النتيجة **مطابقة تماماً للخلل الذي أصلحناه للتوّ**، مرتفعةً درجة واحدة: ملفات بحجم غيغابايتات تبقى يتيمة على القرص بلا أي مسار للوصول إليها.

**ب) لا مغلّف نسخة.** نكتب مصفوفة عارية `[DownloadItem]`. لا يوجد مكان لرقم مخطّط، فلا يمكن ترحيل التنسيق لاحقاً إلا بالتخمين.

**ج) الاقتران البنيوي هو المرض الحقيقي.** `DownloadItem` يحمل حمولات `Movie?`/`Episode?`/`Series?` كاملة (`Downloads.swift:34–36`). أي أن **متانة مكتبة تنزيلات المستخدم مربوطة بثبات مخطّط نموذج البيانات الوصفية كلّه**. الفكّ المتساهل يحوّل «محواً كلّياً» إلى «محو جزئي» — لكنه **لا يفكّ الاقتران**. وهذا يتعارض مباشرة مع القاعدة الحاكمة في [[metadata-agnostic-design]]: سجلّ التنزيلات هو **حالة مشغّل**، لا بيانات وصفية.

## سكتش التنفيذ — `BlankTV/Downloads.swift`

**المرحلة الأولى (افعلها الآن، ~45 سطراً):** مغلّف نسخة + عزل الملف التالف + نسخة احتياطية.

```swift
// MARK: Persistence
private struct Envelope: Codable { var v: Int; var items: [DownloadItem] }
private static let schemaVersion = 2

private func persist() {
    guard let url = Self.storeURL(),
          let data = try? JSONEncoder().encode(Envelope(v: Self.schemaVersion, items: items))
    else { return }
    // Keep the previous good manifest: a torn write is a likelier cause of total
    // loss than any schema change, and .atomic only protects THIS write.
    if let old = try? Data(contentsOf: url) {
        try? old.write(to: url.appendingPathExtension("bak"), options: .atomic)
    }
    try? data.write(to: url, options: .atomic)
}

private struct FailableItem: Decodable {
    let value: DownloadItem?
    let error: Error?          // kept so schema drift is observable, not silent
    init(from decoder: Decoder) throws {          // MUST never throw — see below
        do    { value = try DownloadItem(from: decoder); error = nil }
        catch { value = nil; self.error = error }
    }
}

private static func loadItems() -> [DownloadItem] {
    guard let url = storeURL() else { return [] }
    guard let data = try? Data(contentsOf: url) else { return [] }

    // v2 envelope, then the bare-array v1 layout, then the .bak, then quarantine.
    if let env = try? JSONDecoder().decode(EnvelopeFailable.self, from: data) {
        return env.items.compactMap(\.value)
    }
    if let arr = try? JSONDecoder().decode([FailableItem].self, from: data) {
        return arr.compactMap(\.value)            // legacy v1 file
    }
    if let bak = try? Data(contentsOf: url.appendingPathExtension("bak")),
       let arr = try? JSONDecoder().decode([FailableItem].self, from: bak) {
        return arr.compactMap(\.value)
    }
    // NOTHING parsed. Do NOT return [] and let the next persist() overwrite the
    // user's library — move the file aside so it stays recoverable by support.
    try? FileManager.default.moveItem(
        at: url, to: url.deletingLastPathComponent()
                       .appendingPathComponent("downloads.corrupt.json"))
    return []
}
private struct EnvelopeFailable: Decodable { let v: Int; let items: [FailableItem] }
```

> **ثابتٌ لا يجوز كسره — وثّقه فوق `FailableItem`:**
> `// init(from:) MUST NOT throw. If it does, UnkeyedDecodingContainer.currentIndex never advances (Apple: "Incremented after every successful decode call") and the decode HANGS — an infinite loop, not a crash.`

> **قيدٌ يذكره المرجع نفسه ويجب أن يصير قاعدة مكتوبة:** كل حقل يُضاف مستقبلاً إلى `Movie`/`Episode`/`Series` يجب أن يكون **اختيارياً أو بقيمة افتراضية**، وإلا سقطت كل التنزيلات القديمة عنصراً عنصراً — وهو ما يجعل الفكّ المتساهل يبدو ناجحاً بينما المكتبة تفرغ.

**المرحلة الثانية (الإصلاح الحقيقي، لاحقاً):** فُكّ الاقتران. اجعل `DownloadItem` يحمل `{ id, kind, fileURL, bytes, state, title, posterURL, addedAt }` **ولا شيء غيرها**، وأعِد ترطيب البيانات الوصفية من `CatalogDB` وقت العرض. عندها يستطيع `Movie` أن يتطوّر بحرّية والتنزيلات محصّنة بنيوياً. وإن أردت الحلّ الأقوى: **صفّ واحد لكل تنزيل في GRDB** — نملك التبعية بالفعل، ونملك انضباط `DatabaseMigrator` بالفعل، وصفٌّ تالف لا يستطيع أن يُسقط بقيّة الصفوف. **لا تستعمل SwiftData هنا**: مكدّس تخزين ثانٍ إلى جانب GRDB، وترحيلاته أشدّ صرامة مما تبدو (إضافة حقل **غير اختياري** تتطلّب `VersionedSchema` كاملاً — وهو بعينه نمط الفشل الذي بدأ منه كل هذا).

- **الجهد:** المرحلة 1 ~45 سطراً · ساعتان. المرحلة 2 يوم. **الخطر:** منخفض في المرحلة 1.

---

# البند 5 — رايتا AirPlay + حارس الفيديو

## الحكم: **ADOPT MODIFIED** — تبنَّ الرايات، **وأضِف الشرط الذي بدونه لا تعمل**

## التحقّق من الأحدثية
- [`allowsExternalPlayback`](https://developer.apple.com/documentation/avfoundation/avplayer/allowsexternalplayback) (iOS 6.0+، الافتراضي `true`)، `usesExternalPlaybackWhileExternalScreenIsActive`، `isExternalPlaybackActive`، `externalPlaybackVideoGravity` — **كلها حيّة وغير مهجورة في التوثيق الحالي.**
- **`AVPlayer.externalPlaybackType` غير موجود.** رابطه يعطي 404 ولا يظهر في أي مجموعة «See Also». **لا تكتب شيفرة تعتمد عليه** (ذكرته بعض المصادر الثانوية — تجاهلها).
- [`AVRoutePickerView`](https://developer.apple.com/documentation/avkit/avroutepickerview) (iOS 11+) غير مهجور و**لا يوجد له مكافئ SwiftUI أصيل**؛ توثيق Apple نفسه يعرضه ملفوفاً في `UIViewRepresentable`. للفيديو: اضبط `prioritizesVideoDevices = true`.
- **لا توجد أي جلسة WWDC عن AirPlay للفيديو في 2024/2025/2026.** عدّدتُ كتالوج جلسات [Audio & Video](https://developer.apple.com/videos/audio-video/) كاملاً — لا شيء. هذه نتيجة سلبية مؤكَّدة، لا فجوة بحث.

> **إذن: لا يوجد أحدث. أسلوب المرجع صحيح — لكنه ناقص.**

## ما ينقص المرجع (والذي هو الأهم فعلياً)

**`AVAudioSession.RouteSharingPolicy.longFormVideo`.** توثيق Apple لهذه القيمة ([iOS 13+](https://developer.apple.com/documentation/avfaudio/avaudiosession/routesharingpolicy/longformvideo)) ينصّ على أن الفيديو الذي **لا** يستعمل سياسة المشاركة هذه *«remains local to the playback device even when the system is routing long-form video content to AirPlay»*.

**بعبارة أوضح:** تضبط `allowsExternalPlayback = true` وتعرض منتقي AirPlay وتظنّ أنك أنجزت الميزة — بينما النظام يُبقي الفيديو على الجهاز لأن جلسة الصوت لم تُعلن أنها محتوى فيديو طويل. **لتطبيق IPTV هذا شبه إلزامي.** ويحتاج جزأين:
1. مفتاح `AVInitialRouteSharingPolicy = LongFormVideo` في `Info.plist`؛
2. `try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)` في `configureAudio()` (`BlankTVApp.swift:146`).

## حارس الفيديو — وهنا أوافق المرجع بلا تحفّظ
تقرير التمايز (§الطبقة 1، البند 8) محقّ: شرط `presentationSize != .zero` **يُبطل الفحص أصلاً** — بثّ HEVC داخل TS يملك مسار فيديو مُعلَناً لكنه لا يُعرَض. ويجب تخطّي الانتقال إلى VLC حين `isExternalPlaybackActive == true`، لأن AirPlay يوقف تسليم الإطارات محلّياً وهو سلوك سليم لا عطل.

## سكتش التنفيذ

**`BlankTV/BlankTVApp.swift` — `configureAudio()`:**
```swift
// Without .longFormVideo the system keeps our video LOCAL even while it is routing
// long-form video to AirPlay (Apple, RouteSharingPolicy.longFormVideo). The
// AVInitialRouteSharingPolicy Info.plist key must be set to LongFormVideo to match.
try? AVAudioSession.sharedInstance()
    .setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
```

**`BlankTV/PlayerEngine.swift` — في `setup()` بجوار السطر 347:**
```swift
avPlayer.allowsExternalPlayback = true
avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
```

**`BlankTV/PlayerEngine.swift` — `startVideoWatchdog()` (حوالي `:417–429`):**
```swift
// AirPlay stops local frame delivery by design — that is not a dead video track.
guard !avPlayer.isExternalPlaybackActive else { return }
// presentationSize != .zero was gating this check into uselessness: HEVC-in-TS
// DOES advertise a video track while rendering nothing, which is the exact case
// the watchdog exists to catch.
…
self.errorMsg = L("player.err.no_video")   // لا تكتب نصاً عربياً حرفياً هنا
```

**تنبيه اتّساق:** منتقي AirPlay معروض من `VLCPlayer.swift:682–691`، و**MobileVLCKit لا يدعم AirPlay للفيديو**. أي أن الواجهة تَعِد بميزة على المحرّك الخطأ. اربط ظهور المنتقي بمحرّك `AVPlayerVM` فقط، أو اجعل اختياره يفرض الانتقال إلى المحرّك العتادي.

- **الجهد:** ~20 سطراً + مفتاح `Info.plist` · ساعتان. **الخطر:** منخفض (لكن يحتاج تحقّقاً على جهاز AirPlay حقيقي).

---

# البند 6 — `DatabasePool` بدل `DatabaseQueue`

## الحكم: **ADOPT MODIFIED** ⚠ — **مع ثلاثة شروط مسبقة إلزامية. لا تشحنه بدونها.**

## الوضع الحالي
`CatalogDB.swift:28–36` — اتصال واحد متسلسل:
```swift
static let dbQueue: DatabaseQueue? = {
    let dir = try FileManager.default.url(for: .applicationSupportDirectory, …)
    let q = try DatabaseQueue(path: dir.appendingPathComponent("catalog.sqlite").path)
    try migrator.migrate(q); return q
}()
```
وكل بحث FTS (`:188`) وكل قراءة مُصفَّحة تنتظر خلف `save()` (`:290–326`) — وهي **معاملة واحدة** تحذف نطاقاً كاملاً ثم تُدخل 20–50 ألف صف + نفس العدد في `catalog_fts`.

## ما تقوله GRDB نفسها — وجملةٌ تصف حالتنا حرفياً

الجملة الحاسمة، من دليل `Concurrency` قسم «Concurrent Thinking»:

> ***«Applications that perform slow write transactions (when saving a lot of data from a remote server, for example) may want to replace their queue with a pool so that the reads that feed their user interface can run in parallel.»***

هذا **وصفٌ حرفيّ لحالتنا**: استيراد كتالوج جُملي من خادم بعيد يحجب قراءات الواجهة. وحين سُئل groue في [مسألة #1790](https://github.com/groue/GRDB.swift/issues/1790#issuecomment-3070795943) «هل أجرّب WAL؟» أجاب بسطر واحد: *«Many apps use the WAL mode indeed. **Just replace `DatabaseQueue` with `DatabasePool`.**»*

- التوصية الافتراضية المحافظة موجودة في `DatabaseConnections.md`: *«If you are not sure, choose `DatabaseQueue`. You will always be able to switch to `DatabasePool` later.»* — **لكن «لست متأكّداً» لم تعد تنطبق علينا**: نملك مشكلة تنازع مشخَّصة، وهي المُشغِّل الموثَّق للتبديل.
- والتبديل **متوافق مصدرياً**: *«you can write robust code that works equally well with both `DatabaseQueue` and `DatabasePool`. This allows your app to switch between queues and pools, at your convenience.»*

**متطلَّب عملي أوّل (ميكانيكي):** غيِّر نوع الخاصية إلى `any DatabaseWriter` بدل `DatabaseQueue` — عندها يصير التبديل سطراً واحداً في موضع الإنشاء.

## ⚠ لكن أوّلاً: **قِس قبل أن تبدّل** — قد لا يكون الـ pool هو الحلّ أصلاً

معيار الأداء الرسمي لـ GRDB ([wiki/Performance](https://github.com/groue/GRDB.swift/wiki/Performance)) يُدخل **50,000 صف — مقاسنا بالضبط**:

| الطريقة | زمن إدراج 50 ألف صف |
|---|---|
| سجلّات محسَّنة (بلا `Codable`) | **~0.06 ثانية** — مساوٍ لواجهة SQLite C الخام |
| سجلّات `Codable` | **~0.38 ثانية** — **ستّة أضعاف**، والفارق كلّه تكلفة ترميز `Codable` |

**نحن على مسار `Codable`**: `Chan`/`Mov`/`Ser` سجلّات GRDB و`save()` تستدعي `insert(db)` لكل صفّ (`CatalogDB.swift:298–312`).

> 🔴 **الاستنتاج الذي يقلب أولوية البند:** إن كانت `save()` عندنا أبطأ بكثير من ~0.5 ثانية لـ 50 ألف صف، فالاختناق **في الترميز لا في نوع الاتصال**، والـ pool يعالج عَرَضاً لا سبباً. **قِس أولاً في وضع Release** — يحذّر groue صراحةً: *«development builds are slowed down by the liberal use of assertions. Performance tests are only relevant in the release configuration.»*

**والإصلاح الحقيقي إن ثبت ذلك** — وصفة groue نفسها من [مسألة #926](https://github.com/groue/GRDB.swift/issues/926#issuecomment-786089593)، بأسماء GRDB 6 (تحقّقتُ منها في وسم `v6.24.1`):

```swift
// بدل insert(db) لكل صف: عبارة واحدة مُحضَّرة + وسائط بلا تحقّق.
// groue: "Huge batch inserts, unfortunately, are not on the good side" of the
// ergonomic Codable path — every record re-encodes and rebuilds its own SQL.
let stmt = try db.makeStatement(sql: """
    INSERT INTO movie (scope, id, name, …) VALUES (?, ?, ?, …)
    """)
for x in c.movies {
    stmt.setUncheckedArguments([scope, x.id, x.name, …])   // Statement.swift:329 في 6.24.1
    try stmt.execute()
}
```
ونفس الشيء لحلقة `catalog_fts` (`CatalogDB.swift:318–321`) التي **تجمّع 50 ألف عبارة SQL** اليوم. وإن تكرّر النداء، استعمل `db.cachedStatement(sql:)` بدل `makeStatement`.

**هذا التعديل وحده قد يُغني عن الـ pool تماماً.** لا تشحن البند 6 قبل هذا القياس.

**وإن قرّرت أن الـ pool لازم فعلاً، فالمرجع تبنّاه بلا أيٍّ من الشروط التالية — وهذا ما لا نكرّره.**

## الشرط الأول (الأخطر) — `0xdead10cc` سيقتل التطبيق

توثيق Apple كما تقتبسه GRDB حرفياً: *«**0xDEAD10CC** (pronounced "dead lock"): the operating system terminated the app because it held on to a file lock or SQLite database lock during suspension.»*

نحن نطلق `Task.detached(priority: .utility) { CatalogDB.save(built, scope:) }` (`Core.swift:1762`) — إدراج 20–50 ألف صف. **صغِّر التطبيق أثناءه فيعلّقه النظام وهو ممسكٌ بالقفل ← قتلٌ فوري.** ومع `DatabasePool` تزداد الحساسية (اتصالات أكثر، أقفال `-wal`/`-shm` أكثر).

وتوصية Apple في [توثيق SIGKILL](https://developer.apple.com/documentation/xcode/sigkill) حرفياً: *«Request additional background execution time on the main thread with `beginBackgroundTask(withName:expirationHandler:)`. **Make this request well before starting to write to the file** in order to complete those operations and relinquish the lock before the app suspends.»* — لاحظ **«قبل بدء الكتابة»**، لا أثناءها.

آلية GRDB الرسمية (متوفّرة في 6.24.1 — تحقّقتُ من وسم الإصدار):
```swift
var config = Configuration()
config.observesSuspensionNotifications = true      // GRDB: "in each process that writes"
config.defaultTransactionKind = .immediate         // ← ضروري على 6.x، انظر أدناه
let pool = try DatabasePool(path: …, configuration: config)
```
ثم يُنشَر `Database.suspendNotification` عند دخول الخلفية و`Database.resumeNotification` عند العودة. وتحذّر GRDB من الثمن: *«you will get `SQLITE_INTERRUPT` (code 9) or `SQLITE_ABORT` (code 4) errors, with messages "Database is suspended", "Transaction was aborted", or "interrupted"»* — أي أن **كل موضع `try? q.read`/`q.write` عندنا يجب أن يتحمّل فشلاً جديداً**. هذا صحيح اليوم لأن كلها ملفوفة بـ `try?`، **لكن `save()` يجب ألّا تعتبر الفشل نجاحاً وتكتب `catalog_meta`** — وهو ما تفعله اليوم داخل نفس المعاملة، فالإجهاض يُرجع الجميع، جيّد.

**`defaultTransactionKind = .immediate` ليس تفصيلاً:** في GRDB 6 الافتراضي `DEFERRED`، وقد أرشد groue مُبلِّغ [مسألة #1538](https://github.com/groue/GRDB.swift/issues/1538) إلى ضبطه صراحةً كي تعمل آلية كشف التعليق أصلاً. (في GRDB 7 صار تلقائياً: قراءات `DEFERRED` وكتابات `IMMEDIATE`.)

🔴 **والعقبة الحقيقية:** `BlankTVApp.swift:170–174` **لا يملك فرع `.background` إطلاقاً**، و`beginBackgroundTask` غير موجودة في التطبيق كلّه. **إذن الشرط الأول ليس إعداداً بل شيفرة جديدة، والبند 6 محجوب عليها.**

⚠ **وكن صادقاً مع حدود هذه الآلية:** GRDB نفسها توسم مانع `0xdead10cc` بـ **🔥 EXPERIMENTAL**، وقال groue في #1538 إنه *«makes **optimistic** assumptions today»* — الفحص يقع **مرّة واحدة قبل الخطوة الأولى** لا عند كل خطوة، وأضاف: *«**Maybe such apps should perform iterations in batches**»* — أي أنه يصف حالتنا ويصف الحلّ (الشرط الثالث أدناه). **لا تعامل `observesSuspensionNotifications = true` كضمانة.**

**تصحيح لسوء فهم شائع:** حماية البيانات (Data Protection) مشكلة **منفصلة** عن `0xdead10cc`، وكثيراً ما تُخلط بها. أخطاء `SQLITE_IOERR (10)` / `SQLITE_AUTH (23)` سببها تعذّر الوصول للملف على جهاز مقفل — **ونحن في مأمن منها افتراضياً**: توثيق Apple لأمن المنصّة ينصّ على أن `Protected Until First User Authentication` هي *«the default class for all third-party app data»*. **الإجراء الصحيح هو ألّا تضبط `.complete` على ملف قاعدة البيانات أبداً** — لا أن «تُصلح» شيئاً. وGRDB **لا تملك أي API لحماية الملفات**؛ عدّدتُ كل خصائص `Configuration` في وسم `v6.24.1`، لا وجود لها. المسؤولية على `FileManager` وعلى **المجلّد** (الشرط الثاني).

## الشرط الثاني — المجلّد المخصّص لملف قاعدة البيانات
GRDB تنصّ حرفياً: ***«Regardless of the database location, it is recommended that you wrap the database file inside a dedicated directory. This directory will bundle the main database file and its related SQLite temporary files together. […] On iOS, the directory can be encrypted with data protection, in order to help securing all database files in one shot.»***

السبب: WAL يضيف `-wal` و`-shm` بجوار الملف الأصلي، وSQLite تنشئ ملفّات مؤقّتة أخرى. اليوم `catalog.sqlite` يجلس عارياً في `Application Support`؛ بعد التحويل يصبح ثلاثة ملفات على الأقلّ — وأي منطق «احذف قاعدة البيانات» أو «انقلها» سيترك ملفّات يتيمة تفسد الحالة. وقد شدّد groue على المبدأ نفسه في [#1153](https://github.com/groue/GRDB.swift/issues/1153): *«Setting protection attributes on the database file only does not protect the (many) temporary files created by SQLite. Inconsistent protection does not look like a sane setup.»*

**انقل الملف إلى `Application Support/catalog/db.sqlite` مع ترحيل صامت لمرة واحدة، وطبّق `isExcludedFromBackup` على المجلّد لا على الملف.**
⚠ *صراحةً: `isExcludedFromBackup` **لا تذكرها GRDB إطلاقاً** — بحثتُ الـ README وكامل `Documentation/` و`Documentation.docc/`، صفر نتيجة. توصيتي بتطبيقها على المجلّد **استنتاجٌ** من توصية المجلّد نفسها، لا موقف موثَّق لـ GRDB.*

## الشرط الثالث — قطّع المعاملة الضخمة (بحذر)
معاملة واحدة تُدخل 50 ألف صف تعني، بنصّ توثيق SQLite ([wal.html §6](https://www.sqlite.org/wal.html)): *«**Very large write transactions.** A checkpoint can only complete when no other transactions are running, which means the WAL file cannot be reset in the middle of a write transaction. So a large change to a large database might result in a large WAL file.»* — أي `-wal` يتناسب مع حجم الكتابة كاملةً. زائد **نافذة تعليق واحدة عملاقة** (الشرط الأول).

**فرقٌ يجب فهمه:** تحت `DatabaseQueue`، التقطيع هو **الوسيلة الوحيدة** لإعطاء القرّاء نافذة. تحت `DatabasePool`، القرّاء **لا يُحجبون أصلاً** بفضل WAL — فالتقطيع لم يعد لأجل زمن القراءة، بل لثلاثة أسباب أخرى موثَّقة: حجم `-wal`، ونصيحة groue الصريحة في #1538 (*«perform iterations in batches»*)، وقابلية الإلغاء.

🔴 **والثمن الذي يجب أن يُقال بصراحة: التقطيع يُلغي الذرّية (atomicity).** بين الدفعة 3 والدفعة 4 يرى القارئ نطاقاً **نصف مُعاد التعبئة**. وقاعدة GRDB الثانية للتزامن تقول: *«transactions are the one and single tool that helps you enforce and rely on the invariants of your database»*. **وهذا يصطدم مباشرةً بالدرس الذي دفعنا ثمنه في P7** (`PROJECT_HANDOFF.md §9`): كتالوج ناقص يجب ألّا يصير حقيقة مسجَّلة.

**الحلّ الذي يجمع الاثنين — جدول مرحليّ (staging) ثم مبادلة ذرّية:**
```
1) اكتب الصفوف الجديدة في جدول مرحليّ عبر N معاملة صغيرة  ← بطيء، لكن غير مرئي
2) عاملة واحدة صغيرة: DELETE FROM item WHERE scope = ?;  INSERT INTO item SELECT … FROM staging;
```
الجزء الطويل غير ذرّي وغير مرئي، والجزء المرئي ذرّي ويستغرق أجزاء من الثانية.
⚠ *هذا نمط SQLite قياسي، **وليس وصفة توثّقها GRDB**. قِسه قبل تبنّيه.*

**وشكل الحلقة على 6.24.1:**
```swift
for chunk in rows.chunked(into: 5_000) {
    try await dbPool.write { db in try CatalogItem.batchInsert(db, items: chunk) }
    // GRDB 6 does NOT honour Task cancellation inside `await write {}` — that
    // arrived in GRDB 7. Check it yourself, at the chunk boundary.
    try Task.checkCancellation()
}
```

## أثرٌ جانبي على التصفيح المفتاحي — يمسّ البند المؤجَّل 26
تحت pool، **كل `read {}` معاملة مستقلّة بلقطتها الخاصة**. فمسحٌ مصفَّح عبر `pageMovies` أثناء استيراد جُملي قد يقرأ الصفحة 1 من الكتالوج القديم والصفحة 5 من الجديد ← **تكرارات وفجوات**. الحلّ حين نفعّل التصفيح: نفّذ جلسة التصفّح كلها داخل `read {}` واحدة، أو ثبّت لقطة بـ `dbPool.makeSnapshot()`.

## أسئلة جانبية — أجوبة قصيرة موثَّقة
- **`maximumReaderCount`:** الافتراضي **5** (`Configuration.swift:360`، دون تغيير بين 6.24.1 و`master`). لهاتف بقلة أنوية وقراءات مقيَّدة بالإدخال/الإخراج، خمسة أكثر من كافٍ. **اتركه.** ما قد يفيد فعلاً هو `persistentReadOnlyConnections` إن أظهر التنميط أن فتح الاتصالات هو الكلفة (البحث أثناء الكتابة يفتح قراءات قصيرة متكرّرة).
- **نقاط التفتيش (checkpointing):** GRDB **لا تُعطّل** التلقائي ولا تضبط `journal_size_limit`. SQLite تفتش تلقائياً عند ~1000 صفحة (~4 ميغابايت). **لا تفعل شيئاً في البداية.** ونبّه: التفتيش من اتصال الكاتب في الـ pool **يحجب الكتابة** ([#793](https://github.com/groue/GRDB.swift/issues/793))، والتفتيش من نوع `.truncate` **يكسر بدء `ValueObservation`**.
- **`ValueObservation` لقائمة الكتالوج؟ — لا.** توثيق GRDB: *«ValueObservation can create database contention… observations fetch fresh values, and **can delay read and write database accesses of other application components**»*، و*«Keep your number of observations bounded»*. مراقبة على جدول `item` ستُبطَل عند **كل دفعة** من الاستيراد المقطَّع فتُعيد الجلب مراراً — أي أنها تضيف حملاً على العملية التي نحاول تخفيفها. **أبقِ القراءات المصفّحة يدوية، وأطلق إشارة «تغيّر الكتالوج» واحدة بعد اكتمال `save()`.** (تصلح `ValueObservation` للقيم الصغيرة المحدودة: عدّاد، حالة «هل النطاق معبّأ»، قائمة المفضّلة.)
- **FTS5 مع pool — آمن.** جدول FTS5 مخزَّن في جداول ظلّ عادية (`%_data`, `%_idx`, `%_content`…)، فعزل لقطات WAL ينطبق عليه كأي جدول. المسألة الوحيدة في تاريخ GRDB ([#414](https://github.com/groue/GRDB.swift/pull/414)، 2018) كانت في **المُجزِّئات المخصّصة** فقط — ونحن على `unicode61` المدمج. **لا تنطبق علينا.** *(قاعدة عامة تستحقّ التدقيق مع ذلك: أي شيء مرتبط بالاتصال — دوالّ SQL مخصّصة، ترتيبات مقارنة، مُجزِّئات — يجب تسجيله في `Configuration.prepareDatabase { }` كي تحصل عليه **كل** اتصالات القراءة في الـ pool، لا الكاتب وحده.)*

## سؤال جانبي: هل نرقّي GRDB؟ — **لا الآن، والسبب ليس ما ظننّاه**
- أحدث إصدار: **7.11.1 (18 يونيو 2026)**؛ آخر 6.x هو 6.29.3. نحن متأخّرون **إصداراً رئيسياً و~سنتين ونصف**.
- **CocoaPods trunk متجمّد عند 6.24.1 (6 يناير 2024)** — تحقّقتُ من `trunk.cocoapods.org/api/v1/pods/GRDB.swift` مباشرةً: 290 إصداراً، أعلاها 6.24.1، ولا شيء بعدها.
- 🔴 **تصحيح لتعليق `Podfile:10`:** السبب **ليس** أن «GRDB 7 حصريّ لـ SPM». README الخاص بـ GRDB يقول حرفياً إنها **علّة في CocoaPods نفسها** ([CocoaPods#11839](https://github.com/CocoaPods/CocoaPods/issues/11839)): *«Due to an issue in CocoaPods, it is currently not possible to deploy new versions of GRDB to CocoaPods. The last version available on CocoaPods is 6.24.1.»*
  **وبالتالي الترقية *لا* تتطلّب الهجرة إلى SPM** — يكفي توجيه الـ pod إلى git:
  ```ruby
  pod 'GRDB.swift', git: 'https://github.com/groue/GRDB.swift.git', tag: 'v7.11.1'
  # أو، بلا هجرة Swift 6، آخر 6.x:
  pod 'GRDB.swift', git: 'https://github.com/groue/GRDB.swift.git', tag: 'v6.29.3'
  ```
- **ومع ذلك: أجّلها.** ما يقدّمه GRDB 7 مغرٍ (احترام `Task` للإلغاء، أنواع المعاملات التلقائية، دعم `Sendable` الكامل) لكن ثمنه كسورٌ حقيقية: `ValueObservation` صار `@MainActor` افتراضياً، وتغيّرت توقيعات استراتيجيات `Codable`، وحُذفت `DatabasePool.concurrentRead`. **ولا شيء في البند 6 يحتاجها**: تحقّقتُ أن `DatabasePool` و`observesSuspensionNotifications` و`journalMode` و`Database.checkpoint` و`makeStatement`/`cachedStatement` و`setUncheckedArguments` و`maximumReaderCount` **كلها موجودة وتعمل بنفس الشكل في 6.24.1**. أصلح التزامن على النسخة التي بيدك.

## هل SwiftData تغني عن GRDB هنا؟ — **لا، ولا تقترب.**
عدّ الوكيل البحثي **كامل فهرس رموز SwiftData** من واجهة توثيق Apple: **1167 رمزاً**. تصفيتها على `fts|full.?text|search|token|match` تعطي `Schema.Index` وماكرو `#Index` وأنواع `HistoryToken` فقط. **صفر سطح للبحث النصّي الكامل.** والفهرسة الوحيدة المتاحة (`#Index`) توصّفها Apple بأنها **فهارس ثنائية (binary indices)** — أشجار B للفرز والمساواة والمدى، لا فهرس نصّي معكوس: بلا تجزئة، بلا طيّ للتشكيل، بلا مطابقة بادئة، بلا ترتيب أهمية bm25.

**عملياً:** استبدال GRDB بـ SwiftData يحوّل بحثنا إلى `localizedStandardContains` — مسحُ جدول كامل بلا فهرس **لكل ضغطة مفتاح** على 176 ألف صفّ، بلا طيّ للتشكيل العربي. **هذا وحده ينهي النقاش**، قبل أن نصل إلى فقدان التحكّم في المعاملات والتصفيح المفتاحي.
⚠ *وامتناعٌ صادق: ادّعاءات المدوّنات عن «حدود عدد صفوف» في SwiftData بلا مصدر موثوق، ولا تنشر Apple أرقاماً. **لا أدّعي شيئاً عن أدائها** — حجّة الـ FTS قاطعة وحدها ومصدرها فهرس رموز Apple نفسه.*

## سكتش التنفيذ — `BlankTV/CatalogDB.swift`
```swift
// اكتب النوع كبروتوكول: عندها تصير كل تبديلة لاحقة سطراً واحداً.
static let dbQueue: (any DatabaseWriter)? = {
    do {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        // WAL adds -wal and -shm sidecars. GRDB: "it is recommended that you wrap the
        // database file inside a dedicated directory" — otherwise deleting/moving the
        // store orphans them.
        let dir = base.appendingPathComponent("catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        // Without this the OS kills us with 0xdead10cc if we are suspended while the
        // 20k–50k-row catalogue write holds a lock. GRDB labels the mechanism
        // EXPERIMENTAL and "optimistic" — it is a mitigation, not a guarantee.
        config.observesSuspensionNotifications = true
        // GRDB 6 defaults to DEFERRED; suspension detection needs IMMEDIATE writes.
        // (Automatic in GRDB 7, where this property no longer exists.)
        config.defaultTransactionKind = .immediate
        let p = try DatabasePool(path: dir.appendingPathComponent("db.sqlite").path,
                                 configuration: config)
        try migrator.migrate(p)
        return p
    } catch { return nil }
}()
```
و`BlankTV/BlankTVApp.swift` — الفرع الغائب:
```swift
.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .background: NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    case .active:     NotificationCenter.default.post(name: Database.resumeNotification,  object: nil)
                      … (المنطق الحالي)
    default: break
    }
}
```

## ترتيب التنفيذ داخل البند 6 (لا تخلطه)
| # | الخطوة | لماذا هنا |
|---|---|---|
| 0 | **قِس `save()` في وضع Release** | إن كانت ≪ 0.5 ث لـ 50 ألف صف، فالمشكلة ليست حيث نظنّ |
| 1 | استبدل حلقات `insert(db)`/`db.execute(sql:)` بـ `makeStatement` + `setUncheckedArguments` | أكبر مكسب منفرد، وخطره صفر تقريباً، ولا يمسّ التزامن |
| 2 | أضِف فرع `.background`/`.active` في `BlankTVApp` + `beginBackgroundTask` **قبل** بدء الكتابة | شرط `0xdead10cc` — بدونه لا تُشحن الخطوة 3 |
| 3 | غيّر النوع إلى `any DatabaseWriter` ← `DatabasePool` + `Configuration` | التبديل نفسه |
| 4 | انقل الملف إلى مجلّده الخاص (ترحيل صامت) | ملفّات WAL الجانبية |
| 5 | قطّع `save()` — **مع جدول مرحليّ إن أردنا صون الذرّية** | حجم `-wal` + نافذة التعليق + الإلغاء |

- **الجهد:** ~35 سطراً موزّعة على ثلاثة ملفات + التقطيع · 3–5 ساعات + جولة تحقّق. **الخطر: متوسط** — وهو أعلى بند خطراً في هذا التقرير. **نفّذه وحده في بناء مستقلّ.**
- **المصادر:** [GRDB Concurrency](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Concurrency.md) · [DatabaseConnections](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseConnections.md) · [DatabaseSharing](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md) · [Performance wiki](https://github.com/groue/GRDB.swift/wiki/Performance) · [#926 bulk insert](https://github.com/groue/GRDB.swift/issues/926#issuecomment-786089593) · [#1538 0xdead10cc](https://github.com/groue/GRDB.swift/issues/1538) · [#1790](https://github.com/groue/GRDB.swift/issues/1790) · [Apple SIGKILL / 0xdead10cc](https://developer.apple.com/documentation/xcode/sigkill) · [SQLite WAL §6](https://www.sqlite.org/wal.html) · [CocoaPods trunk API](https://trunk.cocoapods.org/api/v1/pods/GRDB.swift)

---

# البند 7 — نقل رابط القائمة من `UserDefaults` إلى الـ Keychain

## الحكم: **ADOPT MODIFIED** — الوجهة صحيحة، لكن **اقسِم الحمولة**، والخلل الأكبر ليس حيث يظنّ التقرير

## هل هناك API أحدث من `SecItem`؟ — **لا. تحقّقٌ سلبي عبر أربعة مصادر Apple**
1. صفحة [تحديثات Security](https://developer.apple.com/documentation/updates/security) لا تحوي إلا مدخلين: يونيو 2024 (أخطاء وصول الملفات في App Sandbox) ويونيو 2023 (قيود الإطلاق والمكتبات). **لا شيء عن Keychain في iOS 18 ولا 26.**
2. الصفحة الرئيسية لإطار Security: دوالّ Swift الأصيلة الوحيدة هي `SecIdentityCreate` و`sec_protocol_metadata_*`. **لا نوع `Keychain`، ولا `SecItemQuery`، ولا أي سطح Swift أصيل للـ Keychain.**
3. فهرس تحديثات WWDC25: مدخلا الأمن هما «Enabling enhanced security for your app» و«Creating enhanced security helper extensions» (تقوية أمان الذاكرة). لا شيء عن Keychain.
4. دليل Swift في WWDC26 (Swift 6.4): لا شيء عن Security.

وتقول Apple في [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) حرفياً: ***«Choosing a keychain API is easy: Use the `SecItem` API.»***

> **إذن: غلاف `SecItem` مكتوب باليد هو الجواب الصحيح في 2026. وأي ادّعاء بوجود API جديدة للـ Keychain من WWDC 2025/2026 — لم أجد له أي توثيق من Apple: «غير متحقَّق منه».**

**ولا تُضِف مكتبة:** فحصتُ الحالة الحيّة عبر GitHub API بتاريخ 27 يوليو 2026 — `KeychainAccess` (8253 نجمة، **آخر دفعة 31 مايو 2024**، 54 مسألة مفتوحة) هو فخّ «الشعبي لكن الميت»؛ `square/Valet` (12 يوليو 2026، مسألة واحدة مفتوحة) هو الخيار الصحّي الوحيد لو أردت تبعية. لكننا نحتاج **سرّاً واحداً وأربعة نداءات** — والمشروع أصلاً يعاني من احتكاك `project.pbxproj` (`PROJECT_HANDOFF.md §3`). **اكتب الأسطر الأربعين.**

## الخلل الأكبر الذي فاته التقرير: `Keychain` عندنا **موجود أصلاً وضبطه خاطئ لكل المفاتيح**
`BlankTV/Core.swift:749–843` فيه صنف `Keychain` كامل يخزّن `token`, `host`, `user`, `pass`, `userID`, `tokenExpiry`, `deviceID`. وعند `:816` يثبّت **لكل المفاتيح بلا استثناء**:
```swift
kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```
توثيق Apple لـ [`kSecAttrAccessibleWhenUnlocked`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlocked) حرفياً: *«recommended for items that need to be accessible **only while the application is in the foreground**»*.
وتوثيق [`kSecAttrAccessibleAfterFirstUnlock`](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock) حرفياً: *«This is **recommended for items that need to be accessed by background applications**.»*

**النتيجة اليوم، قبل أي نقل لـ `m3uURL`:** أي تنزيل خلفي عبر `URLSession` الخلفية (`Downloads.swift:79`) أو أي تحديث كتالوج يبدأ **والجهاز مقفل** يقرأ `Keychain.shared.token` فيحصل على `nil` ← `APIClient` يرمي `invalidCredentials` (`Core.swift:648–650`). **هذا خلل حيّ قائم**، وفشلٌ متقطّع غير قابل لإعادة الإنتاج على مكتب المطوّر: يعمل نهاراً ويفشل ليلاً. **أصلحه أوّلاً؛ نقل `m3uURL` بند ثانٍ.**

## تصحيح شائع: «غير `ThisDeviceOnly` يتزامن عبر iCloud Keychain» — **خطأ**
توثيق [`kSecAttrSynchronizable`](https://developer.apple.com/documentation/security/ksecattrsynchronizable) حرفياً: *«To add a new synchronizable item … supply this key with a value of `kCFBooleanTrue`. **If the key is not supplied, or has a value of `kCFBooleanFalse`, then no synchronizable items are added or returned.**»*
إذن المزامنة **اشتراكٌ صريح** لن نطلبه أبداً. ما يشتريه إسقاط `ThisDeviceOnly` فعلياً هو **الإدراج في النسخ الاحتياطية المشفّرة والانتقال إلى جهاز جديد عند الاستعادة**، لا مزامنة iCloud.

**واختيارنا: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.** السبب ليس أكاديمياً: حمولتنا اعتماد مزوّد IPTV مقيَّد غالباً بعدد اتصالات لكل جهاز. إحياؤه صامتاً على جهاز مُستعاد أو جهاز ثانٍ يُشعل حظر «too many connections» من جانب المزوّد، ويصل إلى المستخدم بصورة «التطبيق معطّل». وثمن الخسارة عند الترحيل هو **تسجيل دخول واحد عبر بوّابة بنيناها أصلاً**. وقاعدة Apple نفسها: *«Always use the most restrictive option that makes sense for your app.»*

**نتيجة يجب معالجتها:** بعد استعادة جهاز، يعود الـ Keychain بـ `errSecItemNotFound` بينما راية «مسجَّل الدخول» في `UserDefaults` **تنجو** (الـ `UserDefaults` يُنسخ احتياطياً). **اجعل غياب مفتاح الـ Keychain — لا الراية — هو مصدر الحقيقة لحالة الدخول**، وإلا شحنت شاشة فارغة لكل جهاز مُستعاد.

## اقسِم الرابط، ولا تنقله كما هو
`http://host/player_api.php?username=X&password=Y` — كلمة مرور داخل سلسلة استعلام، وهو أسوأ موضع ممكن:
- **سلاسل الاستعلام تتسرّب إلى السجلّات**: سجلّات الخادم، أي وسيط، وصف أخطاء `URLSession`، مخرجات `os_log`، وتقارير الانهيار. أي `print("failed: \(url)")` في طبقة الشبكة يكتب كلمة مرور المستخدم في وحدة تحكّم الجهاز نصّاً صريحاً — وعندنا `print()` على مسار تحميل الكتالوج فعلاً (`HomeView.swift:186/194/201`).
- **`http://` لا `https://`**: الاعتماد يمرّ على السلك صريحاً في كل طلب مهما أحسنّا تخزينه. تخزين الـ Keychain **لا يصلح هذا** — لكنه سببٌ إضافي قويّ لاختيار `ThisDeviceOnly`.
- **تخزين الرابط كاملاً يعطّل تدوير المفتاح**: تغيير المستخدم لكلمة مروره يصبح جراحة نصّية على رابط مخزَّن.

**القسمة المقترحة** (وهي بالضبط شكل صنف `kSecClassInternetPassword` الذي صمّمته Apple لهذا الغرض):
```
UserDefaults : host / base URL / port          (غير سرّي، وتحتاجه الواجهة للعرض)
Keychain     : kSecClassInternetPassword
                 kSecAttrServer  = host
                 kSecAttrAccount = username
                 kSecValueData   = password
                 kSecAttrAccessible = ...AfterFirstUnlockThisDeviceOnly
```
وأعِد تركيب الرابط وقت الطلب، **ولا تسجّله ولا تُبقِه**.

## 🔴 خطر أداء لا يذكره المرجع — اقرأه قبل التنفيذ
`Store.shared.m3uURL` هو **مفتاح النطاق (scope key)** لـ `CatalogDB` و`CatalogDiskCache` (`PROJECT_HANDOFF.md §8`). أي أنه يُقرأ في كل بحث FTS، وكل قراءة مصفّحة، وكل حفظ. و`SecItemCopyMatching` **نداء XPC عبر حدود العملية**، أبطأ من `UserDefaults` بمراتب.
**نقله حرفياً إلى الـ Keychain يضيف قفزة XPC إلى كل قراءة كتالوج.** إلزامي: احتفظ بنسخة في الذاكرة (`private var cachedM3U: String?`) تُملأ مرّة واحدة وتُبطَل عند تبديل الحساب فقط.

## سكتش التنفيذ — `BlankTV/Core.swift`
```swift
// 1) في Keychain: اجعل الصلاحية وسيطاً بدل ثابتٍ خاطئ للجميع
private func save(_ key: Key, value: String,
                  accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) {
    // WhenUnlocked* is Apple's "foreground only" class. Background URLSession
    // downloads and catalogue refreshes run while the device is LOCKED, where it
    // returns nil — an intermittent, undebuggable auth failure.
    …
    kSecAttrAccessible: accessible
}

// 2) ترحيل صامت لمرة واحدة — لا تحذف النسخة الصريحة إلا بعد قراءة تأكيدية
var m3uURL: String? {
    get {
        if let c = cachedM3U { return c }                       // ← لا XPC على المسار الحار
        if let k = Keychain.shared.m3uURL { cachedM3U = k; return k }
        if let legacy = ud.string(forKey: K.m3uURL.rawValue) {   // migration
            Keychain.shared.m3uURL = legacy
            if Keychain.shared.m3uURL == legacy {                // read-back confirms the write
                ud.removeObject(forKey: K.m3uURL.rawValue)
            }
            cachedM3U = legacy; return legacy
        }
        return nil
    }
    set { cachedM3U = newValue; Keychain.shared.m3uURL = newValue }
}
```

**فخّان معروفان** (من Quinn «The Eskimo!» في منتديات Apple):
- **`errSecMissingEntitlement` (‏-34018)**: سببه دائماً تقريباً تمرير `kSecAttrAccessGroup` غير مُخوَّل. **الحلّ عندنا: لا تضبطه إطلاقاً** — تطبيق واحد بلا إضافات، فالمجموعة الافتراضية تكفي ولا تحتاج قدرة Keychain Sharing. وفي أهداف الاختبار يجب ضبط **Test Host Application**، وإلا فشل الوصول — ونحن نبني على Codemagic، فاحسب لهذا حساباً.
- **بقاء عناصر الـ Keychain بعد حذف التطبيق**: أكّد Quinn أنه *«implementation detail»* غير موثَّق، تغيّر في 10.3 beta ثم أُعيد. **لا تعتمد على أيٍّ من السلوكين.** عند أوّل إقلاع بعد تثبيت جديد (راية «سبق الإقلاع» غائبة من `UserDefaults` — وهي **تُمحى** بالحذف — بينما الاعتماد موجود في الـ Keychain): اتّخذ قراراً صريحاً بالتبنّي أو المسح. تبنّيه يعني أن إعادة التثبيت تُسجّل المستخدم صامتاً — مرغوب غالباً، لكن يجب أن يكون قراراً لا مصادفة.

- **الجهد:** ~60 سطراً · 3 ساعات. **الخطر:** متوسط (يمسّ مسار الدخول ومفتاح النطاق).

---

# البند 8 — طبقة قياس جودة التشغيل (QoE)

## الحكم: **REPLACE WITH NEWER** 🔴 — **لا تنقل `Telemetry.swift` من المرجع**

## ما يفعله المرجع
يستخرج يدوياً من `AVPlayerItemAccessLog`/`ErrorLog` (`PlayerEngine.swift:335–336, 487–488, 591–602`) ويضيف في `Telemetry.swift` زمن أوّل إطار، ونِسَب إعادة التخزين بساعة جدارية، و`thermalState`، والبصمة الذاكرية عبر Mach `task_vm_info`. ~170 سطراً و~20 موضع نداء.

## لماذا لا يُنقل — سببان قاطعان

**السبب الأول: Apple شحنت الطبقة كاملةً، ولها أنواع مُصنَّفة.**
[`AVMetrics`](https://developer.apple.com/documentation/avfoundation/avmetrics) — **بنية `struct` مطابقة لـ `AsyncSequence` و`Sendable`**، متاحة من **iOS 18.0 / iPadOS 18.0 / tvOS 18.0 / macOS 15.0 / visionOS 2.0**. قُدِّمت في [WWDC 2024 · جلسة 10113 «Discover media performance metrics in AVFoundation»](https://developer.apple.com/videos/play/wwdc2024/10113/). البروتوكول `AVMetricEventStreamPublisher` مطبَّق على `AVPlayerItem`:

```swift
public protocol AVMetricEventStreamPublisher {
    func metrics<M: AVMetricEvent>(forType: M.Type) -> AVMetrics<M>
    func allMetrics() -> AVMetrics<AVMetricEvent>
}
extension AVPlayerItem: AVMetricEventStreamPublisher
```

و[كتالوج الأحداث](https://developer.apple.com/documentation/avfoundation/metric-event-types) فيه 17 نوعاً، أهمّها لنا `AVMetricPlayerItemPlaybackSummaryEvent` — **سجلّ QoE كامل في حدث واحد**: `stallCount`, `timeSpentInInitialStartup`, `timeSpentRecoveringFromStall`, `timeWeightedAverageBitrate`, `timeWeightedPeakBitrate`, `variantSwitchCount`, `recoverableErrorCount`, `mediaResourceRequestCount`, `playbackDuration`, `errorEvent`.

**هذه هي بالضبط الأرقام التي يجمّعها `Telemetry.swift` يدوياً — تحسبها لك AVFoundation.**

**السبب الثاني، والأقوى: الأساس الذي يقوم عليه نهج المرجع مهجور.**
تحقّقتُ مباشرةً من واجهة توثيق Apple: `AVPlayerItem.accessLog()` **مهجورة اعتباراً من 27.0** على كل المنصّات (iOS، iPadOS، macOS، tvOS، visionOS، watchOS)، وبديلها `fetchAccessLog(completionHandler:)` **متاح من 27.0 فقط** — لأن القديمة تحجب الخيط المستدعي. أي أن نقل نهج المرجع يعني **البناء على API مهجورة، لجمع أرقام تحسبها Apple لك، بديلها غير متاح على هدف نشرنا**.

## المعمارية المقترحة — سلّم ثلاثي
| المحرّك / النظام | المصدر |
|---|---|
| `AVPlayerVM` على **iOS 18+** | `AVMetrics` — المسار الأساسي |
| `AVPlayerVM` على **iOS 17** | `accessLog()` بالحدّ الأدنى (`indicatedBitrate`, `numberOfStalls`, `numberOfDroppedVideoFrames`) — مسار احتياطي فقط |
| `VLCPlayerVM` | **لا يملك سجلّ وصول إطلاقاً** ← بكرة الحالة `hasPlayed` هي المصدر الوحيد. **هنا فقط أسلوب المرجع صحيح ولا بديل له** |

## سكتش التنفيذ — ملف جديد `BlankTV/PlaybackMetrics.swift`

> **تذكير من `PROJECT_HANDOFF.md §3`: لا توجد مجموعات متزامنة في `project.pbxproj` — كل ملف `.swift` جديد يحتاج 4 مدخلات يدوية (PBXBuildFile · PBXFileReference · PBXGroup children · PBXSourcesBuildPhase). المعرّف التالي الحرّ هو `1A1A1A1A000000000000F015`.**

```swift
import AVFoundation

/// One playback session's quality record. Filled from AVMetrics on iOS 18+,
/// from the (27.0-deprecated) access log on iOS 17, and from the VLC state reel
/// when the VLC engine is in use.
struct PlaybackQoE: Sendable {
    var engine: String = ""
    var startupSeconds: Double = 0
    var stallCount: Int = 0
    var stallSeconds: Double = 0
    var averageBitrate: Double = 0
    var variantSwitches: Int = 0
    var recoverableErrors: Int = 0
}

@MainActor
final class PlaybackMetricsCollector {
    private var task: Task<Void, Never>?

    func attach(_ item: AVPlayerItem, engine: String, onFinish: @escaping (PlaybackQoE) -> Void) {
        task?.cancel()
        if #available(iOS 18.0, *) {
            task = Task { [weak self] in
                // AVMetrics is an AsyncSequence of typed events — Apple aggregates the
                // numbers Telemetry.swift computed by hand, and accessLog(), which that
                // approach is built on, is deprecated as of 27.0.
                var qoe = PlaybackQoE(engine: engine)
                for await e in item.metrics(forType: AVMetricPlayerItemPlaybackSummaryEvent.self) {
                    qoe.startupSeconds   = e.timeSpentInInitialStartup
                    qoe.stallCount       = e.stallCount
                    qoe.stallSeconds     = e.timeSpentRecoveringFromStall
                    qoe.averageBitrate   = e.timeWeightedAverageBitrate
                    qoe.variantSwitches  = e.variantSwitchCount
                    qoe.recoverableErrors = e.recoverableErrorCount
                    onFinish(qoe)
                }
                _ = self
            }
        } else {
            // iOS 17 only. Read ONCE at teardown, never on a timer — accessLog() blocks
            // the calling thread, which is exactly why Apple deprecated it in 27.0.
            task = nil
        }
    }
    func detach() { task?.cancel(); task = nil }
}
```

**مواضع الوصل:** `AVPlayerVM.setup()` (`PlayerEngine.swift:338` بجوار `observe(pItem)`) ← `attach`؛ و`cleanup()` (`:376`) و`load()` (`:363`) ← `detach` + تسجيل النتيجة. والاستهلاك في لوحة **«تشخيص محرّك التشغيل»** الموجودة أصلاً في الإعدادات (`EngineStatsView`)، وفي `EngineDecisionCache`/`StreamRouter` كي يصير التوجيه **مبنياً على قياس لا تخمين** — وهو الهدف الحقيقي من البند.

## ثلاثة تحفّظات صادقة
1. **التغطية على MP4 التقدّمي غير موثَّقة لدى Apple.** الأحداث تنقسم بوضوح: `HLS*` و`VariantSwitch*` **حصريّة لـ HLS** (يحمل الأخير `AVAssetVariant` وهو بلا معنى لـ MP4). أمّا `Stall` و`LikelyToKeepUp` و`RateChange` و`Seek` و`PlaybackSummary` و`Error` فتبدو محايدة للصيغة — **لكن هذا استنتاجٌ من شكل الـ API لا التزامٌ موثَّق. قِسه على الجهاز قبل أن تبني عليه قراراً.**
2. **`playImmediately(atRate:)` يكبت `playbackStalledNotification` بنصّ Apple** (انظر البند 2). **تحقّق ميدانياً هل `stallCount` في `AVMetricPlayerItemPlaybackSummaryEvent` يتأثّر** قبل أن تعتبره حقيقة.
3. **`AVMetricEventStream`** (نسخة Objective-C المفوَّضة) **لا** تطابق `AsyncSequence`. من Swift استعمل `AVMetrics` حصراً.

## ولا تنقل هذه من `Telemetry.swift` مهما كان
`NWPathMonitor` يبدأ عند تهيئة المفرد ولا يُلغى أبداً · فكّ قسري (`!`) على مسار قياس ساخن · سلسلة بصمة جهاز · `snapshot()` (لا خادم لدينا أصلاً). **هذه أخطاء المرجع، لا هندسته.**

- **الجهد:** ~130 سطراً (منها ~90 للمسار الحديث) · 4 ساعات. **الخطر:** منخفض — الطبقة قراءة محضة خارج المسار الحرج.
- **مقارنة:** المرجع ~170 سطراً + ~20 موضع نداء يدوي. المسار الحديث **أقصر وأدقّ وغير مهجور**.

---

# قسم إضافي — ثلاث تقنيات لا يملكها أي من التطبيقين وتستحقّ البناء

> نفس المعيار: مصدرٌ موثَّق، وسببٌ واضح للتفوّق، وسكتش تنفيذ. ثلاثة فقط — ولا حشو.

## ج-أ · فخّ `automaticallyWaitsToMinimizeStalling` على البث المباشر — **خلل حيّ عندنا** 🔴

**الموقع:** `BlankTV/PlayerEngine.swift:347` — `avPlayer.automaticallyWaitsToMinimizeStalling = !isLive`

هذا من تحسينات الأداء P6 (`PROJECT_HANDOFF.md §9`)، والنيّة صحيحة: التبديل السريع بين القنوات. **لكن توثيق Apple لـ [`automaticallyWaitsToMinimizeStalling`](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling) يقول شيئاً لم يُحسب حسابه:** حين تكون `false`، فإن حدث نفاد المخزن **يُنزل `timeControlStatus` إلى `.paused` والمعدّل إلى `0.0`** — و**لا يستأنف ذاتياً**. وتوصي Apple بـ `false` **فقط** حين تحتاج تحكّماً دقيقاً في لحظة البدء (مزامنة عدّة مشغّلات)، لا لتسريع البدء.

**النتيجة العملية عندنا:** انقطاع شبكيّ لثانيتين على قناة مباشرة **يجمّد القناة نهائياً**. المخرج الوحيد هو مراقب التوقّف عند 30 ثانية ← خطأ قابل لإعادة المحاولة ← انتقال إلى VLC. أي **30 ثانية شاشة ميتة ثم تبديل محرّك، على قناة سليمة تماماً**. وهذا يضرب بالضبط تجربة «التقليب بين القنوات» التي كان التحسين يخدمها.

**الإصلاح (٨ أسطر، ويحفظ مكسب السرعة):** أبقِ `false` لكن أضِف إعادة إشعال صريحة داخل `likelyKeepUpObs` — المراقب موجود أصلاً عند `PlayerEngine.swift:473`:
```swift
likelyKeepUpObs = pItem.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] it, _ in
    let ok = it.isPlaybackLikelyToKeepUp
    Task { @MainActor [weak self] in
        guard let self, ok else { return }
        self.buffering = false; self.isLoading = false
        // With automaticallyWaitsToMinimizeStalling == false (our live fast-zap path)
        // Apple documents that a buffer-empty event drops the rate to 0 and the player
        // does NOT self-recover. Without this re-kick a 2-second hiccup freezes a live
        // channel until the 30 s stall monitor gives up and fails over to VLC.
        if self.isLive, self.isPlaying, self.avPlayer.rate == 0 {
            self.avPlayer.playImmediately(atRate: 1.0)
        }
    }
}
```
**بند مجاور بسطر واحد:** `pItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false` (`:337`) مثبَّتة لكل العناصر. توثيق Apple يجعلها `true` للبث المباشر كي تبقى `seekableTimeRanges` طازجة أثناء الإيقاف (بثمنٍ في الطاقة). اجعلها `= isLive`.

- **الجهد:** ~8 أسطر · ساعة. **الخطر:** منخفض. **الأثر:** عالٍ جداً على تجربة البث المباشر.

## ج-ب · دورة حياة `AVAudioSession` — أعلى أثر ملموس لكل سطر في التقرير كلّه

**لا يعالج أيٌّ من التطبيقين** أيّاً من الثلاثة. وتحقّقتُ أن هذه **لا تزال** الواجهات الصحيحة في 2026:
- [`AVAudioSession.interruptionNotification`](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification) — **غير مهجورة على iOS** (الهجر الوحيد على visionOS 27.0). تُنشَر على الخيط الرئيسي.
- **تصحيح مهم:** [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication) (iOS 17+) **لم يحلّ محلّها**. تولّى ثلاثة أمور **تخصّ التسجيل** فقط: إذن التسجيل، إذن حقن الميكروفون، وكتم الدخل على مستوى التطبيق. **لا شيء عن المقاطعات ولا المسارات ولا التشغيل.** لتطبيق IPTV هو غير ذي صلة عملياً.
- `mediaServicesWereResetNotification` — غير مهجورة. يجب إعادة بناء المشغّلات وإعادة ضبط الفئة/الوضع/الخيارات، **ومن دون استئناف تلقائي للتشغيل بلا فعل من المستخدم** (نصّ Apple).

**لماذا هي الأعلى أثراً:** مكالمة واردة أو Siri تُسكت الصوت — و**VLC لا يستأنف تلقائياً**؛ ونزع السمّاعات اليوم **يُطلق الصوت من سمّاعة الجهاز**، وهو مخالف صريح لإرشادات Apple ولتوقّع المستخدم في مكان عام.

**سكتش — ملف جديد `BlankTV/AudioSessionLifecycle.swift`** (تذكير: 4 مدخلات في `project.pbxproj`، المعرّف `…F016`):
```swift
NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                       object: nil, queue: .main) { note in
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    switch type {
    case .began: currentVM?.pause()
    case .ended:
        let raw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        if AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume) {
            try? AVAudioSession.sharedInstance().setActive(true)
            currentVM?.play()          // VLC never resumes on its own
        }
    @unknown default: break
    }
}

NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                       object: nil, queue: .main) { note in
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    else { return }
    // Headphones pulled. Apple's guidance is to PAUSE — never keep playing out of the
    // device speaker, which is what happens today.
    currentVM?.pause()
}

NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                       object: nil, queue: .main) { _ in
    // Everything audio-related is invalid: rebuild the engine and re-set the category.
    // Do NOT auto-resume playback (Apple).
    configureAudio(); currentVM?.rebuildAfterMediaServicesReset()
}
```
**ملاحظتان تقنيتان مفيدتان:** `setPrefersNoInterruptionsFromSystemAlerts(_:)` و`setPrefersInterruptionOnRouteDisconnect(_:)` مقبضان حديثان يستحقّان النظر لمشغّل فيديو. وبعد إعادة تهيئة خدمات الوسائط **لا تحتاج** إلى إعادة تسجيل المراقبين ولا KVO.

- **الجهد:** ~80 سطراً · 3 ساعات. **الخطر:** منخفض. **الأثر:** أعلى أثر مستخدم لكل سطر.

## ج-ج · `RouteSharingPolicy.longFormVideo` — الشرط الصامت لعمل AirPlay

مشروح بالكامل في **البند 5**، وأفرده هنا لأنه المثال الأنقى على قاعدة المالك: **ليس نقلاً من المرجع — المرجع لا يملكه — بل الشرط الذي بدونه ما ننقله من المرجع لا يعمل.** ستّة أسطر: مفتاح `AVInitialRouteSharingPolicy = LongFormVideo` في `Info.plist` + `setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)`.

> **تنبيه على `Info.plist`:** التقرير التمايزي يصنّف `Info.plist` عندنا كـ **متطابق بالبايت** مع المرجع (نتيجة حرجة C2). **عدِّل نصّ `NSLocalNetworkUsageDescription` في نفس التحرير** الذي يضيف مفتاح سياسة المسار — بناءٌ واحد يخدم الهندسة والتمايز معاً.

---

## يستحقّ المعرفة، ولا يُنفَّذ الآن (سطران، بلا حشو)

- **إطار `Now Playing` الجديد** ([WWDC 2026 · جلسة 312](https://developer.apple.com/videos/play/wwdc2026/312/)، iOS 27 فقط): بديل Swift-first مبني على `Observable` لـ `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`، بأنواع `MediaSession`, `MediaPlaybackSnapshot`, `MediaCommand`. **وApple تحذّر صراحةً من خلطه بواجهات MediaPlayer القديمة.** لا يُتبنّى على هدف iOS 17 — لكن **لا تُعقِّد `NowPlayingManager` عندنا**، أبقِه ملفّاً واحداً يسهل استبداله.
- **`AVAsset.load(_:)`** (iOS 16+) للتحقّق المسبق من صلاحية الأصل قبل صرف فتحة اتصال. مغرٍ لـ IPTV، **لكنه يصرف فتحة اتصال هو نفسه** على لوحات `max_connections=1`. **لا تنفّذه قبل البند 8** — لا تملك القياس الذي يثبت أنه ربح.

---

## ترتيب التنفيذ الموصى به

| الدفعة | البنود | لماذا هذا الترتيب |
|---|---|---|
| **1 · إغلاق ما نُفّذ** | تعليقا البند 2 + `self.rate` · **المرحلة الأولى من البند 4** | البند 4 ناقص اليوم بطريقة **لا تزال تمحو مكتبة المستخدم** — أعلى ضرر متبقٍّ لكل سطر |
| **2 · أخطاء حيّة موثَّقة** | **ج-أ** (تجميد البث المباشر) · صلاحية الـ Keychain من البند 7 | خللان مؤكَّدان من توثيق Apple، صغيران، بلا مساس بالتصميم |
| **3 · القياس (بوّابة)** | **البند 8** | لا يمكن **إثبات** أي ضبط تشغيل لاحق بدونه. نفِّذه قبل الدفعة 4 |
| **4 · التشغيل** | البند 5 + **ج-ج** + **ج-ب** | كلها في `PlayerEngine`/`AudioSession`، ويصير الحكم عليها ممكناً بعد الدفعة 3 |
| **5 · التخزين** | البند 7 كاملاً (القسمة + الترحيل + الذاكرة المؤقّتة) | يمسّ مفتاح النطاق ومسار الدخول — بناءٌ منفرد |
| **6 · قاعدة البيانات** | قياس Release ← العبارات المُحضَّرة ← فرع `.background` ← **البند 6** ← **البند 1** | الترتيب **إلزامي**: القياس قد يُلغي حاجة الـ pool أصلاً؛ وبلا فرع الخلفية يقتل `0xdead10cc` التطبيق؛ وبلا تقطيع المعاملة يضاعف البند 1 المشكلة لأنه يزيد عدد نداءات `save()` |

> **تحذير على الدفعة 4:** ملف `PlayerView.swift` هو أيضاً الإجراء رقم 2 في `DIFFERENTIATION_REPORT.md` (إعادة تصميم المشغّل). **نفّذ الهندسة والتصميم في نفس الجولة** — بناءٌ واحد يكسب المكسبين ويتجنّب مراجعتين متعارضتين على نفس الملف. وتذكّر سقف رفع TestFlight اليومي (`PROJECT_HANDOFF.md §2`): اجمع بنود الدفعة في بناء واحد.

---

## ملحق — المصادر

**توثيق Apple الرسمي**
[AVMetrics](https://developer.apple.com/documentation/avfoundation/avmetrics) · [Metric event types](https://developer.apple.com/documentation/avfoundation/metric-event-types) · [AVMetricPlayerItemPlaybackSummaryEvent](https://developer.apple.com/documentation/avfoundation/avmetricplayeritemplaybacksummaryevent) · [WWDC24-10113 Discover media performance metrics in AVFoundation](https://developer.apple.com/videos/play/wwdc2024/10113/) · [AVPlayerItem.accessLog() — deprecated 27.0](https://developer.apple.com/documentation/avfoundation/avplayeritem/accesslog()) · [NSKeyValueObservingOptions.initial](https://developer.apple.com/documentation/foundation/nskeyvalueobservingoptions/initial) · [AVAsynchronousKeyValueLoading](https://developer.apple.com/documentation/avfoundation/avasynchronouskeyvalueloading) · [Observable() macro](https://developer.apple.com/documentation/observation/observable()) · [Adopting PiP in a Custom Player](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player) · [preroll(atRate:completionHandler:)](https://developer.apple.com/documentation/avfoundation/avplayer/preroll(atrate:completionhandler:)) · [playImmediately(atRate:)](https://developer.apple.com/documentation/avfoundation/avplayer/playimmediately(atrate:)) · [automaticallyWaitsToMinimizeStalling](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling) · [allowsExternalPlayback](https://developer.apple.com/documentation/avfoundation/avplayer/allowsexternalplayback) · [RouteSharingPolicy.longFormVideo](https://developer.apple.com/documentation/avfaudio/avaudiosession/routesharingpolicy/longformvideo) · [AVAudioSession.interruptionNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification) · [AVAudioApplication](https://developer.apple.com/documentation/avfaudio/avaudioapplication) · [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview) · [UnkeyedDecodingContainer.currentIndex](https://developer.apple.com/documentation/swift/unkeyeddecodingcontainer/currentindex) · [kSecAttrAccessibleAfterFirstUnlock](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock) · [kSecAttrAccessibleWhenUnlocked](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlocked) · [kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable) · [TN3137 On Mac keychains](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) · [Security updates](https://developer.apple.com/documentation/updates/security)

**مهندسو Apple (منتديات المطوّرين / DTS)**
[Quinn — Troubleshooting -34018](https://developer.apple.com/forums/thread/114456) · [Quinn — Keychain after uninstall](https://developer.apple.com/forums/thread/36442)

**مشروع Swift**
[SE-0395 Observability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md) · [swift-foundation JSONDecoder.swift](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/JSON/JSONDecoder.swift) · [SR-5953 Lossy Array Decodes — مفتوح منذ 2017](https://github.com/swiftlang/swift-corelibs-foundation/issues/4414) · [Pitch: UnkeyedDecodingContainer.moveNext()](https://forums.swift.org/t/pitch-unkeyeddecodingcontainer-movenext-to-skip-items-in-deserialization/22151)

**GRDB و SQLite و CocoaPods**
[GRDB Concurrency](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Concurrency.md) · [DatabaseConnections](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseConnections.md) · [DatabaseSharing](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md) · [ValueObservation](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb/valueobservation) · [FullTextSearch guide](https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md) · [GRDB7 Migration Guide](https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB7MigrationGuide.md) · [Performance wiki](https://github.com/groue/GRDB.swift/wiki/Performance) · [README — CocoaPods frozen at 6.24.1](https://github.com/groue/GRDB.swift#cocoapods) · [CocoaPods#11839](https://github.com/CocoaPods/CocoaPods/issues/11839) · مسائل: [#414](https://github.com/groue/GRDB.swift/pull/414) · [#793](https://github.com/groue/GRDB.swift/issues/793) · [#926](https://github.com/groue/GRDB.swift/issues/926#issuecomment-786089593) · [#1153](https://github.com/groue/GRDB.swift/issues/1153) · [#1538](https://github.com/groue/GRDB.swift/issues/1538) · [#1790](https://github.com/groue/GRDB.swift/issues/1790) · [CocoaPods trunk API](https://trunk.cocoapods.org/api/v1/pods/GRDB.swift) · [SQLite FTS5](https://sqlite.org/fts5.html) · [SQLite WAL](https://www.sqlite.org/wal.html) · [Apple SIGKILL / 0xdead10cc](https://developer.apple.com/documentation/xcode/sigkill) · [Apple Platform Security — Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web) · [SwiftData updates](https://developer.apple.com/documentation/updates/swiftdata)

**طرف ثالث (سلطة أدنى — موسوم كذلك)**
[Swift by Sundell — Ignoring invalid JSON elements with Codable](https://www.swiftbysundell.com/articles/ignoring-invalid-json-elements-codable/) · [BetterCodable — مهجورة عملياً](https://github.com/marksands/BetterCodable) · [square/Valet](https://github.com/square/Valet) · [KeychainAccess — راكدة منذ مايو 2024](https://github.com/kishikawakatsumi/KeychainAccess)

---

_انتهى التحكيم. كل ادّعاء عن شيفرتنا تحقّقتُ منه في `blankstor/BlankTV/` مباشرةً بالملف ورقم السطر. وكل ادّعاء عن واجهة برمجية جُلب من مصدره الأوّلي، وما لم أجد له توثيقاً قلتُ ذلك صراحةً._
