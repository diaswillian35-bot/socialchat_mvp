import 'package:flutter/widgets.dart';

import 'models/place_listing.dart';

class LocaisStrings {
  const LocaisStrings._(this.code);

  final String code;

  /// Só para testes. O app deixa nulo e usa o idioma do aparelho.
  static Locale? debugLocale;

  static void resetDebugLocale() {
    debugLocale = null;
  }

  factory LocaisStrings.of(BuildContext context) {
    return LocaisStrings.fromLocale(
      debugLocale ?? Localizations.localeOf(context),
    );
  }

  factory LocaisStrings.fromLocale(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    final country = (locale.countryCode ?? '').toUpperCase();
    if (lang == 'pt' && country == 'PT') return const LocaisStrings._('pt-PT');
    if (lang == 'pt') return const LocaisStrings._('pt');
    if (lang == 'es') return const LocaisStrings._('es');
    if (lang == 'fr') return const LocaisStrings._('fr');
    return const LocaisStrings._('en');
  }

  String get tabLabel =>
      _t(pt: 'Locais', en: 'Places', es: 'Lugares', fr: 'Lieux');

  String get title => tabLabel;

  String get subtitle => _t(
        pt: 'Restaurantes, bares, cafés e hospedagem perto de você',
        ptPt: 'Restaurantes, bares, cafés e alojamento perto de si',
        en: 'Restaurants, bars, cafés and stays near you',
        es: 'Restaurantes, bares, cafés y alojamiento cerca de ti',
        fr: 'Restaurants, bars, cafés et hébergements près de vous',
      );

  String get searchHint => _t(
        pt: 'Buscar cidade ou região',
        ptPt: 'Procurar cidade ou região',
        en: 'Search city or region',
        es: 'Buscar ciudad o región',
        fr: 'Rechercher une ville ou une région',
      );

  String get searchLabel => searchHint;

  String get categoryAll => _t(pt: 'Todos', en: 'All', es: 'Todos', fr: 'Tous');

  String categoryName(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.restaurant:
        return _t(
          pt: 'Restaurante',
          en: 'Restaurant',
          es: 'Restaurante',
          fr: 'Restaurant',
        );
      case PlaceCategory.bar:
        return _t(pt: 'Bar', en: 'Bar', es: 'Bar', fr: 'Bar');
      case PlaceCategory.cafe:
        return _t(pt: 'Café', en: 'Café', es: 'Café', fr: 'Café');
      case PlaceCategory.hotel:
        return _t(pt: 'Hotel', en: 'Hotel', es: 'Hotel', fr: 'Hôtel');
      case PlaceCategory.pousada:
        return _t(
          pt: 'Pousada',
          ptPt: 'Pousada',
          en: 'Inn',
          es: 'Posada',
          fr: 'Auberge',
        );
      case PlaceCategory.nightclub:
        return _t(
          pt: 'Casa noturna',
          ptPt: 'Casa noturna',
          en: 'Nightclub',
          es: 'Discoteca',
          fr: 'Boîte de nuit',
        );
    }
  }

  String get openNow =>
      _t(pt: 'Aberto', en: 'Open', es: 'Abierto', fr: 'Ouvert');

  String get closed =>
      _t(pt: 'Fechado', en: 'Closed', es: 'Cerrado', fr: 'Fermé');

  String get filter =>
      _t(pt: 'Filtros', en: 'Filters', es: 'Filtros', fr: 'Filtres');

  String get filterTitle => filter;

  String get openNowFilter => _t(
        pt: 'Aberto agora',
        en: 'Open now',
        es: 'Abierto ahora',
        fr: 'Ouvert maintenant',
      );

  String get minRatingAny => _t(
        pt: 'Qualquer nota',
        ptPt: 'Qualquer classificação',
        en: 'Any rating',
        es: 'Cualquier nota',
        fr: 'Toutes les notes',
      );

  String get minRating4 => _t(pt: '4,0+', en: '4.0+', es: '4,0+', fr: '4,0+');

  String get minRating45 => _t(pt: '4,5+', en: '4.5+', es: '4,5+', fr: '4,5+');

  String get wheelchair => _t(
        pt: 'Entrada acessível',
        en: 'Accessible entrance',
        es: 'Entrada accesible',
        fr: 'Entrée accessible',
      );

  String get apply =>
      _t(pt: 'Aplicar', en: 'Apply', es: 'Aplicar', fr: 'Appliquer');

  String get clearFilters => _t(
        pt: 'Limpar filtros',
        en: 'Clear filters',
        es: 'Limpiar filtros',
        fr: 'Effacer les filtres',
      );

  String get listView => _t(pt: 'Lista', en: 'List', es: 'Lista', fr: 'Liste');

  String get mapView => _t(pt: 'Mapa', en: 'Map', es: 'Mapa', fr: 'Carte');

  String get loading => _t(
        pt: 'Carregando locais',
        ptPt: 'A carregar locais',
        en: 'Loading places',
        es: 'Cargando lugares',
        fr: 'Chargement des lieux',
      );

  String get emptyTitle => _t(
        pt: 'Nenhum local nesta busca',
        ptPt: 'Nenhum local nesta procura',
        en: 'No places in this search',
        es: 'Ningún lugar en esta búsqueda',
        fr: 'Aucun lieu dans cette recherche',
      );

  String get emptyBody => _t(
        pt: 'Tente outra cidade, região ou filtro.',
        en: 'Try another city, region or filter.',
        es: 'Prueba otra ciudad, región o filtro.',
        fr: 'Essayez une autre ville, région ou un autre filtre.',
      );

  String get errorTitle => _t(
        pt: 'Não foi possível carregar os locais',
        ptPt: 'Não foi possível carregar os locais',
        en: 'Places could not be loaded',
        es: 'No se pudieron cargar los lugares',
        fr: 'Impossible de charger les lieux',
      );

  String get retry => _t(
        pt: 'Tentar novamente',
        en: 'Try again',
        es: 'Intentar de nuevo',
        fr: 'Réessayer',
      );

  String get description => _t(
        pt: 'Descrição',
        en: 'Description',
        es: 'Descripción',
        fr: 'Description',
      );

  String get address => _t(
        pt: 'Endereço',
        ptPt: 'Morada',
        en: 'Address',
        es: 'Dirección',
        fr: 'Adresse',
      );
  String get linkOpenFailed => _t(
        pt: 'Não foi possível abrir o link',
        ptPt: 'Não foi possível abrir a ligação',
        en: 'Could not open the link',
        es: 'No se pudo abrir el enlace',
        fr: "Impossible d'ouvrir le lien",
      );

  String get route => _t(
      pt: 'Como chegar',
      ptPt: 'Como chegar',
      en: 'Directions',
      es: 'Cómo llegar',
      fr: 'Itinéraire');

  String get contact => _t(
        pt: 'Contato',
        ptPt: 'Contacto',
        en: 'Contact',
        es: 'Contacto',
        fr: 'Contact',
      );

  String get phone =>
      _t(pt: 'Telefone', en: 'Phone', es: 'Teléfono', fr: 'Téléphone');

  String get website => _t(pt: 'Site', en: 'Website', es: 'Sitio', fr: 'Site');

  String get instagram => 'Instagram';

  String get hours => _t(
        pt: 'Horários',
        ptPt: 'Horários',
        en: 'Hours',
        es: 'Horarios',
        fr: 'Horaires',
      );

  String get today => _t(pt: 'Hoje', en: 'Today', es: 'Hoy', fr: 'Aujourd’hui');

  String get closedToday => _t(
        pt: 'Fechado neste dia',
        en: 'Closed this day',
        es: 'Cerrado este día',
        fr: 'Fermé ce jour-là',
      );

  String get accessibility => _t(
        pt: 'Acessibilidade',
        en: 'Accessibility',
        es: 'Accesibilidad',
        fr: 'Accessibilité',
      );

  String get wheelchairEntrance => wheelchair;

  String get stepFree => _t(
        pt: 'Percurso sem degrau',
        en: 'Step-free route',
        es: 'Recorrido sin escalón',
        fr: 'Parcours sans marche',
      );

  String get accessibleRestroom => _t(
        pt: 'Banheiro acessível',
        ptPt: 'Casa de banho acessível',
        en: 'Accessible restroom',
        es: 'Baño accesible',
        fr: 'Toilettes accessibles',
      );

  String get reviews => _t(
        pt: 'Avaliações',
        ptPt: 'Avaliações',
        en: 'Reviews',
        es: 'Reseñas',
        fr: 'Avis',
      );

  String get noReviews => _t(
        pt: 'Ainda não há comentários.',
        en: 'No comments yet.',
        es: 'Todavía no hay comentarios.',
        fr: 'Pas encore de commentaires.',
      );

  String get ownerReply => _t(
        pt: 'Resposta do estabelecimento',
        ptPt: 'Resposta do estabelecimento',
        en: 'Response from the place',
        es: 'Respuesta del establecimiento',
        fr: 'Réponse de l’établissement',
      );

  String get writeReview => _t(
      pt: 'Avaliar este local',
      en: 'Review this place',
      es: 'Evaluar este lugar',
      fr: 'Évaluer ce lieu');
  String get reviewComment =>
      _t(pt: 'Comentário', en: 'Comment', es: 'Comentario', fr: 'Commentaire');
  String get sendReview => _t(
      pt: 'Enviar avaliação',
      en: 'Send review',
      es: 'Enviar evaluación',
      fr: 'Envoyer l’avis');
  String get reviewPending => _t(
      pt: 'Avaliação enviada para análise.',
      en: 'Review sent for moderation.',
      es: 'Evaluación enviada a moderación.',
      fr: 'Avis envoyé à la modération.');
  String get requiredPending =>
      _t(pt: 'Pendente', en: 'Required', es: 'Pendiente', fr: 'Requis');
  String get claimPlace => _t(
      pt: 'Reivindicar este local',
      en: 'Claim this place',
      es: 'Reclamar este lugar',
      fr: 'Revendiquer ce lieu');
  String get claimPhone => _t(
      pt: 'Telefone de contato',
      en: 'Contact phone',
      es: 'Teléfono de contacto',
      fr: 'Téléphone de contact');
  String get claimNote => _t(
      pt: 'Explique sua relação com o local',
      en: 'Explain your relationship with the place',
      es: 'Explique su relación con el lugar',
      fr: 'Expliquez votre lien avec le lieu');
  String get claimSent => _t(
      pt: 'Pedido enviado para aprovação da Remdy.',
      en: 'Claim sent for Remdy approval.',
      es: 'Solicitud enviada para aprobación de Remdy.',
      fr: 'Demande envoyée à Remdy pour approbation.');
  String get menu =>
      _t(pt: 'Cardápio', ptPt: 'Menu', en: 'Menu', es: 'Menú', fr: 'Menu');
  String get menuPdf => _t(
      pt: 'Abrir cardápio em PDF',
      ptPt: 'Abrir menu em PDF',
      en: 'Open menu PDF',
      es: 'Abrir menú en PDF',
      fr: 'Ouvrir le menu PDF');
  String get menuNotice => _t(
      pt: 'Preços e disponibilidade podem mudar. Confirme com o estabelecimento.',
      en: 'Prices and availability may change. Confirm with the place.',
      es: 'Los precios y la disponibilidad pueden cambiar. Confirme con el establecimiento.',
      fr: 'Les prix et la disponibilité peuvent changer. Confirmez auprès de l’établissement.');
  String get unavailable => _t(
      pt: 'Indisponível',
      en: 'Unavailable',
      es: 'No disponible',
      fr: 'Indisponible');

  String get upcomingEvents => _t(
        pt: 'Próximos eventos',
        en: 'Upcoming events',
        es: 'Próximos eventos',
        fr: 'Prochains événements',
      );

  String get noEvents => _t(
        pt: 'Nenhum evento publicado.',
        en: 'No published events.',
        es: 'Ningún evento publicado.',
        fr: 'Aucun événement publié.',
      );

  String get merchantTitle => _t(
        pt: 'Portal do comerciante',
        en: 'Merchant portal',
        es: 'Portal del comerciante',
        fr: 'Portail commerçant',
      );

  String get merchantBody => _t(
        pt: 'O app não edita este local. O comerciante atualiza a ficha no portal web e o Remdy passa a ler o mesmo contrato.',
        ptPt:
            'A aplicação não edita este local. O comerciante atualiza a ficha no portal web e o Remdy passa a ler o mesmo contrato.',
        en: 'The app does not edit this place. The merchant updates the listing on the web portal, and Remdy reads the same contract.',
        es: 'La app no edita este lugar. El comerciante actualiza la ficha en el portal web y Remdy lee el mismo contrato.',
        fr: 'L’app ne modifie pas ce lieu. Le commerçant met à jour la fiche sur le portail web et Remdy lit le même contrat.',
      );

  String merchantStep(String key) {
    switch (key) {
      case 'merchant_step_portal':
        return _t(
          pt: 'O comerciante entra no portal web, fora deste app.',
          ptPt: 'O comerciante entra no portal web, fora desta aplicação.',
          en: 'The merchant signs in on the web portal, outside this app.',
          es: 'El comerciante entra en el portal web, fuera de esta app.',
          fr: 'Le commerçant se connecte au portail web, hors de cette app.',
        );
      case 'merchant_step_contract':
        return _t(
          pt: 'O portal grava o documento places.v1 desse local.',
          en: 'The portal saves the places.v1 document for this place.',
          es: 'El portal guarda el documento places.v1 de este lugar.',
          fr: 'Le portail enregistre le document places.v1 de ce lieu.',
        );
      case 'merchant_step_read':
        return _t(
          pt: 'O app só lê esse contrato. Nesta etapa a leitura é um catálogo local de demonstração.',
          ptPt:
              'A aplicação só lê esse contrato. Nesta etapa a leitura é um catálogo local de demonstração.',
          en: 'The app only reads that contract. This stage uses a local demo catalog.',
          es: 'La app solo lee ese contrato. En esta etapa la lectura es un catálogo local de demostración.',
          fr: 'L’app lit seulement ce contrat. Cette étape utilise un catalogue local de démonstration.',
        );
      case 'merchant_step_link':
        return _t(
          pt: 'O link público futuro abre o detalhe do local quando a função estiver ligada.',
          en: 'The future public link opens the place detail when the feature is on.',
          es: 'El enlace público futuro abre el detalle cuando la función esté activa.',
          fr: 'Le lien public futur ouvre le détail lorsque la fonction est activée.',
        );
      default:
        return key;
    }
  }

  String get portalLabel =>
      _t(pt: 'Portal', en: 'Portal', es: 'Portal', fr: 'Portail');

  String get deepLinkLabel => _t(
        pt: 'Link do local',
        ptPt: 'Ligação do local',
        en: 'Place link',
        es: 'Enlace del lugar',
        fr: 'Lien du lieu',
      );

  String get understood => _t(
        pt: 'Entendi',
        ptPt: 'Entendido',
        en: 'Got it',
        es: 'Entendido',
        fr: 'Compris',
      );

  String get results =>
      _t(pt: 'Resultados', en: 'Results', es: 'Resultados', fr: 'Résultats');

  String weekday(int weekday) {
    const pt = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    const ptPt = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    const en = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const es = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    const fr = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    final index = weekday - 1;
    if (index < 0 || index > 6) return '$weekday';
    switch (code) {
      case 'pt-PT':
        return ptPt[index];
      case 'pt':
        return pt[index];
      case 'es':
        return es[index];
      case 'fr':
        return fr[index];
      default:
        return en[index];
    }
  }

  String ratingLine(double rating, int count) {
    final score = rating.toStringAsFixed(1).replaceAll('.', _decimal());
    return '$score · $count';
  }

  String cardLabel({
    required String name,
    required String category,
    required String city,
    required double rating,
    required int count,
    required bool open,
  }) {
    final status = open ? openNow : closed;
    final score = rating.toStringAsFixed(1).replaceAll('.', _decimal());
    return '$name, $category, $city, $score, $count, $status';
  }

  String mapLabel(int count) {
    return _t(
      pt: 'Mapa com $count locais',
      en: 'Map with $count places',
      es: 'Mapa con $count lugares',
      fr: 'Carte avec $count lieux',
    );
  }

  String _decimal() => code == 'en' ? '.' : ',';

  String _t({
    required String pt,
    String? ptPt,
    required String en,
    required String es,
    required String fr,
  }) {
    switch (code) {
      case 'pt-PT':
        return ptPt ?? pt;
      case 'pt':
        return pt;
      case 'es':
        return es;
      case 'fr':
        return fr;
      default:
        return en;
    }
  }
}
