import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/message_link_utils.dart';
import '../services/safe_external_link.dart';

/// Texto de mensagem com links clicáveis (https / Remdy).
class MessageTextWithLinks extends StatefulWidget {
  const MessageTextWithLinks({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.enabled = true,
  });

  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final bool enabled;

  @override
  State<MessageTextWithLinks> createState() => _MessageTextWithLinksState();
}

class _MessageTextWithLinksState extends State<MessageTextWithLinks> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageTextWithLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      for (final r in _recognizers) {
        r.dispose();
      }
      _recognizers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.text.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final links = MessageLinkUtils.extractLinks(widget.text);
    if (links.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final baseLink = widget.linkStyle ??
        widget.style.copyWith(
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w700,
        );

    if (_recognizers.isEmpty) {
      for (final link in links) {
        _recognizers.add(
          TapGestureRecognizer()
            ..onTap = () {
              SafeExternalLink.open(
                context,
                url: link.normalizedHttpsUrl,
                isRemdyInternal: link.isRemdyInternal,
                displayHost: link.displayHost,
              );
            },
        );
      }
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      if (link.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(link.start, link.end),
          style: baseLink,
          recognizer: _recognizers[i],
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
