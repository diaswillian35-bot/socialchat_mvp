
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'events_page_new.dart';

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
    _openEvent();
  }

  Future<void> _openEvent() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        Navigator.pop(context);
        return;
      }

      final data = doc.data() ?? {};

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
builder: (_) => EventsPage(
  openEventId: widget.eventId,
),


        ),
      );
    } catch (e) {
      if (!mounted) return;

      Navigator.pop(context);
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
