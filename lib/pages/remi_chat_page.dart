import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import '../data/remi_lessons_data.dart';
import '../l10n/app_texts.dart';
import '../services/remi_language_contract.dart';
import '../services/remi_session_prefs.dart';
import 'remi_intro_page.dart';
import 'remi_languages_page.dart';

class RemiChatPage extends StatefulWidget {
  /// Código estável do idioma-alvo: `en` | `pt` | `es` | `fr`.
  final String languageCode;
  final String goal;
  final String lesson;

  const RemiChatPage({
    super.key,
    required this.languageCode,
    required this.goal,
    required this.lesson,
  });

  /// Compat com callers legados que ainda passam o label.
  factory RemiChatPage.legacy({
    Key? key,
    required String language,
    required String goal,
    required String lesson,
  }) {
    return RemiChatPage(
      key: key,
      languageCode: RemiLanguageContract.normalize(language),
      goal: goal,
      lesson: lesson,
    );
  }


  @override
  State<RemiChatPage> createState() => _RemiChatPageState();
}

class _RemiChatPageState extends State<RemiChatPage> {
  final TextEditingController _messageC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  final FlutterTts _tts = FlutterTts();
  
final FirebaseAuth _auth = FirebaseAuth.instance;final FirebaseFunctions _functions =
    FirebaseFunctions.instanceFor(region: 'us-central1');
  static const _uuid = Uuid();

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

late final List<_RemiMessage> _messages;
int? _speakingIndex;

bool _showPronunciation = false;
bool _sending = false;

/// Reutilizado no retry da mesma mensagem (idempotência server-side).
String? _pendingRequestId;
String? _pendingText;

String _remiErrorMessage(Object e) {
  if (e is FirebaseFunctionsException) {
    final msg = (e.message ?? '').trim();
    switch (msg) {
      case 'REMI_DAILY_LIMIT_FREE':
        return AppTexts.t('remi_error_daily_limit_free');
      case 'REMI_DAILY_LIMIT_PREMIUM':
        return AppTexts.t('remi_error_daily_limit_premium');
      case 'REMI_MINUTE_LIMIT':
        return AppTexts.t('remi_error_minute_limit');
      case 'REMI_REQUEST_IN_PROGRESS':
        return AppTexts.t('remi_error_request_in_progress');
      case 'REMI_MESSAGE_TOO_LONG':
      case 'REMI_INVALID_MESSAGE':
      case 'REMI_INVALID_REQUEST_ID':
        return AppTexts.t('remi_error_message_too_long');
      case 'REMI_PERMISSION_DENIED':
      case 'REMI_USER_NOT_FOUND':
      case 'REMI_UNAUTHENTICATED':
        return AppTexts.t('remi_error_permission_denied');
      default:
        break;
    }
    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
        return AppTexts.t('remi_error_permission_denied');
      case 'resource-exhausted':
        if (msg == 'REMI_DAILY_LIMIT_FREE') {
          return AppTexts.t('remi_error_daily_limit_free');
        }
        if (msg == 'REMI_DAILY_LIMIT_PREMIUM') {
          return AppTexts.t('remi_error_daily_limit_premium');
        }
        return AppTexts.t('remi_error_minute_limit');
      case 'failed-precondition':
        if (msg == 'REMI_REQUEST_IN_PROGRESS') {
          return AppTexts.t('remi_error_request_in_progress');
        }
        return AppTexts.t('remi_error_temporary');
      case 'invalid-argument':
        return AppTexts.t('remi_error_message_too_long');
      case 'internal':
        return AppTexts.t('remi_error_temporary');
    }
  }
  return AppTexts.t('remi_error_temporary');
}

String _clipMeta(String value, int max) {
  final t = value.trim();
  if (t.length <= max) return t;
  return t.substring(0, max);
}

List<Map<String, String>> _buildHistoryPayload() {
  final thinking = AppTexts.t('remi_thinking');
  return _messages
      .where((m) => m.text != thinking && m.text.trim().isNotEmpty)
      .toList()
      .reversed
      .take(8)
      .toList()
      .reversed
      .map((m) {
        final cleaned = m.text.replaceAll('\n', ' ').trim();
        return {
          'role': m.isUser ? 'user' : 'assistant',
          'text': cleaned.length > 1500
              ? cleaned.substring(0, 1500)
              : cleaned,
        };
      })
      .toList();
}

  @override
void dispose() {
  _tts.stop();
  _messageC.dispose();
  _scrollC.dispose();
  FocusManager.instance.primaryFocus?.unfocus();
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

  // Voz do idioma ESTUDADO (não da UI).
  final target = RemiLanguageContract.normalize(widget.languageCode);
  await _tts.setLanguage(RemiLanguageContract.ttsLocale(target));

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

  final uid = _auth.currentUser?.uid;
  if (uid != null) {
    RemiSessionPrefs.instance.saveSelection(
      uid: uid,
      languageCode: RemiLanguageContract.normalize(widget.languageCode),
      goal: widget.goal,
      lesson: widget.lesson,
    );
  }

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
}

void _openRemiSettings() {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: _remdyBlue),
              title: const Text('Change language'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RemiLanguagesPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.slideshow_rounded, color: _remdyBlue),
              title: Text(AppTexts.t('remi_settings_replay_intro')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RemiIntroPage(reviewMode: true),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

String _lessonExample() {
  final code = RemiLanguageContract.normalize(widget.languageCode);
  final phrases =
      remiCatalogFor(code)[widget.goal]?[widget.lesson] ?? const <String>[];
  if (phrases.isNotEmpty) return phrases.first;
  return AppTexts.t('remi_practice_together');
}

String _uiLanguageCode() {
  return RemiLanguageContract.uiCodeFromLocale(
    Localizations.localeOf(context).languageCode,
  );
}

Future<void> _sendMessage() async {
  if (_sending) return;

  final text = _messageC.text.trim();
  if (text.isEmpty) return;
  if (text.length > 1500) {
    setState(() {
      _messages.add(
        _RemiMessage(
          text: AppTexts.t('remi_error_message_too_long'),
          isUser: false,
        ),
      );
    });
    _scrollToBottom();
    return;
  }

  final user = _auth.currentUser;
  if (user == null) return;

  _messageC.clear();
  _sending = true;

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

  // Idempotência: reusa requestId no retry da mesma mensagem.
  final requestId = (_pendingText == text && _pendingRequestId != null)
      ? _pendingRequestId!
      : _uuid.v4();
  _pendingRequestId = requestId;
  _pendingText = text;

  try {
    final history = _buildHistoryPayload();

    final callable = _functions.httpsCallable('askRemi');

    final targetCode = RemiLanguageContract.normalize(widget.languageCode);
    final result = await callable.call({
      'requestId': requestId,
      'text': text,
      // Contrato novo: código estável. `language` permanece para compat.
      'languageCode': targetCode,
      'language': RemiLanguageContract.englishName(targetCode),
      'uiLanguageCode': _uiLanguageCode(),
      'goal': _clipMeta(widget.goal, 120),
      'lesson': _clipMeta(widget.lesson, 120),
      'history': history,
      'showPronunciation': _showPronunciation,
    });

    final reply = (result.data['reply'] ?? '').toString().trim();

    if (!mounted) return;

    _pendingRequestId = null;
    _pendingText = null;

    setState(() {
      _messages.removeLast();
      _messages.add(
        _RemiMessage(
          text: reply.isEmpty
              ? AppTexts.t('remi_error_temporary')
              : reply,
          isUser: false,
        ),
      );
    });

    _scrollToBottom();
  } catch (e, stack) {
    debugPrint('REMI ERROR: $e');
    debugPrint(stack.toString());

    if (!mounted) return;

    setState(() {
      if (_messages.isNotEmpty &&
          _messages.last.text == AppTexts.t('remi_thinking')) {
        _messages.removeLast();
      }
      _messages.add(
        _RemiMessage(
          text: _remiErrorMessage(e),
          isUser: false,
        ),
      );
    });
  } finally {
    if (mounted) {
      setState(() => _sending = false);
    } else {
      _sending = false;
    }
  }

  _scrollToBottom();
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
      resizeToAvoidBottomInset: true,
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
  IconButton(
    tooltip: AppTexts.t('remi_settings_title'),
    onPressed: _openRemiSettings,
    icon: const Icon(Icons.more_vert_rounded, color: _muted),
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
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1500,
                      decoration: InputDecoration(
                        hintText: AppTexts.t('remi_message_hint'),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        counterText: '',
                      ),
                      onSubmitted: _sending ? null : (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor:
                        _sending ? _muted : _remdyBlue,
                    child: IconButton(
                      onPressed: _sending ? null : _sendMessage,
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
