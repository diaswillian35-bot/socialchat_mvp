import Foundation

enum ShareL10n {
  static let en: [String: String] = [
    "share_title": "Share to Remdy",
    "share_tab_chats": "Chats",
    "share_tab_groups": "My groups",
    "share_search": "Search by name",
    "share_send": "Send",
    "share_cancel": "Cancel",
    "share_loading": "Loading…",
    "share_sending": "Sending…",
    "share_sent": "Sent",
    "share_failed": "Could not send. Try again.",
    "share_empty": "No destinations found.",
    "share_no_permission": "Unavailable",
    "share_need_login": "Open Remdy and sign in to enable sharing.",
    "share_retry": "Something went wrong. Try again.",
  ]

  static let ptBR: [String: String] = [
    "share_title": "Compartilhar no Remdy",
    "share_tab_chats": "Conversas",
    "share_tab_groups": "Meus grupos",
    "share_search": "Pesquisar pelo nome",
    "share_send": "Enviar",
    "share_cancel": "Cancelar",
    "share_loading": "Carregando…",
    "share_sending": "Enviando…",
    "share_sent": "Enviado",
    "share_failed": "Não foi possível enviar. Tente de novo.",
    "share_empty": "Nenhum destino encontrado.",
    "share_no_permission": "Indisponível",
    "share_need_login": "Abra o Remdy e faça login para ativar o compartilhamento.",
    "share_retry": "Algo deu errado. Tente de novo.",
  ]

  static let ptPT: [String: String] = [
    "share_title": "Partilhar no Remdy",
    "share_tab_chats": "Conversas",
    "share_tab_groups": "Os meus grupos",
    "share_search": "Pesquisar pelo nome",
    "share_send": "Enviar",
    "share_cancel": "Cancelar",
    "share_loading": "A carregar…",
    "share_sending": "A enviar…",
    "share_sent": "Enviado",
    "share_failed": "Não foi possível enviar. Tente novamente.",
    "share_empty": "Nenhum destino encontrado.",
    "share_no_permission": "Indisponível",
    "share_need_login": "Abra o Remdy e inicie sessão para ativar a partilha.",
    "share_retry": "Algo correu mal. Tente novamente.",
  ]

  static let es: [String: String] = [
    "share_title": "Compartir en Remdy",
    "share_tab_chats": "Chats",
    "share_tab_groups": "Mis grupos",
    "share_search": "Buscar por nombre",
    "share_send": "Enviar",
    "share_cancel": "Cancelar",
    "share_loading": "Cargando…",
    "share_sending": "Enviando…",
    "share_sent": "Enviado",
    "share_failed": "No se pudo enviar. Inténtalo de nuevo.",
    "share_empty": "No se encontraron destinos.",
    "share_no_permission": "No disponible",
    "share_need_login": "Abre Remdy e inicia sesión para activar el compartido.",
    "share_retry": "Algo salió mal. Inténtalo de nuevo.",
  ]

  static let fr: [String: String] = [
    "share_title": "Partager dans Remdy",
    "share_tab_chats": "Discussions",
    "share_tab_groups": "Mes groupes",
    "share_search": "Rechercher par nom",
    "share_send": "Envoyer",
    "share_cancel": "Annuler",
    "share_loading": "Chargement…",
    "share_sending": "Envoi…",
    "share_sent": "Envoyé",
    "share_failed": "Envoi impossible. Réessayez.",
    "share_empty": "Aucune destination trouvée.",
    "share_no_permission": "Indisponible",
    "share_need_login": "Ouvrez Remdy et connectez-vous pour activer le partage.",
    "share_retry": "Une erreur s’est produite. Réessayez.",
  ]

  static func table(for lang: String) -> [String: String] {
    if lang.hasPrefix("pt-pt") || lang.hasPrefix("pt_pt") { return ptPT }
    if lang.hasPrefix("pt") { return ptBR }
    if lang.hasPrefix("es") { return es }
    if lang.hasPrefix("fr") { return fr }
    return en
  }
}
