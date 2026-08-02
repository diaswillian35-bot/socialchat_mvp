/// Resolve URLs da aba Galeria a partir do documento já aberto no detalhe.
///
/// Isolado: não consulta Firestore, não altera [EventPresentation].
class EventGalleryUrls {
  EventGalleryUrls._();

  static const int maxPhotos = 5;

  /// Ordem: [coverUrl], depois [photoUrls], depois listas públicas legadas
  /// (`images` / `photos`) se forem List — nunca [logoUrl].
  /// Deduplica, remove vazias, aceita só HTTPS, limita a [maxPhotos].
  static List<String> resolve(Map<String, dynamic> data) {
    final out = <String>[];
    final seen = <String>{};

    void add(dynamic raw) {
      if (out.length >= maxPhotos) return;
      final v = raw?.toString().trim() ?? '';
      if (v.isEmpty) return;
      if (!_isHttps(v)) return;
      if (!seen.add(v)) return;
      out.add(v);
    }

    void addAll(dynamic raw) {
      if (raw is! List) return;
      for (final e in raw) {
        add(e);
        if (out.length >= maxPhotos) return;
      }
    }

    add(data['coverUrl']);
    addAll(data['photoUrls']);
    // Campos públicos legados já usados em alguns docs — nunca logoUrl.
    addAll(data['images']);
    addAll(data['photos']);

    return List<String>.unmodifiable(out);
  }

  static bool _isHttps(String url) {
    final u = Uri.tryParse(url);
    return u != null &&
        u.hasScheme &&
        u.scheme.toLowerCase() == 'https' &&
        u.host.isNotEmpty;
  }
}
