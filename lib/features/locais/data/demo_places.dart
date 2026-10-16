import '../models/place_listing.dart';

/// Catálogo local de demonstração. Nenhum destes registros existe em produção.
class DemoPlaces {
  DemoPlaces._();

  static final List<PlaceListing> all = [
    PlaceListing(
      id: 'casa_do_sabor',
      slug: 'casa-do-sabor',
      name: 'Casa do Sabor',
      category: PlaceCategory.restaurant,
      description:
          'Cozinha de mercado com peixe do dia, varanda e mesas para grupos pequenos. O salão principal cabe cerca de quarenta pessoas.',
      photos: [
        PlacePhoto(
          id: 'capa',
          alt: 'Salão da Casa do Sabor',
          color: 0xFF8C3A3A,
        ),
        PlacePhoto(id: 'varanda', alt: 'Varanda com mesas', color: 0xFFB85C38),
      ],
      rating: 4.6,
      ratingCount: 128,
      address: PlaceAddress(
        line1: 'Rua das Flores, 120',
        district: 'Centro',
        city: 'Florianópolis',
        region: 'Santa Catarina',
        countryCode: 'BR',
        postalCode: '88010-000',
        latitude: -27.5954,
        longitude: -48.5480,
      ),
      contact: PlaceContact(
        phone: '+55 48 3000-1200',
        instagram: '@casadosabor.demo',
      ),
      hours: _allWeek('11:30', '23:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: true,
        stepFree: true,
        accessibleRestroom: true,
        notes: 'Entrada pela rua lateral, sem degrau.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Ana Lima',
          rating: 5,
          comment:
              'Peixe fresco e atendimento calmo. Voltaria no fim de semana.',
          createdAt: '2026-08-02',
        ),
        PlaceReview(
          id: 'r2',
          authorName: 'Diego Martins',
          rating: 4,
          comment: 'Bom para ir em grupo. A varanda enche depois das 20h.',
          createdAt: '2026-07-18',
        ),
      ],
      upcomingEvents: [
        PlaceUpcomingEvent(
          id: 'ev_jazz',
          title: 'Noite de jazz',
          startsAt: '2026-10-18T20:00:00',
          note: 'Salão principal, entrada gratuita',
        ),
      ],
    ),
    PlaceListing(
      id: 'bar_do_cais',
      slug: 'bar-do-cais',
      name: 'Bar do Cais',
      category: PlaceCategory.bar,
      description:
          'Balcão comprido, petiscos e música baixa. Abre no fim da tarde e segue depois da meia-noite.',
      photos: [
        PlacePhoto(id: 'capa', alt: 'Balcão do Bar do Cais', color: 0xFF313A5F),
        PlacePhoto(id: 'salao', alt: 'Mesas junto à janela', color: 0xFF24324F),
      ],
      rating: 4.4,
      ratingCount: 86,
      address: PlaceAddress(
        line1: 'Rua dos Remolares, 18',
        district: 'Alfama',
        city: 'Lisboa',
        region: 'Lisboa',
        countryCode: 'PT',
        postalCode: '1100-001',
        latitude: 38.7126,
        longitude: -9.1270,
      ),
      contact: PlaceContact(phone: '+351 21 000 1840'),
      hours: _allWeek('18:00', '02:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: false,
        stepFree: false,
        accessibleRestroom: false,
        notes: 'Entrada com dois degraus. Sem casa de banho acessível.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Inês Rocha',
          rating: 4,
          comment: 'Petiscos bons e espaço apertado quando enche.',
          createdAt: '2026-06-11',
        ),
      ],
      upcomingEvents: [
        PlaceUpcomingEvent(
          id: 'ev_fado',
          title: 'Fado ao vivo',
          startsAt: '2026-10-20T21:30:00',
          note: 'Mesas só com reserva',
        ),
      ],
    ),
    PlaceListing(
      id: 'cafe_atlantico',
      slug: 'cafe-atlantico',
      name: 'Café Atlântico',
      category: PlaceCategory.cafe,
      description:
          'Café de manhã e almoço leve. Tomadas nas mesas da janela e espaço para trabalhar até o meio da tarde.',
      photos: [
        PlacePhoto(
          id: 'capa',
          alt: 'Balcão do Café Atlântico',
          color: 0xFF8A5A2A,
        ),
        PlacePhoto(id: 'janela', alt: 'Mesas da janela', color: 0xFFC4A574),
      ],
      rating: 4.8,
      ratingCount: 214,
      address: PlaceAddress(
        line1: '120 King Street West',
        district: 'Downtown',
        city: 'Toronto',
        region: 'Ontario',
        countryCode: 'CA',
        postalCode: 'M5H 1A1',
        latitude: 43.6486,
        longitude: -79.3817,
      ),
      contact: PlaceContact(
        phone: '+1 416 555 0148',
        website: 'https://remdy.app',
        instagram: '@cafeatlantico.demo',
      ),
      hours: _allWeek('08:00', '16:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: true,
        stepFree: true,
        accessibleRestroom: true,
        notes: 'Porta automática e balcão rebaixado.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Maya Chen',
          rating: 5,
          comment: 'Bom café e mesas quietas de manhã.',
          createdAt: '2026-09-03',
        ),
      ],
      upcomingEvents: [],
    ),
    PlaceListing(
      id: 'hotel_mare',
      slug: 'hotel-mare',
      name: 'Hotel Maré',
      category: PlaceCategory.hotel,
      description:
          'Hotel de frente para a praia, com recepção 24 horas, café da manhã e quartos silenciosos nos andares altos.',
      photos: [
        PlacePhoto(id: 'capa', alt: 'Fachada do Hotel Maré', color: 0xFF1F4E79),
        PlacePhoto(id: 'lobby', alt: 'Recepção', color: 0xFF3D7AB5),
      ],
      rating: 4.7,
      ratingCount: 342,
      address: PlaceAddress(
        line1: 'Avenida Atlântica, 900',
        district: 'Copacabana',
        city: 'Rio de Janeiro',
        region: 'Rio de Janeiro',
        countryCode: 'BR',
        postalCode: '22010-000',
        latitude: -22.9711,
        longitude: -43.1822,
      ),
      contact: PlaceContact(
        phone: '+55 21 3000 0900',
        instagram: '@hotelmare.demo',
      ),
      hours: _allWeek('00:00', '23:59'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: true,
        stepFree: true,
        accessibleRestroom: true,
        notes: 'Elevador até os quartos e recepção no térreo.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Lúcia Ferreira',
          rating: 5,
          comment: 'Recepção atenta e quarto silencioso.',
          createdAt: '2026-05-22',
        ),
      ],
      upcomingEvents: [
        PlaceUpcomingEvent(
          id: 'ev_brunch',
          title: 'Brunch de domingo',
          startsAt: '2026-10-18T10:30:00',
          note: 'Aberto a hóspedes e visitantes',
        ),
      ],
    ),
    PlaceListing(
      id: 'pousada_dunas',
      slug: 'pousada-das-dunas',
      name: 'Pousada das Dunas',
      category: PlaceCategory.pousada,
      description:
          'Pousada pequena a poucos minutos da praia, com café da manhã na varanda e quartos com ventilação cruzada.',
      photos: [
        PlacePhoto(id: 'capa', alt: 'Varanda da pousada', color: 0xFF2F6B4F),
        PlacePhoto(id: 'jardim', alt: 'Jardim interno', color: 0xFF4E8C6A),
      ],
      rating: 4.9,
      ratingCount: 67,
      address: PlaceAddress(
        line1: 'Rua das Dunas, 45',
        district: 'Ponta Negra',
        city: 'Natal',
        region: 'Rio Grande do Norte',
        countryCode: 'BR',
        postalCode: '59090-100',
        latitude: -5.8816,
        longitude: -35.1698,
      ),
      contact: PlaceContact(phone: '+55 84 3000 0045'),
      hours: _allWeek('08:00', '22:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: false,
        stepFree: false,
        accessibleRestroom: false,
        notes: 'Escada na entrada. Sem quarto acessível nesta demonstração.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Paulo Nunes',
          rating: 5,
          comment: 'Café da manhã na varanda e rua tranquila.',
          createdAt: '2026-04-09',
        ),
      ],
      upcomingEvents: [],
    ),
    PlaceListing(
      id: 'aurora_club',
      slug: 'aurora-club',
      name: 'Aurora Club',
      category: PlaceCategory.nightclub,
      description:
          'Pista pequena, som ao vivo aos sábados e bar no mezanino. A casa abre à noite.',
      photos: [
        PlacePhoto(id: 'capa', alt: 'Pista do Aurora Club', color: 0xFF3D2A5C),
        PlacePhoto(id: 'mezanino', alt: 'Mezanino', color: 0xFF6A4C93),
      ],
      rating: 4.3,
      ratingCount: 190,
      address: PlaceAddress(
        line1: 'Rua Harmonia, 210',
        district: 'Vila Madalena',
        city: 'São Paulo',
        region: 'São Paulo',
        countryCode: 'BR',
        postalCode: '05435-000',
        latitude: -23.5558,
        longitude: -46.6919,
      ),
      contact: PlaceContact(
        phone: '+55 11 3000 0210',
        instagram: '@auroraclub.demo',
      ),
      hours: _allWeek('22:00', '05:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: false,
        stepFree: false,
        accessibleRestroom: false,
        notes: 'Acesso à pista por escada. Sem rota sem degrau.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Renata Souza',
          rating: 4,
          comment: 'Som bom. A fila da porta cresce depois das 23h.',
          createdAt: '2026-09-12',
        ),
      ],
      upcomingEvents: [
        PlaceUpcomingEvent(
          id: 'ev_sabado',
          title: 'Banda convidada',
          startsAt: '2026-10-17T23:30:00',
          note: 'Pista principal',
        ),
      ],
    ),
    PlaceListing(
      id: 'cafe_da_se',
      slug: 'cafe-da-se',
      name: 'Café da Sé',
      category: PlaceCategory.cafe,
      description:
          'Padaria e café no centro, com mesas na calçada coberta e almoço simples nos dias de semana.',
      photos: [
        PlacePhoto(id: 'capa', alt: 'Balcão do Café da Sé', color: 0xFF6B4F3A),
      ],
      rating: 4.2,
      ratingCount: 54,
      address: PlaceAddress(
        line1: 'Rua Direita, 30',
        district: 'Sé',
        city: 'São Paulo',
        region: 'São Paulo',
        countryCode: 'BR',
        postalCode: '01002-000',
        latitude: -23.5505,
        longitude: -46.6333,
      ),
      contact: PlaceContact(phone: '+55 11 3000 0030'),
      hours: const [
        PlaceHours(weekday: 2, opens: '09:00', closes: '18:00'),
        PlaceHours(weekday: 3, opens: '09:00', closes: '18:00'),
        PlaceHours(weekday: 4, opens: '09:00', closes: '18:00'),
        PlaceHours(weekday: 5, opens: '09:00', closes: '18:00'),
        PlaceHours(weekday: 6, opens: '09:00', closes: '14:00'),
      ],
      accessibility: PlaceAccessibility(
        wheelchairEntrance: true,
        stepFree: true,
        accessibleRestroom: false,
        notes: 'Entrada plana. Banheiro no fundo, com degrau.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Helena Prado',
          rating: 4,
          comment: 'Pão quente cedo e mesas rápidas na hora do almoço.',
          createdAt: '2026-03-14',
        ),
      ],
      upcomingEvents: [],
    ),
    PlaceListing(
      id: 'taberna_ribeira',
      slug: 'taberna-da-ribeira',
      name: 'Taberna da Ribeira',
      category: PlaceCategory.restaurant,
      description:
          'Mesas junto ao rio, pratos para dividir e sobremesa da casa. Fecha entre o almoço e o jantar.',
      photos: [
        PlacePhoto(
          id: 'capa',
          alt: 'Mesas da Taberna da Ribeira',
          color: 0xFF7A3E2E,
        ),
        PlacePhoto(id: 'rio', alt: 'Vista do rio', color: 0xFF9C5A45),
      ],
      rating: 4.5,
      ratingCount: 161,
      address: PlaceAddress(
        line1: 'Cais da Ribeira, 12',
        district: 'Ribeira',
        city: 'Porto',
        region: 'Porto',
        countryCode: 'PT',
        postalCode: '4050-510',
        latitude: 41.1406,
        longitude: -8.6130,
      ),
      contact: PlaceContact(phone: '+351 22 000 1212'),
      hours: _allWeek('12:00', '22:00'),
      accessibility: PlaceAccessibility(
        wheelchairEntrance: true,
        stepFree: false,
        accessibleRestroom: true,
        notes: 'Rampa na porta. Um degrau entre o salão e o terraço.',
      ),
      reviews: [
        PlaceReview(
          id: 'r1',
          authorName: 'Miguel Costa',
          rating: 5,
          comment: 'Boa mesa para dividir e vista do rio.',
          createdAt: '2026-08-28',
        ),
      ],
      upcomingEvents: [
        PlaceUpcomingEvent(
          id: 'ev_vinho',
          title: 'Prova de vinhos',
          startsAt: '2026-10-22T19:00:00',
          note: 'Doze lugares',
        ),
      ],
    ),
  ];

  static List<PlaceHours> _allWeek(String opens, String closes) {
    return List<PlaceHours>.generate(
      7,
      (index) => PlaceHours(weekday: index + 1, opens: opens, closes: closes),
    );
  }
}
