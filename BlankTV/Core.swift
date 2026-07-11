// ============================================================
// BLANK TV — Core.swift
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
        "tab.live":    [.ar: "مباشر",   .en: "Live",    .fr: "Direct",  .tr: "Canlı",    .es: "En vivo"],
        "tab.movies":  [.ar: "أفلام",   .en: "Movies",  .fr: "Films",   .tr: "Filmler",  .es: "Películas"],
        "tab.series":  [.ar: "مسلسلات", .en: "Series",  .fr: "Séries",  .tr: "Diziler",  .es: "Series"],
        "tab.settings":[.ar: "إعدادات", .en: "Settings",.fr: "Réglages",.tr: "Ayarlar",  .es: "Ajustes"],
        "ctab.all":      [.ar: "الكل",     .en: "All",       .fr: "Tout",     .tr: "Tümü",      .es: "Todo"],
        "ctab.favorites":[.ar: "المفضلة",  .en: "Favorites", .fr: "Favoris",  .tr: "Favoriler", .es: "Favoritos"],
        "ctab.newest":   [.ar: "الأجدد",   .en: "Newest",    .fr: "Récents",  .tr: "En Yeni",   .es: "Nuevos"],
        "ctab.history":  [.ar: "السجل",    .en: "History",   .fr: "Historique",.tr: "Geçmiş",   .es: "Historial"],
        "common.play":    [.ar: "تشغيل",   .en: "Play",     .fr: "Lire",     .tr: "Oynat",   .es: "Reproducir"],
        "common.details": [.ar: "التفاصيل",.en: "Details",  .fr: "Détails",  .tr: "Detaylar",.es: "Detalles"],
        "common.all":     [.ar: "الكل",    .en: "See all",  .fr: "Tout voir",.tr: "Tümü",    .es: "Ver todo"],
        "common.retry":   [.ar: "إعادة المحاولة", .en: "Retry", .fr: "Réessayer", .tr: "Tekrar dene", .es: "Reintentar"],
        "common.close":   [.ar: "إغلاق",   .en: "Close",    .fr: "Fermer",   .tr: "Kapat",   .es: "Cerrar"],
        "common.cancel":  [.ar: "إلغاء",   .en: "Cancel",   .fr: "Annuler",  .tr: "İptal",   .es: "Cancelar"],
        "common.save":    [.ar: "حفظ",     .en: "Save",     .fr: "Enregistrer", .tr: "Kaydet", .es: "Guardar"],
        "reorder.button": [.ar: "ترتيب",   .en: "Sort",     .fr: "Trier",    .tr: "Sırala",  .es: "Ordenar"],
        "reorder.title":  [.ar: "ترتيب الأقسام", .en: "Reorder Categories", .fr: "Réorganiser les catégories", .tr: "Kategorileri Sırala", .es: "Reordenar categorías"],
        "reorder.hint":   [.ar: "اضغط الأقسام بالترتيب الذي تريده — الأول يأخذ الرقم 1، ثم 2، وهكذا. اضغط مرة أخرى لإلغاء الرقم. الأقسام غير المرقّمة تبقى في الأسفل.", .en: "Tap categories in the order you want — the first becomes 1, then 2, and so on. Tap again to remove a number. Un-numbered categories stay at the bottom.", .fr: "Touchez les catégories dans l'ordre souhaité — la première devient 1, puis 2, etc. Touchez à nouveau pour retirer un numéro. Les catégories sans numéro restent en bas.", .tr: "Kategorilere istediğiniz sırayla dokunun — ilki 1, sonra 2 olur. Numarayı kaldırmak için tekrar dokunun. Numarasız kategoriler altta kalır.", .es: "Toca las categorías en el orden que quieras — la primera será 1, luego 2, etc. Toca de nuevo para quitar un número. Las categorías sin número quedan al final."],
        "reorder.reset":  [.ar: "إعادة تعيين", .en: "Reset", .fr: "Réinitialiser", .tr: "Sıfırla", .es: "Restablecer"],
        "reorder.search": [.ar: "ابحث عن قسم…", .en: "Search a category…", .fr: "Rechercher une catégorie…", .tr: "Kategori ara…", .es: "Buscar categoría…"],
        "reorder.clear_all":[.ar: "مسح الترقيم", .en: "Clear numbering", .fr: "Effacer la numérotation", .tr: "Numaralandırmayı temizle", .es: "Borrar numeración"],
        "reorder.numbered":[.ar: "مرقّم", .en: "numbered", .fr: "numérotés", .tr: "numaralı", .es: "numerados"],
        "error.invalid_credentials":[.ar: "اسم المستخدم أو كلمة المرور غير صحيحة", .en: "Incorrect username or password", .fr: "Nom d'utilisateur ou mot de passe incorrect", .tr: "Kullanıcı adı veya şifre yanlış", .es: "Usuario o contraseña incorrectos"],
        "error.account_suspended":[.ar: "تم تعليق حسابك — تواصل مع الدعم الفني", .en: "Your account is suspended — contact support", .fr: "Votre compte est suspendu — contactez le support", .tr: "Hesabınız askıya alındı — desteğe başvurun", .es: "Tu cuenta está suspendida — contacta con soporte"],
        "error.account_expired":[.ar: "انتهت صلاحية اشتراكك — يرجى التجديد", .en: "Your subscription has expired — please renew", .fr: "Votre abonnement a expiré — veuillez renouveler", .tr: "Aboneliğinizin süresi doldu — lütfen yenileyin", .es: "Tu suscripción ha caducado — renueva por favor"],
        "error.max_connections":[.ar: "تم الوصول للحد الأقصى (%ld أجهزة)", .en: "Device limit reached (%ld devices)", .fr: "Limite d'appareils atteinte (%ld appareils)", .tr: "Cihaz sınırına ulaşıldı (%ld cihaz)", .es: "Límite de dispositivos alcanzado (%ld dispositivos)"],
        "error.maintenance":[.ar: "التطبيق في وضع الصيانة", .en: "The app is under maintenance", .fr: "L'application est en maintenance", .tr: "Uygulama bakımda", .es: "La aplicación está en mantenimiento"],
        "error.version_outdated":[.ar: "يرجى تحديث التطبيق إلى الإصدار %@ أو أحدث", .en: "Please update the app to version %@ or newer", .fr: "Veuillez mettre à jour l'application vers la version %@ ou plus récente", .tr: "Lütfen uygulamayı %@ veya daha yeni sürüme güncelleyin", .es: "Actualiza la aplicación a la versión %@ o posterior"],
        "error.network":[.ar: "خطأ في الاتصال: %@", .en: "Connection error: %@", .fr: "Erreur de connexion : %@", .tr: "Bağlantı hatası: %@", .es: "Error de conexión: %@"],
        "error.unknown":[.ar: "حدث خطأ غير متوقع", .en: "An unexpected error occurred", .fr: "Une erreur inattendue s'est produite", .tr: "Beklenmeyen bir hata oluştu", .es: "Se produjo un error inesperado"],
        "error.invalid_server":[.ar: "تعذّر التحقق من السيرفر — تأكد من الرابط وبيانات الدخول", .en: "Couldn't verify the server — check the URL and login details", .fr: "Impossible de vérifier le serveur — vérifiez l'URL et les identifiants", .tr: "Sunucu doğrulanamadı — URL ve giriş bilgilerini kontrol edin", .es: "No se pudo verificar el servidor — comprueba la URL y los datos"],
        "error.playlist_invalid":[.ar: "الرابط ليس قائمة تشغيل صالحة — تأكد من الرابط", .en: "The URL isn't a valid playlist — check the link", .fr: "L'URL n'est pas une playlist valide — vérifiez le lien", .tr: "URL geçerli bir oynatma listesi değil — bağlantıyı kontrol edin", .es: "La URL no es una lista válida — comprueba el enlace"],
        "error.server_rejected":[.ar: "رفض السيرفر الطلب — تأكد من الاشتراك والرابط، أو جرّب شبكة أخرى", .en: "The server rejected the request — check your subscription and URL, or try another network", .fr: "Le serveur a rejeté la demande — vérifiez l'abonnement et l'URL, ou essayez un autre réseau", .tr: "Sunucu isteği reddetti — aboneliği ve URL'yi kontrol edin veya başka bir ağ deneyin", .es: "El servidor rechazó la solicitud — comprueba la suscripción y la URL, o prueba otra red"],
        "error.subscription_invalid":[.ar: "بيانات الاشتراك غير صحيحة أو منتهية (%@)", .en: "Subscription invalid or expired (%@)", .fr: "Abonnement invalide ou expiré (%@)", .tr: "Abonelik geçersiz veya süresi dolmuş (%@)", .es: "Suscripción no válida o caducada (%@)"],
        "player.err.no_url":[.ar: "تعذّر تحميل الرابط", .en: "Couldn't load the stream link", .fr: "Impossible de charger le lien", .tr: "Bağlantı yüklenemedi", .es: "No se pudo cargar el enlace"],
        "player.err.start_failed":[.ar: "تعذّر بدء التشغيل — تحقق من الاتصال أو أعد المحاولة", .en: "Couldn't start playback — check your connection or retry", .fr: "Lecture impossible — vérifiez votre connexion ou réessayez", .tr: "Oynatma başlatılamadı — bağlantıyı kontrol edin veya tekrar deneyin", .es: "No se pudo iniciar — comprueba tu conexión o reintenta"],
        "player.err.failed":[.ar: "فشل تشغيل المحتوى — تحقق من اتصالك أو الرابط", .en: "Playback failed — check your connection or the link", .fr: "Échec de la lecture — vérifiez la connexion ou le lien", .tr: "Oynatma başarısız — bağlantıyı veya linki kontrol edin", .es: "Fallo de reproducción — comprueba la conexión o el enlace"],
        "player.err.interrupted":[.ar: "انقطع البث — تحقق من الاتصال أو أعد المحاولة", .en: "Stream interrupted — check your connection or retry", .fr: "Flux interrompu — vérifiez la connexion ou réessayez", .tr: "Yayın kesildi — bağlantıyı kontrol edin veya tekrar deneyin", .es: "Transmisión interrumpida — comprueba la conexión o reintenta"],
        "play.subtitle.size":[.ar: "حجم الترجمة", .en: "Subtitle size", .fr: "Taille des sous-titres", .tr: "Altyazı boyutu", .es: "Tamaño de subtítulos"],
        "subsize.auto":[.ar: "تلقائي", .en: "Auto", .fr: "Auto", .tr: "Otomatik", .es: "Auto"],
        "subsize.small":[.ar: "صغير", .en: "Small", .fr: "Petit", .tr: "Küçük", .es: "Pequeño"],
        "subsize.medium":[.ar: "متوسط", .en: "Medium", .fr: "Moyen", .tr: "Orta", .es: "Medio"],
        "subsize.large":[.ar: "كبير", .en: "Large", .fr: "Grand", .tr: "Büyük", .es: "Grande"],
        "subsize.xl":[.ar: "ضخم", .en: "Extra large", .fr: "Très grand", .tr: "Çok büyük", .es: "Muy grande"],
        "reorder.your_order":[.ar: "ترتيبك", .en: "Your order", .fr: "Votre ordre", .tr: "Sıralamanız", .es: "Tu orden"],
        "reorder.available":[.ar: "القوائم المتاحة", .en: "Available lists", .fr: "Listes disponibles", .tr: "Mevcut listeler", .es: "Listas disponibles"],
        "reorder.drag_hint":[.ar: "اسحب للترتيب · اضغط ⊖ للحذف", .en: "Drag to reorder · tap ⊖ to remove", .fr: "Glissez pour réorganiser · touchez ⊖ pour retirer", .tr: "Sıralamak için sürükleyin · kaldırmak için ⊖", .es: "Arrastra para reordenar · toca ⊖ para quitar"],
        "reorder.empty_arranged":[.ar: "لم تُرتّب أي قائمة بعد — أضف من الأسفل ↓", .en: "Nothing arranged yet — add from below ↓", .fr: "Rien d'organisé — ajoutez ci-dessous ↓", .tr: "Henüz düzenlenmedi — aşağıdan ekleyin ↓", .es: "Nada organizado aún — añade abajo ↓"],

        // Screen titles
        "title.movies": [.ar: "الأفلام",     .en: "Movies",  .fr: "Films",  .tr: "Filmler", .es: "Películas"],
        "title.series": [.ar: "المسلسلات",   .en: "Series",  .fr: "Séries", .tr: "Diziler", .es: "Series"],
        "title.live":   [.ar: "البث المباشر",.en: "Live TV", .fr: "TV en direct", .tr: "Canlı TV", .es: "TV en vivo"],
        "count.movie":  [.ar: "فيلم",   .en: "movies",   .fr: "films",   .tr: "film",   .es: "películas"],
        "count.series": [.ar: "مسلسل",  .en: "series",   .fr: "séries",  .tr: "dizi",   .es: "series"],
        "count.channel":[.ar: "قناة",   .en: "channels", .fr: "chaînes", .tr: "kanal",  .es: "canales"],

        // Search placeholders
        "search.movies": [.ar: "ابحث في كل الأفلام…",   .en: "Search all movies…",   .fr: "Rechercher des films…", .tr: "Tüm filmlerde ara…", .es: "Buscar películas…"],
        "search.series": [.ar: "ابحث في كل المسلسلات…", .en: "Search all series…",   .fr: "Rechercher des séries…",.tr: "Tüm dizilerde ara…", .es: "Buscar series…"],
        "search.live":   [.ar: "ابحث في كل القنوات…",   .en: "Search all channels…", .fr: "Rechercher des chaînes…",.tr: "Tüm kanallarda ara…", .es: "Buscar canales…"],
        "search.cat":    [.ar: "ابحث عن قسم…",          .en: "Search a category…",   .fr: "Rechercher une catégorie…", .tr: "Kategori ara…", .es: "Buscar categoría…"],

        // Home sections
        "home.live_now":   [.ar: "يُبث الآن",      .en: "Live Now",     .fr: "En direct",     .tr: "Şimdi Canlı",  .es: "En directo"],
        "home.new_movies": [.ar: "أفلام جديدة",    .en: "New Movies",   .fr: "Nouveaux films",.tr: "Yeni Filmler", .es: "Nuevas películas"],
        "home.new_series": [.ar: "مسلسلات جديدة",  .en: "New Series",   .fr: "Nouvelles séries",.tr: "Yeni Diziler",.es: "Nuevas series"],
        "home.continue":   [.ar: "أكمل المشاهدة",  .en: "Continue Watching", .fr: "Reprendre", .tr: "İzlemeye Devam", .es: "Seguir viendo"],
        "home.notifications":[.ar: "الإشعارات",    .en: "Notifications",.fr: "Notifications", .tr: "Bildirimler",  .es: "Notificaciones"],

        // Settings groups
        "set.title":    [.ar: "الإعدادات",        .en: "Settings",  .fr: "Réglages", .tr: "Ayarlar", .es: "Ajustes"],
        "set.player":   [.ar: "المشغّل",          .en: "Player",    .fr: "Lecteur",  .tr: "Oynatıcı",.es: "Reproductor"],
        "set.app":      [.ar: "التطبيق",          .en: "App",       .fr: "App",      .tr: "Uygulama",.es: "App"],
        "set.legal":    [.ar: "الخصوصية والقانوني",.en: "Privacy & Legal", .fr: "Confidentialité", .tr: "Gizlilik", .es: "Privacidad"],
        "set.playlists":[.ar: "القوائم",          .en: "Playlists", .fr: "Listes",   .tr: "Listeler",.es: "Listas"],
        "set.activation":[.ar: "التفعيل",         .en: "Activation",.fr: "Activation",.tr: "Etkinleştirme",.es: "Activación"],
        "set.logout":   [.ar: "تسجيل الخروج",     .en: "Sign out",  .fr: "Déconnexion", .tr: "Çıkış", .es: "Cerrar sesión"],
        "set.notifications":[.ar: "الإشعارات",    .en: "Notifications", .fr: "Notifications", .tr: "Bildirimler", .es: "Notificaciones"],
        "set.about":    [.ar: "عن التطبيق",       .en: "About",     .fr: "À propos", .tr: "Hakkında",.es: "Acerca de"],
        "set.privacy":  [.ar: "سياسة الخصوصية",   .en: "Privacy Policy", .fr: "Confidentialité", .tr: "Gizlilik Politikası", .es: "Política de privacidad"],
        "set.terms":    [.ar: "شروط الاستخدام",   .en: "Terms of Use", .fr: "Conditions", .tr: "Kullanım Şartları", .es: "Términos"],
        "set.delete":   [.ar: "حذف الحساب",       .en: "Delete Account", .fr: "Supprimer le compte", .tr: "Hesabı Sil", .es: "Eliminar cuenta"],
        "set.playlists_manage":[.ar: "إدارة قوائمي", .en: "My Playlists", .fr: "Mes listes", .tr: "Listelerim", .es: "Mis listas"],
        "set.support":  [.ar: "تواصل مع الدعم", .en: "Contact Support", .fr: "Contacter le support", .tr: "Destek ile İletişim", .es: "Contactar soporte"],

        // Detail
        "detail.story": [.ar: "القصة",     .en: "Story",   .fr: "Synopsis",.tr: "Konu",    .es: "Sinopsis"],
        "detail.info":  [.ar: "المعلومات", .en: "Info",    .fr: "Infos",   .tr: "Bilgi",   .es: "Información"],
        "detail.cast":  [.ar: "طاقم العمل",.en: "Cast",    .fr: "Casting", .tr: "Oyuncular",.es: "Reparto"],
        "detail.play_movie":[.ar: "تشغيل الفيلم", .en: "Play Movie", .fr: "Lire le film", .tr: "Filmi Oynat", .es: "Reproducir"],

        // Empty
        "empty.no_results": [.ar: "لا نتائج", .en: "No results", .fr: "Aucun résultat", .tr: "Sonuç yok", .es: "Sin resultados"],

        "home.see_all":  [.ar: "عرض الكل", .en: "See all", .fr: "Tout voir", .tr: "Tümünü gör", .es: "Ver todo"],

        // Reseller code
        "code.have_code":[.ar: "لدي كود موزّع", .en: "I have a reseller code", .fr: "J'ai un code revendeur", .tr: "Bayi kodum var", .es: "Tengo un código de distribuidor"],
        "code.title":    [.ar: "كود الموزّع", .en: "Reseller Code", .fr: "Code revendeur", .tr: "Bayi Kodu", .es: "Código de distribuidor"],
        "code.hint":     [.ar: "أدخل الكود الذي زوّدك به موزّعك لتفعيل التطبيق وتخصيصه.", .en: "Enter the code your reseller gave you to activate and brand the app.", .fr: "Saisissez le code fourni par votre revendeur.", .tr: "Bayinizin verdiği kodu girin.", .es: "Introduce el código que te dio tu distribuidor."],
        "code.activate": [.ar: "تفعيل", .en: "Activate", .fr: "Activer", .tr: "Etkinleştir", .es: "Activar"],
        "code.invalid":  [.ar: "كود غير صالح أو موقوف", .en: "Invalid or inactive code", .fr: "Code invalide ou inactif", .tr: "Geçersiz veya pasif kod", .es: "Código no válido o inactivo"],

        // Parental control hub
        "pc.title":          [.ar: "الرقابة الأبوية", .en: "Parental Control", .fr: "Contrôle parental", .tr: "Ebeveyn Denetimi", .es: "Control parental"],
        "pc.enable":         [.ar: "تفعيل الرقابة الأبوية", .en: "Enable Parental Control", .fr: "Activer le contrôle parental", .tr: "Ebeveyn Denetimini Aç", .es: "Activar control parental"],
        "pc.enable_hint":    [.ar: "أنشئ رمزاً سرياً لقفل أقسام محددة. ستحتاج الرمز لفتحها.", .en: "Create a PIN to lock specific categories. You'll need it to open them.", .fr: "Créez un code pour verrouiller des catégories. Il sera requis pour les ouvrir.", .tr: "Belirli kategorileri kilitlemek için bir PIN oluşturun.", .es: "Crea un PIN para bloquear categorías. Lo necesitarás para abrirlas."],
        "pc.change_pin":     [.ar: "تغيير الرمز", .en: "Change PIN", .fr: "Changer le code", .tr: "PIN'i Değiştir", .es: "Cambiar PIN"],
        "pc.disable":        [.ar: "إيقاف الرقابة الأبوية", .en: "Turn Off Parental Control", .fr: "Désactiver le contrôle parental", .tr: "Ebeveyn Denetimini Kapat", .es: "Desactivar control parental"],
        "pc.on":             [.ar: "مفعّلة", .en: "On", .fr: "Activé", .tr: "Açık", .es: "Activado"],
        "pc.off":            [.ar: "متوقفة", .en: "Off", .fr: "Désactivé", .tr: "Kapalı", .es: "Desactivado"],
        "pc.recovery_title": [.ar: "رمز الاستعادة", .en: "Recovery Code", .fr: "Code de récupération", .tr: "Kurtarma Kodu", .es: "Código de recuperación"],
        "pc.recovery_hint":  [.ar: "احتفظ بهذا الرمز في مكان آمن. ستحتاجه لاستعادة رمزك إن نسيته.", .en: "Keep this code safe. You'll need it to reset your PIN if you forget it.", .fr: "Conservez ce code. Il permettra de réinitialiser votre code oublié.", .tr: "Bu kodu saklayın. PIN'inizi unutursanız sıfırlamak için gerekir.", .es: "Guarda este código. Lo necesitarás para restablecer tu PIN si lo olvidas."],
        "pc.recovery_saved": [.ar: "حفظته — متابعة", .en: "I've saved it", .fr: "Je l'ai enregistré", .tr: "Kaydettim", .es: "Lo he guardado"],
        "pin.forgot":        [.ar: "نسيت الرمز؟", .en: "Forgot PIN?", .fr: "Code oublié ?", .tr: "PIN'i mi unuttunuz?", .es: "¿Olvidaste el PIN?"],
        "locked.lock_all":   [.ar: "قفل الكل", .en: "Lock all", .fr: "Tout verrouiller", .tr: "Tümünü kilitle", .es: "Bloquear todo"],
        "locked.unlock_all": [.ar: "فتح الكل", .en: "Unlock all", .fr: "Tout déverrouiller", .tr: "Tümünü aç", .es: "Desbloquear todo"],
        "recovery.enter":    [.ar: "أدخل رمز الاستعادة المكوّن من 8 خانات", .en: "Enter your 8-character recovery code", .fr: "Saisissez votre code de récupération à 8 caractères", .tr: "8 karakterli kurtarma kodunuzu girin", .es: "Introduce tu código de recuperación de 8 caracteres"],
        "recovery.wrong":    [.ar: "رمز استعادة غير صحيح", .en: "Incorrect recovery code", .fr: "Code de récupération incorrect", .tr: "Yanlış kurtarma kodu", .es: "Código de recuperación incorrecto"],
        "history.remove":[.ar: "حذف من السجل", .en: "Remove from history", .fr: "Retirer de l'historique", .tr: "Geçmişten kaldır", .es: "Quitar del historial"],

        // iPad live pane
        "live.pick_channel": [.ar: "اختر قناة للمشاهدة", .en: "Select a channel to watch", .fr: "Sélectionnez une chaîne", .tr: "İzlemek için bir kanal seçin", .es: "Selecciona un canal"],
        "live.fullscreen":   [.ar: "ملء الشاشة", .en: "Fullscreen", .fr: "Plein écran", .tr: "Tam ekran", .es: "Pantalla completa"],
        "live.no_epg":       [.ar: "دليل البرامج غير متوفّر لهذه القناة", .en: "Program guide unavailable for this channel", .fr: "Guide des programmes indisponible", .tr: "Bu kanal için yayın akışı yok", .es: "Guía de programación no disponible"],

        // Common (extra)
        "common.delete":   [.ar: "حذف",      .en: "Delete",     .fr: "Supprimer", .tr: "Sil",       .es: "Eliminar"],
        "common.activate": [.ar: "تفعيل",    .en: "Activate",   .fr: "Activer",   .tr: "Etkinleştir",.es: "Activar"],
        "common.add":      [.ar: "إضافة",    .en: "Add",        .fr: "Ajouter",   .tr: "Ekle",      .es: "Añadir"],
        "common.done":     [.ar: "تم",       .en: "Done",       .fr: "Terminé",   .tr: "Bitti",     .es: "Hecho"],
        "common.connected":[.ar: "متصل",     .en: "Connected",  .fr: "Connecté",  .tr: "Bağlı",     .es: "Conectado"],
        "common.search_in":[.ar: "ابحث في",  .en: "Search in",  .fr: "Rechercher dans", .tr: "Şurada ara", .es: "Buscar en"],

        // Units / time
        "unit.day":        [.ar: "يوم",      .en: "day",        .fr: "jour",      .tr: "gün",       .es: "día"],
        "unit.minute":     [.ar: "دقيقة",    .en: "min",        .fr: "min",       .tr: "dk",        .es: "min"],
        "unit.second_short":[.ar: "ث",       .en: "s",          .fr: "s",         .tr: "sn",        .es: "s"],
        "unit.item":       [.ar: "عنصر",     .en: "items",      .fr: "éléments",  .tr: "öğe",       .es: "elementos"],
        "unit.channel":    [.ar: "قناة",     .en: "channels",   .fr: "chaînes",   .tr: "kanal",     .es: "canales"],
        "unit.movie":      [.ar: "فيلم",     .en: "movies",     .fr: "films",     .tr: "film",      .es: "películas"],
        "unit.series":     [.ar: "مسلسل",    .en: "series",     .fr: "séries",    .tr: "dizi",      .es: "series"],
        "time.remaining":  [.ar: "متبقٍ",    .en: "Remaining",  .fr: "Restant",   .tr: "Kalan",     .es: "Restante"],
        "season.number":   [.ar: "الموسم",   .en: "Season",     .fr: "Saison",    .tr: "Sezon",     .es: "Temporada"],
        "episode.number":  [.ar: "الحلقة",   .en: "Episode",    .fr: "Épisode",   .tr: "Bölüm",     .es: "Episodio"],

        // Loading / status messages
        "loading.generic":  [.ar: "جارٍ التحميل...", .en: "Loading…",  .fr: "Chargement…", .tr: "Yükleniyor…", .es: "Cargando…"],
        "loading.updating": [.ar: "جارٍ التحديث…",   .en: "Updating…", .fr: "Mise à jour…", .tr: "Güncelleniyor…", .es: "Actualizando…"],
        "loading.channels": [.ar: "جارٍ تحميل القنوات...",   .en: "Loading channels…", .fr: "Chargement des chaînes…", .tr: "Kanallar yükleniyor…", .es: "Cargando canales…"],
        "loading.movies":   [.ar: "جارٍ تحميل الأفلام...",   .en: "Loading movies…",   .fr: "Chargement des films…",   .tr: "Filmler yükleniyor…",  .es: "Cargando películas…"],
        "loading.series":   [.ar: "جارٍ تحميل المسلسلات...", .en: "Loading series…",   .fr: "Chargement des séries…",  .tr: "Diziler yükleniyor…",  .es: "Cargando series…"],
        "loading.error":    [.ar: "خطأ",     .en: "Error",      .fr: "Erreur",    .tr: "Hata",      .es: "Error"],

        // Settings — server / activation
        "settings.language":        [.ar: "اللغة",          .en: "Language",        .fr: "Langue",          .tr: "Dil",             .es: "Idioma"],
        "settings.active_server":   [.ar: "السيرفر النشط",  .en: "Active Server",   .fr: "Serveur actif",   .tr: "Aktif Sunucu",    .es: "Servidor activo"],
        "settings.m3u_list":        [.ar: "قائمة M3U",      .en: "M3U List",        .fr: "Liste M3U",       .tr: "M3U Listesi",     .es: "Lista M3U"],
        "settings.user":            [.ar: "مستخدم",         .en: "User",            .fr: "Utilisateur",     .tr: "Kullanıcı",       .es: "Usuario"],
        "settings.device_id":       [.ar: "معرّف الجهاز",   .en: "Device ID",       .fr: "ID de l'appareil",.tr: "Cihaz Kimliği",   .es: "ID del dispositivo"],

        // Subscription card
        "sub.active":       [.ar: "اشتراكك نشط",            .en: "Your subscription is active", .fr: "Votre abonnement est actif", .tr: "Aboneliğiniz aktif", .es: "Tu suscripción está activa"],
        "sub.expiring":     [.ar: "اشتراكك على وشك الانتهاء",.en: "Your subscription is about to expire", .fr: "Votre abonnement expire bientôt", .tr: "Aboneliğiniz bitmek üzere", .es: "Tu suscripción está por vencer"],
        "sub.renew_now":    [.ar: "تجديد الاشتراك الآن",   .en: "Renew Subscription Now", .fr: "Renouveler maintenant", .tr: "Aboneliği Şimdi Yenile", .es: "Renovar suscripción ahora"],
        "sub.renew":        [.ar: "تجديد الاشتراك",        .en: "Renew Subscription", .fr: "Renouveler l'abonnement", .tr: "Aboneliği Yenile", .es: "Renovar suscripción"],

        // Activation status
        "act.kind_trial":    [.ar: "نسخة تجريبية",        .en: "Free Trial",      .fr: "Version d'essai", .tr: "Deneme Sürümü",   .es: "Versión de prueba"],
        "act.kind_lifetime": [.ar: "اشتراك مدى الحياة",   .en: "Lifetime Subscription", .fr: "Abonnement à vie", .tr: "Ömür Boyu Abonelik", .es: "Suscripción de por vida"],
        "act.kind_yearly":   [.ar: "اشتراك سنوي",         .en: "Yearly Subscription", .fr: "Abonnement annuel", .tr: "Yıllık Abonelik", .es: "Suscripción anual"],
        "act.expires_on":    [.ar: "ينتهي",               .en: "Expires",         .fr: "Expire le",       .tr: "Bitiş",           .es: "Vence"],
        "act.valid_forever": [.ar: "صالح دائماً — لا تاريخ انتهاء", .en: "Valid forever — no expiry", .fr: "Valide à vie — sans expiration", .tr: "Süresiz geçerli — son kullanma yok", .es: "Válido para siempre — sin caducidad"],
        "act.active_owner":  [.ar: "مفعّل (مالك)",        .en: "Activated (Owner)", .fr: "Activé (Propriétaire)", .tr: "Etkin (Sahip)", .es: "Activado (Propietario)"],
        "act.active":        [.ar: "مفعّل ✓",             .en: "Activated ✓",     .fr: "Activé ✓",        .tr: "Etkin ✓",         .es: "Activado ✓"],
        "act.expired":       [.ar: "انتهى التفعيل",       .en: "Activation expired", .fr: "Activation expirée", .tr: "Etkinleştirme süresi doldu", .es: "Activación caducada"],
        "act.blocked":       [.ar: "محظور",               .en: "Blocked",         .fr: "Bloqué",          .tr: "Engellendi",      .es: "Bloqueado"],
        "act.not_activated": [.ar: "غير مفعّل",           .en: "Not activated",   .fr: "Non activé",      .tr: "Etkin değil",     .es: "No activado"],

        // Player group toggles
        "player.autonext.title": [.ar: "تشغيل تلقائي للحلقة التالية", .en: "Auto-play next episode", .fr: "Lecture auto. de l'épisode suivant", .tr: "Sonraki bölümü otomatik oynat", .es: "Reproducir siguiente episodio"],
        "player.autonext.desc":  [.ar: "ينتقل تلقائياً قبل نهاية الحلقة", .en: "Advances before the episode ends", .fr: "Avance avant la fin de l'épisode", .tr: "Bölüm bitmeden önce geçer", .es: "Avanza antes de que termine el episodio"],
        "player.autonext.timer": [.ar: "مؤقّت الانتقال للحلقة التالية", .en: "Next-episode timer", .fr: "Minuteur d'épisode suivant", .tr: "Sonraki bölüm zamanlayıcısı", .es: "Temporizador de siguiente episodio"],
        "player.skipintro.title":[.ar: "إظهار «تخطّي المقدمة»", .en: "Show \"Skip Intro\"", .fr: "Afficher « Passer l'intro »", .tr: "\"Tanıtımı Atla\" göster", .es: "Mostrar \"Saltar intro\""],
        "player.skipintro.desc": [.ar: "زر لتجاوز مقدمة الحلقة", .en: "A button to skip the episode intro", .fr: "Un bouton pour passer l'intro", .tr: "Bölüm tanıtımını atlama düğmesi", .es: "Botón para saltar la introducción"],
        "player.skipintro.dur":  [.ar: "مدة تخطّي المقدمة", .en: "Skip-intro length", .fr: "Durée du saut d'intro", .tr: "Tanıtım atlama süresi", .es: "Duración de salto de intro"],
        "player.quality":        [.ar: "جودة البث",      .en: "Streaming quality", .fr: "Qualité de diffusion", .tr: "Yayın kalitesi", .es: "Calidad de transmisión"],
        "player.pip.desc":       [.ar: "تشغيل في نافذة عائمة", .en: "Play in a floating window", .fr: "Lecture en fenêtre flottante", .tr: "Yüzen pencerede oynat", .es: "Reproducir en ventana flotante"],
        "player.sleep.default":  [.ar: "مؤقت النوم الافتراضي", .en: "Default sleep timer", .fr: "Minuteur de veille par défaut", .tr: "Varsayılan uyku zamanlayıcısı", .es: "Temporizador de apagado predeterminado"],
        "player.engine":         [.ar: "محرّك التشغيل", .en: "Playback engine", .fr: "Moteur de lecture", .tr: "Oynatma motoru", .es: "Motor de reproducción"],
        "player.engine.desc":    [.ar: "تلقائي = عتادي للبث المباشر والأفلام، VLC لبقية الصيغ", .en: "Auto = hardware for live/movies, VLC for other formats", .fr: "Auto = matériel pour direct/films, VLC pour les autres formats", .tr: "Otomatik = canlı/film için donanım, diğer biçimler için VLC", .es: "Auto = hardware para directo/películas, VLC para otros formatos"],
        "player.engine.auto":    [.ar: "تلقائي", .en: "Automatic", .fr: "Automatique", .tr: "Otomatik", .es: "Automático"],
        "player.pip":            [.ar: "صورة داخل صورة", .en: "Picture in Picture", .fr: "Image dans l'image", .tr: "Resim İçinde Resim", .es: "Imagen en imagen"],
        "quality.auto":          [.ar: "تلقائي", .en: "Automatic", .fr: "Automatique", .tr: "Otomatik", .es: "Automático"],
        "quality.high":          [.ar: "عالي HD", .en: "High HD", .fr: "Haute HD", .tr: "Yüksek HD", .es: "Alta HD"],
        "quality.medium":        [.ar: "متوسط", .en: "Medium", .fr: "Moyenne", .tr: "Orta", .es: "Media"],
        "quality.low":           [.ar: "منخفض", .en: "Low", .fr: "Basse", .tr: "Düşük", .es: "Baja"],
        "player.engine.av":      [.ar: "عتادي (الأسرع)", .en: "Hardware (fastest)", .fr: "Matériel (rapide)", .tr: "Donanım (en hızlı)", .es: "Hardware (rápido)"],
        "player.engine.vlc":     [.ar: "شامل (VLC)", .en: "Universal (VLC)", .fr: "Universel (VLC)", .tr: "Evrensel (VLC)", .es: "Universal (VLC)"],

        // Offline downloads
        "set.downloads":         [.ar: "التنزيلات", .en: "Downloads", .fr: "Téléchargements", .tr: "İndirilenler", .es: "Descargas"],
        "downloads.title":       [.ar: "التنزيلات", .en: "Downloads", .fr: "Téléchargements", .tr: "İndirilenler", .es: "Descargas"],
        "downloads.empty.title": [.ar: "لا توجد تنزيلات", .en: "No downloads", .fr: "Aucun téléchargement", .tr: "İndirme yok", .es: "Sin descargas"],
        "downloads.empty.sub":   [.ar: "نزّل الأفلام والحلقات لمشاهدتها دون إنترنت", .en: "Download movies and episodes to watch offline", .fr: "Téléchargez films et épisodes pour les regarder hors ligne", .tr: "Çevrimdışı izlemek için film ve bölüm indirin", .es: "Descarga películas y episodios para verlos sin conexión"],
        "download.failed":       [.ar: "فشل التحميل — اضغط لإعادة المحاولة", .en: "Download failed — tap to retry", .fr: "Échec — appuyez pour réessayer", .tr: "İndirme başarısız — dokunup yeniden dene", .es: "Error — toca para reintentar"],
        "downloads.paused":      [.ar: "متوقّف مؤقتاً", .en: "Paused", .fr: "En pause", .tr: "Duraklatıldı", .es: "En pausa"],
        "downloads.queued":      [.ar: "في الانتظار…", .en: "Queued…", .fr: "En file d'attente…", .tr: "Sırada…", .es: "En cola…"],
        "downloads.turbo":       [.ar: "تحميل توربو (متوازٍ)", .en: "Turbo download (parallel)", .fr: "Téléchargement turbo", .tr: "Turbo indirme", .es: "Descarga turbo"],
        "downloads.turbo.desc":  [.ar: "أسرع عبر عدة اتصالات — قد لا يناسب اشتراكات محدودة الاتصالات", .en: "Faster via multiple connections — may not suit connection-limited lines", .fr: "Plus rapide via plusieurs connexions — déconseillé si connexions limitées", .tr: "Çoklu bağlantıyla daha hızlı — bağlantı limitli hatlara uygun olmayabilir", .es: "Más rápido con varias conexiones — no apto para líneas con conexiones limitadas"],
        "downloads.wifi_only":   [.ar: "التحميل على Wi-Fi فقط", .en: "Download on Wi-Fi only", .fr: "Télécharger en Wi-Fi uniquement", .tr: "Yalnızca Wi-Fi'de indir", .es: "Descargar solo con Wi-Fi"],
        "downloads.wifi_only.desc":[.ar: "ينتظر شبكة Wi-Fi بدلاً من استخدام بيانات الجوّال", .en: "Waits for Wi-Fi instead of using cellular data", .fr: "Attend le Wi-Fi au lieu d'utiliser les données mobiles", .tr: "Hücresel veri yerine Wi-Fi'yi bekler", .es: "Espera Wi-Fi en lugar de usar datos móviles"],
        "downloads.notif.title": [.ar: "اكتمل التنزيل", .en: "Download complete", .fr: "Téléchargement terminé", .tr: "İndirme tamamlandı", .es: "Descarga completada"],
        "downloads.notif.denied":[.ar: "الإشعارات معطّلة — فعّلها لتصلك عند اكتمال التحميل", .en: "Notifications are off — enable them to be alerted when downloads finish", .fr: "Notifications désactivées — activez-les pour être averti à la fin", .tr: "Bildirimler kapalı — indirme bitince haber almak için açın", .es: "Notificaciones desactivadas — actívalas para avisarte al terminar"],
        "downloads.storage_used":[.ar: "المساحة المستخدمة", .en: "Storage used", .fr: "Espace utilisé", .tr: "Kullanılan alan", .es: "Almacenamiento usado"],
        "downloads.free":        [.ar: "المساحة المتاحة", .en: "Available", .fr: "Disponible", .tr: "Kullanılabilir", .es: "Disponible"],
        "downloads.low_warning": [.ar: "مساحة الجهاز منخفضة — احذف بعض التنزيلات", .en: "Low device storage — delete some downloads", .fr: "Stockage faible — supprimez des téléchargements", .tr: "Cihaz alanı az — bazı indirmeleri silin", .es: "Almacenamiento bajo — elimina descargas"],
        "downloads.space_low.title":    [.ar: "مساحة منخفضة", .en: "Low storage", .fr: "Stockage faible", .tr: "Az alan", .es: "Almacenamiento bajo"],
        "downloads.space_low.msg":      [.ar: "مساحة جهازك منخفضة. هل تريد متابعة التحميل؟", .en: "Your device storage is low. Continue the download?", .fr: "Le stockage est faible. Continuer le téléchargement ?", .tr: "Cihaz alanınız az. İndirmeye devam edilsin mi?", .es: "Tu almacenamiento es bajo. ¿Continuar la descarga?"],
        "downloads.space_low.continue": [.ar: "متابعة", .en: "Continue", .fr: "Continuer", .tr: "Devam", .es: "Continuar"],

        // App group
        "app.notif.desc":   [.ar: "تنبيهات انتهاء الاشتراك", .en: "Subscription expiry alerts", .fr: "Alertes d'expiration d'abonnement", .tr: "Abonelik bitiş uyarıları", .es: "Alertas de vencimiento de suscripción"],
        "app.parental":     [.ar: "الرقابة الأبوية",     .en: "Parental Controls", .fr: "Contrôle parental", .tr: "Ebeveyn Denetimi", .es: "Control parental"],
        "app.parental.on":  [.ar: "مفعّلة",              .en: "On",              .fr: "Activé",          .tr: "Açık",            .es: "Activado"],
        "app.parental.off": [.ar: "متوقفة",             .en: "Off",             .fr: "Désactivé",       .tr: "Kapalı",          .es: "Desactivado"],
        "app.locked_cats":  [.ar: "الأقسام المقفلة",    .en: "Locked Categories", .fr: "Catégories verrouillées", .tr: "Kilitli Kategoriler", .es: "Categorías bloqueadas"],
        "app.analytics":    [.ar: "إحصاءات الاستخدام",  .en: "Usage Analytics", .fr: "Statistiques d'usage", .tr: "Kullanım İstatistikleri", .es: "Analítica de uso"],
        "app.analytics.desc":[.ar: "مساعدتنا في تحسين التطبيق", .en: "Help us improve the app", .fr: "Aidez-nous à améliorer l'app", .tr: "Uygulamayı geliştirmemize yardımcı olun", .es: "Ayúdanos a mejorar la app"],

        // Legal group
        "legal.report":     [.ar: "الإبلاغ عن محتوى مخالف", .en: "Report objectionable content", .fr: "Signaler un contenu répréhensible", .tr: "Uygunsuz içeriği bildir", .es: "Reportar contenido inapropiado"],
        "legal.delete.desc":[.ar: "إجراء لا يمكن التراجع عنه", .en: "This action cannot be undone", .fr: "Cette action est irréversible", .tr: "Bu işlem geri alınamaz", .es: "Esta acción no se puede deshacer"],

        // Logout / delete alerts
        "alert.logout.msg":     [.ar: "هل تريد تسجيل الخروج من حسابك؟", .en: "Do you want to sign out of your account?", .fr: "Voulez-vous vous déconnecter de votre compte ?", .tr: "Hesabınızdan çıkmak istiyor musunuz?", .es: "¿Quieres cerrar sesión en tu cuenta?"],
        "alert.delete.msg":     [.ar: "سيُحذف حسابك وجميع بياناتك نهائياً. هذا الإجراء لا يمكن التراجع عنه.", .en: "Your account and all your data will be permanently deleted. This action cannot be undone.", .fr: "Votre compte et toutes vos données seront supprimés définitivement. Cette action est irréversible.", .tr: "Hesabınız ve tüm verileriniz kalıcı olarak silinecek. Bu işlem geri alınamaz.", .es: "Tu cuenta y todos tus datos se eliminarán permanentemente. Esta acción no se puede deshacer."],
        "alert.delete.confirm": [.ar: "حذف نهائياً", .en: "Delete Permanently", .fr: "Supprimer définitivement", .tr: "Kalıcı Olarak Sil", .es: "Eliminar permanentemente"],

        // Playlists
        "playlists.title":      [.ar: "قوائمي",          .en: "My Playlists",    .fr: "Mes listes",      .tr: "Listelerim",      .es: "Mis listas"],
        "playlists.empty.title":[.ar: "لا قوائم محفوظة", .en: "No saved playlists", .fr: "Aucune liste enregistrée", .tr: "Kayıtlı liste yok", .es: "Sin listas guardadas"],
        "playlists.empty.sub":  [.ar: "أضف قائمة M3U أو get.php جديدة", .en: "Add a new M3U or get.php playlist", .fr: "Ajoutez une nouvelle liste M3U ou get.php", .tr: "Yeni bir M3U veya get.php listesi ekleyin", .es: "Añade una nueva lista M3U o get.php"],
        "playlists.active":     [.ar: "نشطة",            .en: "Active",          .fr: "Active",          .tr: "Aktif",           .es: "Activa"],
        "playlists.add":        [.ar: "إضافة قائمة",     .en: "Add Playlist",    .fr: "Ajouter une liste",.tr: "Liste Ekle",      .es: "Añadir lista"],
        "playlists.name_ph":    [.ar: "اسم القائمة (اختياري)", .en: "Playlist name (optional)", .fr: "Nom de la liste (facultatif)", .tr: "Liste adı (isteğe bağlı)", .es: "Nombre de la lista (opcional)"],
        "playlists.url_ph":     [.ar: "رابط M3U / get.php", .en: "M3U / get.php URL", .fr: "URL M3U / get.php", .tr: "M3U / get.php bağlantısı", .es: "URL M3U / get.php"],
        "playlists.add_activate":[.ar: "إضافة وتفعيل",  .en: "Add & Activate",  .fr: "Ajouter et activer", .tr: "Ekle ve Etkinleştir", .es: "Añadir y activar"],
        "playlists.add_failed": [.ar: "تعذّر إضافة القائمة", .en: "Couldn't add the playlist", .fr: "Impossible d'ajouter la liste", .tr: "Liste eklenemedi", .es: "No se pudo añadir la lista"],

        // About
        "about.subtitle":   [.ar: "Premium IPTV Player", .en: "Premium IPTV Player", .fr: "Lecteur IPTV Premium", .tr: "Premium IPTV Oynatıcı", .es: "Reproductor IPTV Premium"],
        "about.version":    [.ar: "الإصدار",            .en: "Version",         .fr: "Version",         .tr: "Sürüm",           .es: "Versión"],

        // Parental PIN
        "pin.verify":       [.ar: "أدخل رمز الرقابة الأبوية", .en: "Enter parental PIN", .fr: "Saisissez le code parental", .tr: "Ebeveyn kodunu girin", .es: "Introduce el PIN parental"],
        "pin.confirm":      [.ar: "أعد إدخال الرمز للتأكيد", .en: "Re-enter PIN to confirm", .fr: "Ressaisissez le code pour confirmer", .tr: "Onaylamak için kodu tekrar girin", .es: "Vuelve a introducir el PIN para confirmar"],
        "pin.create":       [.ar: "أنشئ رمز رقابة (4 أرقام)", .en: "Create a PIN (4 digits)", .fr: "Créez un code (4 chiffres)", .tr: "Bir kod oluşturun (4 hane)", .es: "Crea un PIN (4 dígitos)"],
        "pin.wrong":        [.ar: "رمز غير صحيح",       .en: "Incorrect PIN",   .fr: "Code incorrect",  .tr: "Yanlış kod",      .es: "PIN incorrecto"],
        "pin.mismatch":     [.ar: "الرمز غير متطابق، حاول مجدداً", .en: "PINs don't match, try again", .fr: "Les codes ne correspondent pas, réessayez", .tr: "Kodlar eşleşmiyor, tekrar deneyin", .es: "Los PIN no coinciden, inténtalo de nuevo"],

        // Parental gate
        "gate.locked":      [.ar: "قسم مقفل",           .en: "Locked Category", .fr: "Catégorie verrouillée", .tr: "Kilitli Kategori", .es: "Categoría bloqueada"],
        "gate.protected":   [.ar: "محمي بالرقابة الأبوية", .en: "Protected by parental controls", .fr: "Protégé par le contrôle parental", .tr: "Ebeveyn denetimiyle korunuyor", .es: "Protegido por control parental"],
        "gate.enter_pin":   [.ar: "إدخال الرمز",        .en: "Enter PIN",       .fr: "Saisir le code",  .tr: "Kodu Gir",        .es: "Introducir PIN"],

        // Locked categories manager
        "locked.intro":     [.ar: "اختر الأقسام التي تريد قفلها — ستتطلب الرمز لفتحها.", .en: "Choose the categories to lock — they'll require the PIN to open.", .fr: "Choisissez les catégories à verrouiller — un code sera requis pour les ouvrir.", .tr: "Kilitlenecek kategorileri seçin — açmak için kod gerekecek.", .es: "Elige las categorías a bloquear — requerirán el PIN para abrirlas."],
        "locked.movies":    [.ar: "الأفلام",            .en: "Movies",          .fr: "Films",           .tr: "Filmler",         .es: "Películas"],
        "locked.series":    [.ar: "المسلسلات",          .en: "Series",          .fr: "Séries",          .tr: "Diziler",         .es: "Series"],
        "locked.channels":  [.ar: "القنوات",            .en: "Channels",        .fr: "Chaînes",         .tr: "Kanallar",        .es: "Canales"],

        // Player view
        "play.buffering":   [.ar: "جارٍ التخزين المؤقت…", .en: "Buffering…",     .fr: "Mise en mémoire tampon…", .tr: "Arabelleğe alınıyor…", .es: "Almacenando en búfer…"],
        "play.starting":    [.ar: "جارٍ التشغيل…",      .en: "Starting…",       .fr: "Démarrage…",      .tr: "Başlatılıyor…",   .es: "Iniciando…"],
        "play.reconnecting":[.ar: "جارٍ إعادة الاتصال…", .en: "Reconnecting…",   .fr: "Reconnexion…",    .tr: "Yeniden bağlanılıyor…", .es: "Reconectando…"],
        "play.skip_intro":  [.ar: "تخطّي المقدمة",      .en: "Skip Intro",      .fr: "Passer l'intro",  .tr: "Tanıtımı Atla",   .es: "Saltar intro"],
        "play.next_episode":[.ar: "الحلقة التالية",     .en: "Next Episode",    .fr: "Épisode suivant", .tr: "Sonraki Bölüm",   .es: "Siguiente episodio"],
        "play.live_now":    [.ar: "بث مباشر",           .en: "Live",            .fr: "En direct",       .tr: "Canlı",           .es: "En vivo"],
        "play.audio":       [.ar: "صوت",                .en: "Audio",           .fr: "Audio",           .tr: "Ses",             .es: "Audio"],
        "play.subtitle":    [.ar: "ترجمة",              .en: "Subtitles",       .fr: "Sous-titres",     .tr: "Altyazı",         .es: "Subtítulos"],
        "play.sleep":       [.ar: "نوم",                .en: "Sleep",           .fr: "Veille",          .tr: "Uyku",            .es: "Apagado"],
        "play.sleep.title": [.ar: "مؤقت النوم",         .en: "Sleep Timer",     .fr: "Minuteur de veille", .tr: "Uyku Zamanlayıcısı", .es: "Temporizador de apagado"],
        "play.sleep.will_stop":[.ar: "سيتوقف التشغيل خلال", .en: "Playback will stop in", .fr: "La lecture s'arrêtera dans", .tr: "Oynatma şu sürede duracak", .es: "La reproducción se detendrá en"],
        "play.sleep.cancel":[.ar: "إلغاء المؤقت",       .en: "Cancel Timer",    .fr: "Annuler le minuteur", .tr: "Zamanlayıcıyı İptal Et", .es: "Cancelar temporizador"],
        "play.sleep.choose":[.ar: "اختر مدة المؤقت",    .en: "Choose timer duration", .fr: "Choisir la durée", .tr: "Süre seçin", .es: "Elige la duración"],
        "play.subtitle.title":[.ar: "الترجمة",          .en: "Subtitles",       .fr: "Sous-titres",     .tr: "Altyazı",         .es: "Subtítulos"],
        "play.subtitle.none":[.ar: "بدون ترجمة",        .en: "No subtitles",    .fr: "Aucun sous-titre", .tr: "Altyazı yok",     .es: "Sin subtítulos"],
        "play.subtitle.empty.title":[.ar: "لا توجد ترجمات", .en: "No subtitles", .fr: "Aucun sous-titre", .tr: "Altyazı yok", .es: "Sin subtítulos"],
        "play.subtitle.empty.sub":[.ar: "هذا المحتوى لا يتضمن مسارات ترجمة", .en: "This content has no subtitle tracks", .fr: "Ce contenu ne contient pas de sous-titres", .tr: "Bu içerikte altyazı parçası yok", .es: "Este contenido no tiene pistas de subtítulos"],
        "play.audio_track": [.ar: "المسار الصوتي",      .en: "Audio Track",     .fr: "Piste audio",     .tr: "Ses Parçası",     .es: "Pista de audio"],
        "play.audio_track.title":[.ar: "المسار الصوتي", .en: "Audio Track",     .fr: "Piste audio",     .tr: "Ses Parçası",     .es: "Pista de audio"],
        "play.audio_track.empty.title":[.ar: "لا توجد مسارات صوتية", .en: "No audio tracks", .fr: "Aucune piste audio", .tr: "Ses parçası yok", .es: "Sin pistas de audio"],
        "play.audio_track.empty.sub":[.ar: "هذا المحتوى يحتوي على مسار صوتي واحد فقط", .en: "This content has only one audio track", .fr: "Ce contenu n'a qu'une seule piste audio", .tr: "Bu içerikte yalnızca bir ses parçası var", .es: "Este contenido solo tiene una pista de audio"],
        "play.speed":       [.ar: "السرعة",             .en: "Speed",           .fr: "Vitesse",         .tr: "Hız",             .es: "Velocidad"],
        "play.speed.title": [.ar: "سرعة التشغيل",       .en: "Playback Speed",  .fr: "Vitesse de lecture", .tr: "Oynatma Hızı",  .es: "Velocidad de reproducción"],
        "play.speed.normal":[.ar: "عادي (1x)",          .en: "Normal (1x)",     .fr: "Normal (1x)",     .tr: "Normal (1x)",     .es: "Normal (1x)"],
        "play.unlock":      [.ar: "إلغاء القفل",        .en: "Unlock",          .fr: "Déverrouiller",   .tr: "Kilidi Aç",       .es: "Desbloquear"],

        // Home
        "home.featured":    [.ar: "مميّز",              .en: "Featured",        .fr: "À la une",        .tr: "Öne çıkan",       .es: "Destacado"],
        "home.new_tag":     [.ar: "جديد",               .en: "New",             .fr: "Nouveau",         .tr: "Yeni",            .es: "Nuevo"],
        "home.qn_live":     [.ar: "بث مباشر",           .en: "Live TV",         .fr: "TV en direct",    .tr: "Canlı TV",        .es: "TV en vivo"],
        "home.qn_movies":   [.ar: "أفلام",              .en: "Movies",          .fr: "Films",           .tr: "Filmler",         .es: "Películas"],
        "home.qn_series":   [.ar: "مسلسلات",            .en: "Series",          .fr: "Séries",          .tr: "Diziler",         .es: "Series"],
        "home.clear_all":   [.ar: "مسح الكل",           .en: "Clear All",       .fr: "Tout effacer",    .tr: "Tümünü Temizle",  .es: "Borrar todo"],
        "home.remove_history":[.ar: "حذف من السجل",     .en: "Remove from history", .fr: "Retirer de l'historique", .tr: "Geçmişten kaldır", .es: "Quitar del historial"],
        "home.content_error.title":[.ar: "تعذّر تحميل المحتوى", .en: "Couldn't load content", .fr: "Impossible de charger le contenu", .tr: "İçerik yüklenemedi", .es: "No se pudo cargar el contenido"],
        "home.content_error.sub":[.ar: "تحقّق من اتصالك أو من صلاحية اشتراكك لدى المزوّد، ثم أعد المحاولة", .en: "Check your connection or that your provider subscription is active, then try again", .fr: "Vérifiez votre connexion ou la validité de votre abonnement, puis réessayez", .tr: "Bağlantınızı veya sağlayıcı aboneliğinizin aktif olduğunu kontrol edip tekrar deneyin", .es: "Comprueba tu conexión o que tu suscripción esté activa e inténtalo de nuevo"],
        "home.percent_done":[.ar: "مكتمل",             .en: "complete",        .fr: "terminé",         .tr: "tamamlandı",      .es: "completado"],
        "home.whatsapp":    [.ar: "واتساب",             .en: "WhatsApp",        .fr: "WhatsApp",        .tr: "WhatsApp",        .es: "WhatsApp"],
        "home.telegram":    [.ar: "تيليغرام",           .en: "Telegram",        .fr: "Telegram",        .tr: "Telegram",        .es: "Telegram"],
        "home.preparing":   [.ar: "جارٍ تجهيز مكتبتك…", .en: "Preparing your library…", .fr: "Préparation de votre bibliothèque…", .tr: "Kitaplığınız hazırlanıyor…", .es: "Preparando tu biblioteca…"],
        "home.boot.live":   [.ar: "البث المباشر",       .en: "Live TV",         .fr: "TV en direct",    .tr: "Canlı TV",        .es: "TV en vivo"],
        "home.boot.movies": [.ar: "الأفلام",            .en: "Movies",          .fr: "Films",           .tr: "Filmler",         .es: "Películas"],
        "home.boot.series": [.ar: "المسلسلات",          .en: "Series",          .fr: "Séries",          .tr: "Diziler",         .es: "Series"],

        // Alerts / notifications
        "alerts.announcement":[.ar: "إعلان",            .en: "Announcement",    .fr: "Annonce",         .tr: "Duyuru",          .es: "Anuncio"],
        "alerts.sub_warning": [.ar: "تنبيه الاشتراك",   .en: "Subscription Alert", .fr: "Alerte d'abonnement", .tr: "Abonelik Uyarısı", .es: "Alerta de suscripción"],
        "alerts.sub_active":  [.ar: "اشتراكك نشط",      .en: "Your subscription is active", .fr: "Votre abonnement est actif", .tr: "Aboneliğiniz aktif", .es: "Tu suscripción está activa"],
        "alerts.empty.title": [.ar: "لا توجد إشعارات",  .en: "No notifications", .fr: "Aucune notification", .tr: "Bildirim yok", .es: "Sin notificaciones"],
        "alerts.empty.sub":   [.ar: "ستظهر هنا تنبيهات الإدارة وحالة اشتراكك", .en: "Admin alerts and your subscription status will appear here", .fr: "Les alertes de l'administration et l'état de votre abonnement apparaîtront ici", .tr: "Yönetici uyarıları ve abonelik durumunuz burada görünecek", .es: "Aquí aparecerán las alertas y el estado de tu suscripción"],

        // Channel info sheet
        "channel.live_now": [.ar: "بث مباشر الآن",      .en: "Live now",        .fr: "En direct maintenant", .tr: "Şimdi canlı",  .es: "En directo ahora"],
        "channel.play":     [.ar: "تشغيل القناة",       .en: "Play Channel",    .fr: "Lire la chaîne",  .tr: "Kanalı Oynat",    .es: "Reproducir canal"],
        "epg.next":         [.ar: "التالي",             .en: "Next",            .fr: "Suivant",         .tr: "Sıradaki",        .es: "Siguiente"],
        "refresh.title":    [.ar: "تحديث المحتوى؟",     .en: "Refresh content?", .fr: "Actualiser le contenu ?", .tr: "İçerik yenilensin mi?", .es: "¿Actualizar contenido?"],
        "refresh.msg":      [.ar: "سيُجلب أحدث القنوات والأفلام والمسلسلات من مزوّدك. قد يستغرق بضع ثوانٍ.", .en: "Fetches the latest channels, movies and series from your provider. May take a few seconds.", .fr: "Récupère les dernières chaînes, films et séries de votre fournisseur. Peut prendre quelques secondes.", .tr: "Sağlayıcınızdan en yeni kanalları, filmleri ve dizileri getirir. Birkaç saniye sürebilir.", .es: "Obtiene los últimos canales, películas y series de tu proveedor. Puede tardar unos segundos."],
        "refresh.confirm":  [.ar: "تحديث",              .en: "Refresh",         .fr: "Actualiser",      .tr: "Yenile",          .es: "Actualizar"],

        // Login / Auth
        "login.welcome":    [.ar: "مرحباً بك — سجّل دخولك للمتابعة", .en: "Welcome — sign in to continue", .fr: "Bienvenue — connectez-vous pour continuer", .tr: "Hoş geldiniz — devam etmek için giriş yapın", .es: "Bienvenido — inicia sesión para continuar"],
        "login.username":   [.ar: "اسم المستخدم",       .en: "Username",        .fr: "Nom d'utilisateur",.tr: "Kullanıcı adı",  .es: "Nombre de usuario"],
        "login.password":   [.ar: "كلمة المرور",        .en: "Password",        .fr: "Mot de passe",    .tr: "Şifre",           .es: "Contraseña"],
        "login.m3u_hint":   [.ar: "ألصق رابط قائمة التشغيل M3U / M3U8 — يُحلَّل محلياً على جهازك", .en: "Paste an M3U / M3U8 playlist URL — parsed locally on your device", .fr: "Collez une URL de liste M3U / M3U8 — analysée localement sur votre appareil", .tr: "Bir M3U / M3U8 liste bağlantısı yapıştırın — cihazınızda yerel olarak işlenir", .es: "Pega una URL de lista M3U / M3U8 — se analiza localmente en tu dispositivo"],
        "login.signin":     [.ar: "تسجيل الدخول",       .en: "Sign In",         .fr: "Se connecter",    .tr: "Giriş Yap",       .es: "Iniciar sesión"],
        "login.load_playlist":[.ar: "تحميل قائمة التشغيل", .en: "Load Playlist", .fr: "Charger la liste", .tr: "Listeyi Yükle",  .es: "Cargar lista"],
        "login.advanced":   [.ar: "إعدادات متقدمة",     .en: "Advanced Settings", .fr: "Réglages avancés", .tr: "Gelişmiş Ayarlar", .es: "Ajustes avanzados"],
        "login.advanced_hint":[.ar: "يتصل مباشرةً بمزوّدك — أدخل رابط السيرفر واسم المستخدم وكلمة المرور", .en: "Connects directly to your provider — enter the server URL, username and password", .fr: "Se connecte directement à votre fournisseur — saisissez l'URL du serveur, l'identifiant et le mot de passe", .tr: "Sağlayıcınıza doğrudan bağlanır — sunucu adresini, kullanıcı adını ve şifreyi girin", .es: "Se conecta directamente a tu proveedor — introduce la URL del servidor, usuario y contraseña"],
        "login.server_ph":  [.ar: "http://server.com:8080", .en: "http://server.com:8080", .fr: "http://server.com:8080", .tr: "http://server.com:8080", .es: "http://server.com:8080"],
        "login.server_or_code":[.ar: "رابط السيرفر أو كود الموزّع", .en: "Server URL or reseller code", .fr: "URL du serveur ou code revendeur", .tr: "Sunucu adresi veya bayi kodu", .es: "URL del servidor o código de distribuidor"],
        "login.server_hint":[.ar: "من مزوّدك · مثال: http://host:8080", .en: "From your provider · e.g. http://host:8080", .fr: "De votre fournisseur · ex. http://host:8080", .tr: "Sağlayıcınızdan · örn. http://host:8080", .es: "De tu proveedor · ej. http://host:8080"],
        "login.demo":       [.ar: "تصفّح كنسخة تجريبية (Demo)", .en: "Browse as Demo", .fr: "Parcourir en mode démo", .tr: "Demo olarak gözat", .es: "Explorar en modo demo"],
        "login.need_help":  [.ar: "تحتاج مساعدة في التفعيل؟ تواصل مع الدعم", .en: "Need help activating? Contact support", .fr: "Besoin d'aide pour l'activation ? Contactez le support", .tr: "Etkinleştirmede yardım mı lazım? Destekle iletişime geçin", .es: "¿Necesitas ayuda para activar? Contacta con soporte"],
        "login.agree":      [.ar: "باستخدام التطبيق توافق على", .en: "By using the app you agree to", .fr: "En utilisant l'app, vous acceptez", .tr: "Uygulamayı kullanarak şunları kabul edersiniz", .es: "Al usar la app aceptas"],
        "login.and":        [.ar: "و",                  .en: "and",             .fr: "et",              .tr: "ve",              .es: "y"],
        "login.mode_m3u":   [.ar: "رابط M3U",           .en: "M3U URL",         .fr: "URL M3U",         .tr: "M3U Bağlantısı",  .es: "URL M3U"],
        "common.error":     [.ar: "خطأ",                .en: "Error",           .fr: "Erreur",          .tr: "Hata",            .es: "Error"],

        // Splash
        "splash.device_id": [.ar: "معرّف الجهاز",       .en: "Device ID",       .fr: "ID de l'appareil",.tr: "Cihaz Kimliği",   .es: "ID del dispositivo"],

        // Privacy policy
        "privacy.collect.t": [.ar: "المعلومات التي نجمعها", .en: "Information We Collect", .fr: "Informations que nous collectons", .tr: "Topladığımız Bilgiler", .es: "Información que recopilamos"],
        "privacy.collect.b": [.ar: "نجمع فقط بيانات تسجيل الدخول، معرّف الجهاز، وإحصاءات استخدام أساسية بموافقتك.", .en: "We only collect login data, your device ID, and basic usage analytics with your consent.", .fr: "Nous ne collectons que vos données de connexion, l'ID de l'appareil et des statistiques d'usage de base avec votre consentement.", .tr: "Yalnızca giriş verilerinizi, cihaz kimliğinizi ve onayınızla temel kullanım istatistiklerini topluyoruz.", .es: "Solo recopilamos datos de inicio de sesión, el ID del dispositivo y analítica de uso básica con tu consentimiento."],
        "privacy.use.t":     [.ar: "كيف نستخدم البيانات", .en: "How We Use Data", .fr: "Comment nous utilisons les données", .tr: "Verileri Nasıl Kullanırız", .es: "Cómo usamos los datos"],
        "privacy.use.b":     [.ar: "نستخدم البيانات لتوفير الخدمة وتحسين التطبيق وإرسال إشعارات متعلقة بحسابك فقط.", .en: "We use data to provide the service, improve the app, and send notifications related to your account only.", .fr: "Nous utilisons les données pour fournir le service, améliorer l'app et envoyer des notifications liées à votre compte uniquement.", .tr: "Verileri yalnızca hizmeti sunmak, uygulamayı geliştirmek ve hesabınızla ilgili bildirimler göndermek için kullanırız.", .es: "Usamos los datos solo para prestar el servicio, mejorar la app y enviar notificaciones relacionadas con tu cuenta."],
        "privacy.share.t":   [.ar: "مشاركة البيانات",   .en: "Data Sharing",    .fr: "Partage des données", .tr: "Veri Paylaşımı", .es: "Compartir datos"],
        "privacy.share.b":   [.ar: "لا نبيع ولا نشارك بياناتك الشخصية مع أي طرف ثالث تحت أي ظرف من الظروف.", .en: "We never sell or share your personal data with any third party under any circumstances.", .fr: "Nous ne vendons ni ne partageons jamais vos données personnelles avec un tiers, en aucune circonstance.", .tr: "Kişisel verilerinizi hiçbir koşulda üçüncü taraflarla satmaz veya paylaşmayız.", .es: "Nunca vendemos ni compartimos tus datos personales con terceros bajo ninguna circunstancia."],
        "privacy.security.t":[.ar: "أمان البيانات",     .en: "Data Security",   .fr: "Sécurité des données", .tr: "Veri Güvenliği", .es: "Seguridad de los datos"],
        "privacy.security.b":[.ar: "نحمي بيانات حسابك بتشفير كلمات المرور وتأمين الاتصال بخوادمنا. روابط البث التي تضيفها يتحكّم بها مزوّدك وقد تكون غير مشفّرة.", .en: "We protect your account data with password encryption and secured connections to our servers. Streaming links you add are controlled by your provider and may be unencrypted.", .fr: "Nous protégeons vos données de compte par le chiffrement des mots de passe et des connexions sécurisées à nos serveurs. Les liens de diffusion que vous ajoutez sont contrôlés par votre fournisseur et peuvent être non chiffrés.", .tr: "Hesap verilerinizi şifre şifrelemesi ve sunucularımıza güvenli bağlantılarla koruruz. Eklediğiniz yayın bağlantıları sağlayıcınız tarafından kontrol edilir ve şifresiz olabilir.", .es: "Protegemos los datos de tu cuenta con cifrado de contraseñas y conexiones seguras a nuestros servidores. Los enlaces de transmisión que añades los controla tu proveedor y pueden no estar cifrados."],
        "privacy.rights.t":  [.ar: "حقوقك",             .en: "Your Rights",     .fr: "Vos droits",      .tr: "Haklarınız",      .es: "Tus derechos"],
        "privacy.rights.b":  [.ar: "يمكنك حذف حسابك وجميع بياناتك في أي وقت من خلال إعدادات التطبيق.", .en: "You can delete your account and all your data at any time from the app settings.", .fr: "Vous pouvez supprimer votre compte et toutes vos données à tout moment depuis les réglages de l'app.", .tr: "Hesabınızı ve tüm verilerinizi istediğiniz zaman uygulama ayarlarından silebilirsiniz.", .es: "Puedes eliminar tu cuenta y todos tus datos en cualquier momento desde los ajustes de la app."],
        "privacy.content.t": [.ar: "المحتوى",           .en: "Content",         .fr: "Contenu",         .tr: "İçerik",          .es: "Contenido"],
        "privacy.content.b": [.ar: "التطبيق أداة تشغيل فقط. المستخدم مسؤول كلياً عن مشروعية المحتوى الذي يصل إليه.", .en: "The app is a player tool only. The user is fully responsible for the legality of the content they access.", .fr: "L'app n'est qu'un outil de lecture. L'utilisateur est entièrement responsable de la légalité du contenu auquel il accède.", .tr: "Uygulama yalnızca bir oynatıcı aracıdır. Eriştiği içeriğin yasallığından tamamen kullanıcı sorumludur.", .es: "La app es solo una herramienta de reproducción. El usuario es totalmente responsable de la legalidad del contenido al que accede."],
        "privacy.updated":   [.ar: "آخر تحديث: يونيو 2026", .en: "Last updated: June 2026", .fr: "Dernière mise à jour : juin 2026", .tr: "Son güncelleme: Haziran 2026", .es: "Última actualización: junio de 2026"],

        // Terms
        "terms.accept.t":    [.ar: "قبول الشروط",       .en: "Acceptance of Terms", .fr: "Acceptation des conditions", .tr: "Şartların Kabulü", .es: "Aceptación de los términos"],
        "terms.accept.b":    [.ar: "باستخدام تطبيق BLANK TV، فإنك تقبل هذه الشروط والأحكام بالكامل.", .en: "By using the BLANK TV app, you fully accept these terms and conditions.", .fr: "En utilisant l'application BLANK TV, vous acceptez pleinement ces conditions générales.", .tr: "BLANK TV uygulamasını kullanarak bu şartları ve koşulları tamamen kabul edersiniz.", .es: "Al usar la aplicación BLANK TV, aceptas plenamente estos términos y condiciones."],
        "terms.use.t":       [.ar: "الاستخدام المسموح", .en: "Permitted Use",   .fr: "Utilisation autorisée", .tr: "İzin Verilen Kullanım", .es: "Uso permitido"],
        "terms.use.b":       [.ar: "التطبيق مخصص للاستخدام الشخصي فقط. يُحظر إعادة التوزيع أو الاستخدام التجاري.", .en: "The app is for personal use only. Redistribution or commercial use is prohibited.", .fr: "L'app est réservée à un usage personnel. La redistribution ou l'usage commercial est interdit.", .tr: "Uygulama yalnızca kişisel kullanım içindir. Yeniden dağıtım veya ticari kullanım yasaktır.", .es: "La app es solo para uso personal. Se prohíbe la redistribución o el uso comercial."],
        "terms.content.t":   [.ar: "مسؤولية المحتوى",   .en: "Content Responsibility", .fr: "Responsabilité du contenu", .tr: "İçerik Sorumluluğu", .es: "Responsabilidad del contenido"],
        "terms.content.b":   [.ar: "المستخدم مسؤول مسؤولية تامة عن طبيعة ومشروعية المحتوى الذي يصل إليه.", .en: "The user is fully responsible for the nature and legality of the content they access.", .fr: "L'utilisateur est entièrement responsable de la nature et de la légalité du contenu auquel il accède.", .tr: "Kullanıcı, eriştiği içeriğin niteliği ve yasallığından tamamen sorumludur.", .es: "El usuario es totalmente responsable de la naturaleza y legalidad del contenido al que accede."],
        "terms.terminate.t": [.ar: "إنهاء الخدمة",      .en: "Termination",     .fr: "Résiliation",     .tr: "Fesih",           .es: "Terminación"],
        "terms.terminate.b": [.ar: "نحتفظ بحق إنهاء حسابك في حالة انتهاك هذه الشروط أو الاستخدام غير القانوني.", .en: "We reserve the right to terminate your account for violating these terms or for illegal use.", .fr: "Nous nous réservons le droit de résilier votre compte en cas de violation de ces conditions ou d'usage illégal.", .tr: "Bu şartların ihlali veya yasa dışı kullanım durumunda hesabınızı feshetme hakkımız saklıdır.", .es: "Nos reservamos el derecho de cancelar tu cuenta por incumplir estos términos o por uso ilegal."],
        "terms.changes.t":   [.ar: "التعديلات",         .en: "Changes",         .fr: "Modifications",   .tr: "Değişiklikler",   .es: "Cambios"],
        "terms.changes.b":   [.ar: "نحتفظ بحق تعديل هذه الشروط. الاستمرار في الاستخدام يعني قبول الشروط المحدّثة.", .en: "We reserve the right to modify these terms. Continued use means acceptance of the updated terms.", .fr: "Nous nous réservons le droit de modifier ces conditions. La poursuite de l'utilisation vaut acceptation des conditions mises à jour.", .tr: "Bu şartları değiştirme hakkımız saklıdır. Kullanmaya devam etmek, güncellenen şartların kabulü anlamına gelir.", .es: "Nos reservamos el derecho de modificar estos términos. El uso continuado implica la aceptación de los términos actualizados."],

        // Activation gate
        "actgate.checking": [.ar: "جارٍ التحقق من التفعيل…", .en: "Checking activation…", .fr: "Vérification de l'activation…", .tr: "Etkinleştirme kontrol ediliyor…", .es: "Comprobando activación…"],
        "maintenance.title":[.ar: "التطبيق في صيانة", .en: "Under maintenance", .fr: "En maintenance", .tr: "Bakımda", .es: "En mantenimiento"],
        "maintenance.message":[.ar: "نُجري تحديثات لتحسين الخدمة. يُرجى المحاولة بعد قليل.", .en: "We're making improvements. Please try again shortly.", .fr: "Nous effectuons des améliorations. Veuillez réessayer sous peu.", .tr: "İyileştirmeler yapıyoruz. Lütfen birazdan tekrar deneyin.", .es: "Estamos mejorando el servicio. Inténtalo de nuevo en breve."],
        "update.title":     [.ar: "تحديث مطلوب", .en: "Update required", .fr: "Mise à jour requise", .tr: "Güncelleme gerekli", .es: "Actualización requerida"],
        "update.message":   [.ar: "يجب تحديث التطبيق إلى أحدث إصدار للمتابعة.", .en: "Please update to the latest version to continue.", .fr: "Veuillez mettre à jour vers la dernière version pour continuer.", .tr: "Devam etmek için lütfen en son sürüme güncelleyin.", .es: "Actualiza a la última versión para continuar."],
        "update.latest":    [.ar: "أحدث إصدار:", .en: "Latest version:", .fr: "Dernière version :", .tr: "En son sürüm:", .es: "Última versión:"],
        "update.button":    [.ar: "تحديث الآن", .en: "Update now", .fr: "Mettre à jour", .tr: "Şimdi güncelle", .es: "Actualizar ahora"],
        "actgate.device_id":[.ar: "معرّف جهازك",        .en: "Your Device ID",  .fr: "ID de votre appareil", .tr: "Cihaz Kimliğiniz", .es: "ID de tu dispositivo"],
        "actgate.copied":   [.ar: "تم النسخ ✓",         .en: "Copied ✓",        .fr: "Copié ✓",         .tr: "Kopyalandı ✓",    .es: "Copiado ✓"],
        "actgate.copy_id":  [.ar: "نسخ المعرّف",        .en: "Copy ID",         .fr: "Copier l'ID",     .tr: "Kimliği Kopyala", .es: "Copiar ID"],
        "actgate.recheck":  [.ar: "تحقّق مرة أخرى",     .en: "Check Again",     .fr: "Vérifier à nouveau", .tr: "Tekrar Kontrol Et", .es: "Comprobar de nuevo"],
        "actgate.contact":  [.ar: "تواصل مع الدعم للتفعيل", .en: "Contact support to activate", .fr: "Contactez le support pour activer", .tr: "Etkinleştirmek için destekle iletişime geçin", .es: "Contacta con soporte para activar"],
        "actgate.demo":     [.ar: "تصفّح كنسخة تجريبية (Demo)", .en: "Browse as Demo", .fr: "Parcourir en mode démo", .tr: "Demo olarak gözat", .es: "Explorar en modo demo"],
        "actgate.blocked.title":  [.ar: "هذا الجهاز محظور", .en: "This device is blocked", .fr: "Cet appareil est bloqué", .tr: "Bu cihaz engellendi", .es: "Este dispositivo está bloqueado"],
        "actgate.offline.title":  [.ar: "تعذّر الاتصال", .en: "Connection failed", .fr: "Échec de la connexion", .tr: "Bağlantı başarısız", .es: "Error de conexión"],
        "actgate.notactive.title":[.ar: "الجهاز غير مُفعّل", .en: "Device not activated", .fr: "Appareil non activé", .tr: "Cihaz etkin değil", .es: "Dispositivo no activado"],
        "actgate.offline.msg":    [.ar: "تأكد من اتصالك بالإنترنت ثم أعد المحاولة.", .en: "Check your internet connection and try again.", .fr: "Vérifiez votre connexion Internet et réessayez.", .tr: "İnternet bağlantınızı kontrol edip tekrar deneyin.", .es: "Comprueba tu conexión a Internet e inténtalo de nuevo."],
        "actgate.blocked.msg":    [.ar: "تم حظر هذا الجهاز. تواصل مع موزّعك لمزيد من المعلومات.", .en: "This device has been blocked. Contact your reseller for more information.", .fr: "Cet appareil a été bloqué. Contactez votre revendeur pour plus d'informations.", .tr: "Bu cihaz engellendi. Daha fazla bilgi için bayinizle iletişime geçin.", .es: "Este dispositivo ha sido bloqueado. Contacta con tu distribuidor para más información."],
        "actgate.notactive.msg":  [.ar: "أرسل معرّف جهازك أعلاه إلى موزّعك لتفعيل التطبيق، ثم اضغط «تحقّق مرة أخرى».", .en: "Send the device ID above to your reseller to activate the app, then tap \"Check Again\".", .fr: "Envoyez l'ID de l'appareil ci-dessus à votre revendeur pour activer l'app, puis appuyez sur « Vérifier à nouveau ».", .tr: "Uygulamayı etkinleştirmek için yukarıdaki cihaz kimliğini bayinize gönderin, ardından \"Tekrar Kontrol Et\"e dokunun.", .es: "Envía el ID del dispositivo de arriba a tu distribuidor para activar la app y luego pulsa \"Comprobar de nuevo\"."],
        "trial.banner":     [.ar: "نسخة تجريبية",       .en: "Free Trial",      .fr: "Version d'essai", .tr: "Deneme Sürümü",   .es: "Versión de prueba"],

        // Content lists / empties
        "live.empty.title": [.ar: "لا توجد قنوات",      .en: "No channels",     .fr: "Aucune chaîne",   .tr: "Kanal yok",       .es: "Sin canales"],
        "live.empty.sub":   [.ar: "جرّب كلمات بحث مختلفة", .en: "Try different search terms", .fr: "Essayez d'autres termes", .tr: "Farklı arama terimleri deneyin", .es: "Prueba otros términos de búsqueda"],
        "cats.channels":    [.ar: "أقسام القنوات",      .en: "Channel Categories", .fr: "Catégories de chaînes", .tr: "Kanal Kategorileri", .es: "Categorías de canales"],
        "cats.movies":      [.ar: "أقسام الأفلام",      .en: "Movie Categories", .fr: "Catégories de films", .tr: "Film Kategorileri", .es: "Categorías de películas"],
        "cats.series":      [.ar: "أقسام المسلسلات",    .en: "Series Categories", .fr: "Catégories de séries", .tr: "Dizi Kategorileri", .es: "Categorías de series"],
        "cats.empty.title": [.ar: "لا أقسام",           .en: "No categories",   .fr: "Aucune catégorie",.tr: "Kategori yok",    .es: "Sin categorías"],
        "cats.empty.sub":   [.ar: "جرّب بحثاً مختلفاً", .en: "Try a different search", .fr: "Essayez une autre recherche", .tr: "Farklı bir arama deneyin", .es: "Prueba otra búsqueda"],
        "history.empty":    [.ar: "لا سجل مشاهدة",      .en: "No watch history", .fr: "Aucun historique", .tr: "İzleme geçmişi yok", .es: "Sin historial"],
        "history.empty.generic":[.ar: "لا سجل",         .en: "No history",      .fr: "Aucun historique",.tr: "Geçmiş yok",      .es: "Sin historial"],
        "history.empty.sub":[.ar: "سيظهر هنا ما تشاهده", .en: "What you watch will appear here", .fr: "Ce que vous regardez apparaîtra ici", .tr: "İzledikleriniz burada görünecek", .es: "Lo que veas aparecerá aquí"],
        "movies.empty":     [.ar: "لا توجد أفلام",      .en: "No movies",       .fr: "Aucun film",      .tr: "Film yok",        .es: "Sin películas"],
        "movies.empty.fav": [.ar: "لا أفلام في المفضّلة", .en: "No favorite movies", .fr: "Aucun film favori", .tr: "Favori film yok", .es: "Sin películas favoritas"],
        "series.empty":     [.ar: "لا توجد مسلسلات",    .en: "No series",       .fr: "Aucune série",    .tr: "Dizi yok",        .es: "Sin series"],
        "series.empty.fav": [.ar: "لا مسلسلات في المفضّلة", .en: "No favorite series", .fr: "Aucune série favorite", .tr: "Favori dizi yok", .es: "Sin series favoritas"],
        "grid.empty":       [.ar: "لا توجد عناصر",      .en: "No items",        .fr: "Aucun élément",   .tr: "Öğe yok",         .es: "Sin elementos"],
        "grid.empty.sub":   [.ar: "جرّب بحثاً أو تصنيفاً آخر", .en: "Try another search or category", .fr: "Essayez une autre recherche ou catégorie", .tr: "Başka bir arama veya kategori deneyin", .es: "Prueba otra búsqueda o categoría"],

        // Detail
        "detail.year":      [.ar: "سنة الإنتاج",        .en: "Year",            .fr: "Année",           .tr: "Yıl",             .es: "Año"],
        "detail.duration":  [.ar: "المدة",              .en: "Duration",        .fr: "Durée",           .tr: "Süre",            .es: "Duración"],
        "detail.rating":    [.ar: "التقييم",            .en: "Rating",          .fr: "Note",            .tr: "Puan",            .es: "Valoración"],
        "detail.genre":     [.ar: "التصنيف",            .en: "Genre",           .fr: "Genre",           .tr: "Tür",             .es: "Género"],
        "detail.director":  [.ar: "المخرج",             .en: "Director",        .fr: "Réalisateur",     .tr: "Yönetmen",        .es: "Director"],
        "detail.fav_added": [.ar: "في المفضلة",         .en: "In Favorites",    .fr: "Dans les favoris",.tr: "Favorilerde",     .es: "En favoritos"],
        "detail.fav_add":   [.ar: "إضافة للمفضلة",      .en: "Add to Favorites",.fr: "Ajouter aux favoris", .tr: "Favorilere Ekle", .es: "Añadir a favoritos"],

        // Search
        "search.title":     [.ar: "البحث",              .en: "Search",          .fr: "Recherche",       .tr: "Arama",           .es: "Buscar"],
        "search.prompt":    [.ar: "ابحث في القنوات والأفلام...", .en: "Search channels and movies…", .fr: "Rechercher chaînes et films…", .tr: "Kanal ve filmlerde ara…", .es: "Buscar canales y películas…"],
        "search.empty.title":[.ar: "لا توجد نتائج",     .en: "No results",      .fr: "Aucun résultat",  .tr: "Sonuç yok",       .es: "Sin resultados"],
        "search.empty.sub": [.ar: "جرب كلمات مختلفة",   .en: "Try different keywords", .fr: "Essayez d'autres mots-clés", .tr: "Farklı kelimeler deneyin", .es: "Prueba otras palabras"],
        "search.recent":    [.ar: "عمليات البحث الأخيرة", .en: "Recent searches", .fr: "Recherches récentes", .tr: "Son aramalar", .es: "Búsquedas recientes"],
        "search.clear_all": [.ar: "مسح الكل",           .en: "Clear All",       .fr: "Tout effacer",    .tr: "Tümünü Temizle",  .es: "Borrar todo"],
        "search.type.live": [.ar: "بث مباشر",           .en: "Live",            .fr: "En direct",       .tr: "Canlı",           .es: "En vivo"],
        "search.type.movie":[.ar: "فيلم",               .en: "Movie",           .fr: "Film",            .tr: "Film",            .es: "Película"],
        "search.type.series":[.ar: "مسلسل",             .en: "Series",          .fr: "Série",           .tr: "Dizi",            .es: "Serie"],
        "search.failed.title":[.ar: "تعذّر البحث",       .en: "Search failed",   .fr: "Échec de la recherche", .tr: "Arama başarısız", .es: "Error en la búsqueda"],
        "search.failed.sub": [.ar: "تحقّق من اتصالك وحاول مرة أخرى", .en: "Check your connection and try again", .fr: "Vérifiez votre connexion et réessayez", .tr: "Bağlantınızı kontrol edip tekrar deneyin", .es: "Revisa tu conexión e inténtalo de nuevo"],
        "search.start.title":[.ar: "ابدأ البحث",         .en: "Start searching", .fr: "Commencer la recherche", .tr: "Aramaya başla", .es: "Empieza a buscar"],
        "search.start.sub":  [.ar: "اختر القسم واكتب اسم ما تبحث عنه", .en: "Pick a section and type what you're looking for", .fr: "Choisissez une section et saisissez votre recherche", .tr: "Bir bölüm seçin ve aradığınızı yazın", .es: "Elige una sección y escribe lo que buscas"],

        // Subscription day-count sentences (composed: prefix + N day + suffix)
        "sub.days_left_prefix": [.ar: "تبقّى",          .en: "",                .fr: "Il reste",        .tr: "",                .es: "Quedan"],
        "sub.expire_suffix":    [.ar: "على انتهاء اشتراكك — جدّد الآن لتجنّب انقطاع الخدمة", .en: "left before your subscription expires — renew now to avoid interruption", .fr: "avant l'expiration de votre abonnement — renouvelez maintenant pour éviter toute interruption", .tr: "abonelik bitişine kaldı — kesintiyi önlemek için şimdi yenileyin", .es: "para que venza tu suscripción — renueva ahora para evitar la interrupción"],
        "sub.active_suffix":    [.ar: "على اشتراكك",    .en: "left on your subscription", .fr: "restant sur votre abonnement", .tr: "aboneliğinizde kaldı", .es: "en tu suscripción"],

        // App Store legal disclaimer (Guideline 4.3 / 5.x)
        "legal.disclaimer": [
            .ar: "تطبيق مشغّل فقط — لا يوفّر ولا يستضيف أي قنوات أو محتوى. المستخدم وحده مسؤول عن اشتراكه من مزوّد مرخّص وعن مشروعية المحتوى الذي يصل إليه.",
            .en: "A player only — it does not provide or host any channels or content. The user alone is responsible for their subscription from a licensed provider and for the legality of the content they access.",
            .fr: "Un lecteur uniquement — il ne fournit ni n'héberge aucune chaîne ou contenu. L'utilisateur est seul responsable de son abonnement auprès d'un fournisseur agréé et de la légalité du contenu auquel il accède.",
            .tr: "Yalnızca bir oynatıcı — herhangi bir kanal veya içerik sağlamaz ya da barındırmaz. Lisanslı bir sağlayıcıdan alınan abonelikten ve erişilen içeriğin yasallığından yalnızca kullanıcı sorumludur.",
            .es: "Solo un reproductor — no proporciona ni aloja ningún canal o contenido. El usuario es el único responsable de su suscripción con un proveedor autorizado y de la legalidad del contenido al que accede."
        ],
    ]
}

// MARK: ════════════════════════════════════════
// NETWORK — API CLIENT
// ════════════════════════════════════════════
enum APIConfig {
    // Legacy proxy endpoint (the Xtream-proxy login path is no longer used — all
    // login flows go DIRECT to the user's provider). Kept on HTTPS + the domain
    // so no raw cleartext-HTTP IP ships in the binary (App Store / security).
    static let primary  = "https://strong8k.app/api/v1"
    static let fallback = "https://strong8k.app/api/v1"
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
        case token, host, user, pass, userID, tokenExpiry, deviceID
    }

    /// Persistent device identity (survives app reinstall — stays in Keychain)
    var deviceID: String? {
        get { load(.deviceID) }
        set { newValue == nil ? delete(.deviceID) : save(.deviceID, value: newValue!) }
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
        [Key.token, Key.host, Key.user, Key.pass, Key.userID, Key.tokenExpiry].forEach { delete($0) }
    }

    // MARK: - Private CRUD
    private func save(_ key: Key, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecAttrService: service,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

    // MARK: - Turbo downloads (opt-in, OFF by default)
    // Parallel segmented download (multi-connection Range) for a big speedup on
    // servers that throttle per-connection. OFF by default because Xtream lines
    // limit simultaneous connections — moderate (3 segments) + auto-fallback.
    var turboDownloads: Bool {
        get { ud.bool(forKey: "s8k.turboDownloads") }
        set { ud.set(newValue, forKey: "s8k.turboDownloads") }
    }
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
    var m3uURL: String? {
        get { ud.string(forKey: K.m3uURL.rawValue) }
        set {
            if let v = newValue { ud.set(v, forKey: K.m3uURL.rawValue) }
            else { ud.removeObject(forKey: K.m3uURL.rawValue) }
        }
    }

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
        [K.userInfo, K.serverInfo, K.theme, K.features,
         K.appConfig, K.lastConfigFetch, K.m3uURL, K.loginMode].forEach {
            ud.removeObject(forKey: $0.rawValue)
        }
    }
    func clearAll() {
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
    let url:   String
}

struct M3UContent {
    var channels:         [Channel]  = []
    var liveCategories:   [Category] = []
    var movies:           [Movie]    = []
    var movieCategories:  [Category] = []
    var series:           [Series]   = []
    var seriesCategories: [Category] = []
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
                    epgChannelID: nil,
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
    static func load(scope: String) -> M3UContent? {
        guard let url = fileURL(scope), let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              Date().timeIntervalSince1970 - env.savedAt < ttl else { return nil }
        let c = content(from: env)
        return (c.channels.isEmpty && c.movies.isEmpty && c.series.isEmpty) ? nil : c
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
        guard let urlString = Store.shared.m3uURL,
              let url = URL(string: urlString) else {
            throw AppError.server("لا يوجد رابط قائمة تشغيل محفوظ")
        }

        // Instant cold-start: serve the last good catalog from disk immediately
        // (within TTL) instead of blocking on a full network parse. A refresh
        // (pull-to-refresh / playlist switch) passes force:true to bypass this.
        if !force, let cached = CatalogDiskCache.load(scope: urlString) {
            content = cached
            // Re-parse credentials (pure string work, no network) so lazy
            // series episodes / movie detail still resolve in Xtream-direct mode.
            if let xd = XtreamDirect.parse(urlString) { xtream = xd }
            return cached
        }

        // get.php / player_api.php link → talk to the Xtream API directly
        // (panels like this block M3U export but the API works fine)
        if let xd = XtreamDirect.parse(urlString) {
            let built = try await loadXtreamDirect(xd)
            xtream  = xd
            content = built
            CatalogDiskCache.save(built, scope: urlString)
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
        content = parsed
        CatalogDiskCache.save(parsed, scope: urlString)
        return parsed
    }

    private func bodyLooksLikeM3U(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(4096), encoding: .utf8)
                ?? String(data: data.prefix(4096), encoding: .isoLatin1) else { return false }
        return head.contains("#EXTM3U") || head.contains("#EXTINF")
    }

    func reset() { content = nil; xtream = nil; epgCache = [:] }

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
    private static let epgDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private func epgTime(_ any: Any?) -> Date? {
        if let i = intVal(any), i > 1_000_000 { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let s = str(any) {
            if let i = Int(s), i > 1_000_000 { return Date(timeIntervalSince1970: TimeInterval(i)) }
            return Self.epgDateFormatter.date(from: s)
        }
        return nil
    }

    private static func decodeB64(_ s: String?) -> String? {
        guard let s, let data = Data(base64Encoded: s),
              let text = String(data: data, encoding: .utf8) else { return nil }
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
        let liveCats = dictArray(try await liveCatsData)
        let vodCats  = dictArray(try await vodCatsData)
        let serCats  = dictArray(try await serCatsData)

        func toCategories(_ raw: [[String: Any]]) -> [Category] {
            raw.compactMap { d in
                guard let id = str(d["category_id"]), let name = str(d["category_name"]) else { return nil }
                return Category(id: id, name: name, parentID: nil)
            }
        }
        c.liveCategories   = toCategories(liveCats)
        c.movieCategories  = toCategories(vodCats)
        c.seriesCategories = toCategories(serCats)
        let liveCatName = Dictionary(uniqueKeysWithValues: c.liveCategories.map { ($0.id, $0.name) })

        // 3. Streams — live / VOD / series are independent lists; fetch CONCURRENTLY
        // so login waits ~one slow call instead of the sum of all three.
        async let liveStreamsData = apiData(xd, action: "get_live_streams")
        async let vodStreamsData  = apiData(xd, action: "get_vod_streams")
        async let seriesData      = apiData(xd, action: "get_series")
        let liveStreams = dictArray(try await liveStreamsData)
        let vodStreams  = dictArray(try await vodStreamsData)
        let seriesList  = dictArray(try await seriesData)

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

    /// Episodes for one series (Xtream-direct mode) — get_series_info
    func seasons(seriesID: String) async throws -> [Season] {
        if xtream == nil { _ = try await load() } // ensure credentials are parsed
        guard let xd = xtream else { return [] }
        let data = try await apiData(xd, action: "get_series_info&series_id=\(seriesID)")
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }

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
            directURL: movie.directURL
        )
    }
}

// MARK: ════════════════════════════════════════
// CONTENT SERVICE — Unified facade (Xtream OR M3U)
// ════════════════════════════════════════════
enum ContentService {
    static var mode: LoginMode { Store.shared.loginMode }
    static var isDemo: Bool { Store.shared.demoMode }

    static func liveCategories() async throws -> [Category] {
        if isDemo { return DemoContent.liveCategories }
        if mode == .m3u { return try await PlaylistService.shared.load().liveCategories }
        return try await XtreamService.shared.fetchLiveCategories()
    }
    static func liveStreams() async throws -> [Channel] {
        if isDemo { return DemoContent.channels }
        if mode == .m3u { return try await PlaylistService.shared.load().channels }
        return try await XtreamService.shared.fetchLiveStreams()
    }
    static func vodCategories() async throws -> [Category] {
        if isDemo { return DemoContent.movieCategories }
        if mode == .m3u { return try await PlaylistService.shared.load().movieCategories }
        return try await XtreamService.shared.fetchVODCategories()
    }
    static func movies() async throws -> [Movie] {
        if isDemo { return DemoContent.movies }
        if mode == .m3u { return try await PlaylistService.shared.load().movies }
        return try await XtreamService.shared.fetchMovies()
    }
    static func seriesCategories() async throws -> [Category] {
        if isDemo { return DemoContent.seriesCategories }
        if mode == .m3u { return try await PlaylistService.shared.load().seriesCategories }
        return try await XtreamService.shared.fetchSeriesCategories()
    }
    static func series() async throws -> [Series] {
        if isDemo { return DemoContent.series }
        if mode == .m3u { return try await PlaylistService.shared.load().series }
        return try await XtreamService.shared.fetchSeries()
    }
    /// Full movie metadata for the detail screen (cast/crew/year/plot).
    static func movieDetail(_ movie: Movie) async throws -> Movie {
        if isDemo { return movie }
        if mode == .m3u { return try await PlaylistService.shared.movieInfo(movie) }
        return try await XtreamService.shared.fetchMovieDetail(id: movie.id)
    }

    static func seasons(of series: Series) async throws -> [Season] {
        if isDemo { return series.seasons }
        if mode == .m3u {
            // Raw M3U playlists embed seasons; Xtream-direct fetches them lazily
            if !series.seasons.isEmpty { return series.seasons }
            return try await PlaylistService.shared.seasons(seriesID: series.id)
        }
        return try await XtreamService.shared.fetchSeriesDetail(id: series.id).sortedSeasons
    }

    /// Now/next program guide for a live channel. Empty when unavailable (raw
    /// M3U, demo, or no EPG on the provider) — the UI hides the guide then.
    static func epg(for channel: Channel) async -> [EPGProgram] {
        if isDemo { return [] }
        if mode == .m3u { return await PlaylistService.shared.shortEPG(streamID: channel.id) }
        return (try? await XtreamService.shared.fetchEPG(channelID: channel.id)) ?? []
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
    // --- Videos (verified live; play in MobileVLCKit) ---
    private static let hls   = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    private static let hls2  = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    private static let bunny = "https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_720p_h264.mov"
    private static let sintel = "https://download.blender.org/durian/trailer/sintel_trailer-720p.mp4"
    private static let steel = "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov"
    private static let ed    = "https://upload.wikimedia.org/wikipedia/commons/8/83/Elephants_Dream_%28high_quality%29.ogv"

    // --- Artwork: a DISTINCT vertical poster (2:3) AND a distinct wide backdrop
    // per title (never the same image twice), so cards fill cleanly and the
    // detail header isn't the poster overlapping itself. All Blender open-movie
    // / Wikimedia Commons / Internet Archive assets, verified 200. ---
    private static let pBunny  = "https://commons.wikimedia.org/wiki/Special:FilePath/Big_buck_bunny_poster_big.jpg"
    private static let pSintel = "https://commons.wikimedia.org/wiki/Special:FilePath/Sintel_poster.jpg"
    private static let pSteel  = "https://commons.wikimedia.org/wiki/Special:FilePath/Tos-poster.png"
    private static let pED     = "https://archive.org/services/img/ElephantsDream"
    private static let pSeries = "https://commons.wikimedia.org/wiki/Special:FilePath/Sintel_Poster_Paintover_clean.jpg"
    private static let bBunny  = "https://commons.wikimedia.org/wiki/Special:FilePath/Big_Buck_Bunny_-_forest.jpg"
    private static let bSintel = "https://commons.wikimedia.org/wiki/Special:FilePath/Sintel-hand.png"
    private static let bSteel  = "https://commons.wikimedia.org/wiki/Special:FilePath/Blendertof3.jpg"
    private static let bED     = "https://commons.wikimedia.org/wiki/Special:FilePath/Elephants_Dream_s1_proog.jpg"

    static let liveCategories = [Category(id: "demo_live", name: "تجريبي", parentID: nil)]
    static let movieCategories = [Category(id: "demo_vod", name: "أفلام تجريبية", parentID: nil)]
    static let seriesCategories = [Category(id: "demo_series", name: "مسلسلات تجريبية", parentID: nil)]

    static let channels: [Channel] = [
        Channel(id: "d1", name: "BLANK TV — قناة العرض", logoURL: pBunny,
                groupTitle: "تجريبي", epgChannelID: nil, directURL: hls),
        Channel(id: "d2", name: "Demo Live 4K", logoURL: pSintel,
                groupTitle: "تجريبي", epgChannelID: nil, directURL: hls2),
        Channel(id: "d3", name: "Nature HD (تجريبي)", logoURL: pSteel,
                groupTitle: "تجريبي", epgChannelID: nil, directURL: bunny),
    ]

    static let movies: [Movie] = [
        demoMovie("d_m1", "Big Buck Bunny", bunny, "2008", "8.1", pBunny, bBunny,
                  "فيلم رسوم متحركة قصير مفتوح المصدر من مؤسسة Blender — محتوى تجريبي للعرض."),
        demoMovie("d_m2", "Sintel", sintel, "2010", "7.6", pSintel, bSintel,
                  "فيلم خيالي قصير من مشروع Blender المفتوح — محتوى تجريبي."),
        demoMovie("d_m3", "Tears of Steel", steel, "2012", "7.2", pSteel, bSteel,
                  "فيلم خيال علمي قصير مفتوح المصدر — محتوى تجريبي."),
        demoMovie("d_m4", "Elephants Dream", ed, "2006", "7.0", pED, bED,
                  "أول فيلم مفتوح المصدر من مؤسسة Blender — محتوى تجريبي.", "ogv"),
    ]

    static let series: [Series] = [
        Series(id: "d_s1", name: "BLANK TV Originals (تجريبي)", coverURL: pSeries,
               backdropURL: bBunny, year: "2024", rating: "9.0", genre: "عرض",
               plot: "مسلسل تجريبي يعرض ميزات المشغّل بحلقات من محتوى مفتوح المصدر.",
               cast: nil, director: nil, categoryID: "demo_series",
               seasons: [
                Season(id: "d_s1_1", seasonNumber: 1, name: "الموسم 1", episodes: [
                    demoEpisode("d_e1", "الحلقة التجريبية الأولى", 1, bunny),
                    demoEpisode("d_e2", "الحلقة التجريبية الثانية", 2, sintel),
                    demoEpisode("d_e3", "الحلقة التجريبية الثالثة", 3, steel),
                ])
               ]),
    ]

    private static func demoMovie(_ id: String, _ name: String, _ url: String,
                                  _ year: String, _ rating: String,
                                  _ poster: String, _ backdrop: String,
                                  _ plot: String, _ ext: String = "mp4") -> Movie {
        Movie(id: id, name: name, posterURL: poster, backdropURL: backdrop,
              year: year, rating: rating, genre: "تجريبي", plot: plot,
              duration: "10 دقائق", director: "Blender Foundation", cast: nil,
              categoryID: "demo_vod", containerExtension: ext, directURL: url)
    }
    private static func demoEpisode(_ id: String, _ title: String, _ num: Int, _ url: String) -> Episode {
        Episode(id: id, title: title, episodeNumber: num, seasonNumber: 1,
                containerExtension: "mp4", posterURL: nil, plot: nil,
                duration: "10 دقائق", directURL: url)
    }
}
