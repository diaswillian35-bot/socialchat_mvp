import 'package:flutter/material.dart';

/// ✅ Tela Admin (placeholder)
/// Essa classe precisa existir porque o HomePage chama: const AdminPage()
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: const Center(
        child: Text('AdminPage (placeholder)'),
      ),
    );
  }
}

/// ✅ Widget do título que abre o Admin com "multi-tap"
class _AdminTapTitle extends StatefulWidget {
  final VoidCallback onOpenAdmin;
  const _AdminTapTitle({required this.onOpenAdmin});

  @override
  State<_AdminTapTitle> createState() => _AdminTapTitleState();
}

class _AdminTapTitleState extends State<_AdminTapTitle> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _taps++;
        if (_taps >= 7) {
          _taps = 0;
          widget.onOpenAdmin();
        }
      },
      child: const Text(
        'Talksy',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}