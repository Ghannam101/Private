# تقرير تدقيق مراجعة App Store — «Blank Prime» (`BlankTV`)

**تدقيق عدائي مستقل · بعين مراجع Apple لا بعين المطوّر · 2026-07-28**

> **المنهج:** مشيتُ في التطبيق كما يمشي فيه مراجع حقيقي: جهاز واحد، **بلا اشتراك IPTV**، عشر دقائق، وقائمة تدقيق.
> كل نتيجة أدناه مُثبتة بـ`file:line` من الشيفرة الفعلية على القرص — لا افتراضات ولا تعميم.
> **لم يُعدَّل أي ملف مصدري.** الملف الوحيد المكتوب هو هذا التقرير.
>
> **الغلاف الزمني:** لقطة الشيفرة عند 2026-07-28 ~03:05. (`Core.swift` عُدِّل أثناء التدقيق في commit الساعة 03:00؛ كل الأسطر أدناه محقّقة بعد ذلك التعديل.)
>
> **خارج النطاق عمداً:** **Guideline 4.3 (Design — Spam / التطبيقات المكرّرة)** مغطّى بالكامل في `DIFFERENTIATION_REPORT.md`. لا أُعيده هنا — لكنني أشير إليه في موضع واحد لأن نتيجته تُضاعِف خطر بند آخر (انظر K-17).

---

## 1. جدول الملخص — كل نتيجة في سطر

مرتّب: **REJECTION** أولاً، ثم METADATA REJECTION، ثم LIKELY REJECTION، ثم RISK.

| # | البند (Guideline) | المُشغِّل | الدليل (`file:line`) | الخطورة |
|---|---|---|---|---|
| **R-1** | **5.2.1 Intellectual Property · 5.2.3 · 4.1 Copycats** | **ستة ملصقات أفلام تجارية محمية مُجمَّعة داخل الـbinary وتُعرض ملء الشاشة على أول شاشة يراها المراجع** (Marvel/Disney · Universal · Paramount/Hasbro · Disney + شبه Emma Watson · عمل فنان مستقل بعلامته المائية) | `GatewayView.swift:16` · `GatewayView.swift:99-101` · `Assets.xcassets/gwposter1…6.imageset/` | **REJECTION** |
| **R-2** | **2.1 App Completeness** | حقل الدخول يُعلن «رابط السيرفر **أو كود التفعيل**»، و`resolveCode()` **تُرجع `false` دائماً** ⇒ أي كود يُدخَل يفشل 100 % برسالة «الكود غير صحيح». ميزة معلَن عنها لا يمكن أن تنجح أبداً | `GatewayView.swift:579` · `GatewayView.swift:672-677` · `ActivationService.swift:124` · `Core.swift:385` · `Core.swift:184` | **REJECTION** |
| **M-1** | **2.1 App Completeness (Review Notes)** | تطبيق خلف تسجيل دخول **يجب** أن يحمل حساباً تجريبياً/طريقة دخول في ملاحظات App Store Connect. الوضع التجريبي موجود لكن زرّه **نص رمادي ثانوي** نصّه الإنجليزي «Try it first» — لا يحمل كلمة demo/guest | `GatewayView.swift:640-642` · `Core.swift:387` | **METADATA REJECTION** |
| **M-2** | **5.2.3 · 2.3.1 Accurate Metadata** | صياغة صفحة المتجر: كلمة «IPTV»، وأي وعد بقنوات/باقات/أفلام، ولقطات شاشة تُظهر ملصقات R-1 ⇒ إشارة قرصنة مباشرة | `Core.swift:304` (`"Premium IPTV Player"`) + ملف اللقطات (خارج المستودع) | **METADATA REJECTION** |
| **M-3** | **Age Rating (2.3.6)** | التطبيق يشغّل **أي** بثّ يزوّده المستخدم = وصول غير مقيَّد لمحتوى غير مُصنَّف. لا يوجد تصنيف عمري معلَن في المستودع، والرقابة الأبوية **يمكن إطفاؤها عن بُعد** | `SettingsView.swift:236` (`if config.hasParental`) · `Services.swift:436` | **METADATA REJECTION** |
| **M-4** | **5.1.1 / App Privacy** | رابط سياسة خصوصية في App Store Connect **إلزامي** ولا يوجد أي URL في المستودع (السياسة نصّ داخلي فقط)، وبطاقة App Privacy لم تُملأ | `AuthViews.swift:362-407` (نص داخلي) · لا يوجد URL في أي ملف | **METADATA REJECTION** |
| **L-1** | **5.1.1(v) Account Deletion · 5.1.2 · DPLA 3.3.x** | «حذف الحساب» **لا يحذف** `Key.deviceID` من الـKeychain؛ المعرّف يبقى **بعد حذف التطبيق وإعادة تثبيته** (بصمة جهاز دائمة)، بينما نصّ التطبيق يَعِد بحذف «كل بياناتك» | `Core.swift:731-733` (`clearAll()` بلا `Key.deviceID`) · `Core.swift:686-690` · `DeviceID.swift:16-21` · `Core.swift:284` · `Core.swift:407` | **LIKELY REJECTION** |
| **L-2** | **3.1.1 In-App Purchase** | بطاقة تنبيه «بقي X يوم على انتهاء اشتراكك — **جدّده الآن** قبل أن تنقطع الخدمة» + زرّا **واتساب/تيليغرام** على الصفحة نفسها ⇒ نداء تجديد + قناة الشراء الفعلية | `HomeView.swift:1511-1516` · `Core.swift:502` · `HomeView.swift:1437-1448` · `Core.swift:359-360` | **LIKELY REJECTION** |
| **L-3** | **2.5.2 · 3.2.2(i)** | `ConfigService` يجلب إعدادات من **`strong8k.app`** تُغيّر سلوك التطبيق **بعد** الموافقة: بانر + رابط بانر خارجي + روابط دعم + **إطفاء الرقابة الأبوية** + ثيم كامل | `Services.swift:416-427` · `Core.swift:523-524` · `Models.swift:55-71` · `SettingsView.swift:236` | **LIKELY REJECTION** |
| K-1 | 5.2.3 | إخلاء المسؤولية («مشغّل فقط: لا نوفّر قنوات ولا نستضيف محتوى») **غير موجود على شاشة الدخول** — يظهر فقط في Settings ← About، وفي شاشة تفعيل **لا تُعرض أبداً** | `Core.swift:506-511` · `SettingsView.swift:901-907` · `ActivationView.swift:266-273` (شاشة ميتة) · `GatewayView.swift:634-665` (لا إخلاء) | RISK (عالٍ) |
| K-2 | 2.1 · 2.3.1 | التطبيق يفتح **بالعربية دائماً** متجاهلاً لغة الجهاز؛ لا توجد ملفات `.lproj` ولا `CFBundleLocalizations`؛ وكتالوج العرض عربي مُصمَت لا يتغيّر بتبديل اللغة | `Core.swift:42` · `Core.swift:35` · `Core.swift:2317-2361` · لا `.lproj` في المستودع | RISK (عالٍ) |
| K-3 | 5.1.1(i) Purpose Strings | `NSLocalNetworkUsageDescription` **بالعربية فقط** (مراجع إنجليزي يرى نصاً عربياً في نافذة النظام)، ونصّه **غير دقيق** (يذكر AirPlay، وAirPlay ليس ما يُطلق الإذن) | `Info.plist:11-12` | RISK (عالٍ) |
| K-4 | 2.5.x · ATS | `NSAllowsArbitraryLoads = true` شامل بلا استثناءات نطاقات — يتطلّب تبريراً صريحاً في ملاحظات المراجعة وإلا اسْتُدعي طلب معلومات | `Info.plist:13-16` | RISK |
| K-5 | 5.1.2 Data Use | اسم مستخدم وكلمة مرور المشترك تُخزَّن **نصاً صريحاً** في `UserDefaults` وداخل `catalog.sqlite` (عمود `scope`)، وتُرسَل في **query string فوق HTTP**، **ولا تُحذف** عند حذف الحساب | `Services.swift:112-118` · `Services.swift:127-128` · `Core.swift:1690` · `Core.swift:1734` · `Services.swift:149` · `Services.swift:322-347` | RISK (عالٍ) |
| K-6 | Privacy Manifest | `PrivacyInfo.xcprivacy` **موجود ومسجَّل في الـbuild** وصحيح في 3/3 فئات مستعملة — لكن سبب FileTimestamp خاطئ: `3B52.1` (ملفات يمنحها المستخدم عبر document picker — لا يوجد picker في التطبيق) بدل `C617.1` | `PrivacyInfo.xcprivacy:21-28` · `project.pbxproj:36,67,127,193` | RISK (منخفض) |
| K-7 | 5.1.2 | نصّ الخصوصية داخل التطبيق **يخالف الواقع**: يقول إننا نجمع معرّف الجهاز وإحصاءات (لا نفعل)، ويقول «نؤمّن الاتصال بخوادمنا» بينما الاعتماد يمرّ نصّاً صريحاً | `Core.swift:399` · `Core.swift:405` | RISK |
| K-8 | 2.1 | بوسترات الوضع التجريبي تأتي من محرّك مصغّرات Wikimedia الذي **يُقنِّن الطلبات**: 2 من 4 روابط أعادت **HTTP 429** في فحص حيّ ⇒ بطاقات فارغة برمز بديل أثناء المراجعة | `Core.swift:2312-2315` · `DesignSystem.swift:1228-1240` | RISK |
| K-9 | 2.1 · 4.2 | الكتالوج التجريبي رقيق (4 قنوات · 4 أفلام · مسلسل واحد بـ3 حلقات تعيد استخدام 3 من ملفات الأفلام)، و**«التفاصيل» وEPG وطاقم التمثيل غير قابلة للتجربة إطلاقاً** في وضع العرض | `Core.swift:2323-2362` · `Core.swift:2253` · `Core.swift:2270` · `Core.swift:2277` · `ContentViews.swift:2731` | RISK |
| K-10 | 2.3.1 Accurate Metadata | في وضع العرض تعرض الإعدادات نقطة خضراء و**«متصل · Blank Prime»** وشارة خطّة **«BASIC»** بلا أي مزوّد متصل — معلومة غير صحيحة داخل الواجهة | `SettingsView.swift:131` · `SettingsView.swift:204` | RISK |
| K-11 | Accessibility (spot-check) | **صفر دعم لـDynamic Type**: كل الخطوط `Font.system(size:)` ثابتة، وأصغرها 9pt؛ و11 `accessibilityLabel` فقط في التطبيق كله ⇒ أزرار أيقونية بلا أسماء لـVoiceOver | `DesignSystem.swift:832-849` · إحصاء `accessibilityLabel`: ContentViews 4 · DesignSystem 4 · GatewayView 2 · HomeView 1 | RISK |
| K-12 | 1.2 · 1.4.1 | لا آلية إبلاغ/حجب لمحتوى مسيء، والرقابة الأبوية (PIN + قفل تصنيفات) **قابلة للإطفاء عن بُعد** عبر L-3 | `SettingsView.swift:236` · `SettingsView.swift` (ParentalControlView) | RISK |
| K-13 | 2.1 | لا يوجد أي مراقب اتصال (`NWPathMonitor` غير موجود)، والوضع التجريبي **يعتمد كلياً على الشبكة** رغم تعليق يقول «الوضع التجريبي offline» | `ActivationView.swift:43` (تعليق مضلِّل) · `Core.swift:2297-2315` | RISK |
| K-14 | قانوني (لا مراجعة) | `MobileVLCKit 3.6.0` تحت **LGPLv2.1** — يفرض التزامات إعادة الربط/توفير الشيفرة الكائنية للمستخدم النهائي؛ التطبيق لا يعرض إشعار ترخيص | `Podfile:7` · لا شاشة تراخيص | RISK |
| K-15 | أمن/سمعة | شيفرة خلفية ميتة ما زالت داخل الـbinary: `AuthService.login` يرسل الاعتماد + معرّف الجهاز إلى `strong8k.app`، ومفتاح توقيع **مكتوب في الشيفرة** `"S8K_2025_SIGN"` | `Services.swift:25-80` (بلا مستدعين) · `Core.swift:652` · `Core.swift:523-524` | RISK |
| K-16 | 5.2.1 | محتوى العرض CC-BY (Blender) وصور Wikimedia — **بلا إسناد ترخيص** في أي شاشة، وCC-BY يوجبه | `Core.swift:2287-2378` | RISK (منخفض) |
| K-17 | 4.3 (إحالة) | تقرير التمايز يخلص إلى «حدّي — أقرب إلى الخطر»، وينصّ على أن **الوضع التجريبي تحديداً** يبدو كالتطبيق الآخر — وهو بالضبط ما سيراه المراجع بلا اشتراك | `DIFFERENTIATION_REPORT.md` §0 | RISK (عالٍ) |
| K-18 | جودة | `try?` في موضع الاستدعاء يبتلع فشل حذف الحساب بصمت: الورقة تُغلق ولا شيء يُحذف ولا رسالة خطأ | `SettingsView.swift:521` | RISK (منخفض) |

---

## 2. الحكم

> ### ⛔ **مرفوض — لا حدّي.**
>
> ### السبب الأوّل الأرجح للرفض، بلا منافس:
> **Guideline 5.2.1 / 5.2.3 — ستة ملصقات أفلام تجارية محمية مضمّنة داخل الـbinary وتُعرض ملء الشاشة على شاشة تسجيل الدخول.**

**عدد نتائج بدرجة REJECTION: 2** (R-1، R-2). ويُضاف إليهما **4 نتائج METADATA REJECTION** و**3 LIKELY REJECTION**.

**لماذا هذا هو السبب الأول:** المراجع لا يحتاج إلى فتح حساب ولا إلى قراءة الشيفرة. جدار الملصقات هو **البكسل الأول** الذي يراه، وعليه علامة **Marvel Studios** وعلامة **Disney** وشعار **Hasbro** ونصّ «©2024 PAR. PICS.». هذه ليست «صور تجريبية» — هي مواد تسويقية رسمية لأستوديوهات، في تطبيق **IPTV**، أي في الفئة التي تُدقَّق أصلاً على أنها فئة القرصنة. اجتماع الاثنين (تطبيق IPTV + فن أستوديو غير مرخَّص على شاشة الدخول) هو تعريف 5.2.3 حرفياً. وواحد من الملصقات (`gwposter4`) يحمل **علامة الفنان المائية `POSTER BY WWW.FLORE-MAQUIN.COM` مطبوعة داخل الصورة** — وهذا أوضح دليل ممكن على الاستخدام بلا ترخيص، لأنه اعتراف مطبوع بمالك الحق.

**الخبر الجيّد وسط هذا:** المسار التجريبي نفسه (المحتوى، الروابط، التشغيل) **نظيف قانونياً وهندسياً** — أفلام Blender المفتوحة على archive.org، وبثّ Apple التجريبي، وبثّ Mux. لو حُذف جدار الملصقات وحده، ينتقل التطبيق من «مرفوض بلا نقاش» إلى «حدّي قابل للقبول».

---

## 3. التفاصيل — نتيجة نتيجة

### R-1 · 5.2.1 Intellectual Property + 5.2.3 + 4.1 Copycats — **REJECTION**

**ما الذي يُشغّله.** `GatewayView.swift:16` يُعرّف:

```swift
private let gatewayPosters = ["gwposter1", "gwposter2", "gwposter3", "gwposter4", "gwposter5", "gwposter6"]
```

وتُعرَض في ثلاثة صفوف متحرّكة ملء الشاشة خلف نموذج الدخول (`GatewayView.swift:99-101`). الأصول مُجمَّعة داخل التطبيق (`Assets.xcassets` تُترجَم كاملة، فلا حاجة لتعديل pbxproj) — أي أنها **داخل الـIPA الذي يُرفع إلى Apple**.

**ما هي فعلياً — فحصتُ الست صوراً بصرياً:**

| الأصل | العمل | مالك الحق الظاهر داخل الصورة | مشكلة إضافية |
|---|---|---|---|
| `gwposter1.jpg` | **Thor: Ragnarok** | علامة **MARVEL STUDIOS** مطبوعة | شبه Idris Elba |
| `gwposter2.jpg` | **Wicked (2024)** | **Universal Pictures** في سطر الاعتمادات | أسماء وصور 7 ممثلين |
| `gwposter3.jpg` | **Manjummel Boys (2024)** | Parava Films | — |
| `gwposter4.jpg` | **Django Unchained** (فن معجبين) | **`POSTER BY WWW.FLORE-MAQUIN.COM`** مطبوع داخل الصورة | حقّ الفنان + شبه Jamie Foxx + حقّ العمل الأصلي |
| `gwposter5.jpg` | **La Belle et la Bête (2017)** | كلمة **DISNEY** بالخط الرسمي | شبه **Emma Watson** |
| `gwposter6.jpg` | **Transformers One (2024)** | **Hasbro Entertainment** + `©2024 PAR. PICS. TM HASBRO` | — |

**لماذا هي رفض مؤكّد وليست «خطراً»:**
1. **5.2.1** — استخدام أعمال محمية مملوكة للغير بلا إذن.
2. **4.1 Copycats** — استخدام علامات تجارية للغير (Marvel · Disney · Hasbro · Universal) داخل واجهة التطبيق.
3. **5.2.3** — العرض في تطبيق IPTV يوحي بأن **هذه هي المكتبة التي يوفّرها التطبيق** — وهو ادّعاء توفير محتوى، وهو بالضبط الادّعاء الذي يقتل مشغّلات IPTV.
4. **شبه الأشخاص** — Emma Watson · Idris Elba · Jamie Foxx · طاقم Wicked: حقّ الصورة والاسم، بند مستقل.
5. **الخطر يتعدّى المتجر** — تقرير حقوق مباشر من ديزني أو يونيفرسال يُنزل التطبيق فوراً، ويُلوّث حساب المطوّر بأكمله.

**تنبيه إضافي:** الصور المصدرية ما زالت **في جذر المستودع غير مُتتبَّعة** (`125814207-beast-emma-watson-film-poster-iphone-8.jpg`, `9745951-hd-hollywood-movie-poster-wallpaper.jpg`, …) — أحجامها بالبايت تطابق ملفات `gwposter*` تماماً، وهو ما أكّد مصدرها.

**الإصلاح الأدنى الدقيق:**
1. احذف المجلدات الستة `BlankTV/Assets.xcassets/gwposter1.imageset` … `gwposter6.imageset` (لا حاجة لتعديل `project.pbxproj` — الـasset catalog يُجمَّع كاملاً).
2. استبدلها بأحد ثلاثة خيارات، بالترتيب من الأأمن:
   - **(أ) الأأمن:** استبدل جدار الملصقات بنمط تجريدي مولَّد بالشيفرة (تدرّجات/مستطيلات بألوان العلامة) — صفر مخاطرة، صفر وزن، ولا يعتمد على الشبكة.
   - **(ب)** استخدم بوسترات العرض المفتوحة نفسها الموجودة أصلاً في `Core.swift:2312-2315` (Blender/Wikimedia) كأصول محلّية مضمَّنة، مع سطر إسناد صغير أسفل الشاشة.
   - **(ج) لاحقاً:** ملصقات TMDB عبر خادم المالك مع إسناد TMDB الإلزامي (البند 3 في خارطة `PROJECT_HANDOFF.md`) — لا يحلّ المشكلة قبل هذا التقديم.
3. احذف الصور المصدرية من جذر المستودع (لا تدخل الـbinary لكنها دليل نية).

---

### R-2 · 2.1 App Completeness — ميزة معلَنة لا يمكن أن تعمل — **REJECTION**

**ما الذي يُشغّله.** الحقل الأول على شاشة الدخول الحيّة نصّه الإرشادي:

```swift
// GatewayView.swift:579
S8KTextField(placeholder: L("login.server_or_code"), icon: "server.rack", text: $serverOrCode, …)
```
```swift
// Core.swift:385
"login.server_or_code": [.ar: "رابط السيرفر أو كود التفعيل", .en: "Server URL or reseller code", …]
```

وعند الإرسال، أي نصّ **بلا نقطة ولا `:` ولا `/`** يُعامَل ككود موزّع (`GatewayView.swift:686-692` `looksLikeResellerCode`) ويُمرَّر إلى:

```swift
// GatewayView.swift:672-677
let ok = await activation.resolveCode(typed)
guard ok, let host = Store.shared.resellerHost, !host.isEmpty else {
    auth.isLoading = false; auth.error = .server(L("code.invalid")); return
}
```

و`resolveCode` هي:

```swift
// ActivationService.swift:124
func resolveCode(_ code: String) async -> Bool { false }
```

**النتيجة:** الدالة تُرجع `false` **دائماً وبلا استثناء**. أي مراجع يجرّب ما يقترحه النص الإرشادي — وسيجرّبه، لأنه أسهل من كتابة رابط سيرفر — يحصل حتماً على **«الكود غير صحيح أو انتهت صلاحيته»** (`Core.swift:184`). هذه ميزة **معلَن عنها في الواجهة ومستحيلة النجاح**، وهو التعريف الحرفي لـ2.1.

**وفيها بند ثانٍ:** «كود من موزّع» على شاشة الدخول يقول للمراجع صراحةً إن فتح التطبيق يمرّ عبر **كود يُشترى خارج App Store** — إشارة 3.1.1 مباشرة، حتى لو لم تكن الميزة تعمل.

**الإصلاح الأدنى:** غيّر النص الإرشادي إلى «رابط السيرفر» فقط (`.en: "Server URL"`)، واحذف فرع `looksLikeResellerCode` من `submit()` في `GatewayView.swift:670-680` و`AuthViews.swift:224-243`. بذلك يختفي الادّعاء وتختفي إشارة 3.1.1 معاً. (احذف كذلك `code.*` من جدول `L()` و`ActivationView.swift:241-253` تنظيفاً.)

---

### M-1 · 2.1 — الحساب التجريبي وملاحظات المراجعة — **METADATA REJECTION**

الوضع التجريبي **موجود ويعمل ممتازاً** (فُصِّل في §3-الوضع التجريبي أدناه). المشكلة أنه غير قابل للاكتشاف بالسرعة المطلوبة:

- الزر **نصّ رمادي ثانوي بلا إطار ولا أيقونة**، موضوع تحت الـCTA الذهبي: `GatewayView.swift:640-642` (`.foregroundColor(.s8kTextSecondary)`).
- نصّه الإنجليزي الحالي **«Try it first»** (`Core.swift:387`) لا يحمل كلمة *demo* ولا *guest* ولا *without an account*. (كان `"Browse as Demo"` قبل تعديل الساعة 03:00 — وتلك كانت الصياغة الأصلح للمراجعة.)
- وشاشة الدخول تُفتَح **بالعربية** افتراضياً (K-2)، فالمراجع الإنجليزي يرى نصاً عربياً رمادياً صغيراً.

**Apple تشترط حرفياً:** لأي تطبيق خلف تسجيل دخول، **حساب تجريبي كامل الصلاحية** في حقل *App Review Information → Sign-In Required*، أو شرح واضح لطريقة الدخول بلا حساب. غيابه = رفض 2.1 فوري بلا فتح التطبيق.

**الإصلاح الأدنى (سطران):**
1. `Core.swift:387` → `.en: "Continue as Guest — Demo Mode"` و`.ar: "الدخول كضيف — الوضع التجريبي"`.
2. أعطِ الزرّ إطاراً واضحاً (`.overlay(RoundedRectangle…strokeBorder)`) كما في `ActivationView.swift:257-262`.
3. املأ حقل *Notes* بالنصّ الجاهز في §5.

---

### M-2 · 5.2.3 + 2.3.1 — صياغة صفحة المتجر — **METADATA REJECTION**

هذا أكثر ما يُرفَض عليه مشغّلات IPTV بعد الشيفرة نفسها. **ما يجب ألّا يظهر إطلاقاً** في الاسم/العنوان الفرعي/الكلمات المفتاحية/الوصف/اللقطات:

| ممنوع | لماذا |
|---|---|
| كلمة **IPTV** في الاسم أو العنوان الفرعي أو الكلمات المفتاحية | الكلمة نفسها مُصنَّفة إشارة قرصنة؛ التطبيق يستخدمها داخلياً في `Core.swift:304` («Premium IPTV Player») — احذفها من الواجهة والمتجر معاً |
| أي رقم قنوات/أفلام («+10000 قناة») | ادّعاء توفير محتوى ⇒ 5.2.3 |
| أسماء قنوات أو باقات أو أستوديوهات (beIN · OSN · Netflix · Disney+) | 4.1 + 5.2.1 |
| لقطات شاشة تُظهر ملصقات R-1 أو أي فن أستوديو | نفس رفض R-1 عبر الميتاداتا |
| «مجاني» / «بلا اشتراك» / «شاهد كل شيء» | ادّعاء وصول لمحتوى |
| Telegram/WhatsApp/رابط شراء في الوصف | 3.1.1 |

**ما يجب أن يظهر:** «مشغّل وسائط لاشتراكك الخاص. لا يوفّر التطبيق أي محتوى ولا يستضيفه — تُدخل أنت بيانات مزوّدك المرخَّص.» واللقطات من **الوضع التجريبي** حصراً (محتوى Blender المفتوح).

---

### M-3 · التصنيف العمري — **METADATA REJECTION**

التطبيق يشغّل **أي** رابط بثّ يُدخله المستخدم — أي محتوى غير مُصنَّف وغير مُرشَّح، تماماً كمتصفّح.

- **الواقع في الشيفرة:** لا يوجد تصنيف عمري معلَن في المستودع، والرقابة الأبوية (PIN + قفل تصنيفات) **مشروطة بعلَم عن بُعد**: `SettingsView.swift:236` → `if config.hasParental` → `Services.swift:436` → `features.parentalControl` القادم من `strong8k.app`.
- **ما يجب إعلانه:** أعلى تصنيف (**17+ / 18+**) مع الإجابة بـ«نعم» على سؤال الوصول غير المقيَّد للمحتوى/الويب. أي تصنيف أدنى مع إمكانية بثّ عشوائي = رفض ميتاداتا شبه مؤكّد.
- **إصلاح مرافق إلزامي:** فُكّ ربط الرقابة الأبوية بالـremote config — اجعل `hasParental` تُرجع `true` دائماً. رقابة أبوية يمكن لخادم إطفاؤها بعد الموافقة هي 2.5.2 صريح.

---

### M-4 · سياسة الخصوصية وبطاقة App Privacy — **METADATA REJECTION**

- **داخل التطبيق: ممتاز.** `PrivacyView` و`TermsView` عرضان أصليان (`AuthViews.swift:362-407` و`:410-440`)، ومتاحان **قبل** الدخول من تذييل البوّابة (`GatewayView.swift:657-661`) **وبعده** من الإعدادات (`SettingsView.swift:504-506`). لا روابط وهمية ولا `example.com`.
- **المفقود:** App Store Connect يطلب **رابط `https://` عاماً** لسياسة الخصوصية. لا يوجد أي URL كهذا في المستودع. بلا هذا الرابط لا يُقبل التقديم أصلاً.
- **وبطاقة App Privacy** يجب أن تُملأ. الوضع الحقيقي بعد فحص كامل: **لا شيء يُرسَل إلى خادم تابع لك في المسار الحيّ** — فالإجابة الصحيحة هي **«Data Not Collected»**. لكن هذا **يناقض** نصّ السياسة داخل التطبيق (K-7)، وApple تقارن الاثنين.

---

### L-1 · 5.1.1(v) — حذف الحساب ينجح ظاهرياً ويفشل واقعياً — **LIKELY REJECTION**

**ما يعمل (وهو الأكثر):** الميزة موجودة، داخل التطبيق بالكامل، على **4 لمسات** من الجذر (Settings ← «حول والدعم والقانوني» ← «حذف الحساب» ← «حذف نهائياً»)، بصف أحمر متميّز ونصّ تحذير لا لبس فيه، ومنفصلة تماماً عن «تسجيل الخروج» وعن «حذف قائمة تشغيل». ولا تُحيل إلى موقع أو واتساب. **والعطل الذي أُصلح حديثاً مُصلَح فعلاً على القرص** — `Services.swift:331` صار:

```swift
if mode == .xtream, !Store.shared.demoMode, Keychain.shared.token != nil {
```

فصار الحذف يكتمل في الوضع التجريبي وفي وضع M3U، وهو المسار الذي سيجرّبه المراجع. ✅

**العطل الحقيقي:**

```swift
// Core.swift:731-733
func clearAll() {
    [Key.token, Key.host, Key.user, Key.pass, Key.userID, Key.tokenExpiry].forEach { delete($0) }
}
```

`Key.deviceID` **غائب عن المصفوفة**. والتعليق على السطر 686 يشرح لماذا هذا خطير:

```swift
/// Persistent device identity (survives app reinstall — stays in Keychain)
```

فبعد «حذف الحساب وكل بياناتي»، `DeviceIdentity.current` (`DeviceID.swift:16-21`) يُعيد **نفس المعرّف**. وهو مشتقّ من `identifierForVendor` ثم **يُجمَّد في الـKeychain** — أي أنه يُبطِل عمداً آلية Apple التي تُصفّر IDVF عند حذف التطبيق. هذه بصمة جهاز دائمة، وApple تمنعها صراحةً في اتفاقية المطوّرين، ويتناقض وجودها مع وعد التطبيق نفسه في `Core.swift:284` و`Core.swift:407`.

**متبقّيات أخرى لا يمسّها `deleteAccount()` (`Services.swift:322-347`):**
- **`catalog.sqlite`** — وفيه **اسم المستخدم وكلمة المرور نصّاً صريحاً** داخل عمود `scope` (`Core.swift:1690`, `Core.swift:1734`; السلسلة مبنيّة في `Services.swift:115`).
- **ذاكرة الكتالوج JSON** (`Core.swift:1600-1610`).
- **كل الملفات المنزَّلة + بيان التنزيلات** (`Downloads.swift:494-504`, `:463-466`) — `DownloadManager.clearAll()` (`Downloads.swift:380-382`) لا يُستدعى.

**نقطة إيجابية مهمّة:** لا يوجد **تسجيل جهاز على أي خادم** في المسار الحيّ — `ActivationService` كتلة محلّية بلا شبكة (`ActivationService.swift:3-17, 116-119`)، و`AuthService.login` (المسار الوحيد الذي كان يُسجّل) **بلا مستدعين**. فلا يوجد سجلّ خادمي يتيمّ. هذا يُسقط أخطر صور 5.1.1(v).

**الإصلاح الأدنى (4 أسطر):**
```swift
// Core.swift:731-733 — أضف Key.deviceID
[Key.token, Key.host, Key.user, Key.pass, Key.userID, Key.tokenExpiry, Key.deviceID].forEach { delete($0) }
```
```swift
// Services.swift — داخل deleteAccount()، بعد السطر 336
CatalogDB.deleteAll()                 // أو احذف ملف catalog.sqlite
CatalogDiskCache.clearAll()
await DownloadService.shared.clearAll()
```
وأصلح `SettingsView.swift:521`: استبدل `try?` بـ`do/catch` يعرض الخطأ (K-18).

---

### L-2 · 3.1.1 In-App Purchase — **LIKELY REJECTION**

**ما هو صحيح ومحمود:** يوجد حارس مقصود ومكتوب بوضوح:

```swift
// Core.swift:780-787
enum AppCompliance {
    /// Guideline 3.1.1: iOS apps must NOT link out to external mechanisms for
    /// purchasing digital content/subscriptions. …
    static let allowsExternalPurchaseLinks = false
}
```

وهو يُخفي زرّ «جدّد الاشتراك» (`HomeView.swift:1419`) ويُبطل نقر البانر الخارجي (`HomeView.swift:1075`). ولا يوجد StoreKit ولا أي شراء داخلي. ✅

**ما يتجاوز الخط رغم ذلك — ثلاثة أشياء:**

1. **بطاقة تنبيه التجديد ليست محميّة بالحارس.** `HomeView.swift:1511-1516`:
   ```swift
   if user.daysRemaining <= 7 {
       alertCard(icon: "exclamationmark.triangle.fill", …
                 message: "\(L("sub.days_left_prefix")) \(user.daysRemaining) \(L("unit.day")) \(L("sub.expire_suffix"))")
   ```
   و`sub.expire_suffix` (`Core.swift:502`) نصّه: **«على انتهاء اشتراكك — جدّده قبل أن تنقطع الخدمة»** / `"left before your subscription expires — renew now to avoid interruption"`. هذا **نداء صريح للتجديد** لخدمة تُشترى خارج App Store. لا رابط فيه، وهو ما يجعله «حدّياً» لا «مؤكّداً» — لكن…

2. **…زرّا واتساب/تيليغرام يقفان على المستوى نفسه بلا حارس** (`HomeView.swift:1437-1448`):
   ```swift
   if let wa = config.appConfig.supportWhatsApp {
       supportBtn(L("home.whatsapp"), …) { UIApplication.shared.open(URL(string: "https://wa.me/\(wa)")!) }
   ```
   لاحظ: `allowsExternalPurchaseLinks` تحمي زرّ المتجر والبانر — **ولا تحمي هذين**. المراجع الذي يرى «اشتراكك ينتهي، جدّده» بجوار زرّ واتساب يستنتج المسار كاملاً: التجديد يتمّ عبر واتساب. هذا هو نمط 3.1.1 الكلاسيكي بعينه.

3. **وهما يأتيان من remote config** (L-3)، أي يمكن تشغيلهما **بعد** الموافقة.

**الإصلاح الأدنى:**
- احذف بطاقة تحذير الانتهاء أو جرّدها من نداء الفعل: اجعلها معلومة صرفة — «ينتهي اشتراكك في: {التاريخ}» بلا «جدّده الآن».
- ضع زرّي الدعم خلف الحارس نفسه، أو — الأنظف — **احذف `supportButtons` كلها من بناء iOS**، واستبدلها بصفّ بريد إلكتروني واحد للدعم في الإعدادات (البريد لا يُقرأ كقناة شراء).
- ملاحظة إيجابية: في الوضع التجريبي لا يظهر أيٌّ من هذا (`Services.swift:417` يمنع جلب الإعدادات، و`AppConfig.defaults` كلها `nil`) — لكن ذلك يعني أن الميزة **تظهر للمستخدمين ولا يراها المراجع**، وهو بالضبط ما يجعل L-3 أخطر.

---

### L-3 · 2.5.2 + 3.2.2(i) — تغيير السلوك عن بُعد بعد الموافقة — **LIKELY REJECTION**

```swift
// Services.swift:416-427
func fetchIfStale() async {
    …
    let resp: RemoteConfigResponse = try await APIClient.shared.request(path: "/config/remote")
    apply(features: resp.features, config: resp.config)
    AppTheme.shared.apply(resp.theme)
```
مع `APIConfig.primary = "https://strong8k.app/api/v1"` (`Core.swift:523-524`).

ما يستطيع الخادم تغييره بعد الموافقة (`Models.swift:37-71`): صورة بانر ورابطه الخارجي، رقم واتساب، رابط تيليغرام، رابط متجر، إعلان نصّي، **وضع صيانة يوقف التطبيق**، حدّ إصدار أدنى، **وإطفاء الرقابة الأبوية والقائمة والمؤقّت وEPG وCatchUp**.

Apple تمنع هذا صراحةً في 2.5.2 (لا تنزيل/تفعيل شيفرة أو ميزات لم تُراجَع) و3.2.2(i). وأخطر عنصرين: **إطفاء الرقابة الأبوية** (يُفرِّغ التصنيف العمري) و**رابط البانر الخارجي** (قناة شراء).

**الإصلاح الأدنى:** الدالّة **بلا مستدعين حالياً** — احذف `ConfigService.fetchIfStale` بالكامل، واجعل `features` و`appConfig` ثوابت مُجمَّعة، واجعل `hasParental` تُرجع `true`. ثم احذف `APIConfig`/`APIClient` وما تبقّى من الشيفرة الخلفية الميتة (K-15).

---

### K-1 · 5.2.3 — إخلاء المسؤولية في المكان الخطأ — RISK (عالٍ)

النصّ نفسه **ممتاز الصياغة** (`Core.swift:506-511`):

> «مشغّل فقط: لا نوفّر قنوات ولا نستضيف محتوى. اشتراكك من مزوّد مرخّص، ومشروعية ما تشاهده مسؤوليتك وحدك.»
> _"A player, nothing more: we supply no channels and host no content. Your subscription comes from a licensed provider, and what you watch is your responsibility alone."_

**لكن أين يُعرَض؟** موضعان فقط:
1. `SettingsView.swift:901-907` — داخل `AboutView`، أي **Settings ← About** (5 لمسات، آخر شاشة يفتحها مراجع).
2. `ActivationView.swift:266-273` — داخل `ActivationRequiredView`، وهي شاشة **لا تُعرض أبداً**، لأن البوّابة مثبَّتة على `.allowed` (`ActivationService.swift:45,51`).

**وأين لا يُعرَض؟** على `GatewayView` — **الشاشة الوحيدة التي يضمن المراجع رؤيتها.** تذييلها (`GatewayView.swift:634-665`) يحوي: زرّ العرض، ورابط دعم ميت، و«الشروط · الخصوصية» — ولا إخلاء مسؤولية.

**الإصلاح الأدنى (سطر واحد):** أضف داخل `footer` في `GatewayView.swift`، تحت صفّ الشروط/الخصوصية:
```swift
Text(S8KLegal.disclaimer)
    .font(S8KFont.caption2).foregroundColor(.s8kTextDisabled)
    .multilineTextAlignment(.center).lineSpacing(3)
    .padding(.horizontal, S8KSpace.lg)
```
هذا أرخص إصلاح في التقرير كله وأعلاها مردوداً على 5.2.3.

---

### K-2 · 2.1 + 2.3.1 — التطبيق يفتح بالعربية دائماً — RISK (عالٍ)

```swift
// Core.swift:42
lang = AppLang(rawValue: saved ?? "") ?? .ar
```
```swift
// Core.swift:35
nonisolated(unsafe) static var current: AppLang = .ar
```

لا قراءة لـ`Locale.preferredLanguages` في أي مكان. المراجع على جهاز إنجليزي يفتح تطبيقاً **عربياً بالكامل**: زرّ العرض، التبويبات، الإعدادات. وحتى بعد تبديل اللغة من الحبّة الذهبية (`GatewayView.swift:526-544`)، **يبقى كتالوج العرض عربياً مُصمَتاً** لأنه مكتوب حرفياً في الشيفرة: «بثّ العرض» · «أفلام مفتوحة» · «بلانك ١ · تدفّق متعدّد الجودات» · «١٠ دقائق» · «مفتوح المصدر» (`Core.swift:2317-2361`).

ويُضاعِف الأمر أنه **لا توجد ملفات `.lproj` ولا `CFBundleLocalizations`** — فسيُدرَج التطبيق في المتجر بلغة واحدة، ولن تُترجَم نصوص أذونات النظام (K-3).

**الإصلاح الأدنى:**
```swift
// Core.swift:41-43
let saved = UserDefaults.standard.string(forKey: "s8k.lang")
let system = Locale.preferredLanguages.first.flatMap { AppLang(rawValue: String($0.prefix(2))) }
lang = AppLang(rawValue: saved ?? "") ?? system ?? .ar
```
وأضف إلى `Info.plist`:
```xml
<key>CFBundleDevelopmentRegion</key><string>ar</string>
<key>CFBundleLocalizations</key>
<array><string>ar</string><string>en</string><string>fr</string><string>tr</string><string>es</string></array>
```
ومرّر أسماء `DemoContent` عبر `L()` بدل النصّ الحرفي.

---

### K-3 · 5.1.1(i) — نصوص الأذونات — RISK (عالٍ)

`Info.plist` يحوي **نصّ إذن واحداً**:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>للتواصل مع أجهزة AirPlay على نفس الشبكة</string>
```

**ثلاث مشكلات:**
1. **بالعربية فقط**، وبلا `.lproj` لا سبيل لترجمته ⇒ المراجع الإنجليزي يرى نصاً عربياً في نافذة نظام iOS. Apple ترفض نصوص أذونات غير مفهومة للمراجع.
2. **غير دقيق.** AirPlay **لا يُطلق** إذن الشبكة المحلّية — التوجيه يتمّ خارج العملية عبر `AVRoutePickerView` (`VLCPlayer.swift:690-697`). سبب الإذن الحقيقي مختلف: `Services.swift:146-159` يقبل مضيفاً مجرّداً ويضيف `http://`، فمستخدم يكتب `192.168.1.x` أو `.local` **سيُطلق** الإذن عند `URLSession`. فالنصّ يجب أن يذكر ذلك.
3. **بقيّة الفحص نظيف تماماً:** لا كاميرا، لا صور، لا موقع، لا جهات اتصال، لا ميكروفون، لا تتبّع، لا `NWBrowser`/Bonjour. **لا يوجد أي API يطلب إذناً بلا نصّه** ⇒ صفر خطر انهيار عند الاستخدام. ✅

**الإصلاح الأدنى:**
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>للاتصال بخادم الوسائط أو قائمة التشغيل على شبكتك المحلّية.
Blank Prime needs local network access to reach a media server or playlist you host on your own network.</string>
```
(نصّ ثنائي اللغة حلّ عملي إلى أن تُضاف ملفات `.lproj`.)

---

### K-4 · ATS — `NSAllowsArbitraryLoads` شامل — RISK

```xml
<!-- Info.plist:13-16 -->
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

مبرَّر تقنياً (لوحات Xtream وقوائم M3U غالباً على HTTP وعناوينها يُدخلها المستخدم، فلا يمكن سرد نطاقات)، لكن Apple تطلب التبرير عند المراجعة. **يجب ذكره صراحةً في ملاحظات المراجعة** (النصّ جاهز في §5). لا تحاول تضييقه بـ`NSExceptionDomains` — المضيفون غير معروفين مسبقاً.

**`ITSAppUsesNonExemptEncryption = false`** (`Info.plist:5-6`): **صحيح ومقبول.** التطبيق يستخدم `CryptoKit` (SHA-256 في `DeviceID.swift:32`، HMAC في `Core.swift:667-671`) وHTTPS القياسي — كلاهما ضمن الإعفاء. لا تغيّره ما لم يُضَف تشفير خاص. ✅

---

### K-6 · Privacy Manifest — موجود وصحيح تقريباً — RISK (منخفض)

**عكس المتوقَّع: `PrivacyInfo.xcprivacy` موجود، ومُدرَج في مرحلة الموارد بشكل سليم** (`project.pbxproj:36, 67, 127, 193`). وهذا يُسقط أشهر أسباب الرفض الآلي.

فحصتُ الفئات الخمس التي تُلزم Apple بتبريرها، مقابل ما يستدعيه الكود فعلاً:

| الفئة | مستعملة؟ | الدليل | معلنة؟ |
|---|---|---|---|
| `UserDefaults` | **نعم** | `Core.swift:792`, `:38`, `:41` · `ActivationService.swift:98,103` · `ContentViews.swift:3185,3295,3297` · `DesignSystem.swift:902,941` · `EngineDecisionCache.swift:28,52` · `EngineStats.swift:30,76` | ✅ `CA92.1` — صحيح |
| File timestamp | **نعم** | `Diagnostics.swift:51,54,55` · `Downloads.swift:346,567` | ⚠️ `3B52.1` — **خاطئ** |
| Disk space | **نعم** | `Downloads.swift:512-513` | ✅ `85F4.1` + `E174.1` — صحيح |
| `systemUptime` | **لا** | صفر تطابق | ✅ غائبة بحقّ |
| Active keyboard | **لا** | صفر تطابق (`UITextInputMode` غير مستعمل) | ✅ غائبة بحقّ |

**الخطأ الوحيد:** `3B52.1` تعني «طوابع ملفات منحها المستخدم صراحةً عبر document picker» — ولا يوجد `UIDocumentPickerViewController` في التطبيق إطلاقاً. كل الوصول يقع داخل حاوية التطبيق (Caches/Diagnostics و Documents/Downloads)، وسببها **`C617.1`**.

**الإصلاح الأدنى — استبدل السطر 26 في `BlankTV/PrivacyInfo.xcprivacy`:**
```xml
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>C617.1</string>
    </array>
</dict>
```

**مانيفستات الطرف الثالث:** لا `MobileVLCKit` ولا `GRDB.swift` مُدرَجان في قائمة Apple للـSDKs التي تُلزَم بمانيفست + توقيع، فلا إجراء مطلوب. لكن **بعد أول رفع** تحقّق من بريد App Store Connect بحثاً عن `ITMS-91053 (Missing API declaration)` — إن ورد باسم أحد الـpods، الحلّ هو ترقية الـpod لا تعديل مانيفست التطبيق. ولا يوجد أي SDK تحليلات/إعلانات/تتبّع في المشروع (فحص كامل لكل `import`: `AVFoundation, AVKit, CryptoKit, Foundation, GRDB, ImageIO, MediaPlayer, MetricKit, MobileVLCKit, Security, SwiftUI, UIKit, UserNotifications`)، و`NSPrivacyTracking = false` إعلان صحيح. ✅

---

### K-5 / K-7 · بيانات الاعتماد والسياسة — RISK (عالٍ)

**أين تنتهي كلمة مرور المشترك فعلياً:**
```swift
// Services.swift:112-118 — المسار الحيّ
let url = "\(base)/player_api.php?username=\(eu)&password=\(ep)"
Store.shared.m3uURL = url            // ← UserDefaults، نصّ صريح
```
```swift
// Services.swift:127-128
let pl = SavedPlaylist(name: u, kind: .m3u, url: url)
Store.shared.activePlaylistID = Store.shared.upsertPlaylist(pl)   // ← UserDefaults أيضاً
```
```swift
// Core.swift:1690 و :1734
Task.detached(priority: .utility) { CatalogDB.save(built, scope: urlString) }   // ← عمود scope في SQLite
```
وعند غياب المخطّط يُضاف `http://` (`Services.swift:149`) ⇒ الاعتماد يعبر الشبكة **في query string غير مشفّر**.

الـKeychain **مستعمل بشكل صحيح** (`Core.swift:722-724, 744` بـ`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) — لكن فقط من `AuthService.login` **الميت**. المسار الحيّ لا يستعمله.

هذا متأصّل في بروتوكول Xtream Codes وكل مشغّلات IPTV تفعله، لذلك ليس رفضاً — لكنه **يناقض** نصّ السياسة داخل التطبيق:
- `Core.swift:405`: «نشفّر كلمات المرور ونؤمّن الاتصال بخوادمنا» — لا يحدث.
- `Core.swift:399`: «بيانات دخولك، ومعرّف جهازك، وإحصاءات استخدام أساسية بموافقتك» — التطبيق **لا يرسل أياً منها** لأي خادم تابع لك في المسار الحيّ.

Apple تقارن نصّ السياسة ببطاقة App Privacy. سياسة تُقرّ بجمع لا يحدث، بينما البطاقة تقول «لا نجمع» = تناقض يُرصَد.

**الإصلاح الأدنى:** خزّن الاعتماد في الـKeychain وابنِ الـURL عند الطلب؛ واستعمل مفتاح نطاق **مُجزَّأ** (`sha256(url)`) كـ`scope` في `CatalogDB` بدل الـURL الخام؛ وأعد كتابة `Core.swift:399` و`:405` لتطابق الواقع؛ واحذف الشيفرة الخلفية الميتة (K-15) بما فيها المفتاح المكتوب في الشيفرة `"S8K_2025_SIGN"` (`Core.swift:652`).

---

### الوضع التجريبي — تتبّع كامل من الطرف إلى الطرف (2.1)

**الخلاصة: يعمل. هذا أقوى ما في التطبيق أمام المراجعة**، ولا يوجد فيه أي طريق مسدود.

**الدخول:** `SplashView` (~0.75 ث) ← `ActivationGate` (يمرّ دائماً، `ActivationService.swift:45,51`) ← `GatewayView()` (`BlankTVApp.swift:206`). لا جدار دخول ولا اتصال خادم. `enterDemo()` (`Services.swift:283-290`) لا يستعمل الشبكة ولا يمكن أن يفشل، ويُحفَظ ويُستعاد عند إعادة التشغيل (`Services.swift:371-372`).

**المحتوى (`Core.swift:2287-2378`) — نظيف الترخيص، وفحصتُ كل رابط حيّاً:**

| الرابط | الحالة |
|---|---|
| `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8` | 200 · HLS من Apple |
| `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8` · `…/pts_shift/master.m3u8` | 206 · بثّ Mux تجريبي عام |
| `archive.org/download/CosmosLaundromatFirstCycle/…` · `CaminandesLlamigos/…` · `GlassHalf1080p/…` · `sprite-fright-2021/…` | 206 · `video/mp4` · أفلام Blender المفتوحة **CC-BY** |

كلها HTTPS، حيّة، وقابلة للـbyte-range (أي قابلة للتقديم/التأخير، وهو ما يحتاجه المشغّل). **صفر محتوى محمي للغير، صفر رابط ميت، صفر عنصر نائب.**

**كل تبويب مع بيانات العرض:**
- **الرئيسية** — Hero بـ5 بطاقات، «الأجدد» 4 أفلام + مسلسل، «Top 10» 4 و1، «قنوات» 4. «تابع المشاهدة» **مخفيّ** لا فارغ (`HomeView.swift:1213`). أزرار الدعم غائبة (الإعدادات البعيدة `nil` في العرض). ✅
- **مباشر** — 4 قنوات، والتصنيف يعمل، و**التشغيل يبدأ تلقائياً** في مشغّل مدمج على iPhone (`ContentViews.swift:167, 717`) ⇒ المراجع يرى بثّاً حقيقياً خلال ثوانٍ. شريط EPG يختفي كلياً بدل أن يظهر فارغاً (`ContentViews.swift:734-770`). ✅
- **أفلام / مسلسلات** — Hero + Top-10 + صفّ تصنيف واحد ممتلئ؛ تبويبا «المفضّلة/السجل» يعرضان حالات فراغ مترجَمة صحيحة. ✅
- **البحث** — يعمل (يتجاوز مسار FTS في العرض ويعود للمسح الذاكري، `ContentViews.swift:3212-3254`). ✅
- **الإعدادات** — كل شيء يعمل؛ الخلل تجميلي فقط (K-10). ✅
- **التنزيلات** — **تعمل في العرض**: `DownloadControl` غير مقيَّد بأي علَم (`FeaturesConfig.defaults.downloads == false` في `Models.swift:49` **بلا أي مستهلك** في المشروع)، وarchive.org يدعم 206 ⇒ المراجع يستطيع تنزيل فيلم ومشاهدته دون اتصال. ✅
- **صفحات التفاصيل** — عنوان، تقييم، سطر بيانات، زرّ تشغيل، مفضّلة، تنزيل، ملخّص. قسم طاقم التمثيل **مخفيّ** لأن `cast == nil` (`Core.swift:2370`) ولا يظهر صفّاً فارغاً. ✅
- **زرّ «التفاصيل» ليس زراً ميتاً** — خلافاً لما يوحي به `PROJECT_HANDOFF.md` §10 (**تلك الفقرة قديمة**). الميزة مبنيّة (`Models.swift:192-221`, `DesignSystem.swift:526`) ومعروضة شرطياً:
  ```swift
  if let d = m.details, !d.isEmpty {   // ContentViews.swift:2731
  ```
  وفي العرض `details == nil` (`Core.swift:2253, 2270`) فلا يُرسَم الزرّ أصلاً. **لا ورقة فارغة، لا زرّ بلا وظيفة.** ✅

**نقاط الضعف الحقيقية الوحيدة في المسار (K-8، K-9، K-10):** بوسترات Wikimedia تُقنَّن (429 في 2 من 4)، والكتالوج رقيق، و«التفاصيل»/EPG/الطاقم لا يمكن تجربتها إطلاقاً، والإعدادات تكذب بـ«متصل · BASIC».

**الإصلاح الأدنى:** ضمّن بوسترات العرض الأربعة كأصول محلّية (تحلّ K-8 وتحلّ نصف R-1 بحجرٍ واحد)؛ وأضف عنصراً واحداً بـ`details` مُعبّأة يدوياً وقناة واحدة بـEPG وهمي حتى يرى المراجع الميزتين؛ واستثنِ `demoMode` من نصّ «متصل» وشارة الخطّة.

---

### الجوانب التقنية/الثنائية — ما فُحص وما نتيجته

| البند | النتيجة |
|---|---|
| **`UIBackgroundModes`** | `audio` فقط (`Info.plist:7-10`) — **مبرَّر**: `AVAudioSession` مضبوط على `.playback/.moviePlayback` (`BlankTVApp.swift:270-274`). ✅ |
| **`URLSession` الخلفية للتنزيل** | `URLSessionConfiguration.background` (`Downloads.swift:62-64`) **لا تتطلّب** إدخال `UIBackgroundModes` — وهي بحقّ غير معلَنة. و`handleEventsForBackgroundURLSession` مُنفَّذ (`BlankTVApp.swift:80`). ✅ |
| **`ITSAppUsesNonExemptEncryption`** | موجود = `false`، وصحيح (CryptoKit + HTTPS فقط). ✅ |
| **APIs خاصّة/مهجورة** | لا شيء. `UIScreen.main` مستعمل لسطوع المشغّل (`PlayerView.swift:145, 608, 616`) وهو API عام؛ و`delaysContentTouches = false` (`GatewayView.swift:129`) خاصيّة عامّة على `UIScrollView`. لا `valueForKey`/`NSClassFromString`/رموز `_UI`. ✅ |
| **أيقونة التطبيق** | `AppIcon1024.png` — 1024×1024، **colortype 2 (بلا قناة ألفا)**. ✅ |
| **دعم iPad** | `TARGETED_DEVICE_FAMILY = "1,2"` مع كل الاتجاهات وبلا `UIRequiresFullScreen` ⇒ Split View/Slide Over إلزاميان. تمريرة توافق الأجهزة موثّقة في `DEVICE_MATRIX.md` ونظام `S8KMetrics` مبنيّ لذلك. `ShareActivityView` (`VLCPlayer.swift:610-616`) — أشهر سبب انهيار iPad (`UIActivityViewController` بلا popover) — **معرَّف وغير مستعمل**، فلا خطر. ⚠️ يبقى مطلوباً اختبار جهاز فعلي. |
| **بلا شبكة** | لا `NWPathMonitor` في المشروع. الوضع التجريبي يعتمد كلياً على الشبكة ⇒ في وضع الطيران: بوسترات فارغة وفشل تشغيل بلا رسالة مفيدة. ⚠️ K-13 |
| **إمكانية الوصول** | صفر Dynamic Type — كل الخطوط `Font.system(size:)` ثابتة وأصغرها **9pt** (`DesignSystem.swift:832-849`)؛ و**11 `accessibilityLabel` فقط** في التطبيق كله ⇒ أزرار أيقونية (شريط التبويب، أدوات المشغّل، الإغلاق، القلب) بلا أسماء VoiceOver. ⚠️ K-11 |

---

## 4. قائمة الإصلاحات مرتّبة قبل التقديم التالي

### المرحلة صفر — لا تُقدِّم قبلها (تمنع رفضاً مؤكّداً)

| # | الإصلاح | الجهد |
|---|---|---|
| 1 | **احذف `gwposter1…6.imageset` الستة** واستبدل جدار الملصقات بنمط تجريدي مولَّد بالشيفرة أو ببوسترات Blender المفتوحة المضمَّنة. واحذف الصور المصدرية من جذر المستودع. | **1–2 ساعة** |
| 2 | **أزل ادّعاء «كود التفعيل»**: غيّر `login.server_or_code` إلى «رابط السيرفر» فقط، واحذف فرع `looksLikeResellerCode` من `GatewayView.submit()` و`AuthViews`. | **30 دقيقة** |
| 3 | **أضف إخلاء المسؤولية إلى تذييل `GatewayView`** (`S8KLegal.disclaimer`، 6 أسطر). | **10 دقائق** |
| 4 | **اجعل زرّ الوضع التجريبي واضحاً**: نصّ «Continue as Guest — Demo Mode» + إطار مرئي. | **15 دقيقة** |
| 5 | **`Key.deviceID` إلى `Keychain.clearAll()`** + احذف `catalog.sqlite` والذاكرة والتنزيلات داخل `deleteAccount()` + استبدل `try?` بـ`do/catch` في `SettingsView.swift:521`. | **1 ساعة** |

### المرحلة الأولى — قبل التقديم أيضاً (تمنع رفضاً مرجّحاً)

| # | الإصلاح | الجهد |
|---|---|---|
| 6 | **احذف `ConfigService.fetchIfStale`** واجعل `features`/`appConfig` ثوابت، و`hasParental = true` دائماً. | **45 دقيقة** |
| 7 | **جرّد نداء التجديد**: احذف «جدّده الآن» من `sub.expire_suffix`، وضع زرّي واتساب/تيليغرام خلف `AppCompliance` أو احذفهما من iOS. | **30 دقيقة** |
| 8 | **افتراض لغة الجهاز** (`Core.swift:41-43`) + `CFBundleLocalizations` + مرّر أسماء `DemoContent` عبر `L()`. | **2 ساعة** |
| 9 | **أعد كتابة `NSLocalNetworkUsageDescription`** ثنائي اللغة ودقيق السبب. | **10 دقائق** |
| 10 | **`3B52.1` → `C617.1`** في `PrivacyInfo.xcprivacy`. | **5 دقائق** |
| 11 | **أعد كتابة `Core.swift:399` و`:405`** ليطابق نصّ الخصوصية الواقع، وطابقه ببطاقة App Privacy = *Data Not Collected*. | **30 دقيقة** |
| 12 | **انشر سياسة خصوصية على URL عام** (صفحة ثابتة تكفي) لحقل App Store Connect. | **1 ساعة** |
| 13 | **املأ ملاحظات المراجعة** بالنصّ الجاهز في §5 (يغطّي الوضع التجريبي + تبرير ATS + نموذج «لا محتوى»). | **10 دقائق** |
| 14 | **أعلن التصنيف العمري 17+/18+** مع الإجابة الصادقة عن الوصول غير المقيَّد. | **10 دقائق** |

### المرحلة الثانية — بعد القبول، أو قبله إن اتّسع الوقت

| # | الإصلاح | الجهد |
|---|---|---|
| 15 | احذف الشيفرة الخلفية الميتة كاملة: `AuthService.login`, `APIConfig`, `APIClient`, ومفتاح `"S8K_2025_SIGN"`. | **1–2 ساعة** |
| 16 | انقل اعتماد Xtream إلى الـKeychain، و`scope` مُجزَّأ في `CatalogDB` بدل الـURL الخام. | **3–4 ساعات** |
| 17 | ضمّن بوسترات العرض محلّياً (يحلّ 429) + أضف عنصراً بـ`details` وقناة بـEPG ليُجرَّبا. | **2 ساعة** |
| 18 | استثنِ `demoMode` من «متصل · BASIC» في الإعدادات. | **20 دقيقة** |
| 19 | Dynamic Type في `S8KFont` (`relativeTo:`) + `accessibilityLabel` لكل زرّ أيقوني. | **4–6 ساعات** |
| 20 | `NWPathMonitor` + شاشة «لا اتصال» بإعادة محاولة. | **2 ساعة** |
| 21 | شاشة تراخيص (LGPL لـ`MobileVLCKit`، MIT لـThumbHash، CC-BY لمحتوى Blender). | **1 ساعة** |
| 22 | نفّذ توصيات `DIFFERENTIATION_REPORT.md` — خصوصاً `SplashView` وشاشة المشغّل، لأن **الوضع التجريبي هو ما يراه المراجع**، وهو أشبه ما يكون بالتطبيق الآخر. | حسب التقرير |

---

## 5. مسودة ملاحظات App Store Connect — انسخها كما هي

> ضعها في **App Review Information → Notes**. وفعّل **Sign-In Required** واملأ الحقلين بالقيم أدناه.

### الحقول

| الحقل | القيمة |
|---|---|
| **Sign-In Required** | ✅ نعم |
| **Username** | `demo` |
| **Password** | `demo` |
| **Notes** | النصّ أدناه (إنجليزي ثم عربي) |

> ⚠️ **مهم:** حقلا Username/Password أعلاه **قيمتان صوريتان** لأن التطبيق لا يملك حسابات. **يجب** أن تشرح ذلك في الملاحظات كما في النصّ — وإلا حاول المراجع تسجيل الدخول بهما وفشل ورفض تحت 2.1. البديل الأنظف هو إلغاء تفعيل *Sign-In Required* والاعتماد كلياً على شرح الوضع التجريبي.

### English (الأساسي — اكتبه أولاً)

```
HOW TO REVIEW THIS APP — NO SUBSCRIPTION OR ACCOUNT IS NEEDED

Blank Prime is a media PLAYER. It hosts no content, supplies no channels, and
sells nothing. The user brings their own playlist from a provider they already
pay for (an Xtream Codes login or an M3U playlist URL). There is no in-app
purchase and no external purchase link of any kind.

TO REVIEW WITHOUT ANY CREDENTIALS:
On the first screen, below the green "Sign In" button, tap
"Continue as Guest — Demo Mode".
This opens the full app immediately with a built-in sample catalogue. No
account, no password, no network account of any kind is required.

The "demo / demo" credentials in the fields above are placeholders only — the
app has no user accounts of its own. Please use the Demo Mode button.

WHAT DEMO MODE CONTAINS (all content is openly licensed):
- 4 live channels: Apple's public HLS sample stream and Mux public test streams
- 4 movies and 1 series: Blender Foundation open movies (CC-BY) hosted on
  archive.org — "Sprite Fright", "Cosmos Laundromat", "Caminandes: Llamigos",
  "Glass Half"
- Artwork: Wikimedia Commons
Every tab, search, the detail pages, offline downloads and real playback all
work in Demo Mode. Nothing is locked, time-limited or gated behind a purchase.

ACCOUNT DELETION (Guideline 5.1.1(v)):
Settings tab -> "About & Legal" -> "Delete Account" -> "Delete Permanently".
Fully in-app, four taps from the app root, works in Demo Mode.

ARBITRARY LOADS (NSAllowsArbitraryLoads):
The app connects to media servers whose addresses the USER types in. Those
hosts are unknown at build time and many IPTV panels are HTTP-only, so a
per-domain ATS exception list is not possible. The exception is used solely to
reach user-supplied media endpoints. All first-party and demo endpoints in the
app are HTTPS.

BACKGROUND MODES:
"audio" is declared because playback continues when the app is backgrounded
(AVAudioSession category .playback). Downloads use a background URLSession,
which does not require a background mode.

LANGUAGE:
The app is Arabic-first. A language switch is on the first screen — the gold
globe pill at the top of the sign-in screen switches the whole app to English.

CONTENT AND RIGHTS:
The app plays only what the user's own licensed provider serves. It performs no
search, aggregation, indexing or discovery of third-party content, and ships no
preset servers, bundled playlists or provider directory. This is stated in the
app itself on the sign-in screen and in Settings -> About.
```

### العربية (اختياري — ألحقه بعد الإنجليزي)

```
كيف تُراجَع هذه النسخة — لا حاجة إلى اشتراك ولا إلى حساب

«Blank Prime» مشغّل وسائط. لا يستضيف محتوى، ولا يوفّر قنوات، ولا يبيع شيئاً.
المستخدم يُدخل قائمة التشغيل الخاصة به من مزوّد يدفع له أصلاً (تسجيل دخول
Xtream Codes أو رابط قائمة M3U). لا توجد مشتريات داخل التطبيق ولا أي رابط
شراء خارجي.

للمراجعة بلا أي بيانات دخول:
في الشاشة الأولى، تحت زرّ «تسجيل الدخول»، اضغط
«الدخول كضيف — الوضع التجريبي».
يفتح التطبيق كاملاً فوراً بكتالوج تجريبي مدمج. لا حساب ولا كلمة مرور.

محتوى الوضع التجريبي (كله مرخَّص بشكل مفتوح):
- 4 قنوات مباشرة: بثّ Apple التجريبي العام وبثّ Mux التجريبي العام
- 4 أفلام ومسلسل واحد: أفلام Blender Foundation المفتوحة (CC-BY) على archive.org
- الصور: Wikimedia Commons
كل التبويبات والبحث وصفحات التفاصيل والتنزيل دون اتصال والتشغيل الحقيقي تعمل
في الوضع التجريبي. لا شيء مقفل ولا محدود بوقت ولا خلف دفع.

حذف الحساب (Guideline 5.1.1(v)):
تبويب الإعدادات ← «حول والدعم والقانوني» ← «حذف الحساب» ← «حذف نهائياً».
داخل التطبيق بالكامل، على أربع لمسات من الجذر، ويعمل في الوضع التجريبي.

استثناء ATS:
التطبيق يتصل بخوادم وسائط يكتب المستخدم عناوينها بنفسه، وهي غير معروفة وقت
البناء وكثير منها HTTP فقط، فلا يمكن سرد نطاقات محدّدة. كل نقاط الاتصال
الخاصة بالتطبيق وبالوضع التجريبي HTTPS.

المحتوى والحقوق:
لا يشغّل التطبيق إلا ما يقدّمه مزوّد المستخدم المرخَّص. لا يقوم بأي بحث أو
تجميع أو فهرسة أو اكتشاف لمحتوى الغير، ولا يتضمّن أي خادم جاهز أو قائمة
تشغيل مضمّنة أو دليل مزوّدين. وهذا منصوص عليه داخل التطبيق نفسه على شاشة
الدخول وفي الإعدادات ← حول.
```

---

## 6. ما هو سليم فعلاً — لا تُصلحه

حتى لا يُهدَر وقت على ما لا يحتاج تغييراً:

- ✅ **`PrivacyInfo.xcprivacy` موجود ومُدرَج في الـbuild**، ويغطّي 3/3 من الفئات المستعملة فعلاً. (تصحيح واحد فقط: `3B52.1` → `C617.1`.)
- ✅ **لا يوجد API يطلب إذناً بلا نصّ سبب** — صفر خطر انهيار أو رفض آلي من هذا الباب.
- ✅ **حذف الحساب داخل التطبيق، على 4 لمسات، بعنوان صريح، منفصل عن تسجيل الخروج**، والعطل الذي أُصلح في commit `5d38747` **مُصلَح فعلاً على القرص**.
- ✅ **لا يوجد تسجيل جهاز على خادم في المسار الحيّ** ⇒ لا سجلّ خادمي يتيمّ بعد الحذف.
- ✅ **صفر SDK تحليلات/إعلانات/تتبّع**، و`NSPrivacyTracking = false` إعلان صادق.
- ✅ **محتوى الوضع التجريبي نظيف الترخيص تماماً** (Blender CC-BY · Apple · Mux · Wikimedia) وكل روابطه حيّة ويعمل التشغيل فعلاً.
- ✅ **الوضع التجريبي بلا أي قيد أو عدّاد أو ترويج للشراء** — سبعة عشر موضع اختلاف سلوكي فحصتُها كلها، ولا واحد منها بوّابة دفع.
- ✅ **`AppCompliance.allowsExternalPurchaseLinks = false`** — قرار هندسي صحيح ومكتوب بوعي بالبند 3.1.1 (يحتاج فقط توسيع تغطيته إلى زرّي الدعم).
- ✅ **`ITSAppUsesNonExemptEncryption = false`** صحيح، و**`UIBackgroundModes = [audio]`** مبرَّر ومستعمل فعلاً، و**التنزيل الخلفي معلَن ومنفَّذ بشكل سليم**.
- ✅ **أيقونة 1024×1024 بلا قناة ألفا**.
- ✅ **زرّ «التفاصيل» ليس زراً ميتاً** — معروض شرطياً بشكل صحيح؛ فقرة `PROJECT_HANDOFF.md` §10 عنه **قديمة وتحتاج تحديثاً**.
- ✅ **لا APIs خاصّة ولا مهجورة**، ولا `UIActivityViewController` معروض بلا popover على iPad.

---

_انتهى التقرير. لم يُعدَّل أي ملف مصدري أثناء إعداده._
