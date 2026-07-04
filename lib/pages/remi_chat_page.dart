import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../l10n/app_texts.dart';
class RemiChatPage extends StatefulWidget {
  final String language;
  final String goal;
  final String lesson;

  const RemiChatPage({
    super.key,
   required this.language,
    required this.goal,
    required this.lesson,
  });


  @override
  State<RemiChatPage> createState() => _RemiChatPageState();
}

class _RemiChatPageState extends State<RemiChatPage> {
  bool _showedIntro = false;
  final TextEditingController _messageC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  final FlutterTts _tts = FlutterTts();
  
final FirebaseFirestore _db = FirebaseFirestore.instance;
final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFunctions _functions =
    FirebaseFunctions.instanceFor(region: 'us-central1');



  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

late final List<_RemiMessage> _messages;
int? _speakingIndex;

bool _showPronunciation = false;

  @override
void dispose() {
  _tts.stop();
  _messageC.dispose();
  _scrollC.dispose();
  super.dispose();
}
void _scrollToBottom() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollC.hasClients) return;

    _scrollC.animateTo(
      _scrollC.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  });
}
Future<void> _speak(String text) async {
  if (text.trim().isEmpty) return;

  await _tts.stop();

 final code = Localizations.localeOf(context).languageCode.toLowerCase();

if (code == 'pt') {
  await _tts.setLanguage('pt-BR');
} else if (code == 'es') {
  await _tts.setLanguage('es-ES');
} else if (code == 'fr') {
  await _tts.setLanguage('fr-FR');
} else {
  await _tts.setLanguage('en-US');
}


  await _tts.setSpeechRate(0.65);
  await _tts.setPitch(1.0);
  await _tts.setVolume(1.0);

  final cleanText = text.replaceAll(
    RegExp(
      r'[\u{1F300}-\u{1F9FF}|\u{2600}-\u{26FF}]',
      unicode: true,
    ),
    '',
  );



final speakText = cleanText.trim();

if (speakText.isEmpty) return;

await _tts.speak(speakText);

}


@override
void initState() {
    super.initState();

  _messages = [
    _RemiMessage(
     text:
    '${AppTexts.t('remi_hello')}\n${AppTexts.t('remi_today_practice')} ${widget.lesson.toLowerCase()}.',

      isUser: false,
    ),

    _RemiMessage(
      text: _lessonExample(),
      isUser: false,
    ),
  ];
  WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!_showedIntro && mounted) {
    _showedIntro = true;
    _showRemiIntro();
  }
});

}

void _showRemiIntro() {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(AppTexts.t('remi_intro_title')),
        content: Text(
          AppTexts.t('remi_intro_body')),
    
        actions: [
TextButton(
  onPressed: () => Navigator.pop(context),
  child: Text(
    AppTexts.t('remi_intro_button'),
  ),
),


          
        ],
      );
    },
  );
}

String _lessonExample() {
  switch (widget.lesson.toLowerCase()) {
    case 'coffee shop':
      return 'Can I get a medium coffee?';

    case 'introductions':
      return 'Hi! My name is Alex. Nice to meet you.';

    case 'meeting people':
      return 'Where are you from?';

    case 'asking questions':
      return 'How long have you been in Canada?';

    case 'daily conversations':
      return 'How was your day today?';

    default:
  return AppTexts.t('remi_practice_together');

  }
}
String _appLanguageName() {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();

  switch (code) {
    case 'pt':
      return 'Portuguese';
    case 'es':
      return 'Spanish';
    case 'fr':
      return 'French';
    default:
      return 'English';
  }
}

Future<void> _sendMessage() async {
  final text = _messageC.text.trim();
  if (text.isEmpty) return;

  final user = _auth.currentUser;
  if (user == null) return;

  _messageC.clear();

  setState(() {
    _messages.add(_RemiMessage(text: text, isUser: true));
    _messages.add(
       _RemiMessage(
        text: AppTexts.t('remi_thinking'),
        isUser: false,
      ),
    );
  });
_scrollToBottom();

  try {
final history = _messages
    .where((m) =>
       m.text != AppTexts.t('remi_thinking') &&
        m.text.trim().isNotEmpty)
    .toList()
    .reversed
    .take(8)
    .toList()
    .reversed
    .map((m) {
      final role = m.isUser ? 'User' : 'Remi';

      final cleaned = m.text
          .replaceAll('\n', ' ')
          .trim();

      return '$role: $cleaned';
    })
    .join('\n');


    final callable = _functions.httpsCallable('askRemi');

final result = await callable.call({
  'text': text,
  'language': widget.language,
  'goal': widget.goal,
  'lesson': widget.lesson,
  'history': history,
  'showPronunciation': _showPronunciation,
});



    final reply = (result.data['reply'] ?? '').toString().trim();

    setState(() {
      _messages.removeLast();
      _messages.add(
        _RemiMessage(
          text: reply.isEmpty ? 'Sorry, I could not answer right now.' : reply,
          isUser: false,
        ),
      );
    });

    _scrollToBottom();

} catch (e, stack) {
  debugPrint('REMII ERROR: $e');
  debugPrint(stack.toString());

  setState(() {
    _messages.removeLast();
    _messages.add(
      _RemiMessage(
        
text: 'Error: $e',

        isUser: false,
      ),
    );
  });
}

_scrollToBottom();
}



  String _mockReply(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('hello') || lower.contains('hi')) {
      return 'Hello! 😊 What language do you want to practice today?';
    }

    if (lower.contains('inglês') || lower.contains('english')) {
      return 'Great! Send me a sentence in English and I’ll help you improve it.';
    }

    if (lower.contains('francês') || lower.contains('french')) {
      return 'Très bien! 🇫🇷 Send me a sentence in French.';
    }

    if (lower.contains('espanhol') || lower.contains('spanish')) {
      return '¡Perfecto! 🇪🇸 Envíame una frase en español.';
    }

    if (lower.contains('português') || lower.contains('portuguese')) {
      return 'Perfeito! 🇧🇷 Posso te ajudar com português também.';
    }

    return 'Nice! In the next version, I’ll correct your sentence and explain it. For now, this is Remi test mode 🤖';
  }

String _translatedLesson(String lesson) {
  switch (lesson.toLowerCase()) {
    case 'small talk':
      return AppTexts.t('lesson_small_talk');

    case 'coffee shop':
      return AppTexts.t('lesson_coffee_shop');

    case 'job interview':
      return AppTexts.t('lesson_job_interview');

    case 'introductions':
      return AppTexts.t('lesson_introductions');

    case 'meeting people':
      return AppTexts.t('lesson_meeting_people');

    case 'daily life':
      return AppTexts.t('lesson_daily_life');

    default:
      return lesson;
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: _text),
title: Row(
  mainAxisSize: MainAxisSize.min,
  children: [

Image.asset(
  'assets/remdy_icon.png',
  height: 28,
),

    const SizedBox(width: 8),
    const Text(
      'Remi',
      style: TextStyle(
        color: _text,
        fontWeight: FontWeight.w900,
      ),
    ),
  ],
),



        centerTitle: true,
        actions: [
  IconButton(
    tooltip: _showPronunciation ? 'Pronunciation ON' : 'Pronunciation OFF',
    onPressed: () {
      setState(() {
        _showPronunciation = !_showPronunciation;
      });
    },
    icon: Icon(
      _showPronunciation
          ? Icons.record_voice_over_rounded
          : Icons.record_voice_over_outlined,
      color: _showPronunciation ? _remdyBlue : _muted,
    ),
  ),
],


      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Colors.white,
            child: Text(
              AppTexts.t('remi_practice_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
  controller: _scrollC,

              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];

                return Align(
                  alignment:
                      msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isUser ? _remdyBlue : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: msg.isUser
                          ? null
                          : Border.all(color: _border),
                    ),
                  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      msg.text,
      style: TextStyle(
        color: msg.isUser ? Colors.white : _text,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    ),

    if (!msg.isUser) ...[
      const SizedBox(height: 8),

      InkWell(
       onTap: () async {
  setState(() {
    _speakingIndex = index;
  });

  await _speak(msg.text);

  if (!mounted) return;

  setState(() {
    _speakingIndex = null;
  });
},

          // áudio depois
       
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children:[
            Icon(
             
_speakingIndex == index
    ? Icons.graphic_eq_rounded
    : Icons.volume_up_rounded,

              size: 18,
              color: _muted,
            ),
            SizedBox(width: 4),
            Text(
              _speakingIndex == index ? AppTexts.t('remi_speaking') : AppTexts.t('remi_listen'),
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ],
  ],
),

                  ),
                );
              },
            ),
          ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: _border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageC,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: AppTexts.t('remi_message_hint'),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _remdyBlue,
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemiMessage {
  final String text;
  final bool isUser;
final bool isSpeaking;

 

  const _RemiMessage({
    required this.text,
    
   required this.isUser,
this.isSpeaking = false,

  });
}
