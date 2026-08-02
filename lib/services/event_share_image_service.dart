import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_texts.dart';
import '../models/event_presentation.dart';
import '../widgets/remdy_logo.dart';

/// Gera imagem social localmente (≈1200×630) e abre o share sheet nativo.
/// Sem upload Firebase — menor custo.
class EventShareImageService {
  EventShareImageService._();

  static const double socialWidth = 1200;
  static const double socialHeight = 630;

  static Future<void> shareEvent({
    required BuildContext context,
    required EventPresentation event,
    required String languageCode,
  }) async {
    final link = 'https://remdy.app/e/${event.id}';
    final text = '${event.title}\n'
        '${AppTexts.t('events_share_text')}\n'
        '$link';

    final bytes = await generateSocialPng(
      event: event,
      languageCode: languageCode,
    );

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/remdy_event_${event.id}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: '${event.title}.png')],
      text: text,
      subject: event.title,
    );

    // Limpeza best-effort — não bloqueia UX.
    Future<void>.delayed(const Duration(minutes: 10), () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    });
  }

  static Future<Uint8List> generateSocialPng({
    required EventPresentation event,
    required String languageCode,
  }) async {
    ui.Image? cover;
    final url = event.primaryImageUrl;
    if (url.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 8),
        );
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(
            res.bodyBytes,
            targetWidth: socialWidth.toInt(),
          );
          final frame = await codec.getNextFrame();
          cover = frame.image;
        }
      } catch (_) {}
    }

    ui.Image? logo;
    final logoUrl = event.logoUrl;
    if (logoUrl.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(logoUrl)).timeout(
          const Duration(seconds: 6),
        );
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(res.bodyBytes);
          final frame = await codec.getNextFrame();
          logo = frame.image;
        }
      } catch (_) {}
    }

    ui.Image? wordmark;
    try {
      final data = await rootBundle.load(RemdyLogo.assetPath);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetHeight: 72,
      );
      final frame = await codec.getNextFrame();
      wordmark = frame.image;
    } catch (_) {}

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(socialWidth, socialHeight);

    // Background
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(socialWidth, socialHeight),
        const [Color(0xFF313A5F), Color(0xFF1A2038)],
      );
    canvas.drawRect(Offset.zero & size, bg);

    if (cover != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: cover,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x99000000),
      );
    }

    if (logo != null) {
      final logoSize = 220.0;
      paintImage(
        canvas: canvas,
        rect: Rect.fromCenter(
          center: const Offset(socialWidth / 2, socialHeight / 2 - 40),
          width: logoSize,
          height: logoSize,
        ),
        image: logo,
        fit: BoxFit.contain,
      );
    }

    // Bottom info bar
    canvas.drawRect(
      const Rect.fromLTWH(0, socialHeight - 160, socialWidth, 160),
      Paint()..color = const Color(0xE6313A5F),
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: event.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: socialWidth - 280);

    titlePainter.paint(canvas, const Offset(48, socialHeight - 140));

    final meta = [
      event.shortDateLabel(),
      event.locationLine(languageCode),
    ].where((e) => e.trim().isNotEmpty).join('  ·  ');

    final metaPainter = TextPainter(
      text: TextSpan(
        text: meta,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: socialWidth - 280);
    metaPainter.paint(canvas, const Offset(48, socialHeight - 70));

    if (wordmark != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(
          socialWidth - 200,
          socialHeight - 120,
          150,
          56,
        ),
        image: wordmark,
        fit: BoxFit.contain,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      socialWidth.toInt(),
      socialHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    cover?.dispose();
    logo?.dispose();
    wordmark?.dispose();
    image.dispose();
    if (byteData == null) {
      throw StateError('share_image_encode_failed');
    }
    return byteData.buffer.asUint8List();
  }
}
