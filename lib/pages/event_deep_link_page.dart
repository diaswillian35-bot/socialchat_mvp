import 'package:flutter/material.dart';

import '../services/event_deep_link_service.dart';

/// Abre um evento a partir de deep link (`/e/{eventId}`).
class EventDeepLinkPage extends StatefulWidget {
  final String eventId;

  const EventDeepLinkPage({
    super.key,
    required this.eventId,
  });

  @override
  State<EventDeepLinkPage> createState() => _EventDeepLinkPageState();
}

class _EventDeepLinkPageState extends State<EventDeepLinkPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openEvent());
  }

  Future<void> _openEvent() async {
    final opened = await EventDeepLinkService.openEventById(
      context,
      eventId: widget.eventId,
      replace: true,
    );

    if (!mounted) return;
    if (!opened && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
