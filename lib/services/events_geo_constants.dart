/// Constantes geográficas da lista clássica de Eventos.
class EventsGeoConstants {
  EventsGeoConstants._();

  /// Raio máximo da aba Arredores (Haversine, linha reta).
  static const double eventsSurroundingsRadiusKm = 110;

  /// Alias explícito pedido pelo produto.
  static const double EVENTS_SURROUNDINGS_RADIUS_KM = eventsSurroundingsRadiusKm;

  /// Página nacional / arredores: mais docs que a lista por cidade.
  static const int publicExplorePageSize = 300;

  /// Página seguinte (cursor) para exploração nacional.
  static const int publicExplorePageSizeMax = 500;
}
