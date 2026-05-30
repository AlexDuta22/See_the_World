import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  final _tts = FlutterTts();

  final List<_ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isLoading = false;
  bool _speechAvailable = false;
  bool _ttsEnabled = false;
  bool _english = false;
  final String _apiKey = _defaultApiKey;
  String _partialText = '';

  // Cheia ta Gemini. Pune-o aici între ghilimele (defaultValue) sau
  // furnizeaz-o la build cu --dart-define=GEMINI_API_KEY=...
  static const String _defaultApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyBvf3c5i8stciC_pavxwdi0FUtTVXVXV74',
  );

  static const String _model = 'gemini-2.5-flash';

  static const String _systemPromptRo =
      'Ești un asistent de călătorie specializat în România și Europa. '
      'Când utilizatorul îți descrie timpul disponibil, preferințele și interesele, '
      'oferi recomandări personalizate de destinații, locuri de vizitat, '
      'activități, rute și sfaturi practice. '
      'Răspunde întotdeauna în română. '
      'Fii concis dar informativ — oferă 3-5 recomandări specifice cu descrieri scurte. '
      'Dacă utilizatorul menționează tipul de vacanță (munte, mare, oraș, natură) și durata, '
      'adaptează recomandările exact la aceste criterii. '
      'Când recomanzi locuri, include și ce activități se pot face acolo.';

  static const String _systemPromptEn =
      'You are a travel assistant specialized in Romania and Europe. '
      'When the user describes their available time, preferences and interests, '
      'you give personalized recommendations of destinations, places to visit, '
      'activities, routes and practical tips. '
      'Always reply in English. '
      'Be concise but informative — give 3-5 specific recommendations with short descriptions. '
      'If the user mentions the type of trip (mountains, seaside, city, nature) and the duration, '
      'adapt the recommendations exactly to these criteria. '
      'When recommending places, include what activities can be done there.';

  String get _systemPrompt => _english ? _systemPromptEn : _systemPromptRo;

  static const String _welcomeRo =
      'Salut! Sunt asistentul tău de călătorie AI. 🗺️\n\n'
      'Spune-mi câte zile ai libere, ce tip de destinație preferi '
      '(munte, mare, oraș, natură) și orice alte preferințe, '
      'iar eu îți voi oferi recomandări personalizate.\n\n'
      'Poți vorbi prin microfon sau scrie direct.';

  static const String _welcomeEn =
      "Hi! I'm your AI travel assistant. 🗺️\n\n"
      'Tell me how many days you have free, what type of destination you prefer '
      '(mountains, seaside, city, nature) and any other preferences, '
      'and I will give you personalized recommendations.\n\n'
      'You can speak through the microphone or type directly.';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    _messages.add(
      const _ChatMessage(text: _welcomeRo, isUser: false, isWelcome: true),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_english ? 'en-US' : 'ro-RO');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _toggleLanguage() {
    setState(() {
      _english = !_english;
      // Dacă nu s-a început încă o conversație, actualizează mesajul de bun venit.
      if (_messages.length == 1 && _messages.first.isWelcome) {
        _messages[0] = _ChatMessage(
          text: _english ? _welcomeEn : _welcomeRo,
          isUser: false,
          isWelcome: true,
        );
      }
    });
    _tts.stop();
    _tts.setLanguage(_english ? 'en-US' : 'ro-RO');
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_partialText.trim().isNotEmpty) {
        final text = _partialText.trim();
        _partialText = '';
        await _sendMessage(text);
      }
      return;
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recunoașterea vocală nu este disponibilă pe acest dispozitiv.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _isListening = true;
      _partialText = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _partialText = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          final text = result.recognizedWords.trim();
          _partialText = '';
          _isListening = false;
          _sendMessage(text);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _english ? 'en_US' : 'ro_RO',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cheia API Gemini nu este configurată.')),
      );
      return;
    }

    _textController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final result = await _callGemini(trimmed);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.text != null) {
        _messages.add(_ChatMessage(text: result.text!, isUser: false));
        if (_ttsEnabled) _tts.speak(result.text!);
      } else {
        _messages.add(
          _ChatMessage(
            text: result.error ??
                'Nu am putut obține un răspuns. Verifică cheia API sau conexiunea la internet.',
            isUser: false,
          ),
        );
      }
    });
    _scrollToBottom();
  }

  Future<({String? text, String? error})> _callGemini(String userText) async {
    try {
      final contents = <Map<String, dynamic>>[];
      for (final m in _messages) {
        if (m.isWelcome) continue;
        contents.add({
          'role': m.isUser ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        });
      }
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userText},
        ],
      });

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$_model:generateContent?key=$_apiKey',
      );
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': _systemPrompt},
                ],
              },
              'contents': contents,
              'generationConfig': {'maxOutputTokens': 1024},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return (
          text: null,
          error: 'Eroare ${response.statusCode}: ${response.body}',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return (text: null, error: 'Răspuns gol de la Gemini: ${response.body}');
      }
      final content =
          (candidates.first as Map<String, dynamic>)['content']
              as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return (text: null, error: 'Răspuns fără text: ${response.body}');
      }
      final text = (parts.first as Map<String, dynamic>)['text']?.toString();
      return (text: text, error: null);
    } catch (e) {
      return (text: null, error: 'Excepție: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'AI Assistant',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _toggleLanguage,
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              _english ? 'EN' : 'RO',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            tooltip: _ttsEnabled ? 'Dezactivează vocea' : 'Activează vocea',
            onPressed: () {
              setState(() => _ttsEnabled = !_ttsEnabled);
              if (!_ttsEnabled) _tts.stop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                return _MessageBubble(
                  message: _messages[index],
                  isDark: isDark,
                );
              },
            ),
          ),
          if (_isListening && _partialText.isNotEmpty)
            Container(
              width: double.infinity,
              color: isDark ? Colors.blue.shade900 : Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.mic,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _partialText,
                      style: TextStyle(
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                decoration: InputDecoration(
                  hintText: _english
                      ? 'E.g. I have 2 days and want mountains...'
                      : 'Ex: Am 2 zile și vreau la munte...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _MicButton(isListening: _isListening, onTap: _toggleListening),
            const SizedBox(width: 4),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              icon: const Icon(Icons.send, size: 20),
              onPressed: _isLoading
                  ? null
                  : () => _sendMessage(_textController.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isWelcome = false,
  });
  final String text;
  final bool isUser;
  final bool isWelcome;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isDark});
  final _ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.blue
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? Colors.white
                : (isDark ? Colors.white : Colors.black87),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final opacity = ((_ctrl.value - delay).abs() < 0.4)
                  ? 0.3 + 0.7 * _ctrl.value
                  : 0.3;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white54 : Colors.grey.shade500)
                      .withValues(alpha: opacity.clamp(0.3, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.isListening, required this.onTap});
  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening ? Colors.red : Colors.blue.shade700,
          boxShadow: isListening
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ]
              : [],
        ),
        child: Icon(
          isListening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
