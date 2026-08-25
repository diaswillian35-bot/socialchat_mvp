import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wiring tests for Share Extension two-step confirmation (select → Enviar).
void main() {
  late String ui;
  late String l10n;
  late String cell;

  setUpAll(() {
    ui = File('ios/ShareExtension/ShareViewController.swift').readAsStringSync();
    l10n = File('ios/ShareExtension/ShareL10n.swift').readAsStringSync();
    cell = File('ios/ShareExtension/ShareDestinationCell.swift').readAsStringSync();
  });

  group('two-step confirmation', () {
    test('tap destination selects without sending', () {
      final didSelect = RegExp(
        r'func tableView\(_ tableView: UITableView, didSelectRowAt[\s\S]*?\n  \}',
      ).firstMatch(ui)?.group(0);
      expect(didSelect, isNotNull);
      expect(didSelect!, contains('selectedDestination = row'));
      expect(didSelect!, contains('destination_selected'));
      expect(didSelect!, isNot(contains('send(to:')));
      expect(didSelect!, isNot(contains('completeRequest')));
      expect(didSelect!, isNot(contains('saveImageJob')));
    });

    test('send only starts from sendTapped / Enviar', () {
      expect(ui, contains('@objc private func sendTapped()'));
      expect(ui, contains('sendButton.addTarget(self, action: #selector(sendTapped)'));
      expect(ui, contains('guard let dest = selectedDestination'));
      expect(ui, contains('send(to: dest)'));
    });

    test('Enviar disabled without selection; sending locks UI', () {
      expect(ui, contains('updateSendButton'));
      expect(ui, contains('selectedDestination != nil'));
      expect(ui, contains('sendButton.isEnabled = canSend'));
      expect(ui, contains('table.isUserInteractionEnabled = canBrowse'));
      expect(ui, contains('share_sending'));
    });

    test('double-tap guarded by sendingId', () {
      expect(ui, contains('guard sendingId == nil, !didFinish'));
      expect(ui, contains('sendingId = dest.destinationId'));
    });

    test('cancel before send does not persist job', () {
      final cancel = RegExp(
        r'@objc private func cancelTapped\(\)[\s\S]*?\n  \}',
      ).firstMatch(ui)?.group(0);
      expect(cancel, isNotNull);
      expect(cancel!, contains('cancelRequest'));
      expect(cancel!, contains('selectedDestination = nil'));
      expect(cancel!, isNot(contains('saveImageJob')));
      expect(cancel!, isNot(contains('ShareCallableClient.send')));
    });

    test('failure keeps extension open and preserves selection for retry', () {
      expect(ui, contains('applyState(.failed'));
      expect(ui, isNot(contains('completeRequest(returningItems: nil)')));
      // completeRequest only via finishSuccessfully after success
      expect(ui, contains('finishSuccessfully'));
      final retry = RegExp(
        r'@objc private func retryTapped\(\)[\s\S]*?\n  \}',
      ).firstMatch(ui)?.group(0);
      expect(retry, isNotNull);
      expect(retry!, contains('selectedDestination'));
      expect(retry!, contains('send(to: dest)'));
    });

    test('bootstrap / cache never auto-sends', () {
      expect(ui, contains('never auto-send / never completeRequest here'));
      // send(to:) only from sendTapped / retry — not from bootstrap/cache/select.
      final sendCallSites = RegExp(r'send\(to:').allMatches(ui).length;
      expect(sendCallSites, 2); // sendTapped + retryTapped
      expect(ui, contains('@objc private func sendTapped()'));
      expect(ui.contains('applyCachedDestinations()'), isTrue);
      expect(
        ui.contains('completeRequest') && ui.contains('finishSuccessfully'),
        isTrue,
      );
    });

    test('cell shows selected checkmark without remote avatars', () {
      expect(cell, contains('selected: Bool'));
      expect(cell, contains('accessoryType = selected ? .checkmark'));
      expect(cell, isNot(contains('URLSession.shared')));
    });
  });

  group('l10n confirmation copy', () {
    test('pt-BR required strings', () {
      expect(l10n, contains('"share_send": "Enviar"'));
      expect(l10n, contains('"share_sending": "Enviando…"'));
      expect(l10n, contains('"share_cancel": "Cancelar"'));
      expect(l10n, contains('"share_retry": "Tentar novamente"'));
      expect(
        l10n,
        contains('"share_select_hint": "Selecione uma conversa ou grupo"'),
      );
    });

    test('en / es / fr / pt-PT keys present', () {
      for (final key in [
        'share_send',
        'share_sending',
        'share_cancel',
        'share_retry',
        'share_select_hint',
      ]) {
        expect(l10n.contains('"$key":'), isTrue, reason: key);
      }
      expect(l10n, contains('"share_send": "Send"'));
      expect(l10n, contains('"share_send": "Envoyer"'));
      expect(l10n, contains('"share_send": "Enviar"')); // pt + es
    });
  });

  group('memory budget unchanged', () {
    test('image and destination caps remain', () {
      expect(ui, contains('maxImages = 3'));
      expect(ui, contains('maxVisibleDestinations = 30'));
      expect(ui, contains('jpegMaxDimension: CGFloat = 960'));
      expect(ui, contains('downsampledJPEG'));
    });
  });
}
