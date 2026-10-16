import 'package:flutter/material.dart';

import '../locais_strings.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';

class LocaisMapView extends StatelessWidget {
  const LocaisMapView({
    super.key,
    required this.places,
    required this.strings,
    this.onSelect,
    this.highlightId,
  });

  final List<PlaceListing> places;
  final LocaisStrings strings;
  final ValueChanged<PlaceListing>? onSelect;
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: strings.mapLabel(places.length),
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE7EEF6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LocaisColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(
                painter: _MapPainter(),
                child: SizedBox.expand(),
              ),
              if (places.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      strings.emptyTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: LocaisColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                ..._pins(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pins() {
    var minLat = places.first.address.latitude;
    var maxLat = minLat;
    var minLng = places.first.address.longitude;
    var maxLng = minLng;
    for (final place in places) {
      final lat = place.address.latitude;
      final lng = place.address.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    final latSpan = (maxLat - minLat).abs() < 0.4 ? 0.4 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng).abs() < 0.4 ? 0.4 : (maxLng - minLng);
    final midLat = (minLat + maxLat) / 2;
    final midLng = (minLng + maxLng) / 2;

    return [
      for (final place in places)
        _pin(
          place,
          dx: ((place.address.longitude - (midLng - lngSpan / 2)) / lngSpan)
              .clamp(0.12, 0.88),
          dy: (1 -
                  ((place.address.latitude - (midLat - latSpan / 2)) / latSpan))
              .clamp(0.16, 0.84),
        ),
    ];
  }

  Widget _pin(PlaceListing place, {required double dx, required double dy}) {
    final selected = place.id == highlightId;
    return Align(
      alignment: Alignment(dx * 2 - 1, dy * 2 - 1),
      child: Semantics(
        button: onSelect != null,
        label: place.name,
        child: IconButton(
          key: Key('place_pin_${place.id}'),
          tooltip: place.name,
          onPressed: onSelect == null ? null : () => onSelect!(place),
          icon: Icon(
            Icons.location_on_rounded,
            color: selected ? const Color(0xFFB45309) : LocaisColors.navy,
            size: 36,
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final water = Paint()..color = const Color(0xFFD5E4F2);
    canvas.drawRect(Offset.zero & size, water);
    final land = Paint()..color = const Color(0xFFE7F0E4);
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.05,
        size.width * 0.92,
        size.height * 0.28,
      )
      ..lineTo(size.width * 0.84, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.95,
        size.width * 0.06,
        size.height * 0.7,
      )
      ..close();
    canvas.drawPath(path, land);
    final road = Paint()
      ..color = const Color(0xFFCDD6C8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.4),
      Offset(size.width * 0.8, size.height * 0.55),
      road,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
