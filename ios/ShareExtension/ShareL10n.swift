import Foundation

enum ShareL10n {
  static let en: [String: String] = [
    "share_title": "Share to Remdy",
    "share_tab_chats": "Chats",
    "share_tab_groups": "My groups",
    "share_search": "Search by name",
    "share_cancel": "Cancel",
    "share_loading": "Loading…",
    "share_sending": "Sending…",
    "share_sent": "Sent",
    "share_failed": "Could not send.",
    "share_retry": "Try again",
    "share_empty_chats": "No chats yet.",
    "share_empty_groups": "No groups yet.",
    "share_no_permission": "Unavailable",
    "share_need_login": "Open Remdy and sign in to enable sharing.",
    "share_offline": "No internet connection.",
    "share_one_photo": "1 photo",
    "share_n_photos": "{n} photos",
    "share_members": "{n} members",
  ]

  static let ptBR: [String: String] = [
    "share_title": "Compartilhar no Remdy",
    "share_tab_chats": "Conversas",
    "share_tab_groups": "Meus grupos",
    "share_search": "Pesquisar pelo nome",
    "share_cancel": "Cancelar",
    "share_loading": "Carregando…",
    "share_sending": "Enviando…",
    "share_sent": "Enviado",
    "share_failed": "Não foi possível enviar.",
    "share_retry": "Tentar novamente",
    "share_empty_chats": "Nenhuma conversa.",
    "share_empty_groups": "Nenhum grupo.",
    "share_no_permission": "Indisponível",
    "share_need_login": "Abra a Remdy e entre na sua conta para ativar o compartilhamento.",
    "share_offline": "Sem conexão com a internet.",
    "share_one_photo": "1 foto",
    "share_n_photos": "{n} fotos",
    "share_members": "{n} participantes",
  ]

  static let ptPT: [String: String] = [
    "share_title": "Partilhar no Remdy",
    "share_tab_chats": "Conversas",
    "share_tab_groups": "Os meus grupos",
    "share_search": "Pesquisar pelo nome",
    "share_cancel": "Cancelar",
    "share_loading": "A carregar…",
    "share_sending": "A enviar…",
    "share_sent": "Enviado",
    "share_failed": "Não foi possível enviar.",
    "share_retry": "Tentar novamente",
    "share_empty_chats": "Nenhuma conversa.",
    "share_empty_groups": "Nenhum grupo.",
    "share_no_permission": "Indisponível",
    "share_need_login": "Abra a Remdy e inicie sessão para ativar a partilha.",
    "share_offline": "Sem ligação à internet.",
    "share_one_photo": "1 foto",
    "share_n_photos": "{n} fotos",
    "share_members": "{n} participantes",
  ]

  static let es: [String: String] = [
    "share_title": "Compartir en Remdy",
    "share_tab_chats": "Chats",
    "share_tab_groups": "Mis grupos",
    "share_search": "Buscar por nombre",
    "share_cancel": "Cancelar",
    "share_loading": "Cargando…",
    "share_sending": "Enviando…",
    "share_sent": "Enviado",
    "share_failed": "No se pudo enviar.",
    "share_retry": "Intentar de nuevo",
    "share_empty_chats": "No hay chats.",
    "share_empty_groups": "No hay grupos.",
    "share_no_permission": "No disponible",
    "share_need_login": "Abre Remdy e inicia sesión para activar el compartido.",
    "share_offline": "Sin conexión a internet.",
    "share_one_photo": "1 foto",
    "share_n_photos": "{n} fotos",
    "share_members": "{n} participantes",
  ]

  static let fr: [String: String] = [
    "share_title": "Partager dans Remdy",
    "share_tab_chats": "Discussions",
    "share_tab_groups": "Mes groupes",
    "share_search": "Rechercher par nom",
    "share_cancel": "Annuler",
    "share_loading": "Chargement…",
    "share_sending": "Envoi…",
    "share_sent": "Envoyé",
    "share_failed": "Envoi impossible.",
    "share_retry": "Réessayer",
    "share_empty_chats": "Aucune discussion.",
    "share_empty_groups": "Aucun groupe.",
    "share_no_permission": "Indisponible",
    "share_need_login": "Ouvrez Remdy et connectez-vous pour activer le partage.",
    "share_offline": "Pas de connexion Internet.",
    "share_one_photo": "1 photo",
    "share_n_photos": "{n} photos",
    "share_members": "{n} membres",
  ]

  static func table(for lang: String) -> [String: String] {
    if lang.hasPrefix("pt-pt") || lang.hasPrefix("pt_pt") { return ptPT }
    if lang.hasPrefix("pt") { return ptBR }
    if lang.hasPrefix("es") { return es }
    if lang.hasPrefix("fr") { return fr }
    return en
  }
}
