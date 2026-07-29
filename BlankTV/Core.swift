// ============================================================
// Blank Prime — Core.swift
// Network + Storage + Security — All in one file
// ============================================================

import Foundation
import Security
import CryptoKit
import UIKit
import SwiftUI

// MARK: ════════════════════════════════════════
// LOCALIZATION — multi-language (AR / EN / FR / TR / ES)
// ════════════════════════════════════════════
enum AppLang: String, CaseIterable, Identifiable {
    case ar, en, fr, tr, es
    var id: String { rawValue }
    var display: String {
        switch self {
        case .ar: return "العربية"
        case .en: return "English"
        case .fr: return "Français"
        case .tr: return "Türkçe"
        case .es: return "Español"
        }
    }
    var isRTL: Bool { self == .ar }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    /// Nonisolated mirror of the current language for string lookups from
    /// anywhere (updated on the main thread whenever `lang` changes).
    nonisolated(unsafe) static var current: AppLang = .ar

    @Published var lang: AppLang {
        didSet { Self.current = lang; UserDefaults.standard.set(lang.rawValue, forKey: "s8k.lang") }
    }
    private init() {
        let saved = UserDefaults.standard.string(forKey: "s8k.lang")
        lang = AppLang(rawValue: saved ?? "") ?? .ar
        Self.current = lang
    }
    func set(_ l: AppLang) { lang = l }
}

/// Convenience — `L("tab.home")` (nonisolated; reads the current language mirror).
func L(_ key: String) -> String {
    L10n.table[key]?[LocalizationManager.current] ?? L10n.table[key]?[.en] ?? key
}

enum L10n {
    // key : [lang : value]   (Arabic is the source of truth)
    static let table: [String: [AppLang: String]] = [
        "tab.home":    [.ar: "الرئيسية", .en: "Home",    .fr: "Accueil", .tr: "Ana Sayfa", .es: "Inicio"],
        "tab.live":    [.ar: "مباشر",   .en: "Live",    .fr: "Direct",  .tr: "Canlı",    .es: "En directo"],
        "tab.movies":  [.ar: "أفلام",   .en: "Movies",  .fr: "Films",   .tr: "Filmler",  .es: "Cine"],
        "tab.series":  [.ar: "مسلسلات", .en: "Series",  .fr: "Séries",  .tr: "Diziler",  .es: "Series"],
        "tab.settings":[.ar: "إعدادات", .en: "Settings",.fr: "Réglages",.tr: "Ayarlar",  .es: "Ajustes"],
        "ctab.all":      [.ar: "الكل",     .en: "All",       .fr: "Tout",     .tr: "Tümü",      .es: "Todo"],
        "ctab.favorites":[.ar: "المفضلة",  .en: "Favorites", .fr: "Favoris",  .tr: "Favoriler", .es: "Favoritos"],
        "ctab.newest":   [.ar: "الأجدد",   .en: "Newest",    .fr: "Nouveautés",  .tr: "Yeniler",   .es: "Novedades"],
        "ctab.history":  [.ar: "السجل",    .en: "History",   .fr: "Historique",.tr: "Geçmiş",   .es: "Historial"],
        "common.play":    [.ar: "تشغيل",   .en: "Play",     .fr: "Lire",     .tr: "Oynat",   .es: "Reproducir"],
        "common.details": [.ar: "التفاصيل",.en: "Details",  .fr: "Détails",  .tr: "Detaylar",.es: "Detalles"],
        "common.all":     [.ar: "الكل",    .en: "See all",  .fr: "Voir tout",.tr: "Hepsini gör",    .es: "Ver todo"],
        "common.retry":   [.ar: "حاول ثانيةً", .en: "Try again", .fr: "Réessayer", .tr: "Tekrar dene", .es: "Reintentar"],
        "common.close":   [.ar: "إغلاق",   .en: "Close",    .fr: "Fermer",   .tr: "Kapat",   .es: "Cerrar"],
        "common.cancel":  [.ar: "إلغاء",   .en: "Cancel",   .fr: "Annuler",  .tr: "İptal",   .es: "Cancelar"],
        "common.save":    [.ar: "حفظ",     .en: "Save",     .fr: "Enregistrer", .tr: "Kaydet", .es: "Guardar"],
        "reorder.button": [.ar: "ترتيب",   .en: "Sort",     .fr: "Trier",    .tr: "Sırala",  .es: "Ordenar"],
        "reorder.title":  [.ar: "ترتيب الأقسام", .en: "Reorder Categories", .fr: "Ordre des catégories", .tr: "Kategori sırası", .es: "Orden de categorías"],
        "reorder.manage": [.ar: "ترتيب المحتوى", .en: "Organize Content", .fr: "Organiser le contenu", .tr: "İçeriği Düzenle", .es: "Organizar contenido"],
        "reorder.manage.desc":[.ar: "رتّب أقسام الأفلام والمسلسلات والبث في مكان واحد", .en: "Arrange Movies, Series & Live categories in one place", .fr: "Organisez les catégories en un seul endroit", .tr: "Tüm kategorileri tek yerde düzenleyin", .es: "Organiza todas las categorías en un lugar"],
        "reorder.quick":  [.ar: "ترتيب سريع", .en: "Quick sort", .fr: "Tri rapide", .tr: "Hızlı sıralama", .es: "Orden rápido"],
        "reorder.applied":[.ar: "تم التطبيق — اسحب للتخصيص", .en: "Applied — drag to fine-tune", .fr: "Appliqué — glissez pour ajuster", .tr: "Uygulandı — sürükleyin", .es: "Aplicado — arrastra para ajustar"],
        "region.arabic":  [.ar: "عربي", .en: "Arabic", .fr: "Arabe", .tr: "Arapça", .es: "Árabe"],
        "region.european":[.ar: "أوروبي", .en: "European", .fr: "Européen", .tr: "Avrupa", .es: "Europeo"],
        "region.american":[.ar: "أمريكي", .en: "American", .fr: "Américain", .tr: "Amerikan", .es: "Americano"],
        "accounts.switch":[.ar: "تبديل الحساب", .en: "Switch account", .fr: "Changer de compte", .tr: "Hesap değiştir", .es: "Cambiar cuenta"],
        "detail.resume": [.ar: "متابعة", .en: "Resume", .fr: "Reprendre", .tr: "Devam et", .es: "Reanudar"],
        "common.more":[.ar: "المزيد", .en: "More", .fr: "Plus", .tr: "Daha fazla", .es: "Más"],
        "common.less":  [.ar: "أقل",   .en: "Less", .fr: "Moins", .tr: "Daha az", .es: "Menos"],
        "detail.episodes_n": [.ar: "حلقة", .en: "episodes", .fr: "épisodes", .tr: "bölüm", .es: "episodios"],
        "a11y.pause":       [.ar: "إيقاف مؤقّت",    .en: "Pause",       .fr: "Pause",             .tr: "Duraklat",      .es: "Pausa"],
        "a11y.add_account": [.ar: "إضافة حساب",     .en: "Add account", .fr: "Ajouter un compte", .tr: "Hesap ekle",    .es: "Añadir cuenta"],
        "a11y.refresh":     [.ar: "تحديث",          .en: "Refresh",     .fr: "Actualiser",        .tr: "Yenile",        .es: "Actualizar"],
        "a11y.clear_text":  [.ar: "مسح ما كُتب",     .en: "Clear text",  .fr: "Effacer le texte",  .tr: "Metni temizle", .es: "Borrar texto"],
        "a11y.reorder":     [.ar: "إعادة الترتيب",  .en: "Reorder",     .fr: "Réorganiser",       .tr: "Yeniden sırala",.es: "Reordenar"],
        "a11y.show_password":[.ar: "إظهار كلمة المرور", .en: "Show password", .fr: "Afficher le mot de passe", .tr: "Şifreyi göster", .es: "Mostrar contraseña"],
        "a11y.hide_password": [.ar: "إخفاء كلمة المرور", .en: "Hide password", .fr: "Masquer le mot de passe", .tr: "Şifreyi gizle", .es: "Ocultar contraseña"],
        "accounts.title": [.ar: "الحسابات", .en: "Accounts", .fr: "Comptes", .tr: "Hesaplar", .es: "Cuentas"],
        "accounts.add":   [.ar: "إضافة حساب", .en: "Add account", .fr: "Ajouter un compte", .tr: "Hesap ekle", .es: "Añadir cuenta"],
        "accounts.current":[.ar: "الحساب الحالي", .en: "Current", .fr: "Actuel", .tr: "Mevcut", .es: "Actual"],
        "accounts.rename":[.ar: "تعديل الاسم", .en: "Rename", .fr: "Renommer", .tr: "Yeniden adlandır", .es: "Renombrar"],
        "accounts.name_ph":[.ar: "اسم الحساب", .en: "Account name", .fr: "Nom du compte", .tr: "Hesap adı", .es: "Nombre de la cuenta"],
        "reorder.search": [.ar: "ابحث عن قسم…", .en: "Search a category…", .fr: "Trouver une catégorie…", .tr: "Kategori bul…", .es: "Encontrar categoría…"],
        "error.invalid_credentials":[.ar: "اسم المستخدم أو كلمة المرور غير صحيحة", .en: "Incorrect username or password", .fr: "Identifiant ou mot de passe incorrect", .tr: "Kullanıcı adı ya da şifre hatalı", .es: "Usuario o contraseña no válidos"],
        "error.account_suspended":[.ar: "تم تعليق حسابك — تواصل مع الدعم الفني", .en: "Your account is suspended — contact support", .fr: "Compte suspendu — écrivez au support", .tr: "Hesabınız askıda — destek ekibine yazın", .es: "Cuenta suspendida — escribe a soporte"],
        "error.account_expired":[.ar: "انتهت صلاحية اشتراكك — يرجى التجديد", .en: "Your subscription has expired — please renew", .fr: "Abonnement expiré — pensez à le renouveler", .tr: "Aboneliğiniz sona erdi — lütfen yenileyin", .es: "Suscripción vencida — renuévala para seguir"],
        "error.max_connections":[.ar: "تم الوصول للحد الأقصى (%ld أجهزة)", .en: "Device limit reached (%ld devices)", .fr: "Vous avez atteint la limite (%ld appareils)", .tr: "Cihaz limiti doldu (%ld cihaz)", .es: "Has llegado al límite (%ld dispositivos)"],
        "error.maintenance":[.ar: "التطبيق في وضع الصيانة", .en: "The app is under maintenance", .fr: "L'app est en maintenance", .tr: "Uygulama şu an bakımda", .es: "La app está en mantenimiento"],
        "error.version_outdated":[.ar: "يرجى تحديث التطبيق إلى الإصدار %@ أو أحدث", .en: "Please update the app to version %@ or newer", .fr: "Passez à la version %@ ou plus récente", .tr: "Uygulamayı %@ ya da daha yeni sürüme geçirin", .es: "Pasa a la versión %@ o más reciente"],
        "error.network":[.ar: "خطأ في الاتصال: %@", .en: "Connection error: %@", .fr: "Problème de connexion : %@", .tr: "Bağlantı sorunu: %@", .es: "Problema de conexión: %@"],
        "error.unknown":[.ar: "حدث خطأ غير متوقع", .en: "An unexpected error occurred", .fr: "Une erreur imprévue est survenue", .tr: "Beklenmedik bir sorun oluştu", .es: "Ha ocurrido un error inesperado"],
        "error.invalid_server":[.ar: "تعذّر التحقق من السيرفر — تأكد من الرابط وبيانات الدخول", .en: "Couldn't verify the server — check the URL and login details", .fr: "Serveur non vérifié — contrôlez l'adresse et vos identifiants", .tr: "Sunucu doğrulanmadı — adresi ve giriş bilgilerini kontrol edin", .es: "No hemos podido verificar el servidor — revisa la dirección y tus datos"],
        "error.playlist_invalid":[.ar: "الرابط ليس قائمة تشغيل صالحة — تأكد من الرابط", .en: "The URL isn't a valid playlist — check the link", .fr: "Ce lien n'est pas une playlist valide — vérifiez-le", .tr: "Bu bağlantı geçerli bir liste değil — kontrol edin", .es: "Ese enlace no es una lista válida — revísalo"],
        "error.server_rejected":[.ar: "رفض السيرفر الطلب — تأكد من الاشتراك والرابط، أو جرّب شبكة أخرى", .en: "The server rejected the request — check your subscription and URL, or try another network", .fr: "Le serveur a refusé la requête — contrôlez votre abonnement et l'adresse, ou changez de réseau", .tr: "Sunucu isteği geri çevirdi — aboneliğinizi ve adresi kontrol edin ya da ağı değiştirin", .es: "El servidor ha rechazado la petición — revisa tu suscripción y la dirección, o cambia de red"],
        "error.subscription_invalid":[.ar: "بيانات الاشتراك غير صحيحة أو منتهية (%@)", .en: "Subscription invalid or expired (%@)", .fr: "Abonnement non valide ou expiré (%@)", .tr: "Abonelik geçersiz ya da sona ermiş (%@)", .es: "Suscripción no válida o vencida (%@)"],
        "player.err.no_url":[.ar: "تعذّر تحميل الرابط", .en: "Couldn't load the stream link", .fr: "Impossible de charger le flux", .tr: "Yayın bağlantısı yüklenemedi", .es: "No se pudo cargar el flujo"],
        "player.err.start_failed":[.ar: "تعذّر بدء التشغيل — تحقق من الاتصال أو أعد المحاولة", .en: "Couldn't start playback — check your connection or retry", .fr: "La lecture n'a pas démarré — contrôlez votre connexion ou réessayez", .tr: "Oynatma başlamadı — bağlantınızı kontrol edin ya da yeniden deneyin", .es: "La reproducción no arrancó — revisa tu conexión o reinténtalo"],
        "player.err.failed":[.ar: "فشل تشغيل المحتوى — تحقق من اتصالك أو الرابط", .en: "Playback failed — check your connection or the link", .fr: "La lecture a échoué — contrôlez la connexion ou le lien", .tr: "Oynatma yapılamadı — bağlantıyı ya da adresi kontrol edin", .es: "La reproducción falló — revisa la conexión o el enlace"],
        "player.err.interrupted":[.ar: "انقطع البث — تحقق من الاتصال أو أعد المحاولة", .en: "Stream interrupted — check your connection or retry", .fr: "Le flux s'est coupé — contrôlez la connexion ou réessayez", .tr: "Yayın koptu — bağlantınızı kontrol edin ya da yeniden deneyin", .es: "Se cortó la emisión — revisa la conexión o reinténtalo"],
        "play.subtitle.size":[.ar: "حجم الترجمة", .en: "Subtitle size", .fr: "Taille des sous-titres", .tr: "Altyazı boyutu", .es: "Tamaño de subtítulos"],
        "subsize.small":[.ar: "صغير", .en: "Small", .fr: "Petit", .tr: "Küçük", .es: "Pequeño"],
        "subsize.medium":[.ar: "متوسط", .en: "Medium", .fr: "Moyen", .tr: "Orta", .es: "Medio"],
        "subsize.large":[.ar: "كبير", .en: "Large", .fr: "Grand", .tr: "Büyük", .es: "Grande"],
        "subsize.xl":[.ar: "ضخم", .en: "Extra large", .fr: "Très grand", .tr: "Çok büyük", .es: "Muy grande"],
        "reorder.your_order":[.ar: "ترتيبك", .en: "Your order", .fr: "Votre ordre", .tr: "Sıralamanız", .es: "Tu orden"],
        "reorder.available":[.ar: "القوائم المتاحة", .en: "Available lists", .fr: "Listes disponibles", .tr: "Mevcut listeler", .es: "Listas disponibles"],
        "reorder.drag_hint":[.ar: "اسحب للترتيب · اضغط ⊖ للحذف", .en: "Drag to reorder · tap ⊖ to remove", .fr: "Faites glisser pour classer · ⊖ pour retirer", .tr: "Sürükleyerek sıralayın · ⊖ ile çıkarın", .es: "Arrastra para ordenar · ⊖ para quitar"],
        "reorder.empty_arranged":[.ar: "لم تُرتّب أي قائمة بعد — أضف من الأسفل ↓", .en: "Nothing arranged yet — add from below ↓", .fr: "Rien de classé — ajoutez depuis le bas ↓", .tr: "Henüz bir şey yok — aşağıdan ekleyin ↓", .es: "Aún no hay nada — añade desde abajo ↓"],

        // Screen titles
        "title.movies": [.ar: "الأفلام",     .en: "Movies",  .fr: "Films",  .tr: "Filmler", .es: "Películas"],
        "title.series": [.ar: "المسلسلات",   .en: "Series",  .fr: "Séries", .tr: "Diziler", .es: "Series"],
        "title.live":   [.ar: "البث المباشر",.en: "Live TV", .fr: "TV en direct", .tr: "Canlı TV", .es: "TV en directo"],

        // Search placeholders
        "search.movies": [.ar: "في كل الأفلام…",   .en: "Across all movies…",   .fr: "Dans tous les films…", .tr: "Bütün filmlerde…", .es: "En todas las películas…"],
        "search.series": [.ar: "في كل المسلسلات…", .en: "Across all series…",   .fr: "Dans toutes les séries…",.tr: "Bütün dizilerde…", .es: "En todas las series…"],
        "search.live":   [.ar: "في كل القنوات…",   .en: "Across all channels…", .fr: "Dans toutes les chaînes…",.tr: "Bütün kanallarda…", .es: "En todos los canales…"],
        "search.all":    [.ar: "ابحث في كل المحتوى…",   .en: "Search everything…",   .fr: "Tout rechercher…",     .tr: "Her şeyde ara…",     .es: "Buscar todo…"],
        "search.cat":    [.ar: "اسم القسم…",          .en: "Category name…",   .fr: "Nom de la catégorie…", .tr: "Kategori adı…", .es: "Nombre de la categoría…"],

        // Home sections
        "home.live_now":   [.ar: "على الهواء",      .en: "On air",     .fr: "À l'antenne",     .tr: "Yayında",  .es: "Al aire"],
        "home.new_movies": [.ar: "وصل حديثاً · أفلام",    .en: "Just added · Movies",   .fr: "Nouveautés · Films",.tr: "Yeni eklendi · Filmler", .es: "Recién añadido · Películas"],
        "home.new_series": [.ar: "وصل حديثاً · مسلسلات",  .en: "Just added · Series",   .fr: "Nouveautés · Séries",.tr: "Yeni eklendi · Diziler",.es: "Recién añadido · Series"],
        "home.continue":   [.ar: "تابع من حيث توقّفت",  .en: "Pick up where you left off", .fr: "Reprenez où vous en étiez", .tr: "Kaldığınız yerden devam", .es: "Continúa donde lo dejaste"],

        // Settings groups
        "set.player":   [.ar: "المشغّل",          .en: "Player",    .fr: "Lecteur",  .tr: "Oynatıcı",.es: "Reproductor"],
        "set.app":      [.ar: "التطبيق",          .en: "App",       .fr: "App",      .tr: "Uygulama",.es: "App"],
        "set.logout":   [.ar: "تسجيل الخروج",     .en: "Sign out",  .fr: "Déconnexion", .tr: "Çıkış", .es: "Cerrar sesión"],
        "set.notifications":[.ar: "الإشعارات",    .en: "Notifications", .fr: "Notifications", .tr: "Bildirimler", .es: "Notificaciones"],
        "set.about":    [.ar: "عن التطبيق",       .en: "About",     .fr: "À propos", .tr: "Hakkında",.es: "Acerca de"],
        "set.privacy":  [.ar: "سياسة الخصوصية",   .en: "Privacy Policy", .fr: "Confidentialité", .tr: "Gizlilik Politikası", .es: "Política de privacidad"],
        "set.terms":    [.ar: "شروط الاستخدام",   .en: "Terms of Use", .fr: "Conditions", .tr: "Kullanım Şartları", .es: "Términos"],
        "set.delete":   [.ar: "حذف الحساب",       .en: "Delete Account", .fr: "Supprimer le compte", .tr: "Hesabı Sil", .es: "Eliminar cuenta"],
        "set.support":  [.ar: "تواصل مع الدعم", .en: "Contact Support", .fr: "Écrire au support", .tr: "Destek ekibine yaz", .es: "Escribir a soporte"],
        "set.connection":[.ar: "الاتصال والحساب", .en: "Connection & Account", .fr: "Connexion et compte", .tr: "Bağlantı ve Hesap", .es: "Conexión y cuenta"],
        "set.about_legal":[.ar: "حول والدعم والقانوني", .en: "About & Legal", .fr: "À propos et mentions", .tr: "Hakkında ve Yasal", .es: "Acerca de y legal"],
        "set.connection.sub":[.ar: "الخادم · معرّف الجهاز · القوائم", .en: "Server · Device ID · Playlists", .fr: "Serveur · Appareil · Listes", .tr: "Sunucu · Cihaz · Listeler", .es: "Servidor · Dispositivo · Listas"],
        "set.player.sub":[.ar: "التشغيل التلقائي · المحرّك · الجودة", .en: "Autoplay · Engine · Quality", .fr: "Lecture auto · Moteur · Qualité", .tr: "Otomatik · Motor · Kalite", .es: "Reproducción · Motor · Calidad"],
        "set.app.sub":[.ar: "اللغة · التنزيلات · الإشعارات", .en: "Language · Downloads · Notifications", .fr: "Langue · Téléchargements · Notifications", .tr: "Dil · İndirmeler · Bildirimler", .es: "Idioma · Descargas · Notificaciones"],
        "set.about.sub":[.ar: "الإصدار · الدعم · الخصوصية · الشروط", .en: "Version · Support · Privacy · Terms", .fr: "Version · Support · Confidentialité", .tr: "Sürüm · Destek · Gizlilik", .es: "Versión · Soporte · Privacidad"],
        "reorder.sub":[.ar: "رتّب أقسام الأفلام والمسلسلات والقنوات", .en: "Arrange movies, series & channel rows", .fr: "Organiser films, séries et chaînes", .tr: "Film, dizi ve kanalları düzenle", .es: "Organizar películas, series y canales"],
        "diag.engine.title":[.ar: "تشخيص محرّك التشغيل", .en: "Playback Engine Diagnostics", .fr: "Diagnostic du moteur", .tr: "Oynatıcı Tanılama", .es: "Diagnóstico del motor"],
        "diag.engine.memory":[.ar: "الذاكرة", .en: "Memory", .fr: "Mémoire", .tr: "Bellek", .es: "Memoria"],
        "diag.engine.usage":[.ar: "الاستخدام", .en: "Usage", .fr: "Utilisation", .tr: "Kullanım", .es: "Uso"],
        "diag.engine.health":[.ar: "الأداء", .en: "Health", .fr: "Santé", .tr: "Sağlık", .es: "Estado"],
        "diag.remembered":[.ar: "عناصر محفوظة", .en: "Remembered items", .fr: "Éléments mémorisés", .tr: "Hatırlanan öğeler", .es: "Elementos recordados"],
        "diag.opens":[.ar: "عمليات الفتح", .en: "Opens", .fr: "Ouvertures", .tr: "Açılışlar", .es: "Aperturas"],
        "diag.from_cache":[.ar: "فُتحت من الذاكرة", .en: "Opened from memory", .fr: "Ouvert depuis la mémoire", .tr: "Bellekten açıldı", .es: "Abierto desde memoria"],
        "diag.default_route":[.ar: "توجيه افتراضي", .en: "Default-routed", .fr: "Routage par défaut", .tr: "Varsayılan yönlendirme", .es: "Enrutado por defecto"],
        "diag.forced":[.ar: "باختيار المستخدم", .en: "User-forced", .fr: "Forcé par l'utilisateur", .tr: "Kullanıcı seçti", .es: "Forzado por usuario"],
        "diag.stable_plays":[.ar: "تشغيل مستقرّ ناجح", .en: "Stable successful plays", .fr: "Lectures stables réussies", .tr: "Kararlı başarılı oynatma", .es: "Reproducciones estables"],
        "diag.failovers":[.ar: "تبديل تلقائي للمحرّك", .en: "Auto engine switches", .fr: "Changements auto de moteur", .tr: "Otomatik motor değişimi", .es: "Cambios automáticos de motor"],
        "diag.reset":[.ar: "تصفير العدّادات", .en: "Reset counters", .fr: "Réinitialiser", .tr: "Sayaçları sıfırla", .es: "Restablecer contadores"],
        "set.device_copied":[.ar: "تم نسخ معرّف الجهاز", .en: "Device ID copied", .fr: "Identifiant copié", .tr: "Cihaz kimliği kopyalandı", .es: "ID de dispositivo copiado"],

        // Detail
        "detail.story": [.ar: "القصة",     .en: "Story",   .fr: "L'histoire",.tr: "Hikâye",    .es: "La historia"],
        "detail.cast":  [.ar: "طاقم العمل",.en: "Cast",    .fr: "Distribution", .tr: "Oyuncu kadrosu",.es: "Reparto"],
        "detail.play_movie":[.ar: "تشغيل الفيلم", .en: "Play Movie", .fr: "Lancer le film", .tr: "Filmi başlat", .es: "Ver la película"],

        // Empty
        "empty.no_results": [.ar: "لا نتائج", .en: "No results", .fr: "Aucun résultat", .tr: "Sonuç yok", .es: "Sin resultados"],

        "home.see_all":  [.ar: "استعرض الكل", .en: "Browse all", .fr: "Parcourir tout", .tr: "Hepsine göz at", .es: "Explorar todo"],

        // Reseller code

        // Parental control hub
        "pc.title":          [.ar: "الرقابة الأبوية", .en: "Parental Control", .fr: "Contrôle parental", .tr: "Ebeveyn Denetimi", .es: "Control parental"],
        "pc.enable":         [.ar: "تفعيل الرقابة الأبوية", .en: "Enable Parental Control", .fr: "Activer le contrôle parental", .tr: "Ebeveyn Denetimini Aç", .es: "Activar control parental"],
        "pc.enable_hint":    [.ar: "أنشئ رمزاً سرياً لقفل أقسام محددة. ستحتاج الرمز لفتحها.", .en: "Create a PIN to lock specific categories. You'll need it to open them.", .fr: "Définissez un code pour verrouiller certaines catégories. Il vous sera demandé pour les ouvrir.", .tr: "Bazı kategorileri kilitlemek için bir PIN belirleyin. Açmak için bu PIN gerekir.", .es: "Define un PIN para bloquear ciertas categorías. Te lo pediremos para abrirlas."],
        "pc.change_pin":     [.ar: "تغيير الرمز", .en: "Change PIN", .fr: "Changer le code", .tr: "PIN'i Değiştir", .es: "Cambiar PIN"],
        "pc.disable":        [.ar: "إيقاف الرقابة الأبوية", .en: "Turn Off Parental Control", .fr: "Désactiver le contrôle parental", .tr: "Ebeveyn Denetimini Kapat", .es: "Desactivar control parental"],
        "pc.locked_cats.sub":[.ar: "اختر الأقسام التي تتطلّب الرمز", .en: "Choose which categories need the PIN", .fr: "Catégories nécessitant le code", .tr: "PIN gerektiren kategoriler", .es: "Categorías que requieren PIN"],
        "pc.change_pin.sub": [.ar: "عيّن رمزاً جديداً من أربعة أرقام", .en: "Set a new four-digit PIN", .fr: "Définir un nouveau code", .tr: "Yeni dört haneli PIN", .es: "Nuevo PIN de cuatro dígitos"],
        "pc.disable.sub":    [.ar: "إلغاء القفل وإظهار كل المحتوى", .en: "Unlock and reveal all content", .fr: "Déverrouiller tout le contenu", .tr: "Kilidi aç, tüm içeriği göster", .es: "Desbloquear todo el contenido"],
        "pc.recovery_title": [.ar: "رمز الاستعادة", .en: "Recovery Code", .fr: "Code de récupération", .tr: "Kurtarma Kodu", .es: "Código de recuperación"],
        "pc.recovery_hint":  [.ar: "احتفظ بهذا الرمز في مكان آمن. ستحتاجه لاستعادة رمزك إن نسيته.", .en: "Keep this code safe. You'll need it to reset your PIN if you forget it.", .fr: "Gardez ce code en lieu sûr. Il servira à redéfinir votre code si vous l'oubliez.", .tr: "Bu kodu güvenli bir yerde tutun. PIN'inizi unutursanız onunla sıfırlarsınız.", .es: "Guarda este código en un sitio seguro. Con él podrás restablecer tu PIN si lo olvidas."],
        "pc.recovery_saved": [.ar: "حفظته — متابعة", .en: "I've saved it", .fr: "Je l'ai noté", .tr: "Kaydettim", .es: "Ya lo guardé"],
        "pin.forgot":        [.ar: "نسيت الرمز؟", .en: "Forgot PIN?", .fr: "Code oublié ?", .tr: "PIN'i mi unuttunuz?", .es: "¿Olvidaste el PIN?"],
        "locked.lock_all":   [.ar: "قفل الكل", .en: "Lock all", .fr: "Tout verrouiller", .tr: "Tümünü kilitle", .es: "Bloquear todo"],
        "locked.unlock_all": [.ar: "فتح الكل", .en: "Unlock all", .fr: "Tout déverrouiller", .tr: "Tümünü aç", .es: "Desbloquear todo"],
        "recovery.enter":    [.ar: "أدخل رمز الاستعادة المكوّن من 8 خانات", .en: "Enter your 8-character recovery code", .fr: "Tapez votre code de récupération (8 caractères)", .tr: "Kurtarma kodunuzu girin (8 karakter)", .es: "Escribe tu código de recuperación (8 caracteres)"],
        "recovery.wrong":    [.ar: "رمز استعادة غير صحيح", .en: "Incorrect recovery code", .fr: "Code de récupération erroné", .tr: "Kurtarma kodu hatalı", .es: "Código de recuperación no válido"],
        "history.remove":[.ar: "حذف من السجل", .en: "Remove from history", .fr: "Retirer de l'historique", .tr: "Geçmişten kaldır", .es: "Quitar del historial"],

        // iPad live pane
        "live.pick_channel": [.ar: "اختر قناة لتبدأ", .en: "Pick a channel to start", .fr: "Choisissez une chaîne pour commencer", .tr: "Başlamak için bir kanal seçin", .es: "Elige un canal para empezar"],
        "live.fullscreen":   [.ar: "ملء الشاشة", .en: "Fullscreen", .fr: "Plein écran", .tr: "Tam ekran", .es: "Pantalla completa"],

        // Common (extra)
        "common.delete":   [.ar: "حذف",      .en: "Delete",     .fr: "Supprimer", .tr: "Sil",       .es: "Eliminar"],
        "common.activate": [.ar: "تفعيل",    .en: "Activate",   .fr: "Activer",   .tr: "Etkinleştir",.es: "Activar"],
        "common.done":     [.ar: "تم",       .en: "Done",       .fr: "Terminé",   .tr: "Tamam",     .es: "Listo"],
        "common.connected":[.ar: "متصل",     .en: "Connected",  .fr: "Connecté",  .tr: "Bağlı",     .es: "Conectado"],
        "common.search_in":[.ar: "ابحث داخل",  .en: "Search inside",  .fr: "Chercher dans", .tr: "İçinde ara", .es: "Buscar dentro de"],

        // Units / time
        "unit.day":        [.ar: "يوم",      .en: "day",        .fr: "jour",      .tr: "gün",       .es: "día"],
        "unit.minute":     [.ar: "دقيقة",    .en: "min",        .fr: "min",       .tr: "dk",        .es: "min"],
        "unit.item":       [.ar: "عنصر",     .en: "items",      .fr: "éléments",  .tr: "öğe",       .es: "elementos"],
        "unit.channel":    [.ar: "قناة",     .en: "channels",   .fr: "chaînes",   .tr: "kanal",     .es: "canales"],
        "unit.movie":      [.ar: "فيلم",     .en: "movies",     .fr: "films",     .tr: "film",      .es: "películas"],
        "unit.series":     [.ar: "مسلسل",    .en: "series",     .fr: "séries",    .tr: "dizi",      .es: "series"],
        "season.number":   [.ar: "الموسم",   .en: "Season",     .fr: "Saison",    .tr: "Sezon",     .es: "Temporada"],
        "episode.number":  [.ar: "الحلقة",   .en: "Episode",    .fr: "Épisode",   .tr: "Bölüm",     .es: "Episodio"],

        // Loading / status messages
        "loading.generic":  [.ar: "لحظة…", .en: "One moment…",  .fr: "Un instant…", .tr: "Bir saniye…", .es: "Un momento…"],
        "loading.error":    [.ar: "خطأ",     .en: "Error",      .fr: "Erreur",    .tr: "Hata",      .es: "Error"],

        // Settings — server / activation
        "settings.language":        [.ar: "اللغة",          .en: "Language",        .fr: "Langue",          .tr: "Dil",             .es: "Idioma"],
        "settings.m3u_list":        [.ar: "قائمة M3U",      .en: "M3U List",        .fr: "Liste M3U",       .tr: "M3U Listesi",     .es: "Lista M3U"],
        "settings.user":            [.ar: "مستخدم",         .en: "User",            .fr: "Utilisateur",     .tr: "Kullanıcı",       .es: "Usuario"],
        "settings.device_id":       [.ar: "معرّف الجهاز",   .en: "Device ID",       .fr: "ID de l'appareil",.tr: "Cihaz Kimliği",   .es: "ID del dispositivo"],

        // Subscription card
        "sub.renew":        [.ar: "جدّد الاشتراك",        .en: "Renew now", .fr: "Renouveler maintenant", .tr: "Şimdi yenile", .es: "Renovar ahora"],

        // Activation status

        // Player group toggles
        "player.autonext.title": [.ar: "تشغيل تلقائي للحلقة التالية", .en: "Auto-play next episode", .fr: "Enchaîner l'épisode suivant", .tr: "Sonraki bölüme otomatik geç", .es: "Pasar al siguiente episodio"],
        "player.skipintro.title":[.ar: "إظهار «تخطّي المقدمة»", .en: "Show \"Skip Intro\"", .fr: "Afficher « Sauter l'intro »", .tr: "\"Jeneriği Geç\" göster", .es: "Mostrar \"Omitir intro\""],
        "player.quality":        [.ar: "جودة البث",      .en: "Streaming quality", .fr: "Qualité du flux", .tr: "Akış kalitesi", .es: "Calidad de emisión"],
        "player.sleep.default":  [.ar: "مؤقت النوم الافتراضي", .en: "Default sleep timer", .fr: "Minuteur par défaut", .tr: "Varsayılan uyku süresi", .es: "Temporizador predeterminado"],
        "player.engine":         [.ar: "محرّك التشغيل", .en: "Playback engine", .fr: "Moteur de lecture", .tr: "Oynatma motoru", .es: "Motor de reproducción"],
        "player.engine.auto":    [.ar: "تلقائي", .en: "Automatic", .fr: "Automatique", .tr: "Otomatik", .es: "Automático"],
        "player.pip":            [.ar: "صورة داخل صورة", .en: "Picture in Picture", .fr: "Image dans l'image", .tr: "Resim İçinde Resim", .es: "Imagen en imagen"],
        "quality.auto":          [.ar: "تلقائي", .en: "Automatic", .fr: "Automatique", .tr: "Otomatik", .es: "Automático"],
        "quality.high":          [.ar: "عالي HD", .en: "High HD", .fr: "Haute HD", .tr: "Yüksek HD", .es: "Alta HD"],
        "quality.medium":        [.ar: "متوسط", .en: "Medium", .fr: "Moyenne", .tr: "Orta", .es: "Media"],
        "quality.low":           [.ar: "منخفض", .en: "Low", .fr: "Basse", .tr: "Düşük", .es: "Baja"],
        "player.engine.av":      [.ar: "عتادي (الأسرع)", .en: "Hardware (fastest)", .fr: "Matériel (le plus rapide)", .tr: "Donanım (en hızlı)", .es: "Hardware (el más rápido)"],
        "player.engine.vlc":     [.ar: "شامل (VLC)", .en: "Universal (VLC)", .fr: "Universel (VLC)", .tr: "Evrensel (VLC)", .es: "Universal (VLC)"],

        // Offline downloads
        "set.downloads":         [.ar: "التنزيلات", .en: "Downloads", .fr: "Téléchargements", .tr: "İndirilenler", .es: "Descargas"],
        "downloads.title":       [.ar: "التنزيلات", .en: "Downloads", .fr: "Téléchargements", .tr: "İndirilenler", .es: "Descargas"],
        "downloads.empty.title": [.ar: "لا توجد تنزيلات", .en: "No downloads", .fr: "Aucun téléchargement", .tr: "İndirme yok", .es: "Sin descargas"],
        "downloads.empty.sub":   [.ar: "نزّل الأفلام والحلقات لمشاهدتها دون إنترنت", .en: "Download movies and episodes to watch offline", .fr: "Enregistrez films et épisodes pour les voir sans connexion", .tr: "İnternetsiz izlemek için film ve bölüm indirin", .es: "Guarda películas y episodios y míralos sin internet"],
        "download.failed":       [.ar: "فشل التحميل — اضغط لإعادة المحاولة", .en: "Download failed — tap to retry", .fr: "Téléchargement échoué — touchez pour reprendre", .tr: "İndirme başarısız — yeniden denemek için dokunun", .es: "Descarga fallida — toca para reintentar"],
        "downloads.paused":      [.ar: "متوقّف مؤقتاً", .en: "Paused", .fr: "En pause", .tr: "Duraklatıldı", .es: "En pausa"],
        "downloads.queued":      [.ar: "في الانتظار…", .en: "Queued…", .fr: "En attente…", .tr: "Sırada…", .es: "En cola…"],
        "downloads.wifi_only":   [.ar: "التحميل على Wi-Fi فقط", .en: "Download on Wi-Fi only", .fr: "Télécharger uniquement en Wi-Fi", .tr: "Sadece Wi-Fi ile indir", .es: "Descargar solo por Wi-Fi"],
        "downloads.notif.title": [.ar: "اكتمل التنزيل", .en: "Download complete", .fr: "Téléchargement terminé", .tr: "İndirme tamamlandı", .es: "Descarga completada"],
        "downloads.notif.denied":[.ar: "الإشعارات معطّلة — فعّلها لتصلك عند اكتمال التحميل", .en: "Notifications are off — enable them to be alerted when downloads finish", .fr: "Notifications coupées — activez-les pour savoir quand un téléchargement finit", .tr: "Bildirimler kapalı — indirme bittiğinde haberdar olmak için açın", .es: "Notificaciones apagadas — actívalas y te avisamos al terminar"],
        "downloads.storage_used":[.ar: "المساحة المستخدمة", .en: "Storage used", .fr: "Espace utilisé", .tr: "Kullanılan alan", .es: "Almacenamiento usado"],
        "downloads.free":        [.ar: "المساحة المتاحة", .en: "Available", .fr: "Espace libre", .tr: "Boş alan", .es: "Espacio libre"],
        "downloads.low_warning": [.ar: "مساحة الجهاز منخفضة — احذف بعض التنزيلات", .en: "Low device storage — delete some downloads", .fr: "Espace insuffisant — supprimez quelques téléchargements", .tr: "Depolama alanı azaldı — birkaç indirmeyi silin", .es: "Queda poco espacio — borra algunas descargas"],
        "downloads.space_low.title":    [.ar: "مساحة منخفضة", .en: "Low storage", .fr: "Espace insuffisant", .tr: "Alan azaldı", .es: "Poco espacio"],
        "downloads.space_low.msg":      [.ar: "مساحة جهازك منخفضة. هل تريد متابعة التحميل؟", .en: "Your device storage is low. Continue the download?", .fr: "Il reste peu d'espace sur l'appareil. Poursuivre le téléchargement ?", .tr: "Cihazınızda az yer kaldı. İndirme sürsün mü?", .es: "Queda poco espacio en el dispositivo. ¿Seguimos con la descarga?"],
        "downloads.space_low.continue": [.ar: "متابعة", .en: "Continue", .fr: "Continuer", .tr: "Devam", .es: "Continuar"],

        // App group
        "app.parental":     [.ar: "الرقابة الأبوية",     .en: "Parental Controls", .fr: "Contrôle parental", .tr: "Ebeveyn Denetimi", .es: "Control parental"],
        "app.parental.on":  [.ar: "مفعّلة",              .en: "On",              .fr: "Activé",          .tr: "Açık",            .es: "Activado"],
        "app.parental.off": [.ar: "متوقفة",             .en: "Off",             .fr: "Désactivé",       .tr: "Kapalı",          .es: "Desactivado"],
        "app.locked_cats":  [.ar: "الأقسام المقفلة",    .en: "Locked Categories", .fr: "Catégories verrouillées", .tr: "Kilitli Kategoriler", .es: "Categorías bloqueadas"],

        // Legal group

        // Logout / delete alerts
        "alert.logout.msg":     [.ar: "هل تريد تسجيل الخروج من حسابك؟", .en: "Do you want to sign out of your account?", .fr: "Souhaitez-vous quitter votre compte ?", .tr: "Hesabınızdan çıkış yapılsın mı?", .es: "¿Seguro que quieres salir de tu cuenta?"],
        "alert.delete.msg":     [.ar: "سيُحذف حسابك وجميع بياناتك نهائياً. هذا الإجراء لا يمكن التراجع عنه.", .en: "Your account and all your data will be permanently deleted. This action cannot be undone.", .fr: "Votre compte et l'ensemble de vos données seront effacés pour toujours. Rien ne pourra être récupéré.", .tr: "Hesabınız ve bütün verileriniz kalıcı olarak silinir. Bu işlemin geri dönüşü yoktur.", .es: "Se borrarán para siempre tu cuenta y todos tus datos. No habrá vuelta atrás."],
        "alert.delete.confirm": [.ar: "حذف نهائياً", .en: "Delete Permanently", .fr: "Effacer définitivement", .tr: "Tamamen sil", .es: "Borrar para siempre"],

        // Playlists
        "playlists.title":      [.ar: "قوائمي",          .en: "My Playlists",    .fr: "Mes listes",      .tr: "Listelerim",      .es: "Mis listas"],
        "playlists.empty.title":[.ar: "لا قوائم محفوظة", .en: "No saved playlists", .fr: "Aucune liste enregistrée", .tr: "Kayıtlı liste yok", .es: "Sin listas guardadas"],
        "playlists.empty.sub":  [.ar: "أضف قائمة M3U أو get.php جديدة", .en: "Add a new M3U or get.php playlist", .fr: "Ajoutez une liste M3U ou get.php", .tr: "Bir M3U ya da get.php listesi ekleyin", .es: "Añade una lista M3U o get.php"],
        "playlists.active":     [.ar: "نشطة",            .en: "Active",          .fr: "Active",          .tr: "Aktif",           .es: "Activa"],
        "playlists.add":        [.ar: "إضافة قائمة",     .en: "Add Playlist",    .fr: "Ajouter une liste",.tr: "Liste Ekle",      .es: "Añadir lista"],
        "playlists.name_ph":    [.ar: "اسم القائمة (اختياري)", .en: "Playlist name (optional)", .fr: "Nom de la liste (optionnel)", .tr: "Liste adı (opsiyonel)", .es: "Nombre (opcional)"],
        "playlists.url_ph":     [.ar: "رابط M3U / get.php", .en: "M3U / get.php URL", .fr: "URL M3U / get.php", .tr: "M3U / get.php bağlantısı", .es: "URL M3U / get.php"],
        "playlists.add_activate":[.ar: "إضافة وتفعيل",  .en: "Add & Activate",  .fr: "Ajouter et activer", .tr: "Ekle ve Etkinleştir", .es: "Añadir y activar"],
        "playlists.add_failed": [.ar: "تعذّر إضافة القائمة", .en: "Couldn't add the playlist", .fr: "La liste n'a pas pu être ajoutée", .tr: "Liste eklenemedi", .es: "No se pudo añadir la lista"],
        "subs.title":       [.ar: "اشتراكاتي",           .en: "My Subscriptions", .fr: "Mes abonnements",  .tr: "Aboneliklerim",   .es: "Mis suscripciones"],
        "subs.choose":      [.ar: "اختر اشتراكاً للمتابعة", .en: "Choose a subscription to continue", .fr: "Choisissez un abonnement", .tr: "Devam etmek için bir abonelik seçin", .es: "Elige una suscripción para continuar"],
        "subs.add":         [.ar: "إضافة اشتراك",        .en: "Add subscription", .fr: "Ajouter un abonnement", .tr: "Abonelik ekle", .es: "Añadir suscripción"],
        "subs.add_first":   [.ar: "أضف اشتراكك الأول",    .en: "Add your first subscription", .fr: "Ajoutez votre premier abonnement", .tr: "İlk aboneliğinizi ekleyin", .es: "Añade tu primera suscripción"],
        "subs.welcome":     [.ar: "مرحباً بك في %@", .en: "Welcome to %@", .fr: "Bienvenue sur %@", .tr: "Hoş geldiniz — %@", .es: "Bienvenido a %@"],

        // About
        "about.subtitle":   [.ar: "Premium IPTV Player", .en: "Premium IPTV Player", .fr: "Lecteur IPTV Premium", .tr: "Premium IPTV Oynatıcı", .es: "Reproductor IPTV Premium"],
        "about.version":    [.ar: "الإصدار",            .en: "Version",         .fr: "Version",         .tr: "Sürüm",           .es: "Versión"],

        // Parental PIN
        "pin.verify":       [.ar: "أدخل رمز الرقابة الأبوية", .en: "Enter parental PIN", .fr: "Entrez le code parental", .tr: "Ebeveyn kodunu girin", .es: "Escribe el PIN parental"],
        "pin.confirm":      [.ar: "أعد إدخال الرمز للتأكيد", .en: "Re-enter PIN to confirm", .fr: "Entrez le code une seconde fois", .tr: "Kodu bir kez daha girin", .es: "Escribe el PIN otra vez para confirmar"],
        "pin.create":       [.ar: "أنشئ رمز رقابة (4 أرقام)", .en: "Create a PIN (4 digits)", .fr: "Choisissez un code à 4 chiffres", .tr: "4 haneli bir kod belirleyin", .es: "Elige un PIN de 4 dígitos"],
        "pin.wrong":        [.ar: "رمز غير صحيح",       .en: "Incorrect PIN",   .fr: "Code erroné",  .tr: "Kod hatalı",      .es: "PIN no válido"],
        "pin.mismatch":     [.ar: "الرمز غير متطابق، حاول مجدداً", .en: "PINs don't match, try again", .fr: "Les deux codes diffèrent, recommencez", .tr: "Kodlar aynı değil, yeniden deneyin", .es: "Los dos PIN no son iguales, prueba otra vez"],

        // Parental gate
        "gate.locked":      [.ar: "قسم مقفل",           .en: "Locked Category", .fr: "Catégorie verrouillée", .tr: "Kilitli Kategori", .es: "Categoría bloqueada"],
        "gate.protected":   [.ar: "محمي بالرقابة الأبوية", .en: "Protected by parental controls", .fr: "Protégé par le contrôle parental", .tr: "Ebeveyn denetimiyle korunuyor", .es: "Protegido por control parental"],
        "gate.enter_pin":   [.ar: "إدخال الرمز",        .en: "Enter PIN",       .fr: "Entrer le code",  .tr: "PIN'i gir",        .es: "Escribir el PIN"],

        // Locked categories manager
        "locked.movies":    [.ar: "الأفلام",            .en: "Movies",          .fr: "Films",           .tr: "Filmler",         .es: "Películas"],
        "locked.series":    [.ar: "المسلسلات",          .en: "Series",          .fr: "Séries",          .tr: "Diziler",         .es: "Series"],
        "locked.channels":  [.ar: "القنوات",            .en: "Channels",        .fr: "Chaînes",         .tr: "Kanallar",        .es: "Canales"],

        // Player view
        "play.reconnecting":[.ar: "نستعيد الاتصال…", .en: "Getting the stream back…",   .fr: "On rétablit le flux…",    .tr: "Yayın geri getiriliyor…", .es: "Recuperando la señal…"],
        "play.skip_intro":  [.ar: "تجاوز المقدّمة",      .en: "Skip the intro",      .fr: "Sauter l'intro",  .tr: "Jeneriği geç",   .es: "Omitir intro"],
        "play.next_episode":[.ar: "الحلقة التالية",     .en: "Next Episode",    .fr: "Épisode suivant", .tr: "Sonraki Bölüm",   .es: "Siguiente episodio"],
        "play.live_now":    [.ar: "بث مباشر",           .en: "Live",            .fr: "En direct",       .tr: "Canlı",           .es: "En directo"],
        "play.audio":       [.ar: "صوت",                .en: "Audio",           .fr: "Audio",           .tr: "Ses",             .es: "Audio"],
        "play.subtitle":    [.ar: "ترجمة",              .en: "Subtitles",       .fr: "Sous-titres",     .tr: "Altyazı",         .es: "Subtítulos"],
        "play.sleep":       [.ar: "مؤقّت",                .en: "Timer",           .fr: "Minuteur",          .tr: "Uyku",            .es: "Apagado"],
        "play.sleep.title": [.ar: "مؤقت النوم",         .en: "Sleep Timer",     .fr: "Arrêt programmé", .tr: "Uyku sayacı", .es: "Apagado automático"],
        "play.sleep.will_stop":[.ar: "يتوقّف بعد", .en: "Stops in", .fr: "Arrêt dans", .tr: "Şu kadar sonra durur", .es: "Se detiene en"],
        "play.sleep.cancel":[.ar: "أوقف المؤقت",       .en: "Stop the timer",    .fr: "Arrêter le minuteur", .tr: "Sayacı durdur", .es: "Detener el temporizador"],
        "play.sleep.choose":[.ar: "بعد كم يتوقّف؟",    .en: "Stop after how long?", .fr: "Arrêter dans combien de temps ?", .tr: "Ne kadar sonra dursun?", .es: "¿Dentro de cuánto se detiene?"],
        "play.subtitle.title":[.ar: "الترجمة",          .en: "Subtitles",       .fr: "Sous-titres",     .tr: "Altyazı",         .es: "Subtítulos"],
        "play.subtitle.none":[.ar: "بلا ترجمة",        .en: "Subtitles off",    .fr: "Sous-titres désactivés", .tr: "Altyazı kapalı",     .es: "Subtítulos desactivados"],
        "play.subtitle.empty.title":[.ar: "لا توجد ترجمات", .en: "No subtitles", .fr: "Aucun sous-titre", .tr: "Altyazı yok", .es: "Sin subtítulos"],
        "play.subtitle.empty.sub":[.ar: "هذا المحتوى لا يتضمن مسارات ترجمة", .en: "This content has no subtitle tracks", .fr: "Aucune piste de sous-titres dans ce contenu", .tr: "Bu içeriğe altyazı eklenmemiş", .es: "Este contenido no incluye pistas de subtítulos"],
        "play.audio_track": [.ar: "المسار الصوتي",      .en: "Audio Track",     .fr: "Piste audio",     .tr: "Ses Parçası",     .es: "Pista de audio"],
        "play.audio_track.title":[.ar: "المسار الصوتي", .en: "Audio Track",     .fr: "Piste audio",     .tr: "Ses Parçası",     .es: "Pista de audio"],
        "play.audio_track.empty.title":[.ar: "لا توجد مسارات صوتية", .en: "No audio tracks", .fr: "Aucune piste audio", .tr: "Ses parçası yok", .es: "Sin pistas de audio"],
        "play.audio_track.empty.sub":[.ar: "هذا المحتوى يحتوي على مسار صوتي واحد فقط", .en: "This content has only one audio track", .fr: "Ce contenu ne propose qu'une piste audio", .tr: "Bu içerikte tek bir ses parçası bulunuyor", .es: "Este contenido incluye una sola pista de audio"],
        "play.speed":       [.ar: "السرعة",             .en: "Speed",           .fr: "Vitesse",         .tr: "Hız",             .es: "Velocidad"],
        "play.speed.title": [.ar: "سرعة التشغيل",       .en: "Playback Speed",  .fr: "Vitesse de lecture", .tr: "Oynatma Hızı",  .es: "Velocidad de reproducción"],
        "play.speed.normal":[.ar: "عادي ×١",          .en: "Normal ×1",     .fr: "Normale ×1",     .tr: "Normal ×1",     .es: "Normal ×1"],
        "play.unlock":      [.ar: "افتح القفل",        .en: "Unlock",          .fr: "Déverrouiller",   .tr: "Kilidi Aç",       .es: "Desbloquear"],

        // Home
        "home.featured":    [.ar: "مختارات",              .en: "Handpicked",        .fr: "Notre sélection",        .tr: "Seçtiklerimiz",       .es: "Nuestra selección"],
        "home.new_tag":     [.ar: "جديد",               .en: "New",             .fr: "Nouveau",         .tr: "Yeni",            .es: "Nuevo"],
        "home.top_movies":  [.ar: "الأفلام الأعلى تقييماً", .en: "Top Rated Movies", .fr: "Films les mieux notés", .tr: "En Çok Beğenilen Filmler", .es: "Películas mejor valoradas"],
        "home.top_series":  [.ar: "المسلسلات الأعلى تقييماً", .en: "Top Rated Series", .fr: "Séries les mieux notées", .tr: "En Çok Beğenilen Diziler", .es: "Series mejor valoradas"],
        "home.edit":        [.ar: "تحرير السجل",           .en: "Edit history",            .fr: "Modifier l'historique", .tr: "Geçmişi düzenle", .es: "Editar historial"],
        "home.clear_all":   [.ar: "امسح السجل",           .en: "Clear the history",       .fr: "Effacer l'historique",    .tr: "Geçmişi temizle",  .es: "Borrar el historial"],
        "home.remove_history":[.ar: "أزِل من السجل",     .en: "Drop from history", .fr: "Effacer de l'historique", .tr: "Geçmişten sil", .es: "Borrar del historial"],
        "home.content_error.title":[.ar: "تعذّر تحميل المحتوى", .en: "Couldn't load content", .fr: "Le contenu n'a pas pu être chargé", .tr: "İçerik getirilemedi", .es: "No hemos podido cargar el contenido"],
        "home.content_error.sub":[.ar: "تحقّق من اتصالك أو من صلاحية اشتراكك لدى المزوّد، ثم أعد المحاولة", .en: "Check your connection or that your provider subscription is active, then try again", .fr: "Contrôlez votre connexion ou la validité de votre abonnement chez le fournisseur, puis réessayez", .tr: "Bağlantınızı ya da sağlayıcınızdaki aboneliğinizin geçerliliğini kontrol edip yeniden deneyin", .es: "Revisa tu conexión o si tu suscripción con el proveedor sigue activa, y vuelve a intentarlo"],
        "home.percent_done":[.ar: "شوهد",             .en: "watched",        .fr: "vu",         .tr: "izlendi",      .es: "visto"],
        "home.whatsapp":    [.ar: "واتساب",             .en: "WhatsApp",        .fr: "WhatsApp",        .tr: "WhatsApp",        .es: "WhatsApp"],
        "home.telegram":    [.ar: "تيليغرام",           .en: "Telegram",        .fr: "Telegram",        .tr: "Telegram",        .es: "Telegram"],

        // Alerts / notifications
        "alerts.title":       [.ar: "التنبيهات", .en: "Notifications", .fr: "Notifications", .tr: "Bildirimler", .es: "Notificaciones"],
        "alerts.announcement":[.ar: "إعلان",            .en: "Announcement",    .fr: "Annonce",         .tr: "Duyuru",          .es: "Anuncio"],
        "alerts.sub_warning": [.ar: "تنبيه الاشتراك",   .en: "Subscription Alert", .fr: "Alerte d'abonnement", .tr: "Abonelik Uyarısı", .es: "Alerta de suscripción"],
        "alerts.sub_active":  [.ar: "اشتراكك نشط",      .en: "Your subscription is active", .fr: "Votre abonnement est actif", .tr: "Aboneliğiniz aktif", .es: "Tu suscripción está activa"],
        "alerts.empty.title": [.ar: "لا توجد إشعارات",  .en: "No notifications", .fr: "Aucune notification", .tr: "Bildirim yok", .es: "Sin notificaciones"],
        "alerts.empty.sub":   [.ar: "ستظهر هنا تنبيهات الإدارة وحالة اشتراكك", .en: "Admin alerts and your subscription status will appear here", .fr: "Les avis de l'équipe et l'état de votre abonnement s'afficheront ici", .tr: "Yönetim duyuruları ve abonelik durumunuz burada listelenir", .es: "Aquí verás los avisos del equipo y el estado de tu suscripción"],

        // Channel info sheet
        "channel.live_now": [.ar: "على الهواء الآن",      .en: "On air now",        .fr: "À l'antenne en ce moment", .tr: "Şu an yayında",  .es: "Al aire ahora mismo"],
        "channel.play":     [.ar: "شغّل القناة",       .en: "Play this channel",    .fr: "Lancer cette chaîne",  .tr: "Bu kanalı aç",    .es: "Ver este canal"],
        "epg.next":         [.ar: "التالي",             .en: "Next",            .fr: "À suivre",         .tr: "Sırada",        .es: "A continuación"],
        "refresh.title":    [.ar: "تحديث المحتوى؟",     .en: "Refresh content?", .fr: "Actualiser le contenu ?", .tr: "İçerik yenilensin mi?", .es: "¿Actualizar contenido?"],
        "refresh.msg":      [.ar: "سيُجلب أحدث القنوات والأفلام والمسلسلات من مزوّدك. قد يستغرق بضع ثوانٍ.", .en: "Fetches the latest channels, movies and series from your provider. May take a few seconds.", .fr: "Les dernières chaînes, films et séries seront récupérés chez votre fournisseur. Comptez quelques secondes.", .tr: "En yeni kanallar, filmler ve diziler sağlayıcınızdan alınır. Birkaç saniye sürebilir.", .es: "Traeremos los últimos canales, películas y series de tu proveedor. Tardará unos segundos."],
        "refresh.confirm":  [.ar: "تحديث",              .en: "Refresh",         .fr: "Actualiser",      .tr: "Yenile",          .es: "Actualizar"],

        // Login / Auth
        "login.welcome":    [.ar: "أهلاً بك في بلانك — بياناتك وندخل", .en: "Welcome to Blank — your details and you're in", .fr: "Bienvenue sur Blank — vos identifiants et c'est parti", .tr: "Blank'e hoş geldiniz — bilgilerinizi girin, hazırsınız", .es: "Bienvenido a Blank — tus datos y listo"],
        "login.username":   [.ar: "اسم المستخدم",       .en: "Username",        .fr: "Nom d'utilisateur",.tr: "Kullanıcı adı",  .es: "Nombre de usuario"],
        "login.password":   [.ar: "كلمة المرور",        .en: "Password",        .fr: "Mot de passe",    .tr: "Şifre",           .es: "Contraseña"],
        "login.m3u_hint":   [.ar: "ألصق رابط M3U أو M3U8 — يُقرأ على جهازك ولا يغادره", .en: "Paste an M3U or M3U8 link — read on your device, never sent anywhere", .fr: "Collez un lien M3U ou M3U8 — lu sur votre appareil, jamais envoyé ailleurs", .tr: "Bir M3U ya da M3U8 bağlantısı yapıştırın — cihazınızda okunur, hiçbir yere gönderilmez", .es: "Pega un enlace M3U o M3U8 — se lee en tu dispositivo y no sale de ahí"],
        "login.signin":     [.ar: "دخول",       .en: "Sign In",         .fr: "Connexion",    .tr: "Giriş Yap",       .es: "Iniciar sesión"],
        "login.load_playlist":[.ar: "افتح القائمة", .en: "Open the playlist", .fr: "Ouvrir la liste", .tr: "Listeyi aç",  .es: "Abrir la lista"],
        "login.need_url":      [.ar: "أدخل رابط السيرفر كاملاً — مثل http://host:8080", .en: "Enter the full server URL — e.g. http://host:8080", .fr: "Saisissez l'URL complète du serveur — ex. http://host:8080", .tr: "Tam sunucu adresini girin — örn. http://host:8080", .es: "Introduce la URL completa del servidor — p. ej. http://host:8080"],
        "login.server_or_code":[.ar: "رابط السيرفر", .en: "Server URL", .fr: "URL du serveur", .tr: "Sunucu adresi", .es: "URL del servidor"],
        "login.server_hint":[.ar: "يعطيك إيّاه مزوّدك · مثل http://host:8080", .en: "Your provider gives you this · e.g. http://host:8080", .fr: "Fourni par votre opérateur · ex. http://host:8080", .tr: "Sağlayıcınız verir · örn. http://host:8080", .es: "Te lo da tu proveedor · ej. http://host:8080"],
        "login.demo":       [.ar: "ادخل للتجربة أولاً", .en: "Try it first", .fr: "Essayer d'abord", .tr: "Önce dene", .es: "Probar primero"],
        "login.need_help":  [.ar: "تعثّر التفعيل؟ الدعم جاهز", .en: "Activation stuck? Support is here", .fr: "L'activation bloque ? Le support est là", .tr: "Etkinleştirme takıldı mı? Destek burada", .es: "¿Se atasca la activación? Soporte está aquí"],
        "login.agree":      [.ar: "بدخولك أنت توافق على", .en: "By signing in you agree to", .fr: "En vous connectant, vous acceptez", .tr: "Giriş yaparak şunları kabul edersiniz", .es: "Al iniciar sesión aceptas"],
        "login.and":        [.ar: "و",                  .en: "and",             .fr: "et",              .tr: "ve",              .es: "y"],
        "login.mode_m3u":   [.ar: "رابط قائمة",           .en: "Playlist link",         .fr: "Lien de liste",         .tr: "Liste bağlantısı",  .es: "Enlace de lista"],
        "common.error":     [.ar: "خطأ",                .en: "Error",           .fr: "Erreur",          .tr: "Hata",            .es: "Error"],

        // Splash
        "splash.device_id": [.ar: "معرّف الجهاز",       .en: "Device ID",       .fr: "ID de l'appareil",.tr: "Cihaz Kimliği",   .es: "ID del dispositivo"],

        // Privacy policy
        "privacy.collect.t": [.ar: "ما نجمعه", .en: "What we collect", .fr: "Ce que nous collectons", .tr: "Neleri topluyoruz", .es: "Qué recopilamos"],
        "privacy.collect.b": [.ar: "بيانات دخولك، ومعرّف جهازك، وإحصاءات استخدام أساسية بموافقتك. لا شيء غير ذلك.", .en: "Your sign-in details, your device ID, and basic usage statistics with your consent. Nothing else.", .fr: "Vos identifiants de connexion, l'ID de l'appareil et des statistiques d'usage de base, avec votre accord. Rien d'autre.", .tr: "Giriş bilgileriniz, cihaz kimliğiniz ve onayınızla temel kullanım istatistikleri. Başka hiçbir şey.", .es: "Tus datos de acceso, el ID del dispositivo y estadísticas de uso básicas, con tu permiso. Nada más."],
        "privacy.use.t":     [.ar: "فيمَ نستخدمها", .en: "What we use it for", .fr: "À quoi elles servent", .tr: "Ne için kullanıyoruz", .es: "Para qué los usamos"],
        "privacy.use.b":     [.ar: "لتشغيل الخدمة، ولتحسين التطبيق، ولإشعارات تخصّ حسابك وحده.", .en: "To run the service, to improve the app, and for notifications about your account alone.", .fr: "À faire fonctionner le service, à améliorer l'app et à vous notifier au sujet de votre compte, rien de plus.", .tr: "Hizmeti çalıştırmak, uygulamayı iyileştirmek ve yalnızca hesabınızla ilgili bildirimler göndermek için.", .es: "Para que el servicio funcione, para mejorar la app y para avisarte solo sobre tu cuenta."],
        "privacy.share.t":   [.ar: "من يطّلع عليها",   .en: "Who sees it",    .fr: "Qui y a accès", .tr: "Kim görebilir", .es: "Quién los ve"],
        "privacy.share.b":   [.ar: "لا أحد. لا نبيع بياناتك الشخصية ولا نشاركها مع أي طرف ثالث، تحت أي ظرف.", .en: "Nobody. We do not sell your personal data and we do not share it with any third party, under any circumstances.", .fr: "Personne. Nous ne vendons pas vos données personnelles et ne les partageons avec aucun tiers, en aucun cas.", .tr: "Hiç kimse. Kişisel verilerinizi satmayız ve hiçbir koşulda üçüncü kişilerle paylaşmayız.", .es: "Nadie. No vendemos tus datos personales ni los compartimos con terceros, bajo ninguna circunstancia."],
        "privacy.security.t":[.ar: "كيف نحميها",     .en: "How we protect it",   .fr: "Comment nous les protégeons", .tr: "Nasıl koruyoruz", .es: "Cómo los protegemos"],
        "privacy.security.b":[.ar: "نشفّر كلمات المرور ونؤمّن الاتصال بخوادمنا. أمّا روابط البثّ فيتحكّم بها مزوّدك، وقد تصلك دون تشفير.", .en: "We encrypt passwords and secure the connection to our servers. Stream links, however, are controlled by your provider and may reach you unencrypted.", .fr: "Nous chiffrons les mots de passe et sécurisons la liaison avec nos serveurs. Les liens de diffusion, eux, dépendent de votre fournisseur et peuvent vous parvenir sans chiffrement.", .tr: "Şifreleri şifreler, sunucularımıza olan bağlantıyı güvene alırız. Yayın bağlantıları ise sağlayıcınızın denetimindedir ve size şifresiz ulaşabilir.", .es: "Ciframos las contraseñas y aseguramos la conexión con nuestros servidores. Los enlaces de emisión, en cambio, los controla tu proveedor y pueden llegarte sin cifrar."],
        "privacy.rights.t":  [.ar: "ما تملكه أنت",             .en: "What is yours",     .fr: "Ce qui vous appartient",      .tr: "Size ait olan",      .es: "Lo que es tuyo"],
        "privacy.rights.b":  [.ar: "تستطيع حذف حسابك وكل بياناتك متى شئت، من داخل الإعدادات.", .en: "You can delete your account and all of your data whenever you like, from inside Settings.", .fr: "Vous pouvez supprimer votre compte et toutes vos données quand vous le souhaitez, depuis les réglages.", .tr: "Hesabınızı ve tüm verilerinizi dilediğiniz an Ayarlar'dan silebilirsiniz.", .es: "Puedes eliminar tu cuenta y todos tus datos cuando quieras, desde Ajustes."],
        "privacy.content.t": [.ar: "عن المحتوى",           .en: "About the content",         .fr: "À propos du contenu",         .tr: "İçerik hakkında",          .es: "Sobre el contenido"],
        "privacy.content.b": [.ar: "التطبيق أداة تشغيل لا أكثر. مشروعية ما تصل إليه مسؤوليتك وحدك.", .en: "The app is a player, nothing more. Whether what you reach is lawful is your responsibility alone.", .fr: "L'app est un lecteur, rien de plus. La légalité de ce que vous atteignez ne relève que de vous.", .tr: "Uygulama bir oynatıcıdır, fazlası değil. Eriştiğiniz içeriğin yasallığı yalnızca sizin sorumluluğunuzdadır.", .es: "La app es un reproductor, nada más. La legalidad de lo que abras es solo responsabilidad tuya."],
        "privacy.updated":   [.ar: "آخر تحديث: يوليو ٢٠٢٦", .en: "Last updated: July 2026", .fr: "Dernière mise à jour : juillet 2026", .tr: "Son güncelleme: Temmuz 2026", .es: "Última actualización: julio de 2026"],

        // Terms
        "terms.accept.t":    [.ar: "موافقتك",       .en: "Your agreement", .fr: "Votre accord", .tr: "Onayınız", .es: "Tu acuerdo"],
        "terms.accept.b":    [.ar: "باستخدام تطبيق %@، فإنك تقبل هذه الشروط والأحكام بالكامل.", .en: "By using the %@ app, you fully accept these terms and conditions.", .fr: "En utilisant l'application %@, vous acceptez pleinement ces conditions générales.", .tr: "%@ uygulamasını kullanarak bu şartları ve koşulları tamamen kabul edersiniz.", .es: "Al usar la aplicación %@, aceptas plenamente estos términos y condiciones."],
        "terms.use.t":       [.ar: "حدود الاستخدام", .en: "Limits of use",   .fr: "Limites d'utilisation", .tr: "Kullanım sınırları", .es: "Límites de uso"],
        "terms.use.b":       [.ar: "التطبيق للاستخدام الشخصي وحده. إعادة التوزيع أو الاستخدام التجاري ممنوعان.", .en: "The app is for personal use alone. Redistribution and commercial use are not permitted.", .fr: "L'app est réservée à votre usage personnel. La redistribution et l'exploitation commerciale sont exclues.", .tr: "Uygulama yalnızca kişisel kullanımınız içindir. Yeniden dağıtım ve ticari kullanım kabul edilmez.", .es: "La app es solo para tu uso personal. No se admite la redistribución ni el uso comercial."],
        "terms.content.t":   [.ar: "من يتحمّل مسؤولية المحتوى",   .en: "Who is responsible for the content", .fr: "Qui répond du contenu", .tr: "İçerikten kim sorumlu", .es: "Quién responde del contenido"],
        "terms.content.b":   [.ar: "أنت وحدك. طبيعة ما تصل إليه ومشروعيته مسؤوليتك التامة.", .en: "You alone. The nature and the lawfulness of what you reach are entirely your responsibility.", .fr: "Vous seul. La nature et la légalité de ce que vous atteignez relèvent entièrement de vous.", .tr: "Yalnızca siz. Eriştiğiniz içeriğin niteliği ve yasallığı tümüyle size aittir.", .es: "Solo tú. La naturaleza y la legalidad de lo que abras dependen enteramente de ti."],
        "terms.terminate.t": [.ar: "متى نوقف حسابك",      .en: "When we close an account",     .fr: "Quand un compte est fermé",     .tr: "Hesabı ne zaman kapatırız",           .es: "Cuándo cerramos una cuenta"],
        "terms.terminate.b": [.ar: "عند مخالفة هذه الشروط أو أي استخدام غير قانوني، نحتفظ بحقّ إنهاء حسابك.", .en: "If these terms are broken or the app is used unlawfully, we reserve the right to end your account.", .fr: "En cas de manquement à ces conditions ou d'usage illicite, nous pouvons mettre fin à votre compte.", .tr: "Bu şartlara uyulmaması ya da yasa dışı kullanım hâlinde hesabınızı kapatma hakkımız saklıdır.", .es: "Si se incumplen estos términos o se usa la app de forma ilegal, podemos cerrar tu cuenta."],
        "terms.changes.t":   [.ar: "إن تغيّرت الشروط",         .en: "If the terms change",         .fr: "Si les conditions changent",   .tr: "Şartlar değişirse",   .es: "Si los términos cambian"],
        "terms.changes.b":   [.ar: "قد نعدّل هذه الشروط. استمرارك في الاستخدام بعد التعديل يعني قبولك بها.", .en: "We may amend these terms. Carrying on using the app after an amendment means you accept it.", .fr: "Ces conditions peuvent évoluer. Continuer à utiliser l'app après une modification vaut acceptation.", .tr: "Bu şartlar değişebilir. Değişiklikten sonra uygulamayı kullanmayı sürdürmeniz kabul anlamına gelir.", .es: "Estos términos pueden cambiar. Seguir usando la app tras un cambio significa que lo aceptas."],

        // Activation gate
        "actgate.checking": [.ar: "نتأكّد من تفعيلك…", .en: "Checking your activation…", .fr: "On vérifie votre activation…", .tr: "Etkinleştirmeniz denetleniyor…", .es: "Comprobando tu activación…"],
        "maintenance.title":[.ar: "صيانة قصيرة", .en: "Brief maintenance", .fr: "Courte maintenance", .tr: "Kısa bir bakım", .es: "Mantenimiento breve"],
        "maintenance.message":[.ar: "نُحسّن الخدمة الآن. عُد بعد قليل.", .en: "We're improving the service. Come back shortly.", .fr: "Nous améliorons le service. Revenez dans un instant.", .tr: "Hizmeti iyileştiriyoruz. Birazdan tekrar uğrayın.", .es: "Estamos mejorando el servicio. Vuelve en un momento."],
        "update.title":     [.ar: "يلزم تحديث", .en: "Update needed", .fr: "Mise à jour nécessaire", .tr: "Güncelleme gerekiyor", .es: "Hace falta actualizar"],
        "update.message":   [.ar: "هذه النسخة قديمة. حدّثها للمتابعة.", .en: "This version is out of date. Update it to carry on.", .fr: "Cette version est dépassée. Mettez-la à jour pour continuer.", .tr: "Bu sürüm eskidi. Devam etmek için güncelleyin.", .es: "Esta versión está anticuada. Actualízala para seguir."],
        "update.latest":    [.ar: "الإصدار الأحدث:", .en: "Newest version:", .fr: "Dernière version :", .tr: "En son sürüm:", .es: "Última versión:"],
        "update.button":    [.ar: "حدّث الآن", .en: "Update now", .fr: "Mettre à jour maintenant", .tr: "Şimdi güncelle", .es: "Actualizar ahora"],
        "actgate.device_id":[.ar: "معرّف جهازك",        .en: "Your device ID",  .fr: "ID de votre appareil", .tr: "Cihaz Kimliğiniz", .es: "ID de tu dispositivo"],
        "actgate.copied":   [.ar: "نُسخ ✓",         .en: "Copied ✓",        .fr: "Copié ✓",         .tr: "Kopyalandı ✓",    .es: "Copiado ✓"],
        "actgate.copy_id":  [.ar: "انسخ المعرّف",        .en: "Copy the ID",         .fr: "Copier l'ID",     .tr: "Kimliği Kopyala", .es: "Copiar ID"],
        "actgate.recheck":  [.ar: "أعد الفحص",     .en: "Check again",     .fr: "Revérifier", .tr: "Yeniden denetle", .es: "Volver a comprobar"],
        "actgate.contact":  [.ar: "الدعم يفعّل لك الجهاز", .en: "Support can activate your device", .fr: "Le support peut activer votre appareil", .tr: "Destek ekibi cihazınızı etkinleştirebilir", .es: "Soporte puede activar tu dispositivo"],
        "actgate.demo":     [.ar: "ادخل للتجربة أولاً", .en: "Try it first", .fr: "Essayer d'abord", .tr: "Önce dene", .es: "Probar primero"],
        "actgate.blocked.title":  [.ar: "الجهاز موقوف", .en: "Device suspended", .fr: "Appareil suspendu", .tr: "Cihaz askıya alındı", .es: "Dispositivo suspendido"],
        "actgate.offline.title":  [.ar: "لا اتصال", .en: "No connection", .fr: "Pas de connexion", .tr: "Bağlantı yok", .es: "Sin conexión"],
        "actgate.notactive.title":[.ar: "لم يُفعَّل بعد", .en: "Not activated yet", .fr: "Pas encore activé", .tr: "Henüz etkinleştirilmedi", .es: "Aún sin activar"],
        "actgate.offline.msg":    [.ar: "لا نصل إلى الشبكة. تحقّق من اتصالك ثم حاول ثانيةً.", .en: "We can't reach the network. Check your connection and try again.", .fr: "Le réseau est injoignable. Contrôlez votre connexion et réessayez.", .tr: "Ağa ulaşamıyoruz. Bağlantınızı kontrol edip yeniden deneyin.", .es: "No llegamos a la red. Revisa tu conexión e inténtalo otra vez."],
        "actgate.blocked.msg":    [.ar: "أُوقف هذا الجهاز عن الخدمة. موزّعك وحده يستطيع إعادة تفعيله.", .en: "This device has been suspended. Only your reseller can activate it again.", .fr: "Cet appareil a été suspendu. Seul votre revendeur peut le réactiver.", .tr: "Bu cihaz askıya alındı. Yalnızca bayiniz yeniden etkinleştirebilir.", .es: "Este dispositivo ha sido suspendido. Solo tu distribuidor puede reactivarlo."],
        "actgate.notactive.msg":  [.ar: "أرسل معرّف جهازك أعلاه إلى موزّعك، وحين يفعّله اضغط «أعد الفحص».", .en: "Send the device ID above to your reseller, then tap “Check again” once they activate it.", .fr: "Envoyez l'ID ci-dessus à votre revendeur, puis touchez « Revérifier » dès qu'il l'active.", .tr: "Yukarıdaki cihaz kimliğini bayinize gönderin, etkinleştirdiğinde \"Yeniden denetle\"ye dokunun.", .es: "Envía el ID de arriba a tu distribuidor y, cuando lo active, pulsa \"Volver a comprobar\"."],
        "trial.banner":     [.ar: "وضع التجربة",       .en: "Trial mode",      .fr: "Mode essai", .tr: "Deneme modu",   .es: "Modo de prueba"],

        // Content lists / empties
        "live.empty.title": [.ar: "لا توجد قنوات",      .en: "No channels",     .fr: "Aucune chaîne",   .tr: "Kanal yok",       .es: "Sin canales"],
        "live.empty.sub":   [.ar: "جرّب كلمات بحث مختلفة", .en: "Try different search terms", .fr: "Essayez d'autres mots", .tr: "Başka kelimeler deneyin", .es: "Prueba con otras palabras"],
        "cats.channels":    [.ar: "تصنيفات القنوات",      .en: "Channel categories", .fr: "Catégories de chaînes", .tr: "Kanal Kategorileri", .es: "Categorías de canales"],
        "cats.movies":      [.ar: "تصنيفات الأفلام",      .en: "Movie categories", .fr: "Catégories de films", .tr: "Film Kategorileri", .es: "Categorías de películas"],
        "cats.series":      [.ar: "تصنيفات المسلسلات",    .en: "Series categories", .fr: "Catégories de séries", .tr: "Dizi Kategorileri", .es: "Categorías de series"],
        "cats.empty.title": [.ar: "لا أقسام",           .en: "No categories",   .fr: "Aucune catégorie",.tr: "Kategori yok",    .es: "Sin categorías"],
        "cats.empty.sub":   [.ar: "جرّب بحثاً مختلفاً", .en: "Try a different search", .fr: "Essayez une autre recherche", .tr: "Farklı bir arama deneyin", .es: "Prueba otra búsqueda"],
        "history.empty":    [.ar: "لا سجل مشاهدة",      .en: "No watch history", .fr: "Aucun historique de visionnage", .tr: "İzleme geçmişi yok", .es: "Sin historial de visionado"],
        "history.empty.generic":[.ar: "لا سجل",         .en: "No history",      .fr: "Aucun historique",.tr: "Geçmiş yok",      .es: "Sin historial"],
        "history.empty.sub":[.ar: "سيظهر هنا ما تشاهده", .en: "What you watch will appear here", .fr: "Vos visionnages s'afficheront ici", .tr: "İzledikleriniz burada listelenir", .es: "Lo que veas se mostrará aquí"],
        "movies.empty":     [.ar: "لا توجد أفلام",      .en: "No movies",       .fr: "Aucun film",      .tr: "Film yok",        .es: "Sin películas"],
        "movies.empty.fav": [.ar: "لا أفلام في المفضّلة", .en: "No favorite movies", .fr: "Aucun film favori", .tr: "Favori film yok", .es: "Sin películas favoritas"],
        "series.empty":     [.ar: "لا توجد مسلسلات",    .en: "No series",       .fr: "Aucune série",    .tr: "Dizi yok",        .es: "Sin series"],
        "series.empty.fav": [.ar: "لا مسلسلات في المفضّلة", .en: "No favorite series", .fr: "Aucune série favorite", .tr: "Favori dizi yok", .es: "Sin series favoritas"],
        "grid.empty":       [.ar: "لا توجد عناصر",      .en: "No items",        .fr: "Aucun élément",   .tr: "Öğe yok",         .es: "Sin elementos"],
        "grid.empty.sub":   [.ar: "جرّب بحثاً أو تصنيفاً آخر", .en: "Try another search or category", .fr: "Essayez une autre recherche ou catégorie", .tr: "Başka bir arama veya kategori deneyin", .es: "Prueba otra búsqueda o categoría"],

        // Detail
        "detail.fav_added": [.ar: "في المفضلة",         .en: "In Favorites",    .fr: "Dans les favoris",.tr: "Favorilerde",     .es: "En favoritos"],
        "detail.fav_add":   [.ar: "إضافة للمفضلة",      .en: "Add to Favorites",.fr: "Ajouter aux favoris", .tr: "Favorilere Ekle", .es: "Añadir a favoritos"],

        // Details sheet — every row is optional, see S8KTitleDetails
        "details.title":         [.ar: "التفاصيل",        .en: "Details",         .fr: "Détails",         .tr: "Ayrıntılar",      .es: "Detalles"],
        "details.original_name": [.ar: "الاسم الأصلي",    .en: "Original title",  .fr: "Titre original",  .tr: "Orijinal ad",     .es: "Título original"],
        "details.country":       [.ar: "بلد الإنتاج",     .en: "Country",         .fr: "Pays",            .tr: "Ülke",            .es: "País"],
        "details.release_date":  [.ar: "تاريخ الإصدار",   .en: "Release date",    .fr: "Date de sortie",  .tr: "Yayın tarihi",    .es: "Fecha de estreno"],
        "details.age":           [.ar: "التصنيف العمري",  .en: "Age rating",      .fr: "Classification",  .tr: "Yaş sınırı",      .es: "Clasificación"],
        "details.runtime":       [.ar: "المدة",           .en: "Runtime",         .fr: "Durée",           .tr: "Süre",            .es: "Duración"],
        "details.resolution":    [.ar: "الدقة",           .en: "Resolution",      .fr: "Résolution",      .tr: "Çözünürlük",      .es: "Resolución"],
        "details.video":         [.ar: "ترميز الفيديو",   .en: "Video",           .fr: "Vidéo",           .tr: "Video",           .es: "Vídeo"],
        "details.audio":         [.ar: "ترميز الصوت",     .en: "Audio",           .fr: "Audio",           .tr: "Ses",             .es: "Audio"],
        "details.channels":      [.ar: "قنوات الصوت",     .en: "Channels",        .fr: "Canaux",          .tr: "Kanallar",        .es: "Canales"],
        "details.bitrate":       [.ar: "معدل البت",       .en: "Bitrate",         .fr: "Débit",           .tr: "Bit hızı",        .es: "Tasa de bits"],
        "details.trailer":       [.ar: "المقطع الدعائي",  .en: "Trailer",         .fr: "Bande-annonce",   .tr: "Fragman",         .es: "Tráiler"],
        "details.file":          [.ar: "الملف",           .en: "File",            .fr: "Fichier",         .tr: "Dosya",           .es: "Archivo"],
        "details.minutes":       [.ar: "دقيقة",           .en: "min",             .fr: "min",             .tr: "dk",              .es: "min"],
        "details.about":         [.ar: "عن العمل",        .en: "About",           .fr: "À propos",        .tr: "Hakkında",        .es: "Acerca de"],

        // Search
        "search.title":     [.ar: "البحث",              .en: "Search",          .fr: "Recherche",       .tr: "Arama",           .es: "Buscar"],
        "search.empty.title":[.ar: "لا توجد نتائج",     .en: "No results",      .fr: "Aucun résultat",  .tr: "Sonuç yok",       .es: "Sin resultados"],
        "search.empty.sub": [.ar: "جرب كلمات مختلفة",   .en: "Try different keywords", .fr: "Essayez d'autres mots-clés", .tr: "Farklı kelimeler deneyin", .es: "Prueba otras palabras"],
        "search.recent":    [.ar: "بحثت مؤخّراً", .en: "Searched recently", .fr: "Recherches récentes", .tr: "Son aramalar", .es: "Búsquedas recientes"],
        "search.clear_all": [.ar: "مسح الكل",           .en: "Clear All",       .fr: "Tout effacer",    .tr: "Tümünü Temizle",  .es: "Borrar todo"],
        "search.type.live": [.ar: "بث مباشر",           .en: "Live",            .fr: "En direct",       .tr: "Canlı",           .es: "En directo"],
        "search.type.movie":[.ar: "فيلم",               .en: "Movie",           .fr: "Film",            .tr: "Film",            .es: "Película"],
        "search.type.series":[.ar: "مسلسل",             .en: "Series",          .fr: "Série",           .tr: "Dizi",            .es: "Serie"],
        "search.type.all":  [.ar: "الكل",               .en: "All",             .fr: "Tout",            .tr: "Tümü",            .es: "Todo"],
        "search.failed.title":[.ar: "تعذّر البحث",       .en: "Search failed",   .fr: "Échec de la recherche", .tr: "Arama başarısız", .es: "Error en la búsqueda"],
        "search.failed.sub": [.ar: "تحقّق من اتصالك وحاول مرة أخرى", .en: "Check your connection and try again", .fr: "Vérifiez votre connexion et réessayez", .tr: "Bağlantınızı kontrol edip tekrar deneyin", .es: "Revisa tu conexión e inténtalo de nuevo"],
        "search.start.title":[.ar: "ما الذي تبحث عنه؟",         .en: "What are you after?", .fr: "Que cherchez-vous ?", .tr: "Ne arıyorsunuz?", .es: "¿Qué estás buscando?"],
        "search.start.sub":  [.ar: "اختر النوع، ثم اكتب", .en: "Pick a type, then start typing", .fr: "Choisissez un type, puis tapez", .tr: "Bir tür seçin, sonra yazmaya başlayın", .es: "Elige un tipo y empieza a escribir"],

        // Subscription day-count sentences (composed: prefix + N day + suffix)
        "sub.days_left_prefix": [.ar: "بقي",          .en: "",                .fr: "Il reste",        .tr: "",                .es: "Quedan"],
        "sub.expire_suffix":    [.ar: "على انتهاء اشتراكك — جدّده قبل أن تنقطع الخدمة", .en: "left on your subscription — renew before the service cuts out", .fr: "avant la fin de votre abonnement — renouvelez avant la coupure", .tr: "aboneliğinizin bitmesine kaldı — hizmet kesilmeden yenileyin", .es: "para que acabe tu suscripción — renueva antes de quedarte sin servicio"],
        "sub.active_suffix":    [.ar: "على اشتراكك",    .en: "left on your subscription", .fr: "sur votre abonnement", .tr: "abonelik süreniz kaldı", .es: "de tu suscripción"],

        // App Store legal disclaimer (Guideline 4.3 / 5.x)
        "legal.disclaimer": [
            .ar: "مشغّل فقط: لا نوفّر قنوات ولا نستضيف محتوى. اشتراكك من مزوّد مرخّص، ومشروعية ما تشاهده مسؤوليتك وحدك.",
            .en: "A player, nothing more: we supply no channels and host no content. Your subscription comes from a licensed provider, and what you watch is your responsibility alone.",
            .fr: "Un lecteur, rien de plus : nous ne fournissons aucune chaîne et n'hébergeons aucun contenu. Votre abonnement vient d'un fournisseur agréé, et ce que vous regardez ne relève que de vous.",
            .tr: "Yalnızca bir oynatıcı: hiçbir kanal sunmaz, hiçbir içerik barındırmayız. Aboneliğiniz lisanslı bir sağlayıcıdan gelir ve izlediğiniz şey yalnızca sizin sorumluluğunuzdadır.",
            .es: "Un reproductor, nada más: no ofrecemos canales ni alojamos contenido. Tu suscripción viene de un proveedor autorizado y lo que ves es responsabilidad solo tuya."
        ],
    ]
}

// MARK: ════════════════════════════════════════
// NETWORK — API CLIENT
// ════════════════════════════════════════════
enum APIConfig {
    // UNREACHABLE, and the address says so on purpose.
    //
    // Every caller of `APIClient.request` passes requiresAuth: true except
    // `AuthService.login`, which throws on a nil Keychain token — and `login` is
    // itself dead: the UI only ever calls loginXtream / loginM3U, which go DIRECT to
    // the user's own provider. So `Keychain.shared.token` is never written anywhere
    // in the app, and no request here can reach the network. Verified by tracing
    // every call site, not assumed.
    //
    // It used to read `https://strong8k.app/api/v1`, and that shipped as a literal in
    // the binary. `strings` on the IPA showed the REFERENCE app's live domain sitting
    // inside an app we are arguing is independent — which is precisely the kind of
    // evidence that makes a Guideline 4.3 rejection stick. `.invalid` is reserved by
    // RFC 2606 and can never resolve, so it also documents the truth: there is no
    // endpoint. The right end state is deleting this subsystem outright; that is a
    // wide change across ~15 call sites and wants its own reviewed commit.
    static let primary  = "https://api.invalid/v1"
    static let fallback = "https://api.invalid/v1"
    static let timeout: TimeInterval = 25
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

enum HTTPMethod: String { case GET, POST, PUT, DELETE }

actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private var baseURL = APIConfig.primary
    private var failCount = 0

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = APIConfig.timeout
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy         = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept":       "application/json",
            "X-App-Version": APIConfig.version,
            "X-Platform":    "iOS"
        ]
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Generic Request
    func request<T: Decodable>(
        path: String,
        method: HTTPMethod = .GET,
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {

        var urlStr = baseURL + path
        if let q = query, !q.isEmpty {
            let items = q.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            urlStr += "?\(items)"
        }

        guard let url = URL(string: urlStr) else {
            throw AppError.server("رابط غير صالح")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue

        if requiresAuth {
            guard let token = Keychain.shared.token else {
                throw AppError.invalidCredentials
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        addSignature(&req)

        let data = try await executeWithFallback(req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.server("خطأ في معالجة البيانات")
        }
    }

    // MARK: - Execute + Fallback
    private func executeWithFallback(_ req: URLRequest) async throws -> Data {
        do {
            let data = try await execute(req)
            failCount = 0
            return data
        } catch {
            failCount += 1
            if failCount >= 3 {
                baseURL  = APIConfig.fallback
                failCount = 0
            }
            throw error
        }
    }

    private func execute(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.server("استجابة غير صالحة")
        }
        try handle(statusCode: http.statusCode, data: data)
        return data
    }

    // MARK: - Status Code Handler
    private func handle(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299: return
        case 401: throw AppError.invalidCredentials
        case 403:
            if let err = try? JSONDecoder().decode(ServerError.self, from: data) {
                switch err.error {
                case "ACCOUNT_SUSPENDED":  throw AppError.accountSuspended
                case "ACCOUNT_EXPIRED":    throw AppError.accountExpired
                case "MAX_CONNECTIONS":    throw AppError.maxConnections(err.max ?? 1)
                case "MAINTENANCE":        throw AppError.maintenance(err.message)
                case "VERSION_OUTDATED":   throw AppError.versionOutdated(err.minVersion ?? "1.0.0")
                default:                   throw AppError.server(err.message ?? "خطأ")
                }
            }
            throw AppError.server("غير مصرح")
        case 503: throw AppError.server("السيرفر غير متاح")
        default:  throw AppError.server("خطأ (\(statusCode))")
        }
    }

    // MARK: - Request Signing
    private func addSignature(_ req: inout URLRequest) {
        let ts     = "\(Int(Date().timeIntervalSince1970))"
        let device = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let path   = req.url?.path ?? ""
        let msg    = "\(ts):\(device):\(path)"
        let sig    = msg.hmac256(key: "S8K_2025_SIGN")
        req.setValue(ts,     forHTTPHeaderField: "X-Timestamp")
        req.setValue(sig,    forHTTPHeaderField: "X-Signature")
        req.setValue(device, forHTTPHeaderField: "X-Device-ID")
    }
}

private struct ServerError: Decodable {
    let error:      String?
    let message:    String?
    let minVersion: String?
    let max:        Int?
}

extension String {
    func hmac256(key: String) -> String {
        let k = SymmetricKey(data: Data(key.utf8))
        let m = HMAC<SHA256>.authenticationCode(for: Data(self.utf8), using: k)
        return Data(m).map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: ════════════════════════════════════════
// STORAGE — KEYCHAIN
// ════════════════════════════════════════════
final class Keychain {
    static let shared = Keychain()
    private init() {}
    private let service = "com.blanktv.app"

    private enum Key: String {
        case token, host, user, pass, userID, tokenExpiry, deviceID, m3uURL
    }

    /// Persistent device identity (survives app reinstall — stays in Keychain)
    var deviceID: String? {
        get { load(.deviceID) }
        set { newValue == nil ? delete(.deviceID) : save(.deviceID, value: newValue!) }
    }

    /// The playlist URL. For an Xtream line this CONTAINS the username and password
    /// in its query string, which is why it belongs here and not in UserDefaults.
    var m3uURL: String? {
        get { load(.m3uURL) }
        set { newValue == nil ? delete(.m3uURL) : save(.m3uURL, value: newValue!) }
    }

    var token: String? {
        get { load(.token) }
        set { newValue == nil ? delete(.token) : save(.token, value: newValue!) }
    }
    var host: String?  {
        get { load(.host) }
        set { newValue == nil ? delete(.host)  : save(.host, value: newValue!) }
    }
    var xtreamUser: String? {
        get { load(.user) }
        set { newValue == nil ? delete(.user)  : save(.user, value: newValue!) }
    }
    var xtreamPass: String? {
        get { load(.pass) }
        set { newValue == nil ? delete(.pass)  : save(.pass, value: newValue!) }
    }
    var userID: String? {
        get { load(.userID) }
        set { newValue == nil ? delete(.userID) : save(.userID, value: newValue!) }
    }
    var tokenExpiry: TimeInterval? {
        get { load(.tokenExpiry).flatMap { Double($0) } }
        set { newValue == nil ? delete(.tokenExpiry) : save(.tokenExpiry, value: "\(newValue!)") }
    }

    var tokenValid: Bool {
        guard let t = token, !t.isEmpty, let exp = tokenExpiry else { return false }
        return Date().timeIntervalSince1970 < (exp - 300) // 5 min buffer
    }

    func saveServerCredentials(host: String, user: String, pass: String) {
        self.host = host; self.xtreamUser = user; self.xtreamPass = pass
    }

    func serverCredentials() -> (host: String, user: String, pass: String)? {
        guard let h = host, let u = xtreamUser, let p = xtreamPass else { return nil }
        return (h, u, p)
    }

    func clearAll() {
        [Key.token, Key.host, Key.user, Key.pass, Key.userID, Key.tokenExpiry,
         Key.m3uURL].forEach { delete($0) }
    }

    /// One-shot: rewrite every stored item so it carries the CURRENT accessibility
    /// class. `save()` is delete-then-add, so an item written by an older build keeps
    /// `WhenUnlocked` until something rewrites it — which for `deviceID` (deliberately
    /// preserved across reinstall) and for a token that is only refreshed on login can
    /// be never. Without this the background-relaunch fix reaches `m3uURL` and stops
    /// there, and the token beside it stays unreadable on a locked device.
    func upgradeAccessibilityIfNeeded() {
        let flag = "s8k.kc.accessibility.v2"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        for k in [Key.token, .host, .user, .pass, .userID, .tokenExpiry, .deviceID, .m3uURL] {
            if let v = load(k) { save(k, value: v) }   // rewrites with the new class
        }
        UserDefaults.standard.set(true, forKey: flag)
    }

    /// Deleted ONLY by account deletion. `clearAll()` deliberately keeps the device ID
    /// because logout calls it, and minting a new identity on every logout would break
    /// the activation binding.
    ///
    /// HONEST LIMIT: this removes the STORED copy, and a Keychain item otherwise
    /// survives deleting the app itself. It does NOT make the device unrecognisable —
    /// `DeviceIdentity.generate()` is a pure function of `identifierForVendor`, so the
    /// next read mints the identical value. Seeding the identity from a random UUID
    /// instead is a deliberate decision about activation binding, not a cleanup, so it
    /// is not made here.
    func deleteDeviceID() { delete(.deviceID) }

    // MARK: - Private CRUD
    private func save(_ key: Key, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecAttrService: service,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load(_ key: Key) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrAccount:  key.rawValue,
            kSecAttrService:  service,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ key: Key) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}




// MARK: ════════════════════════════════════════
// STORAGE — APP STORAGE (UserDefaults)
// ════════════════════════════════════════════
// MARK: - App Store compliance
enum AppCompliance {
    /// Guideline 3.1.1: iOS apps must NOT link out to external mechanisms for
    /// purchasing digital content/subscriptions. We hard-disable purchase/store
    /// links on iOS (this build) so the App Store version can never violate it.
    /// Support/contact links (no prices, no purchase) stay allowed.
    /// The Android/Fire TV client (separate project) is free of this rule.
    static let allowsExternalPurchaseLinks = false
}

final class Store {
    static let shared = Store()
    private init() {}
    private let ud = UserDefaults.standard

    enum K: String {
        case onboarded, theme, features, appConfig
        case userInfo, serverInfo, lastConfigFetch
        case favChannels, favMovies, favSeries
        case watchHistory, watchlist
        case parentalOn, parentalPIN
        case sleepMins, quality, analyticsConsent
        case advancedURL
        case loginMode, m3uURL
        case pipOn, watermarkOn, notifOn
        case demoMode
        case savedPlaylists, activePlaylist
        case autoPlayNext, skipIntroOn, skipIntroSecs, autoNextSecs
        case lockedCats, parentalRecov
        case resellerCode, resellerHost, brandName, brandColor, brandLogo
        case lastSubtitleName, lastAudioName, playbackRate
    }

    // MARK: - Player preferences (remember last audio / subtitle across episodes)
    var lastSubtitleName: String? {
        get { ud.string(forKey: K.lastSubtitleName.rawValue) }
        set { newValue == nil ? ud.removeObject(forKey: K.lastSubtitleName.rawValue) : ud.set(newValue, forKey: K.lastSubtitleName.rawValue) }
    }
    var lastAudioName: String? {
        get { ud.string(forKey: K.lastAudioName.rawValue) }
        set { newValue == nil ? ud.removeObject(forKey: K.lastAudioName.rawValue) : ud.set(newValue, forKey: K.lastAudioName.rawValue) }
    }
    /// Subtitle font size in px for the VLC renderer (0 = auto/VLC default). App-wide,
    /// remembered across episodes/sessions.
    var subtitleFontSize: Int {
        get { ud.integer(forKey: "s8k.subFontSize") }   // 0 when unset = auto
        set { ud.set(newValue, forKey: "s8k.subFontSize") }
    }

    // MARK: - Playback engine preference
    // "auto" → hardware AVPlayer for HLS/mp4, VLC for everything else (default).
    // "av"   → force the hardware AVPlayer engine.  "vlc" → force the VLC engine.
    // Matches the per-app "Select Player" found in pro IPTV apps (Smarters/OTT Nav).
    var playerEnginePref: String {
        get { ud.string(forKey: "s8k.engine") ?? "auto" }
        set { ud.set(newValue, forKey: "s8k.engine") }
    }

    // MARK: - Turbo downloads (disabled)
    /// Parallel ("turbo") segmented downloading, over multi-connection HTTP Range.
    /// FORCED OFF, and deliberately no longer a stored preference.
    ///
    /// It runs on a `Task`, not on the background URLSession — and a `Task` is
    /// suspended the moment the app leaves the foreground, so a turbo download stops
    /// dead when the user switches away and never reports why. Its settings toggle was
    /// removed at some point WITHOUT clearing the key, which left anyone who had
    /// enabled it stranded on the broken path with no UI to turn it off.
    ///
    /// Reading `false` here also heals those installs: `launch` takes the background
    /// path for everyone. Re-enable only if turbo is rebuilt on the background session.
    var turboDownloads: Bool { false }
    /// Download only on Wi-Fi (waits for Wi-Fi instead of using cellular). OFF by default.
    var downloadWifiOnly: Bool {
        get { ud.bool(forKey: "s8k.downloadWifiOnly") }
        set { ud.set(newValue, forKey: "s8k.downloadWifiOnly") }
    }

    // MARK: - Reseller code (customer entered a reseller's code → branded + auto-activated)
    var resellerCode: String? {
        get { ud.string(forKey: K.resellerCode.rawValue) }
        set { newValue == nil ? ud.removeObject(forKey: K.resellerCode.rawValue) : ud.set(newValue, forKey: K.resellerCode.rawValue) }
    }
    var resellerHost: String? {
        get { ud.string(forKey: K.resellerHost.rawValue) }
        set { ud.set(newValue, forKey: K.resellerHost.rawValue) }
    }
    var brandName:  String? { get { ud.string(forKey: K.brandName.rawValue) }  set { ud.set(newValue, forKey: K.brandName.rawValue) } }
    var brandColor: String? { get { ud.string(forKey: K.brandColor.rawValue) } set { ud.set(newValue, forKey: K.brandColor.rawValue) } }
    var brandLogo:  String? { get { ud.string(forKey: K.brandLogo.rawValue) }  set { ud.set(newValue, forKey: K.brandLogo.rawValue) } }
    func clearReseller() {
        for k in [K.resellerCode, K.resellerHost, K.brandName, K.brandColor, K.brandLogo] { ud.removeObject(forKey: k.rawValue) }
    }

    // MARK: - Playback (auto-next + skip-intro). Default ON.
    var autoPlayNext: Bool {
        get { ud.object(forKey: K.autoPlayNext.rawValue) == nil ? true : ud.bool(forKey: K.autoPlayNext.rawValue) }
        set { ud.set(newValue, forKey: K.autoPlayNext.rawValue) }
    }
    /// Countdown (seconds) shown before auto-advancing to the next episode.
    var autoNextSeconds: Int {
        get { let v = ud.integer(forKey: K.autoNextSecs.rawValue); return v == 0 ? 10 : v }
        set { ud.set(newValue, forKey: K.autoNextSecs.rawValue) }
    }
    var skipIntroEnabled: Bool {
        get { ud.object(forKey: K.skipIntroOn.rawValue) == nil ? true : ud.bool(forKey: K.skipIntroOn.rawValue) }
        set { ud.set(newValue, forKey: K.skipIntroOn.rawValue) }
    }
    /// Seconds the "skip intro" button jumps to (configurable; default 85).
    var skipIntroSeconds: Int {
        get { let v = ud.integer(forKey: K.skipIntroSecs.rawValue); return v == 0 ? 85 : v }
        set { ud.set(newValue, forKey: K.skipIntroSecs.rawValue) }
    }

    // MARK: - Saved playlists (multiple)
    var savedPlaylists: [SavedPlaylist] {
        get { load([SavedPlaylist].self, key: .savedPlaylists) ?? [] }
        set { save(newValue, key: .savedPlaylists) }
    }
    var activePlaylistID: String? {
        get { ud.string(forKey: K.activePlaylist.rawValue) }
        set {
            if let v = newValue { ud.set(v, forKey: K.activePlaylist.rawValue) }
            else { ud.removeObject(forKey: K.activePlaylist.rawValue) }
        }
    }
    /// Insert/update a saved playlist and return its STABLE id. When an entry with
    /// the same kind+url already exists, its EXISTING id is preserved (not replaced
    /// by the incoming random UUID) so the per-playlist scope — favorites, history,
    /// watchlist, category order, all keyed by playlist id — survives a logout→login
    /// to the same line. Callers must use the returned id for `activePlaylistID`.
    @discardableResult
    func upsertPlaylist(_ p: SavedPlaylist) -> String {
        var list = savedPlaylists
        if let i = list.firstIndex(where: { $0.id == p.id }) {
            list[i] = p; savedPlaylists = list; return p.id
        } else if let i = list.firstIndex(where: { $0.kind == p.kind && $0.url == p.url }) {
            var merged = p; merged.id = list[i].id      // keep the existing (stable) scope id
            list[i] = merged; savedPlaylists = list; return merged.id
        } else {
            list.append(p); savedPlaylists = list; return p.id
        }
    }

    /// Demo Mode (App Store Review, Guideline 2.1) — shows the full app with
    /// working sample content, no subscription or activation required.
    var demoMode: Bool {
        get { ud.bool(forKey: K.demoMode.rawValue) }
        set { ud.set(newValue, forKey: K.demoMode.rawValue) }
    }

    // MARK: - Session
    var onboarded: Bool {
        get { ud.bool(forKey: K.onboarded.rawValue) }
        set { ud.set(newValue, forKey: K.onboarded.rawValue) }
    }
    var advancedURL: String? {
        get { ud.string(forKey: K.advancedURL.rawValue) }
        set { ud.set(newValue, forKey: K.advancedURL.rawValue) }
    }

    // MARK: - Login Mode (Xtream / M3U)
    var loginMode: LoginMode {
        get { LoginMode(rawValue: ud.string(forKey: K.loginMode.rawValue) ?? "") ?? .xtream }
        set { ud.set(newValue.rawValue, forKey: K.loginMode.rawValue) }
    }
    /// Outer nil = not read yet. Inner nil = read, and there is no URL. Cached
    /// because this is read on ~30 paths and a Keychain round trip costs far more than
    /// a UserDefaults read.
    ///
    /// LOCKED, and not optionally. `Store` has no isolation, and two of the readers —
    /// `PlaylistService._load` and `.validateCredentials` — sit inside an `actor`, so
    /// they run OFF the main thread while `AuthService` writes on it. UserDefaults was
    /// thread-safe and hid this; a plain stored `String??` is not, and its payload is a
    /// refcounted String, which makes the race a crash rather than a stale read.
    private var m3uURLCache: String??  = nil
    private let m3uLock = NSLock()

    /// The playlist URL — **credentials**. For an Xtream line the username and password
    /// are in its query string, so this lives in the Keychain. It used to live in
    /// UserDefaults, which is an unencrypted plist inside the app container and is
    /// carried into an unencrypted device backup.
    var m3uURL: String? {
        get {
            m3uLock.lock(); defer { m3uLock.unlock() }
            if let cached = m3uURLCache { return cached }
            // MIGRATION, once per install: an older build wrote this in the clear.
            // Move it, then delete the plaintext copy — leaving it behind would make
            // the whole change cosmetic for every existing user.
            if let legacy = ud.string(forKey: K.m3uURL.rawValue), !legacy.isEmpty {
                Keychain.shared.m3uURL = legacy
                // READ IT BACK before destroying the only other copy. `Keychain.save`
                // discards SecItemAdd's status, so a failure — no first unlock yet, a
                // keychain-access-group misconfiguration — would otherwise delete the
                // plaintext, leave nothing behind, and silently log the user out at the
                // NEXT launch with no way back. If the write did not take, keep the
                // plaintext and try again next time.
                if Keychain.shared.m3uURL == legacy {
                    ud.removeObject(forKey: K.m3uURL.rawValue)
                }
                m3uURLCache = .some(legacy)
                return legacy
            }
            let v = Keychain.shared.m3uURL
            // Cache a VALUE, never an absence. A Keychain read returns nil when the
            // device has not been unlocked since boot, and `restore()` reads this on
            // every launch INCLUDING a background relaunch for a finished download.
            // Memoising that nil would log the user out for the whole process.
            if v != nil { m3uURLCache = .some(v) }
            return v
        }
        set {
            m3uLock.lock(); defer { m3uLock.unlock() }
            // Keychain FIRST, then the cache: a concurrent reader must never observe
            // `.some(nil)` while the item still exists.
            Keychain.shared.m3uURL = newValue
            m3uURLCache = .some(newValue)
            // Belt and braces: never leave a plaintext copy behind, even if a legacy
            // value was written by an older build after this one first read.
            ud.removeObject(forKey: K.m3uURL.rawValue)
        }
    }

    /// Drop the cached URL. Anything that clears the session must call this, or the
    /// next read would hand back credentials that were just deleted.
    func invalidateM3UCache() { m3uLock.lock(); m3uURLCache = nil; m3uLock.unlock() }

    // MARK: - Config Cache
    func save<T: Encodable>(_ val: T, key: K) {
        ud.set(try? JSONEncoder().encode(val), forKey: key.rawValue)
    }
    func load<T: Decodable>(_ type: T.Type, key: K) -> T? {
        guard let data = ud.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func saveTheme(_ t: ThemeConfig)      { save(t, key: .theme) }
    func loadTheme() -> ThemeConfig?      { load(ThemeConfig.self, key: .theme) }
    func saveFeatures(_ f: FeaturesConfig){ save(f, key: .features) }
    func loadFeatures() -> FeaturesConfig?{ load(FeaturesConfig.self, key: .features) }
    func saveAppConfig(_ c: AppConfig)    { save(c, key: .appConfig) }
    func loadAppConfig() -> AppConfig?    { load(AppConfig.self, key: .appConfig) }
    func saveUserInfo(_ u: UserInfo)      { save(u, key: .userInfo) }
    func loadUserInfo() -> UserInfo?      { load(UserInfo.self, key: .userInfo) }
    func saveServerInfo(_ s: ServerInfo)  { save(s, key: .serverInfo) }
    func loadServerInfo() -> ServerInfo?  { load(ServerInfo.self, key: .serverInfo) }

    var lastConfigFetch: Date? {
        get {
            let t = ud.double(forKey: K.lastConfigFetch.rawValue)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { ud.set(newValue?.timeIntervalSince1970 ?? 0, forKey: K.lastConfigFetch.rawValue) }
    }
    var configStale: Bool {
        guard let last = lastConfigFetch else { return true }
        return Date().timeIntervalSince(last) > 1800 // 30 min
    }

    // MARK: - Settings
    var parentalEnabled: Bool {
        get { ud.bool(forKey: K.parentalOn.rawValue) }
        set { ud.set(newValue, forKey: K.parentalOn.rawValue) }
    }
    var parentalPIN: String? {
        get { ud.string(forKey: K.parentalPIN.rawValue) }
        set { ud.set(newValue, forKey: K.parentalPIN.rawValue) }
    }
    /// Hash of the one-time recovery code (used to reset a forgotten PIN).
    var parentalRecovery: String? {
        get { ud.string(forKey: K.parentalRecov.rawValue) }
        set { ud.set(newValue, forKey: K.parentalRecov.rawValue) }
    }
    /// Categories the user chose to lock (keys like "movie:123").
    var lockedCategories: Set<String> {
        get { Set(ud.stringArray(forKey: K.lockedCats.rawValue) ?? []) }
        set { ud.set(Array(newValue), forKey: K.lockedCats.rawValue) }
    }
    var sleepTimerMins: Int {
        get { let v = ud.integer(forKey: K.sleepMins.rawValue); return v == 0 ? 30 : v }
        set { ud.set(newValue, forKey: K.sleepMins.rawValue) }
    }
    var preferredQuality: StreamQuality {
        get { StreamQuality(rawValue: ud.string(forKey: K.quality.rawValue) ?? "") ?? .auto }
        set { ud.set(newValue.rawValue, forKey: K.quality.rawValue) }
    }
    var analyticsConsent: Bool {
        get { ud.bool(forKey: K.analyticsConsent.rawValue) }
        set { ud.set(newValue, forKey: K.analyticsConsent.rawValue) }
    }
    // Default true until the user disables them
    var pipEnabled: Bool {
        get { ud.object(forKey: K.pipOn.rawValue) == nil ? true : ud.bool(forKey: K.pipOn.rawValue) }
        set { ud.set(newValue, forKey: K.pipOn.rawValue) }
    }
    var watermarkEnabled: Bool {
        get { ud.object(forKey: K.watermarkOn.rawValue) == nil ? true : ud.bool(forKey: K.watermarkOn.rawValue) }
        set { ud.set(newValue, forKey: K.watermarkOn.rawValue) }
    }
    var notificationsEnabled: Bool {
        get { ud.object(forKey: K.notifOn.rawValue) == nil ? true : ud.bool(forKey: K.notifOn.rawValue) }
        set { ud.set(newValue, forKey: K.notifOn.rawValue) }
    }

    // MARK: - Per-playlist scoping
    // History, favorites and watchlist are ALL keyed by the active playlist/account
    // so one playlist's data never leaks into another. Demo has its own fixed
    // scope ("demo") so demo data never mixes with real playlists.
    private var scopeID: String { demoMode ? "demo" : (activePlaylistID ?? "default") }
    private func scopedKey(_ base: String) -> String { "\(base).\(scopeID)" }

    // MARK: - Favorites (scoped per playlist)
    var favChannels: Set<String> {
        get { Set(ud.stringArray(forKey: scopedKey("s8k.fav.channels")) ?? []) }
        set { ud.set(Array(newValue), forKey: scopedKey("s8k.fav.channels")) }
    }
    var favMovies: Set<String> {
        get { Set(ud.stringArray(forKey: scopedKey("s8k.fav.movies")) ?? []) }
        set { ud.set(Array(newValue), forKey: scopedKey("s8k.fav.movies")) }
    }
    var favSeries: Set<String> {
        get { Set(ud.stringArray(forKey: scopedKey("s8k.fav.series")) ?? []) }
        set { ud.set(Array(newValue), forKey: scopedKey("s8k.fav.series")) }
    }

    // MARK: - Watch History (scoped per active playlist, so each playlist keeps
    // its own history and deletions persist for that playlist only)
    private var historyKey: String { scopedKey("s8k.history") }
    func saveHistory(_ items: [WatchHistory]) {
        ud.set(try? JSONEncoder().encode(items), forKey: historyKey)
    }
    func loadHistory() -> [WatchHistory] {
        guard let data = ud.data(forKey: historyKey),
              let v = try? JSONDecoder().decode([WatchHistory].self, from: data) else { return [] }
        return v
    }

    // MARK: - Watchlist (scoped per playlist)
    func saveWatchlist(_ ids: [String]) { ud.set(ids, forKey: scopedKey("s8k.watchlist")) }
    func loadWatchlist() -> [String]    { ud.stringArray(forKey: scopedKey("s8k.watchlist")) ?? [] }

    // MARK: - Category order (user-customized, scoped per playlist)
    // Saved value = the category IDs the user numbered (1,2,3…). section is
    // "live" | "movies" | "series". Empty = provider default order.
    func categoryOrder(_ section: String) -> [String] {
        ud.stringArray(forKey: scopedKey("s8k.catorder2.\(section)")) ?? []
    }
    func setCategoryOrder(_ ids: [String], _ section: String) {
        ud.set(ids, forKey: scopedKey("s8k.catorder2.\(section)"))
    }
    /// Pure reorder: the user's numbered categories first (in the saved order),
    /// then everything else in its original order. Unknown/removed IDs are
    /// ignored and brand-new provider categories fall to the end automatically.
    /// Returns the input unchanged when no custom order is saved.
    func orderedCategories(_ cats: [Category], _ section: String) -> [Category] {
        let order = categoryOrder(section)
        guard !order.isEmpty else { return cats }
        var rank: [String: Int] = [:]
        for (i, id) in order.enumerated() { rank[id] = i }
        let numbered = cats.filter { rank[$0.id] != nil }
                           .sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
        let rest = cats.filter { rank[$0.id] == nil }
        return numbered + rest
    }

    // MARK: - Migration (run once at launch)
    // Existing users stored favorites/watchlist under GLOBAL keys. Move them into
    // the active playlist's scope so nothing is lost, without crashing on first
    // launch. History real-playlist keys are unchanged (same format), so they
    // need no migration. Idempotent via a one-time flag.
    func migrateLegacyScopedDataIfNeeded() {
        let flag = "s8k.migrated.scopedV2"
        guard !ud.bool(forKey: flag) else { return }
        let target = activePlaylistID ?? "default"   // never the demo scope
        mergeLegacy(old: "favChannels", into: "s8k.fav.channels.\(target)")
        mergeLegacy(old: "favMovies",   into: "s8k.fav.movies.\(target)")
        mergeLegacy(old: "favSeries",   into: "s8k.fav.series.\(target)")
        mergeLegacy(old: "watchlist",   into: "s8k.watchlist.\(target)")
        ud.set(true, forKey: flag)
    }
    private func mergeLegacy(old: String, into newKey: String) {
        guard let legacy = ud.stringArray(forKey: old), !legacy.isEmpty else { return }
        let existing = ud.stringArray(forKey: newKey) ?? []
        ud.set(Array(Set(existing + legacy)), forKey: newKey)   // merge, no clobber
        ud.removeObject(forKey: old)
    }

    /// Remove all per-playlist data (history/favorites/watchlist) for a deleted
    /// playlist — affects ONLY that playlist's scope.
    func clearScopedData(playlistID: String) {
        for base in ["s8k.history", "s8k.fav.channels", "s8k.fav.movies", "s8k.fav.series", "s8k.watchlist",
                     "s8k.catorder2.live", "s8k.catorder2.movies", "s8k.catorder2.series"] {
            ud.removeObject(forKey: "\(base).\(playlistID)")
        }
    }

    // MARK: - Clear
    func clearSession() {
        // The URL itself now lives in the Keychain (see m3uURL) and is removed by
        // Keychain.clearAll(); this drops the in-memory copy and any legacy plaintext.
        invalidateM3UCache()
        [K.userInfo, K.serverInfo, K.theme, K.features,
         K.appConfig, K.lastConfigFetch, K.m3uURL, K.loginMode].forEach {
            ud.removeObject(forKey: $0.rawValue)
        }
    }
    func clearAll() {
        invalidateM3UCache()
        if let id = Bundle.main.bundleIdentifier {
            ud.removePersistentDomain(forName: id)
        }
    }
}

// MARK: ════════════════════════════════════════
// SECURITY — JAILBREAK DETECTION
// ════════════════════════════════════════════
struct SecurityCheck {
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // When our iOS app runs on a Mac (Designed-for-iPad / Catalyst), macOS
        // legitimately has Unix paths like /bin/bash and /usr/sbin/sshd, which
        // would false-positive the jailbreak checks and BLOCK login. A Mac is not
        // a jailbroken iPhone — skip the check there. This is why customers on the
        // Mac App Store couldn't log in.
        if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp {
            return false
        }
        // Note: no out-of-sandbox write probe — writing to /private trips App
        // Store static analysis. Path + URL-scheme checks are sufficient.
        return checkPaths() || checkApps()
        #endif
    }

    private static func checkPaths() -> Bool {
        let paths = [
            "/Applications/Cydia.app", "/Applications/Sileo.app",
            "/usr/sbin/sshd", "/bin/bash", "/etc/apt",
            "/private/var/lib/apt/", "/private/var/lib/cydia",
            "/Library/MobileSubstrate/MobileSubstrate.dylib"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func checkApps() -> Bool {
        ["cydia://", "sileo://", "zbra://"].compactMap { URL(string: $0) }
            .contains { UIApplication.shared.canOpenURL($0) }
    }
}

// MARK: ════════════════════════════════════════
// XTREAM SERVICE
// ════════════════════════════════════════════
actor XtreamService {
    static let shared = XtreamService()
    private init() {}

    private var cache: [String: (data: Data, date: Date)] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    // MARK: - Stream URLs (nonisolated — read-only Keychain access)
    nonisolated func liveURL(id: String) -> URL? {
        guard let c = Keychain.shared.serverCredentials() else { return nil }
        return URL(string: "\(c.host)/live/\(c.user)/\(c.pass)/\(id).m3u8")
    }
    nonisolated func vodURL(id: String, ext: String) -> URL? {
        guard let c = Keychain.shared.serverCredentials() else { return nil }
        return URL(string: "\(c.host)/movie/\(c.user)/\(c.pass)/\(id).\(ext)")
    }
    nonisolated func seriesURL(episodeID: String, ext: String) -> URL? {
        guard let c = Keychain.shared.serverCredentials() else { return nil }
        return URL(string: "\(c.host)/series/\(c.user)/\(c.pass)/\(episodeID).\(ext)")
    }

    // MARK: - Fetch Methods
    func fetchLiveCategories() async throws -> [Category] {
        try await APIClient.shared.request(path: "/xtream/live/categories")
    }
    func fetchLiveStreams(categoryID: String? = nil) async throws -> [Channel] {
        var q: [String: String] = [:]
        if let cat = categoryID { q["category_id"] = cat }
        return try await APIClient.shared.request(path: "/xtream/live/streams", query: q)
    }
    func fetchVODCategories() async throws -> [Category] {
        try await APIClient.shared.request(path: "/xtream/vod/categories")
    }
    func fetchMovies(categoryID: String? = nil) async throws -> [Movie] {
        var q: [String: String] = [:]
        if let cat = categoryID { q["category_id"] = cat }
        return try await APIClient.shared.request(path: "/xtream/vod/streams", query: q)
    }
    func fetchSeriesCategories() async throws -> [Category] {
        try await APIClient.shared.request(path: "/xtream/series/categories")
    }
    func fetchSeries(categoryID: String? = nil) async throws -> [Series] {
        var q: [String: String] = [:]
        if let cat = categoryID { q["category_id"] = cat }
        return try await APIClient.shared.request(path: "/xtream/series", query: q)
    }
    func fetchSeriesDetail(id: String) async throws -> SeriesDetailResponse {
        try await APIClient.shared.request(path: "/xtream/series/\(id)")
    }
    func fetchMovieDetail(id: String) async throws -> Movie {
        try await APIClient.shared.request(path: "/xtream/vod/\(id)")
    }
    func fetchEPG(channelID: String) async throws -> [EPGProgram] {
        try await APIClient.shared.request(path: "/xtream/epg/\(channelID)")
    }
}

// MARK: ════════════════════════════════════════
// M3U / M3U8 PARSER
// ════════════════════════════════════════════
struct M3UEntry {
    let name:  String
    let logo:  String?
    let group: String
    /// tvg-id — the guide-matching key. Optional: most messy providers omit it.
    let tvgID: String?
    let url:   String
}

struct M3UContent {
    var channels:         [Channel]  = []
    var liveCategories:   [Category] = []
    var movies:           [Movie]    = []
    var movieCategories:  [Category] = []
    var series:           [Series]   = []
    var seriesCategories: [Category] = []
    /// At least one of the three stream lists failed to load and degraded to empty.
    /// Safe to SHOW for this session, never safe to CACHE — see PlaylistService.
    var isPartial: Bool = false
}

enum M3UParser {

    // MARK: - Raw entries
    static func entries(from text: String) -> [M3UEntry] {
        var result: [M3UEntry] = []
        var pendingInfo: String? = nil

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                pendingInfo = line
            } else if !line.isEmpty, !line.hasPrefix("#"), let info = pendingInfo {
                result.append(M3UEntry(
                    name:  displayName(in: info),
                    logo:  attribute("tvg-logo", in: info),
                    group: attribute("group-title", in: info) ?? "عام",
                    // `tvg-id` is the ONLY key that links a raw-M3U channel to a
                    // programme guide. It was never parsed, so every M3U user had
                    // permanently no EPG — not a degraded guide, none at all.
                    // Some providers emit a feed suffix ("AbuDhabiTV.ae@SD"); strip it,
                    // and lower-case so it matches the guide's lower-cased ids.
                    tvgID: attribute("tvg-id", in: info)
                        .map { $0.components(separatedBy: "@")[0]
                                 .trimmingCharacters(in: .whitespaces).lowercased() }
                        .flatMap { $0.isEmpty ? nil : $0 },
                    url:   line
                ))
                pendingInfo = nil
            }
        }
        return result
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: "\(key)=\"") else { return nil }
        let after = line[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        let value = String(after[..<end]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func displayName(in line: String) -> String {
        // Name is everything after the last comma outside quotes — practically: after the final comma
        if let idx = line.lastIndex(of: ",") {
            let name = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return "بدون اسم"
    }

    // MARK: - Classification → Channels / Movies / Series
    static func build(from text: String) -> M3UContent {
        let all = entries(from: text)
        var content = M3UContent()
        var liveGroups:   [String] = []
        var movieGroups:  [String] = []
        var seriesGroups: [String] = []
        // seriesName → (group, logo, [(season, episode, entry)])
        var seriesBuckets: [String: (group: String, logo: String?, eps: [(s: Int, e: Int, entry: M3UEntry)])] = [:]

        for entry in all {
            // Series only when the name carries an SxxEyy pattern AND it isn't an
            // explicit VOD movie URL (/movie/) AND it doesn't sit in a group that
            // explicitly reads as movies/films. This stops a movie that happens to
            // have "S01E02" in its title (common in raw-M3U movie filenames with no
            // /movie/ path) from being misfiled as a series episode, while still
            // treating real episodes — including those in neutral or "VOD" groups —
            // as series.
            if let (seriesName, season, episode) = seriesInfo(from: entry.name),
               !entry.url.lowercased().contains("/movie/"),
               !groupIsExplicitMovies(entry.group) {
                var bucket = seriesBuckets[seriesName] ?? (entry.group, entry.logo, [])
                if bucket.logo == nil { bucket.logo = entry.logo }
                bucket.eps.append((season, episode, entry))
                seriesBuckets[seriesName] = bucket
                if !seriesGroups.contains(entry.group) { seriesGroups.append(entry.group) }
            } else if isMovieLike(entry) {
                content.movies.append(Movie(
                    id: stableID("movie", entry.url),
                    name: entry.name,
                    posterURL: entry.logo, backdropURL: nil,
                    year: nil, rating: nil, genre: nil, plot: nil,
                    duration: nil, director: nil, cast: nil,
                    categoryID: entry.group,
                    containerExtension: fileExtension(of: entry.url),
                    directURL: entry.url
                ))
                if !movieGroups.contains(entry.group) { movieGroups.append(entry.group) }
            } else {
                content.channels.append(Channel(
                    id: stableID("live", entry.url),
                    name: entry.name,
                    logoURL: entry.logo,
                    groupTitle: entry.group,
                    // Carry the parsed tvg-id through and persist it (`CatalogDB.Chan`
                    // already has the column). GROUNDWORK ONLY — be precise about what
                    // this does and does not do: nothing READS `epgChannelID` yet
                    // (`ContentService.epg(for:)` passes `channel.id`, and the M3U path
                    // has no Xtream endpoint at all), so this does not by itself give an
                    // M3U user a guide. It captures the ONLY key that can ever match one,
                    // at the only moment it is available — without it the future guide
                    // client would have nothing to match on.
                    epgChannelID: entry.tvgID,
                    directURL: entry.url
                ))
                if !liveGroups.contains(entry.group) { liveGroups.append(entry.group) }
            }
        }

        // Assemble series with seasons + episodes
        content.series = seriesBuckets.map { name, bucket in
            let bySeason = Dictionary(grouping: bucket.eps, by: { max(1, $0.s) })
            let seasons: [Season] = bySeason.keys.sorted().map { num in
                let eps = bySeason[num]!
                    .sorted { $0.e < $1.e }
                    .map { item in
                        Episode(
                            id: stableID("ep", item.entry.url),
                            title: item.entry.name,
                            episodeNumber: item.e,
                            seasonNumber: num,
                            containerExtension: fileExtension(of: item.entry.url),
                            posterURL: item.entry.logo,
                            plot: nil, duration: nil,
                            directURL: item.entry.url
                        )
                    }
                return Season(id: "\(stableID("season", name))_\(num)", seasonNumber: num,
                              name: "الموسم \(num)", episodes: eps)
            }
            return Series(
                id: stableID("series", name),
                name: name,
                coverURL: bucket.logo, backdropURL: nil,
                year: nil, rating: nil, genre: nil, plot: nil,
                cast: nil, director: nil,
                categoryID: bucket.group,
                seasons: seasons
            )
        }
        .sorted { $0.name < $1.name }

        content.liveCategories   = liveGroups.map   { Category(id: $0, name: $0, parentID: nil) }
        content.movieCategories  = movieGroups.map  { Category(id: $0, name: $0, parentID: nil) }
        content.seriesCategories = seriesGroups.map { Category(id: $0, name: $0, parentID: nil) }
        return content
    }

    // MARK: - Heuristics
    /// True only for groups that explicitly read as movies/films AND not as a
    /// series group. Deliberately narrow (no generic "vod" token, since series
    /// are often dumped under "VOD" groups) so it only rescues a clear movie from
    /// series misclassification without dragging real episodes into the movie tab.
    private static func groupIsExplicitMovies(_ group: String) -> Bool {
        let g = group.lowercased()
        if g.contains("series") || g.contains("مسلسل") || g.contains("tv show") { return false }
        return g.contains("movie") || g.contains("film")
            || g.contains("فيلم") || g.contains("افلام") || g.contains("أفلام")
    }

    private static func isMovieLike(_ e: M3UEntry) -> Bool {
        let url = e.url.lowercased()
        if url.contains("/movie/") { return true }
        let g = e.group.lowercased()
        if g.contains("vod") || g.contains("movie") || g.contains("film")
            || g.contains("فيلم") || g.contains("افلام") || g.contains("أفلام") { return true }
        // Live streams end with m3u8/ts or have no file extension
        let ext = fileExtension(of: url)
        return !["m3u8", "ts", ""].contains(ext)
    }

    /// Extracts "Series Name", season and episode from titles like "Show S01 E03",
    /// "Show.S01.E03", "Show S1E3", or "S01E03 ..." (pattern at the start).
    private static func seriesInfo(from name: String) -> (series: String, season: Int, episode: Int)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|[\s._-])S(\d{1,2})[\s._-]?E(\d{1,4})\b"#, options: [.caseInsensitive]
        ) else { return nil }
        let ns = name as NSString
        guard let m = regex.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)),
              let season  = Int(ns.substring(with: m.range(at: 1))),
              let episode = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        var series = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
        if series.isEmpty { series = name }
        return (series, season, episode)
    }

    private static func fileExtension(of url: String) -> String {
        let clean = url.components(separatedBy: "?").first ?? url
        guard let last = clean.components(separatedBy: "/").last,
              last.contains("."),
              let ext = last.components(separatedBy: ".").last,
              ext.count <= 5 else { return "" }
        return ext.lowercased()
    }

    /// Stable ID across launches (djb2 hash — Swift's hashValue is randomized per launch)
    private static func stableID(_ prefix: String, _ value: String) -> String {
        var h: UInt64 = 5381
        for b in value.utf8 { h = (h &* 33) &+ UInt64(b) }
        return "m3u_\(prefix)_\(h)"
    }
}

// MARK: ════════════════════════════════════════
// XTREAM DIRECT — credentials extracted from get.php links
// (panels often block full M3U export but allow the Xtream API)
// ════════════════════════════════════════════
struct XtreamDirect {
    let base: String   // scheme://host[:port]
    let user: String
    let pass: String

    static func parse(_ urlString: String) -> XtreamDirect? {
        guard let comps = URLComponents(string: urlString) else { return nil }
        let path = comps.path.lowercased()
        guard path.contains("get.php") || path.contains("player_api.php") else { return nil }
        let items = comps.queryItems ?? []
        guard let u = items.first(where: { $0.name == "username" })?.value, !u.isEmpty,
              let p = items.first(where: { $0.name == "password" })?.value, !p.isEmpty,
              let scheme = comps.scheme, let host = comps.host else { return nil }
        var base = "\(scheme)://\(host)"
        if let port = comps.port { base += ":\(port)" }
        return XtreamDirect(base: base, user: u, pass: p)
    }

    private var q: String {
        let cs = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let eu = user.addingPercentEncoding(withAllowedCharacters: cs) ?? user
        let ep = pass.addingPercentEncoding(withAllowedCharacters: cs) ?? pass
        return "username=\(eu)&password=\(ep)"
    }
    func apiURL(action: String?) -> URL? {
        var s = "\(base)/player_api.php?\(q)"
        if let action { s += "&action=\(action)" }
        return URL(string: s)
    }
    func liveURL(id: String)             -> String { "\(base)/live/\(user)/\(pass)/\(id).m3u8" }
    func movieURL(id: String, ext: String)  -> String { "\(base)/movie/\(user)/\(pass)/\(id).\(ext)" }
    func seriesURL(id: String, ext: String) -> String { "\(base)/series/\(user)/\(pass)/\(id).\(ext)" }
}

// MARK: ════════════════════════════════════════
// CATALOG DISK CACHE — instant cold-start (stale-while-revalidate)
// Persists the parsed M3U/Xtream-direct catalog to the Caches dir so a relaunch
// paints the full library immediately instead of blocking on a fresh network
// parse of (often 10k+) entries. A pull-to-refresh / playlist switch passes
// force:true to bypass it and fetch live. Keyed by the playlist URL, so each
// account keeps its own cache and they never cross-contaminate.
//
// Uses dedicated Codable DTOs (NOT the models' API-mapped CodingKeys) so the
// runtime-only fields the player needs — directURL and raw-M3U embedded seasons —
// survive the round-trip (those fields are intentionally absent from the API
// CodingKeys, so encoding the models directly would silently drop them).
// ════════════════════════════════════════════
enum CatalogDiskCache {
    /// How long a cached catalog is served before a live fetch is preferred.
    static let ttl: TimeInterval = 12 * 3600

    private struct DChannel: Codable {
        let id, name: String; let logoURL: String?; let groupTitle: String
        let epgChannelID: String?; let directURL: String?
    }
    private struct DMovie: Codable {
        let id, name: String
        let posterURL, backdropURL, year, rating, genre, plot, duration, director, cast: String?
        let categoryID, containerExtension: String; let directURL: String?
    }
    private struct DEpisode: Codable {
        let id, title: String; let episodeNumber, seasonNumber: Int
        let containerExtension: String; let posterURL, plot, duration, directURL: String?
    }
    private struct DSeason: Codable {
        let id: String; let seasonNumber: Int; let name: String; let episodes: [DEpisode]
    }
    private struct DSeries: Codable {
        let id, name: String
        let coverURL, backdropURL, year, rating, genre, plot, cast, director: String?
        let categoryID: String; let seasons: [DSeason]
    }
    private struct Envelope: Codable {
        let savedAt: Double
        let channels: [DChannel]
        let movies: [DMovie]
        let series: [DSeries]
        let liveCategories: [Category]      // Category round-trips safely (all props in CodingKeys)
        let movieCategories: [Category]
        let seriesCategories: [Category]
    }

    private static func envelope(from c: M3UContent) -> Envelope {
        Envelope(
            savedAt: Date().timeIntervalSince1970,
            channels: c.channels.map { DChannel(id: $0.id, name: $0.name, logoURL: $0.logoURL,
                                                groupTitle: $0.groupTitle, epgChannelID: $0.epgChannelID,
                                                directURL: $0.directURL) },
            movies: c.movies.map { DMovie(id: $0.id, name: $0.name, posterURL: $0.posterURL,
                                          backdropURL: $0.backdropURL, year: $0.year, rating: $0.rating,
                                          genre: $0.genre, plot: $0.plot, duration: $0.duration,
                                          director: $0.director, cast: $0.cast, categoryID: $0.categoryID,
                                          containerExtension: $0.containerExtension, directURL: $0.directURL) },
            series: c.series.map { s in
                DSeries(id: s.id, name: s.name, coverURL: s.coverURL, backdropURL: s.backdropURL,
                        year: s.year, rating: s.rating, genre: s.genre, plot: s.plot, cast: s.cast,
                        director: s.director, categoryID: s.categoryID,
                        seasons: s.seasons.map { se in
                            DSeason(id: se.id, seasonNumber: se.seasonNumber, name: se.name,
                                    episodes: se.episodes.map { e in
                                        DEpisode(id: e.id, title: e.title, episodeNumber: e.episodeNumber,
                                                 seasonNumber: e.seasonNumber, containerExtension: e.containerExtension,
                                                 posterURL: e.posterURL, plot: e.plot, duration: e.duration,
                                                 directURL: e.directURL)
                                    })
                        })
            },
            liveCategories: c.liveCategories, movieCategories: c.movieCategories, seriesCategories: c.seriesCategories
        )
    }

    private static func content(from e: Envelope) -> M3UContent {
        var c = M3UContent()
        c.channels = e.channels.map { Channel(id: $0.id, name: $0.name, logoURL: $0.logoURL,
                                              groupTitle: $0.groupTitle, epgChannelID: $0.epgChannelID,
                                              directURL: $0.directURL) }
        c.movies = e.movies.map { Movie(id: $0.id, name: $0.name, posterURL: $0.posterURL,
                                        backdropURL: $0.backdropURL, year: $0.year, rating: $0.rating,
                                        genre: $0.genre, plot: $0.plot, duration: $0.duration,
                                        director: $0.director, cast: $0.cast, categoryID: $0.categoryID,
                                        containerExtension: $0.containerExtension, directURL: $0.directURL) }
        c.series = e.series.map { s in
            Series(id: s.id, name: s.name, coverURL: s.coverURL, backdropURL: s.backdropURL,
                   year: s.year, rating: s.rating, genre: s.genre, plot: s.plot, cast: s.cast,
                   director: s.director, categoryID: s.categoryID,
                   seasons: s.seasons.map { se in
                       Season(id: se.id, seasonNumber: se.seasonNumber, name: se.name,
                              episodes: se.episodes.map { e in
                                  Episode(id: e.id, title: e.title, episodeNumber: e.episodeNumber,
                                          seasonNumber: e.seasonNumber, containerExtension: e.containerExtension,
                                          posterURL: e.posterURL, plot: e.plot, duration: e.duration,
                                          directURL: e.directURL)
                              })
                   })
        }
        c.liveCategories = e.liveCategories
        c.movieCategories = e.movieCategories
        c.seriesCategories = e.seriesCategories
        return c
    }

    /// Drop every cached catalogue, all scopes. Account deletion only.
    static func purgeAll() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? fm.removeItem(at: base.appendingPathComponent("S8KCatalog", isDirectory: true))
    }

    private static func fileURL(_ scope: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("S8KCatalog", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var h: UInt64 = 5381                       // djb2 — stable across launches
        for b in scope.utf8 { h = (h &* 33) &+ UInt64(b) }
        return dir.appendingPathComponent("cat_\(h).json")
    }

    static func save(_ c: M3UContent, scope: String) {
        guard let url = fileURL(scope),
              let data = try? JSONEncoder().encode(envelope(from: c)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns a fresh (within TTL) cached catalog, or nil if missing/stale/empty.
    /// Is there a catalogue on disk for this scope? Deliberately a stat, not a read:
    /// the fast paths use it to decide whether to issue a network request at all, and
    /// decoding tens of megabytes to answer that would cost more than the request.
    static func exists(scope: String) -> Bool {
        guard let url = fileURL(scope) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func load(scope: String) -> M3UContent? {
        read(scope: scope)?.content
    }

    /// The cached catalogue plus how old it is, with NO freshness test. `load` keeps
    /// the 12h contract for callers that want it; this one lets the caller decide.
    static func read(scope: String) -> (content: M3UContent, age: TimeInterval)? {
        guard let url = fileURL(scope),
              // Memory-mapped: a large line writes tens of megabytes here, and reading
              // it into a Data first doubled the peak for no benefit.
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        let c = content(from: env)
        if c.channels.isEmpty && c.movies.isEmpty && c.series.isEmpty { return nil }
        return (c, max(0, Date().timeIntervalSince1970 - env.savedAt))
    }
}

// MARK: ════════════════════════════════════════
// PLAYLIST SERVICE (M3U mode — raw M3U or direct Xtream API)
// ════════════════════════════════════════════
actor PlaylistService {
    static let shared = PlaylistService()
    private init() {}

    private var content: M3UContent?
    private var xtream:  XtreamDirect?
    /// The one in-flight fetch, so concurrent callers coalesce onto it instead of
    /// each starting their own. The boot screen fires load() three times at once
    /// (live/movies/series); actor reentrancy at the network `await` would other-
    /// wise let all three miss the cache and run THREE full catalog fetches (~21
    /// API calls, which cheap IPTV panels rate-limit → a valid line shows an empty
    /// home). Single-flight makes it exactly ONE fetch shared by all callers.
    private var inFlight: Task<M3UContent, Error>?

    /// Refresh from the network and replace what a stale serve just handed out.
    ///
    /// Separate from `load(force:)` on purpose — that one joins an in-flight fetch,
    /// which is right for a concurrent pull-to-refresh and wrong here. The flag is
    /// enough to keep two revalidations from overlapping: actor isolation makes the
    /// check and the set one step.
    private var revalidating = false
    func revalidate() async {
        if revalidating { return }
        revalidating = true
        defer { revalidating = false }
        _ = try? await _load(force: true)
    }

    func load(force: Bool = false) async throws -> M3UContent {
        if let content, !force { return content }
        if let inFlight { return try await inFlight.value }   // join the running fetch
        let task = Task<M3UContent, Error> { try await self._load(force: force) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func _load(force: Bool) async throws -> M3UContent {
        if let content, !force { return content }
        S8KPerf.begin("الكتالوج")
        guard let urlString = Store.shared.m3uURL,
              let url = URL(string: urlString) else {
            throw AppError.server("لا يوجد رابط قائمة تشغيل محفوظ")
        }

        // Instant cold-start: serve the last good catalog from disk immediately
        // (within TTL) instead of blocking on a full network parse. A refresh
        // (pull-to-refresh / playlist switch) passes force:true to bypass this.
        if !force, let cached = CatalogDiskCache.read(scope: urlString) {
            S8KPerf.end("الكتالوج", "من القرص")
            content = cached.content
            // Re-parse credentials (pure string work, no network) so lazy
            // series episodes / movie detail still resolve in Xtream-direct mode.
            if let xd = XtreamDirect.parse(urlString) { xtream = xd }
            // STALE-WHILE-REVALIDATE. The comment above this function claimed it for a
            // long time; the code was a hard 12h cliff. Past the TTL the whole cache was
            // thrown away and the user waited out a full network parse with a perfectly
            // good catalogue sitting on disk — so anyone who opens the app once a day
            // ALWAYS took the slow path. That is a large part of the owner's "three
            // minutes after signing in".
            //
            // Serve the stale copy now, refresh behind it. The refresh is detached so it
            // cannot delay this return, and it deliberately does NOT go through
            // `load(force:)`: that joins any fetch already in flight, and the fetch in
            // flight right now is THIS one — so it would hand back the same stale
            // catalogue and the revalidation would silently never happen.
            if cached.age >= CatalogDiskCache.ttl {
                Task.detached(priority: .utility) { await PlaylistService.shared.revalidate() }
            }
            return cached.content
        }

        // get.php / player_api.php link → talk to the Xtream API directly
        // (panels like this block M3U export but the API works fine)
        if let xd = XtreamDirect.parse(urlString) {
            let built = try await loadXtreamDirect(xd)
            S8KPerf.end("الكتالوج", "من الشبكة · \(built.channels.count) قناة · \(built.movies.count) فلم · \(built.series.count) مسلسل")
            xtream  = xd
            content = built
            // NEVER persist a PARTIAL catalogue. Since one failed list no longer
            // aborts the whole load, a VOD timeout would otherwise write movies=[]
            // straight over the last good 12-hour cache AND wipe the FTS rows
            // (CatalogDB.save deletes the scope before re-inserting). The user would
            // then see an empty Movies tab with no error to retry from, surviving a
            // relaunch. Serving the partial for THIS session is fine; recording it
            // as the truth is not.
            if !built.isPartial {
                // BOTH writes are detached. `CatalogDiskCache.save` used to run
                // SYNCHRONOUSLY here, before `return built` — it JSON-encodes the whole
                // catalogue (tens of megabytes for a large line) and writes it, and the
                // seven tab view models were all blocked behind that on the actor's
                // return path, for seconds, before a single one of them could ask for
                // its first row. The content is already in hand at this point; caching
                // it is bookkeeping and belongs behind the user, not in front of them.
                Task.detached(priority: .utility) { CatalogDiskCache.save(built, scope: urlString) }
                // Shadow-write the same catalog into the SQLite store (off-actor, off-main).
                // No reader yet (step 3) — this only POPULATES the DB so a later switch to
                // paged reads is instant. Never blocks the return; store failure is a no-op.
                Task.detached(priority: .utility) { CatalogDB.save(built, scope: urlString) }
            }
            return built
        }

        // IPTV panels often reject unknown clients — identify as VLC and
        // retry with a generic player UA if the first attempt is refused.
        let userAgents = ["VLC/3.0.20 LibVLC/3.0.20", "IPTVSmartersPlayer", "okhttp/4.12.0"]
        var lastStatus = 0
        var data = Data()

        for (i, ua) in userAgents.enumerated() {
            var req = URLRequest(url: url)
            req.timeoutInterval = 45
            req.setValue(ua,    forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            do {
                let (d, response) = try await URLSession.shared.data(for: req)
                data = d
                lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 200
                // Some panels return odd status codes but still send the playlist —
                // accept any response whose body actually looks like M3U.
                if (200...299).contains(lastStatus) || bodyLooksLikeM3U(d) { break }
            } catch {
                if i == userAgents.count - 1 { throw AppError.network(error) }
                continue
            }
            if i == userAgents.count - 1 {
                throw AppError.server("السيرفر رفض الطلب (\(lastStatus)) — تأكد من صحة الرابط وصلاحية الاشتراك")
            }
        }

        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("#EXTINF") else {
            throw AppError.server("الملف ليس قائمة M3U صالحة — جرّب إضافة type=m3u_plus للرابط")
        }
        let parsed = M3UParser.build(from: text)
        guard !(parsed.channels.isEmpty && parsed.movies.isEmpty && parsed.series.isEmpty) else {
            throw AppError.server("قائمة التشغيل فارغة")
        }
        S8KPerf.end("الكتالوج", "M3U · \(parsed.channels.count) قناة · \(parsed.movies.count) فلم · \(parsed.series.count) مسلسل")
        content = parsed
        // Detached for the same reason as the Xtream branch above: this encodes the
        // entire catalogue and writes it, and every tab view model was blocked behind
        // it on the return path before it could ask for its first row.
        Task.detached(priority: .utility) { CatalogDiskCache.save(parsed, scope: urlString) }
        // Shadow-write into the SQLite store too (off-actor, off-main; no reader yet).
        Task.detached(priority: .utility) { CatalogDB.save(parsed, scope: urlString) }
        return parsed
    }

    private func bodyLooksLikeM3U(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(4096), encoding: .utf8)
                ?? String(data: data.prefix(4096), encoding: .isoLatin1) else { return false }
        return head.contains("#EXTM3U") || head.contains("#EXTINF")
    }

    func reset() {
        content = nil; xtream = nil; epgCache = [:]; Self.panelTimeZone = .current
        // The live fast path holds a task and two stashes built from the OLD account.
        // Left alone, the next line's first channelsFast() joined that task and got the
        // previous account's channels — whose directURL embeds the previous account's
        // username and password. A stale list is bad; streaming another account's
        // credentials is not something to leave to chance.
        accountGen &+= 1
        // `inFlight` is the one that mattered most and was still being missed. A full
        // load started for the PREVIOUS account survived reset(), and the next
        // `load()` joined it (`if let inFlight`) and wrote the previous account's
        // catalogue straight into `content` — movies whose directURL carries the
        // previous account's username and password. Cancel it with the rest.
        inFlight?.cancel(); inFlight = nil
        liveFast?.cancel(); liveFast = nil
        fastChannels = nil; fastLiveCategories = []
        for t in fastCatTasks.values { t.cancel() }
        fastCatTasks = [:]; fastCats = [:]
        // Keyed by SERIES ID, and Xtream ids are small integers that collide across
        // panels — left populated, a fetch that returns early on the new account
        // would show the PREVIOUS account's metadata.
        seriesDetailsCache = [:]; seriesDetailsOrder = []
    }

    // MARK: ── EPG (Xtream-direct short program guide) ──
    private var epgCache: [String: (date: Date, programs: [EPGProgram])] = [:]

    /// Now/next short EPG for a live channel (Xtream `get_short_epg`). Cached 5
    /// min. Returns [] for raw M3U (no EPG API) or on any failure — callers hide
    /// the guide gracefully when empty.
    func shortEPG(streamID: String) async -> [EPGProgram] {
        if let c = epgCache[streamID], Date().timeIntervalSince(c.date) < 300 { return c.programs }
        if xtream == nil { _ = try? await load() }
        guard let xd = xtream,
              let data = try? await apiData(xd, action: "get_short_epg&stream_id=\(streamID)&limit=12"),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let listings = root["epg_listings"] as? [[String: Any]] else { return [] }
        let progs = listings.compactMap { parseEPG($0, channelID: streamID) }
            .sorted { $0.startTime < $1.startTime }
        epgCache[streamID] = (Date(), progs)
        return progs
    }

    private func parseEPG(_ d: [String: Any], channelID: String) -> EPGProgram? {
        guard let start = epgTime(d["start_timestamp"]) ?? epgTime(d["start"]),
              let end   = epgTime(d["stop_timestamp"]) ?? epgTime(d["end"]), end > start else { return nil }
        let title = Self.decodeB64(str(d["title"])) ?? str(d["title"]) ?? "—"
        let desc  = Self.decodeB64(str(d["description"]))
        return EPGProgram(id: str(d["id"]) ?? "\(channelID)_\(Int(start.timeIntervalSince1970))",
                          channelID: channelID, title: title,
                          description: (desc?.isEmpty == false) ? desc : nil,
                          startTime: start, endTime: end)
    }

    /// Accepts a Unix timestamp (Int or String) or a "yyyy-MM-dd HH:mm:ss" string.
    ///
    /// `start_timestamp` / `stop_timestamp` are the ONLY safe time fields: they are true
    /// epoch seconds. The `start` / `end` strings carry NO timezone and are rendered in
    /// the PANEL's local time — reading them as UTC (which this did) silently shifts the
    /// whole guide by the panel's offset, and that is the classic Xtream catch-up bug.
    /// The panel publishes its zone in `server_info.timezone`; use it when we have it,
    /// and fall back to the DEVICE's zone rather than UTC, which is right far more often.
    nonisolated(unsafe) static var panelTimeZone: TimeZone = .current
    private static let epgDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private func epgTime(_ any: Any?) -> Date? {
        if let i = intVal(any), i > 1_000_000 { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let s = str(any) {
            if let i = Int(s), i > 1_000_000 { return Date(timeIntervalSince1970: TimeInterval(i)) }
            // Panels emit "0000-00-00 00:00:00" as a null sentinel — must not poison the row.
            guard !s.hasPrefix("0000-") else { return nil }
            Self.epgDateFormatter.timeZone = Self.panelTimeZone
            return Self.epgDateFormatter.date(from: s)
        }
        return nil
    }

    /// Xtream base64-encodes ONLY `title` and `description` — and not every panel does.
    /// The naive "try to decode, keep it if it is valid UTF-8" test is not safe: a short
    /// ASCII title is frequently itself valid base64 ("News" decodes to 3 bytes), so a
    /// perfectly good title could be silently replaced by mojibake. Guard with the
    /// properties real base64 has — length ≥ 8, a multiple of 4, only alphabet
    /// characters — and reject anything that decodes to control characters.
    /// Standard alphabet only: `.ignoreUnknownCharacters` DELETES `-`/`_` rather than`r`n    /// translating them, which shifts the 6-bit groups and produces exactly the mojibake`r`n    /// this guard exists to prevent. URL-safe input is rejected, not mangled.
    private static func decodeB64(_ s: String?) -> String? {
        guard let s, s.count >= 8, s.count % 4 == 0,
              s.range(of: "^[A-Za-z0-9+/=]+$", options: .regularExpression) != nil,
              let data = Data(base64Encoded: s),
              let text = String(data: data, encoding: .utf8),
              !text.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\r" && $0 != "\t" })
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: ── Xtream API direct loading ──────────────

    private func apiData(_ xd: XtreamDirect, action: String?, timeout: TimeInterval = 22) async throws -> Data {
        guard let url = xd.apiURL(action: action) else {
            throw AppError.server(L("error.invalid_server"))
        }
        // Try a few client User-Agents before giving up (a 403 login is usually a
        // panel filtering the UA). Keep okhttp FIRST — it's the original, proven
        // default, so every panel that already worked returns byte-identical data
        // for ALL actions incl. get_series_info; VLC/others are only fallbacks for
        // panels that 403 okhttp.
        let userAgents = ["okhttp/4.12.0", "VLC/3.0.20 LibVLC/3.0.20", "IPTVSmartersPlayer"]
        var lastError: Error?
        for ua in userAgents {
            var req = URLRequest(url: url)
            req.timeoutInterval = timeout
            req.setValue(ua,    forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if (200...299).contains(status) { return data }
                // non-2xx (e.g. 403 UA block) → try the next UA
            } catch {
                // A TIMEOUT won't be fixed by a different UA (same host/network) →
                // fail fast so a hung server costs ONE timeout, not 3× (was ~66s).
                // A connection RESET/refused can be a UA-filter dropping the
                // connection — it returns instantly, so retry the next UA (cheap)
                // before giving up, preserving a valid line on such panels.
                if (error as? URLError)?.code == .timedOut { throw AppError.network(error) }
                lastError = error
            }
        }
        if let lastError { throw AppError.network(lastError) }
        throw AppError.server(L("error.server_rejected"))
    }

    /// Panel APIs return ids sometimes as Int, sometimes as String — normalize
    private func str(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let i = any as? Int    { return String(i) }
        if let d = any as? Double { return String(Int(d)) }
        return nil
    }
    private func intVal(_ any: Any?) -> Int? {
        if let i = any as? Int    { return i }
        if let s = any as? String { return Int(s) }
        if let d = any as? Double { return Int(d) }
        return nil
    }
    private func dictArray(_ data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Cheap login pre-flight: validate the Xtream account with a SINGLE call so a
    /// bad/expired line is rejected on the LOGIN screen, while the full catalog is
    /// fetched later (on the boot screen) with real progress — so the login button
    /// no longer blocks on the whole library. No-op for a raw .m3u file URL (its
    /// download IS the catalog, validated when the boot load runs).
    func validateCredentials() async throws {
        guard let urlString = Store.shared.m3uURL, let url = URL(string: urlString) else {
            throw AppError.server(L("error.invalid_server"))
        }
        if let xd = XtreamDirect.parse(urlString) {
            try await validateAuth(xd)                 // Xtream: full auth/status check
        } else {
            try await validateM3UReachable(url)        // raw .m3u: reachability check
        }
    }

    /// Lightweight reachability pre-flight for a raw .m3u URL so a dead/404 link is
    /// rejected on the LOGIN screen instead of persisting a "logged-in-but-broken"
    /// session. NEVER falsely rejects a valid line: a cheap HEAD accepts any 2xx/3xx;
    /// only if HEAD is unreachable or 404 do we CONFIRM with a small ranged GET (some
    /// servers mishandle HEAD), rejecting only if that also fails / isn't a playlist.
    private func validateM3UReachable(_ url: URL) async throws {
        func vlcReq(_ u: URL) -> URLRequest {
            var r = URLRequest(url: u); r.timeoutInterval = 12
            r.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
            return r
        }
        // 1) Cheap HEAD — accept any reachable non-404 response.
        var head = vlcReq(url); head.httpMethod = "HEAD"
        if let (_, resp) = try? await URLSession.shared.data(for: head),
           let code = (resp as? HTTPURLResponse)?.statusCode, code != 404 {
            return
        }
        // 2) HEAD failed/404/mishandled → confirm with a ranged GET of the first bytes.
        var get = vlcReq(url)
        get.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        let (data, resp) = try await URLSession.shared.data(for: get)   // throws → network error on login
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
        guard (200...399).contains(code) else { throw AppError.server(L("error.playlist_invalid")) }
        // Got bytes → make sure they look like a playlist (else it's an HTML/parked page).
        if !data.isEmpty {
            let prefix = String(data: data.prefix(1024), encoding: .utf8) ?? ""
            if !prefix.contains("#EXTM3U") && !prefix.contains("#EXTINF") {
                throw AppError.server(L("error.playlist_invalid"))
            }
        }
    }

    /// The auth/status check (shared by validateCredentials and the full load).
    private func validateAuth(_ xd: XtreamDirect) async throws {
        // Shorter timeout for the login pre-flight (it's a small fast call); combined
        // with apiData's fail-fast, a hung server costs ~12s, not ~66s.
        let authData = try await apiData(xd, action: nil, timeout: 12)
        // REQUIRE a parseable Xtream `user_info`. A 200 without it (wrong host, a
        // parked/HTML page, non-JSON) is NOT a valid line → reject here (on the login
        // screen) instead of letting the user enter to an empty home.
        guard let root = (try? JSONSerialization.jsonObject(with: authData)) as? [String: Any],
              let info = root["user_info"] as? [String: Any] else {
            throw AppError.server(L("error.invalid_server"))
        }
        let authed = intVal(info["auth"]) == 1
        let status = (info["status"] as? String ?? "").lowercased()
        guard authed, status != "expired", status != "banned", status != "disabled" else {
            throw AppError.server(String(format: L("error.subscription_invalid"), status))
        }
        // Capture the panel's timezone while we are already parsing this response. The
        // EPG's `start`/`end` strings carry no zone and are rendered in PANEL-local time,
        // so without this every guide time on a non-UTC panel is silently shifted.
        // TOTAL assignment, not if let: a second panel that omits 	imezone (or
        // reports an unknown identifier) must fall back to the device zone, never
        // silently inherit the PREVIOUS panel's offset.
        Self.panelTimeZone = (root["server_info"] as? [String: Any])
            .flatMap { $0["timezone"] as? String }
            .flatMap { TimeZone(identifier: $0) } ?? .current
    }

    private func loadXtreamDirect(_ xd: XtreamDirect) async throws -> M3UContent {
        // 1. Validate credentials first for a clear error message
        try await validateAuth(xd)

        var c = M3UContent()

        // 2. Categories (id → name lookup for channel group titles) — the three
        // requests are independent, so fetch them CONCURRENTLY. `async let` releases
        // the actor at each network await, so the round-trips overlap instead of
        // running one-after-another.
        async let liveCatsData = apiData(xd, action: "get_live_categories")
        async let vodCatsData  = apiData(xd, action: "get_vod_categories")
        async let serCatsData  = apiData(xd, action: "get_series_categories")
        // Categories are a NICETY — they only supply group titles. A panel that
        // times out on one of them must not cost the user the whole catalogue;
        // channels simply fall back to the "عام" group name below.
        let liveCats = dictArray((try? await liveCatsData) ?? Data())
        let vodCats  = dictArray((try? await vodCatsData) ?? Data())
        let serCats  = dictArray((try? await serCatsData) ?? Data())

        func toCategories(_ raw: [[String: Any]]) -> [Category] {
            raw.compactMap { d in
                guard let id = str(d["category_id"]), let name = str(d["category_name"]) else { return nil }
                return Category(id: id, name: name, parentID: nil)
            }
        }
        c.liveCategories   = toCategories(liveCats)
        c.movieCategories  = toCategories(vodCats)
        c.seriesCategories = toCategories(serCats)
        // `uniquingKeysWith` (NOT uniqueKeysWithValues, which TRAPS on duplicate
        // keys): messy IPTV panels often return the same category_id twice, which
        // would crash the whole content load.
        let liveCatName = Dictionary(c.liveCategories.map { ($0.id, $0.name) },
                                     uniquingKeysWith: { first, _ in first })

        // 3. Streams — live / VOD / series are independent lists; fetch CONCURRENTLY
        // so login waits ~one slow call instead of the sum of all three.
        async let liveStreamsData = apiData(xd, action: "get_live_streams")
        async let vodStreamsData  = apiData(xd, action: "get_vod_streams")
        async let seriesData      = apiData(xd, action: "get_series")
        // PARTIAL-FAILURE TOLERANCE. These are three independent lists, and on a
        // busy panel one of them times out fairly often — usually VOD, which is by
        // far the largest payload. With `try await` that single failure threw away
        // a perfectly good channel list and the user saw a login error instead of
        // their TV. Each list now degrades to empty on its own, and the load only
        // fails when ALL THREE came back with nothing (a genuinely dead panel;
        // auth already passed `validateAuth` above, so this is not a credentials
        // problem and must not be reported as one).
        let liveRaw = try? await liveStreamsData
        let vodRaw  = try? await vodStreamsData
        let serRaw  = try? await seriesData
        // Flagged, not thrown: the catalogue is served for this session but must not
        // be written over the last good cache. The all-empty case is already handled
        // by the existing "no content in this subscription" throw further down.
        c.isPartial = (liveRaw == nil || vodRaw == nil || serRaw == nil)
        let liveStreams = dictArray(liveRaw ?? Data())
        let vodStreams  = dictArray(vodRaw  ?? Data())
        let seriesList  = dictArray(serRaw  ?? Data())

        // Live channels
        for d in liveStreams {
            guard let id = str(d["stream_id"]), let name = str(d["name"]) else { continue }
            let catID = str(d["category_id"]) ?? ""
            c.channels.append(Channel(
                id: id, name: name,
                logoURL: str(d["stream_icon"]),
                groupTitle: liveCatName[catID] ?? "عام",
                epgChannelID: str(d["epg_channel_id"]),
                directURL: xd.liveURL(id: id)
            ))
        }

        // 4. Movies
        for d in vodStreams {
            guard let id = str(d["stream_id"]), let name = str(d["name"]) else { continue }
            let ext = str(d["container_extension"]) ?? "mp4"
            c.movies.append(Movie(
                id: id, name: name,
                posterURL: str(d["stream_icon"]),
                backdropURL: nil,
                year: str(d["year"]) ?? str(d["releaseDate"]),
                rating: str(d["rating"]),
                genre: str(d["genre"]), plot: nil, duration: nil,
                director: nil, cast: nil,
                categoryID: str(d["category_id"]) ?? "",
                containerExtension: ext,
                directURL: xd.movieURL(id: id, ext: ext)
            ))
        }

        // 5. Series (episodes are fetched lazily per-series)
        for d in seriesList {
            guard let id = str(d["series_id"]), let name = str(d["name"]) else { continue }
            c.series.append(Series(
                id: id, name: name,
                coverURL: str(d["cover"]),
                backdropURL: nil,
                year: str(d["year"]) ?? str(d["releaseDate"]),
                rating: str(d["rating"]),
                genre: str(d["genre"]),
                plot: str(d["plot"]),
                cast: str(d["cast"]), director: str(d["director"]),
                categoryID: str(d["category_id"]) ?? ""
            ))
        }

        guard !(c.channels.isEmpty && c.movies.isEmpty && c.series.isEmpty) else {
            throw AppError.server("لم يُعثر على محتوى في هذا الاشتراك")
        }
        return c
    }

    // MARK: - Live-first fast path
    //
    // WHY THIS EXISTS, and why it is shaped like this.
    //
    // The Xtream API offers NO pagination of any kind. I verified that against a panel
    // implementation of player_api.php and against an independent client library, not
    // against documentation: get_live_streams / get_vod_streams / get_series accept
    // only `category_id`, and nothing anywhere accepts limit, offset, page, or a
    // modified-since filter. So a client cannot ask for "the first hundred movies" —
    // the only lever the protocol gives is ASK FOR LESS.
    //
    // And the sizes are not comparable. An Xtream row is ~320 bytes, dominated by the
    // title and the poster URL, so a 25k-title account is ~8 MB of VOD against a few
    // hundred KB of channels. `load()` awaits all six requests before it returns
    // anything, so the Live tab was sitting empty behind a movies payload it never
    // reads. That wait is the "three minutes" the owner reported, and none of it is
    // work the live path needs.
    //
    // This path asks for the two smallest lists and nothing else. The full `load()`
    // still runs and supersedes it. The price is ONE duplicate get_live_streams on a
    // cold start — the cheapest of the six — and once `content` exists, from the disk
    // cache or from the full load, this costs nothing at all.
    /// Bumped by `reset()`. Every fast path captures it before its first await and
    /// refuses to cache a result whose generation no longer matches, so a fetch that
    /// was already in flight when the user switched account cannot land on the new one.
    private var accountGen = 0

    private var liveFast: Task<[Channel], Error>?
    private var fastChannels: [Channel]?
    private var fastLiveCategories: [Category] = []

    func channelsFast() async throws -> [Channel] {
        if let content { return content.channels }
        // The RESULT is cached, and that is not an optimisation — it is a safety
        // interlock. Search falls back to an in-memory scan until the FTS store is
        // populated, which only happens at the END of a successful full load, and it
        // asks for channels on every 350ms debounce tick. Without this, typing ten
        // characters during the slow cold load this path exists to fix would issue
        // ~20 extra player_api.php requests in a few seconds — straight into a cheap
        // panel's rate limiter, and an IP ban reads to the user as a dead subscription.
        if let fastChannels { return fastChannels }
        if let liveFast { return try await liveFast.value }   // join, never a second fetch
        guard let urlString = Store.shared.m3uURL,
              let xd = XtreamDirect.parse(urlString) else {
            // Raw M3U is one document — there is no cheaper subset to ask for. Fill
            // BOTH stashes from the real load: without the categories line here,
            // liveCategoriesFast returned [] for every raw-M3U user, on every first
            // load, and LiveTVVM latches `loaded = true` — so the category browser was
            // gone for the whole session. Deterministic, not a race.
            let full = try await load()
            fastLiveCategories = full.liveCategories
            fastChannels = full.channels
            return full.channels
        }
        // If a catalogue is already on disk, the full load serves it with NO network
        // at all. Firing our own request would turn a network-free warm launch into an
        // extra round trip — and offline it would be the only thing that could fail,
        // over a catalogue sitting right there and perfectly usable.
        if CatalogDiskCache.exists(scope: urlString) { return try await load().channels }

        let gen = accountGen
        let task = Task<[Channel], Error> { [xd] in try await self.fetchChannelsOnly(xd) }
        liveFast = task
        defer { if gen == accountGen { liveFast = nil } }   // a reset already cleared it
        let result = try await task.value
        // A reset while this was in flight means the result belongs to an account the
        // user has left. Serve it to this caller — it is what they asked for — but do
        // not cache it for the line that replaced it.
        guard gen == accountGen else { return result }
        fastChannels = result
        return result
    }

    /// Live categories without paying for the VOD payload. Piggybacks on the fetch
    /// above so calling either one first is fine.
    func liveCategoriesFast() async throws -> [Category] {
        if let content { return content.liveCategories }
        _ = try await channelsFast()
        // `content` first: the call above may have gone through the full load.
        return content?.liveCategories ?? fastLiveCategories
    }

    private func fetchChannelsOnly(_ xd: XtreamDirect) async throws -> [Channel] {
        async let catsData = apiData(xd, action: "get_live_categories")
        async let listData = apiData(xd, action: "get_live_streams")
        // Categories are a nicety here exactly as they are in the full load: they only
        // supply group titles, so one that times out must not cost the channel list.
        let cats = dictArray((try? await catsData) ?? Data())
        let list = dictArray(try await listData)

        var catName: [String: String] = [:]
        var cs: [Category] = []
        for d in cats {
            guard let id = str(d["category_id"]), let n = str(d["category_name"]) else { continue }
            // FIRST wins, matching the full load's `uniquingKeysWith: { first, _ in first }`.
            // Messy panels repeat a category_id, and last-wins here would give a channel a
            // different folder than the full load gives it — so channels would visibly jump
            // folders when the full load superseded this one.
            guard catName[id] == nil else { continue }
            catName[id] = n
            cs.append(Category(id: id, name: n, parentID: nil))
        }
        fastLiveCategories = cs

        let built: [Channel] = list.compactMap { d in
            guard let id = str(d["stream_id"]), let name = str(d["name"]) else { return nil }
            return Channel(id: id, name: name,
                           logoURL: str(d["stream_icon"]),
                           groupTitle: catName[str(d["category_id"]) ?? ""] ?? "عام",
                           epgChannelID: str(d["epg_channel_id"]),
                           directURL: xd.liveURL(id: id))
        }
        // An expired or banned line answers get_live_streams with a user_info OBJECT,
        // not an array, so this would otherwise hand back an empty list and NO error —
        // the user sees "no channels" instead of "subscription expired", with nothing
        // to retry. The full load runs validateAuth and raises the real message, so
        // anything that yields nothing here defers to it rather than guessing.
        guard !built.isEmpty else { return try await load().channels }
        return built
    }

    // MARK: - Categories fast path
    //
    // A category list is dozens of rows; the stream list beside it is thousands. The
    // Movies and Series tabs awaited the pair with `try await (cats, movs)`, so a
    // folder list that is ready in ~200ms was gated on an ~8MB payload it never reads.
    //
    // Unlike `channelsFast`, an EMPTY result here is NOT treated as a failure. A line
    // legitimately can have no VOD categories, and the caller is awaiting the streams
    // alongside this — that await goes through the full load, which runs validateAuth
    // and raises the real error for an expired line. So there is nothing to rescue here
    // and no reason to spend a second round trip guessing.
    enum CatalogSection: String {
        case vod    = "get_vod_categories"
        case series = "get_series_categories"
    }
    private var fastCats: [String: [Category]] = [:]
    private var fastCatTasks: [String: Task<[Category], Error>] = [:]

    func categoriesFast(_ section: CatalogSection) async throws -> [Category] {
        if let content {
            return section == .vod ? content.movieCategories : content.seriesCategories
        }
        let key = section.rawValue
        if let cached = fastCats[key] { return cached }
        if let running = fastCatTasks[key] { return try await running.value }
        guard let urlString = Store.shared.m3uURL,
              let xd = XtreamDirect.parse(urlString) else {
            // Raw M3U is one document — categories come out of the same parse.
            let full = try await load()
            return section == .vod ? full.movieCategories : full.seriesCategories
        }
        // Same rule as channelsFast: never race the network against a disk copy that
        // the full load will serve for free, and never be the reason an offline launch
        // fails.
        if CatalogDiskCache.exists(scope: urlString) {
            let full = try await load()
            return section == .vod ? full.movieCategories : full.seriesCategories
        }

        let gen = accountGen
        let task = Task<[Category], Error> { [xd] in
            await self.fetchCategoriesOnly(xd, action: key)
        }
        fastCatTasks[key] = task
        defer { if gen == accountGen { fastCatTasks[key] = nil } }   // a reset already cleared it
        let result = try await task.value

        // EMPTY IS NOT AN ANSWER TO CACHE. It means the request failed, or the panel
        // returned a non-array body under load — and caching it latched the tab: the
        // view model sets `loaded = true` and early-returns forever after, so the
        // folder browser stayed empty for the whole session with no error to retry
        // from, while the full load's own copy of these categories arrived correctly a
        // second later. Defer to that copy instead. It costs nothing extra: the caller
        // is already awaiting the streams from the same load.
        guard !result.isEmpty else {
            let full = try await load()
            return section == .vod ? full.movieCategories : full.seriesCategories
        }
        guard gen == accountGen else { return result }
        fastCats[key] = result
        return result
    }

    private func fetchCategoriesOnly(_ xd: XtreamDirect, action: String) async -> [Category] {
        // `try?`, matching the full load: categories are a NICETY that only supply
        // folder names. The full load has always treated a timeout here as survivable
        // (a busy panel drops one of these fairly often), and this request now fires
        // alongside eight others to the same panel, so it is MORE likely to drop, not
        // less. A bare `try` here turned that into a full-page error over a library
        // that had loaded perfectly.
        let raw = dictArray((try? await apiData(xd, action: action)) ?? Data())
        // FIRST wins on a repeated category_id, matching the full load's
        // `uniquingKeysWith: { first, _ in first }` — otherwise a folder could be named
        // one thing now and another thing after the full load supersedes this.
        var seen = Set<String>()
        var out: [Category] = []
        for d in raw {
            guard let id = str(d["category_id"]), let name = str(d["category_name"]),
                  seen.insert(id).inserted else { continue }
            out.append(Category(id: id, name: name, parentID: nil))
        }
        return out
    }

    /// Episodes for one series (Xtream-direct mode) — get_series_info
    func seasons(seriesID: String) async throws -> [Season] {
        if xtream == nil { _ = try await load() } // ensure credentials are parsed
        guard let xd = xtream else { return [] }
        let data = try await apiData(xd, action: "get_series_info&series_id=\(seriesID)")
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        // Same payload, no extra request — see cacheSeriesDetails.
        if let info = root["info"] as? [String: Any] {
            cacheSeriesDetails(titleDetails(from: info), for: seriesID)
        }

        // "episodes" is usually {"1":[...],"2":[...]} but some panels send [[...],[...]]
        var seasonsRaw: [(num: Int, eps: [[String: Any]])] = []
        if let dict = root["episodes"] as? [String: [[String: Any]]] {
            seasonsRaw = dict.compactMap { k, v in Int(k).map { ($0, v) } }
        } else if let arr = root["episodes"] as? [[[String: Any]]] {
            seasonsRaw = arr.enumerated().map { ($0.offset + 1, $0.element) }
        }

        return seasonsRaw.sorted { $0.num < $1.num }.map { num, eps in
            let episodes: [Episode] = eps.compactMap { e in
                guard let id = str(e["id"]) else { return nil }
                let info = e["info"] as? [String: Any]
                let ext  = str(e["container_extension"]) ?? "mp4"
                return Episode(
                    id: id,
                    title: str(e["title"]) ?? "حلقة",
                    episodeNumber: intVal(e["episode_num"]) ?? 0,
                    seasonNumber: num,
                    containerExtension: ext,
                    posterURL: str(info?["movie_image"]),
                    plot: str(info?["plot"]),
                    duration: str(info?["duration"]),
                    directURL: xd.seriesURL(id: id, ext: ext)
                )
            }
            .sorted { $0.episodeNumber < $1.episodeNumber }
            return Season(id: "\(seriesID)_\(num)", seasonNumber: num,
                          name: "الموسم \(num)", episodes: episodes)
        }
    }

    /// Full movie metadata (cast, director, plot, rating, year) via get_vod_info.
    /// Returns the original movie enriched with whatever the panel provides.
    func movieInfo(_ movie: Movie) async throws -> Movie {
        if xtream == nil { _ = try await load() }
        guard let xd = xtream else { return movie }
        let data = try await apiData(xd, action: "get_vod_info&vod_id=\(movie.id)")
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let info = root["info"] as? [String: Any] else { return movie }
        let movieData = root["movie_data"] as? [String: Any]
        return Movie(
            id: movie.id, name: movie.name,
            posterURL: str(info["movie_image"]) ?? movie.posterURL,
            backdropURL: (info["backdrop_path"] as? [String])?.first ?? movie.backdropURL,
            year: str(info["releasedate"]) ?? str(info["year"]) ?? movie.year,
            rating: str(info["rating"]) ?? movie.rating,
            genre: str(info["genre"]) ?? movie.genre,
            plot: str(info["plot"]) ?? str(info["description"]) ?? movie.plot,
            duration: str(info["duration"]) ?? movie.duration,
            director: str(info["director"]) ?? movie.director,
            cast: str(info["cast"]) ?? str(info["actors"]) ?? movie.cast,
            categoryID: movie.categoryID,
            containerExtension: str(movieData?["container_extension"]) ?? movie.containerExtension,
            directURL: movie.directURL,
            details: titleDetails(from: info)
        )
    }

    /// Pull the extra facts out of an `info` block. Called on payloads the app is
    /// ALREADY fetching (`get_vod_info` for the detail page, `get_series_info` for
    /// the episode list), so it never costs a request. Panels disagree wildly about
    /// which keys they publish and about their spelling, hence the alternatives.
    fileprivate func titleDetails(from info: [String: Any]) -> S8KTitleDetails {
        var d = S8KTitleDetails()
        d.originalName = str(info["o_name"]) ?? str(info["original_name"])
        d.country      = str(info["country"])
        // Three spellings in the wild — Movie.CodingKeys already maps the camelCase one.
        d.releaseDate  = str(info["releasedate"]) ?? str(info["release_date"]) ?? str(info["releaseDate"])
        d.ageRating    = str(info["age"]) ?? str(info["mpaa_rating"])
        d.tmdbID       = str(info["tmdb_id"]) ?? str(info["tmdb"])
        d.trailer      = str(info["youtube_trailer"]) ?? str(info["trailer"])
        // Series report an array of run times ["45"]; movies a duration string.
        // Series report a bare number of MINUTES (often inside an array); movies a
        // formatted duration like "01:52:30". A bare "45" under the label "المدة" is
        // ambiguous, so the number gets its unit and the two formats stop clashing.
        let runtimeRaw = str((info["episode_run_time"] as? [Any])?.first)
                      ?? str(info["episode_run_time"])
        if let r = runtimeRaw {
            d.runtime = Int(r).map { "\($0) \(L("details.minutes"))" } ?? r
        } else {
            d.runtime = str(info["duration"])
        }
        // The technical block exists only for VOD, and only on panels that probe.
        if let v = info["video"] as? [String: Any] {
            d.videoCodec = str(v["codec_name"])?.uppercased()
            if let w = intVal(v["width"]), let h = intVal(v["height"]), w > 0, h > 0 {
                d.resolution = Self.resolutionLabel(width: w, height: h)
            }
        }
        if let a = info["audio"] as? [String: Any] {
            d.audioCodec = str(a["codec_name"])?.uppercased()
            if let ch = intVal(a["channels"]), ch > 0 { d.audioChannels = "\(ch)" }
        }
        // Panels report bitrate in kb/s. Below ~1 Mb/s the rounded Mb/s figure would
        // read "0", so keep those in kb/s rather than print a wrong zero.
        if let br = intVal(info["bitrate"]), br > 0 {
            // Integer division read 1500 kb/s as "1 Mb/s" — and 1500–2500 is exactly
            // where 1080p sits, so most titles were reported a full digit low.
            d.bitrate = br >= 1000 ? String(format: "%.1f Mb/s", Double(br) / 1000)
                                   : "\(br) kb/s"
        }
        return d
    }

    /// A marketing label the user recognises, derived from the real pixel size —
    /// never trusted from a "quality" string, which panels routinely lie about.
    /// Keyed on the LONG edge so vertical or oddly-cropped masters still classify.
    private static func resolutionLabel(width: Int, height: Int) -> String {
        let long = max(width, height)
        switch long {
        case 3400...: return "4K"
        case 2300...: return "2K"
        case 1800...: return "1080p"
        case 1200...: return "720p"
        case 800...:  return "576p"
        default:      return "\(width)×\(height)"
        }
    }

    /// Details harvested from the LAST `get_series_info` for a series. `seasons`
    /// already downloads the whole payload; caching the extra facts here is what
    /// keeps the details sheet at zero additional requests. Bounded because a
    /// browsing session can open a lot of series.
    private var seriesDetailsCache: [String: S8KTitleDetails] = [:]
    private var seriesDetailsOrder: [String] = []
    fileprivate func cacheSeriesDetails(_ d: S8KTitleDetails, for id: String) {
        if seriesDetailsCache[id] == nil {
            seriesDetailsOrder.append(id)
            if seriesDetailsOrder.count > 60 {
                seriesDetailsCache.removeValue(forKey: seriesDetailsOrder.removeFirst())
            }
        }
        seriesDetailsCache[id] = d
    }
    func seriesDetails(for id: String) -> S8KTitleDetails? { seriesDetailsCache[id] }
}

// MARK: ════════════════════════════════════════
// CONTENT SERVICE — Unified facade (Xtream OR M3U)
// ════════════════════════════════════════════
enum ContentService {
    static var isDemo: Bool { Store.shared.demoMode }

    // INDEPENDENCE (M0b-1, 2026-07-22): DIRECT-ONLY. Every content path now goes to
    // the user's OWN provider via PlaylistService (raw M3U or Xtream-direct), or to
    // DemoContent. The old `XtreamService` proxy fallback (→ strong8k.app) has been
    // removed structurally, so no content request can ever reach the backend —
    // regardless of `mode`. Blank Prime is a pure, independent player.
    // The two live accessors take the fast path: channels do not wait on the movies
    // and series payloads, which are many times their size. See PlaylistService
    // .channelsFast for why the protocol leaves no other lever.
    static func liveCategories() async throws -> [Category] {
        if isDemo { return DemoContent.liveCategories }
        return try await PlaylistService.shared.liveCategoriesFast()
    }
    static func liveStreams() async throws -> [Channel] {
        if isDemo { return DemoContent.channels }
        return try await PlaylistService.shared.channelsFast()
    }
    static func vodCategories() async throws -> [Category] {
        if isDemo { return DemoContent.movieCategories }
        return try await PlaylistService.shared.categoriesFast(.vod)
    }
    static func movies() async throws -> [Movie] {
        if isDemo { return DemoContent.movies }
        return try await PlaylistService.shared.load().movies
    }
    static func seriesCategories() async throws -> [Category] {
        if isDemo { return DemoContent.seriesCategories }
        return try await PlaylistService.shared.categoriesFast(.series)
    }
    static func series() async throws -> [Series] {
        if isDemo { return DemoContent.series }
        return try await PlaylistService.shared.load().series
    }
    /// Full movie metadata for the detail screen (cast/crew/year/plot).
    static func movieDetail(_ movie: Movie) async throws -> Movie {
        if isDemo { return movie }
        return try await PlaylistService.shared.movieInfo(movie)
    }

    static func seasons(of series: Series) async throws -> [Season] {
        if isDemo { return series.seasons }
        // Raw M3U playlists embed seasons; Xtream-direct fetches them lazily.
        if !series.seasons.isEmpty { return series.seasons }
        return try await PlaylistService.shared.seasons(seriesID: series.id)
    }

    /// Details for a series. Read-only: `seasons(of:)` harvests them from the very
    /// same `get_series_info` payload, so this NEVER issues a request. nil until the
    /// episode list has loaded, and nil forever for demo and raw-M3U sources — the
    /// details button simply doesn't appear then.
    /// `async` only to hop onto the PlaylistService actor — it performs no I/O.
    static func seriesDetails(of series: Series) async -> S8KTitleDetails? {
        if isDemo { return nil }
        return await PlaylistService.shared.seriesDetails(for: series.id)
    }

    /// Now/next program guide for a live channel. Empty when unavailable (raw
    /// M3U, demo, or no EPG on the provider) — the UI hides the guide then.
    static func epg(for channel: Channel) async -> [EPGProgram] {
        if isDemo { return [] }
        return await PlaylistService.shared.shortEPG(streamID: channel.id)
    }
}

// MARK: ════════════════════════════════════════
// DEMO CONTENT — Apple Review (Guideline 2.1)
// Public test streams that actually play, so reviewers see every feature
// without a real subscription. No third-party / copyrighted content.
// ════════════════════════════════════════════
enum DemoContent {
    // Royalty-free public test assets (Blender Foundation / Internet Archive /
    // Apple / Mux). All verified live over HTTPS and play in MobileVLCKit.
    // NOTE: the old Google `gtv-videos-bucket` links were retired (HTTP 403),
    // which broke demo playback — replaced with these stable mirrors.
    // --- Videos. Every URL below was probed live (HTTP 206 with a byte range, i.e.
    // seekable, which a player needs) before it was committed. Deliberately a
    // DIFFERENT set of Blender open movies than the obvious four everyone ships:
    // same licence (CC-BY, Blender Foundation), same legal footing, but a catalogue
    // a reviewer has not already seen in another player. ---
    private static let hls   = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    private static let hls2  = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    private static let hls3  = "https://test-streams.mux.dev/pts_shift/master.m3u8"
    private static let cosmos = "https://archive.org/download/CosmosLaundromatFirstCycle/Cosmos%20Laundromat%20-%20First%20Cycle%20(1080p).mp4"
    private static let camin  = "https://archive.org/download/CaminandesLlamigos/Caminandes_%20Llamigos-1080p.mp4"
    private static let glass  = "https://archive.org/download/GlassHalf1080p/Glass%20Half-1080p.mp4"
    private static let sprite = "https://archive.org/download/sprite-fright-2021/Sprite%20Fright%20%282021%29.mp4"

    // Artwork from Wikimedia Commons, NOT the Internet Archive item thumbnails: those
    // are auto-generated 180px video frames (a close-up of a shoe, in one case), and
    // review found them upscaled ~6-9x into a 2:3 card and then again across a full
    // detail canvas — blurry smears on the one screen App Review ever sees.
    // Cosmos and Sprite Fright are true 2:3 posters; the other two are official stills
    // (no poster exists on Commons) so they crop in a 2:3 card, but they are SHARP,
    // which is the whole point. `?width=800` keeps the download honest.
    private static let pCosmos = "https://commons.wikimedia.org/wiki/Special:FilePath/CosmosLaundromatPoster.jpg?width=800"
    private static let pSprite = "https://commons.wikimedia.org/wiki/Special:FilePath/Sprite_Fright-movie_poster.jpg?width=800"
    private static let pCamin  = "https://commons.wikimedia.org/wiki/Special:FilePath/Blender_Foundation_-_Caminandes_-_Episode_3_-_Llamigos_-_Cover_thumbnail.png?width=800"
    private static let pGlass  = "https://commons.wikimedia.org/wiki/Special:FilePath/Glass_Half_-_screenshot-Min_and_Max_artwork_style.png?width=800"

    static let liveCategories = [Category(id: "demo_live", name: "بثّ العرض", parentID: nil)]
    static let movieCategories = [Category(id: "demo_vod", name: "أفلام مفتوحة", parentID: nil)]
    static let seriesCategories = [Category(id: "demo_series", name: "سلسلة العرض", parentID: nil)]

    // Each channel demonstrates a DIFFERENT thing the engine has to handle, and says
    // so — a demo lineup should show what the player does, not pad a list.
    static let channels: [Channel] = [
        Channel(id: "d1", name: "بلانك ١ · تدفّق متعدّد الجودات", logoURL: pGlass,
                groupTitle: "بثّ العرض", epgChannelID: nil, directURL: hls),
        Channel(id: "d2", name: "بلانك ٢ · تبديل تلقائي للجودة", logoURL: pCamin,
                groupTitle: "بثّ العرض", epgChannelID: nil, directURL: hls2),
        Channel(id: "d3", name: "بلانك ٣ · إزاحة زمنية", logoURL: pSprite,
                groupTitle: "بثّ العرض", epgChannelID: nil, directURL: hls3),
        Channel(id: "d4", name: "بلانك ٤ · ملفّ مباشر بلا تقطيع", logoURL: pCosmos,
                groupTitle: "بثّ العرض", epgChannelID: nil, directURL: cosmos),
    ]

    static let movies: [Movie] = [
        demoMovie("d_m1", "Sprite Fright", sprite, "2021", "8.4", pSprite,
                  "مجموعة مراهقين في رحلة تخييم يقابلون كائنات صغيرة لا تُحتمل. "
                  + "أحدث هذه الأفلام وأثقلها إضاءةً — عيّنة جيّدة لقياس التدرّج اللوني."),
        demoMovie("d_m2", "Cosmos Laundromat", cosmos, "2015", "8.0", pCosmos,
                  "خروفٌ يائس على جزيرة مقفرة يلتقي بائعاً يعرض عليه حيواتٍ بديلة. "
                  + "مشاهد واسعة بحركة كاميرا بطيئة — تكشف أي تقطيع في العرض."),
        demoMovie("d_m3", "Caminandes: Llamigos", camin, "2016", "7.9", pCamin,
                  "لاما في باتاغونيا يتنازع مع طائر بطريق على آخر حبّة توت. "
                  + "حركة سريعة وألوان صريحة — اختبار لانسيابية الإطارات."),
        demoMovie("d_m4", "Glass Half", glass, "2015", "7.5", pGlass,
                  "زوّار متحف يختلفون على معنى لوحة، فيحتدم الخلاف. "
                  + "قصيرٌ وحواريّ — يُظهر تزامن الصوت مع الصورة بوضوح."),
    ]

    static let series: [Series] = [
        Series(id: "d_s1", name: "جولة في المشغّل", coverURL: pCosmos,
               backdropURL: nil, year: "2026", rating: "9.0", genre: "عرض",
               plot: "ثلاث حلقات قصيرة، كلٌّ منها تعرض جانباً مختلفاً من المشغّل: "
                   + "الاستئناف من حيث توقّفت، تبديل مسار الصوت، والتشغيل دون اتّصال.",
               cast: nil, director: nil, categoryID: "demo_series",
               seasons: [
                Season(id: "d_s1_1", seasonNumber: 1, name: "الموسم ١", episodes: [
                    demoEpisode("d_e1", "١ · الاستئناف من حيث توقّفت", 1, camin),
                    demoEpisode("d_e2", "٢ · مسارات الصوت والترجمة", 2, glass),
                    demoEpisode("d_e3", "٣ · التنزيل والمشاهدة دون اتّصال", 3, sprite),
                ])
               ]),
    ]

    private static func demoMovie(_ id: String, _ name: String, _ url: String,
                                  _ year: String, _ rating: String,
                                  _ poster: String, _ plot: String,
                                  _ ext: String = "mp4") -> Movie {
        Movie(id: id, name: name, posterURL: poster, backdropURL: nil,
              year: year, rating: rating, genre: "مفتوح المصدر", plot: plot,
              duration: "١٠ دقائق", director: "Blender Foundation", cast: nil,
              categoryID: "demo_vod", containerExtension: ext, directURL: url)
    }
    private static func demoEpisode(_ id: String, _ title: String, _ num: Int, _ url: String) -> Episode {
        Episode(id: id, title: title, episodeNumber: num, seasonNumber: 1,
                containerExtension: "mp4", posterURL: nil, plot: nil,
                duration: "١٠ دقائق", directURL: url)
    }
}
