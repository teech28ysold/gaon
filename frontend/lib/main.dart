import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const GaonApp());
}

class GaonApp extends StatelessWidget {
  const GaonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가온(Gaon) AI 비서',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 프리미엄 딥 틸(Deep Teal) & 소프트 민트 테마
        primaryColor: const Color(0xFF0F5A5C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F5A5C),
          primary: const Color(0xFF0F5A5C),
          secondary: const Color(0xFF28B59E),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F4F4),
        fontFamily: 'NanumGothic', // 기본 폰트 적용 및 글씨 크기 확장 대비
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isAnalyzingYoutube = false;
  bool _isHomeMode = true;
  List<String> _guardianNumbers = [];
  String? _currentlySpeakingText;
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _speechText = '';

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  // 4대 관심사 및 단축 질문 정의
  final List<Map<String, dynamic>> _shortcutCategories = [
    {
      'title': '🩺 건강 정보',
      'icon': Icons.medical_services_rounded,
      'color': const Color(0xFFE11D48),
      'bgColor': const Color(0xFFFFF1F2),
      'questions': [
        '고혈압 예방에 좋은 음식과 식습관 알려줘 😊',
        '무릎 관절통을 줄여주는 무리 없는 스트레칭 알려줘 🩺',
        '치매 예방을 위해 매일 쉽게 할 수 있는 뇌 운동 알려줘 🧠',
        '나이가 들면서 생기는 불면증 극복 방법 알려줘 💤',
      ],
    },
    {
      'title': '🍳 소화 잘되는 요리',
      'icon': Icons.restaurant_rounded,
      'color': const Color(0xFFD97706),
      'bgColor': const Color(0xFFFEF3C7),
      'questions': [
        '소화가 아주 잘되는 어르신 아침 죽 만드는 법 알려줘 🍳',
        '단백질이 가득해 뼈에 좋은 맛있는 두부 반찬 요리법 알려줘 🥘',
        '당뇨 환자도 맛있게 먹을 수 있는 저염식 나물 무침 알려줘 🥗',
        '기력 회복에 도움되는 초간단 삼계탕 끓이는 법 알려줘 🍲',
      ],
    },
    {
      'title': '⛰️ 추천 등산 코스',
      'icon': Icons.terrain_rounded,
      'color': const Color(0xFF059669),
      'bgColor': const Color(0xFFECFDF5),
      'questions': [
        '초보자도 무릎 아프지 않게 걷기 좋은 평탄한 둘레길 추천해줘 🚶‍♂️',
        '관절 무리 없이 상쾌하게 다녀올 수 있는 완만한 등산로 추천해줘 ⛰',
        '어르신들이 주말에 바람 쐬기 좋은 예쁜 생태 공원 알려줘 🌸',
        '피톤치드 마시며 힐링할 수 있는 전국 유명 숲길 알려줘 🌲',
      ],
    },
    {
      'title': '🌸 재미와 소식',
      'icon': Icons.emoji_emotions_rounded,
      'color': const Color(0xFF2563EB),
      'bgColor': const Color(0xFFEFF6FF),
      'questions': [
        '오늘 뇌 운동에 도움되는 재치 만점 퀴즈 하나 내줘 🧠',
        '마음이 차분해지는 따뜻한 시 한 편 다정하게 읽어줘 📝',
        '요즘 60~70대 친구들이 가장 선호하는 유익한 취미 생활 추천해줘 🎨',
        '은퇴 후에 나라에서 받을 수 있는 소소한 혜택이나 복지 정보 알려줘 🎁',
      ],
    },
  ];

  // 5. 카메라 이미지 촬영 및 서버 전송 로직
  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      final tempUserMessage = {
        'id': -1,
        'sender': 'user',
        'message': '📷 [사진] 문서 해독을 요청하셨습니다.',
        'timestamp': DateTime.now().toString(),
      };

      setState(() {
        _messages.add(tempUserMessage);
        _isSending = true;
        _isHomeMode = false;
      });
      _scrollToBottom();

      final bytes = await image.readAsBytes();
      final response = await ApiService.sendChatImage(bytes, image.name);

      if (response['status'] == 'success') {
        setState(() {
          final int tempIdx = _messages.indexOf(tempUserMessage);
          if (tempIdx != -1) {
            _messages[tempIdx] = response['user_message'];
          }
          _messages.add(response['ai_message']);
          _isSending = false;
        });
        _scrollToBottom();

        if (_guardianNumbers.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _showGuardianSmsAlert("부모님 문서/처방전 사진 분석 완료");
          });
        }
      }
    } catch (e) {
      setState(() {
        _isSending = false;
        _messages.removeWhere((msg) => msg['id'] == -1);
      });
      _showErrorSnackBar("이미지 분석 처리 중 오류가 발생했습니다. 다시 시도해 주세요.");
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGuardianNumbers();
    _loadHistory();
    _scheduleDailyReminders();

    // TTS 재생 완료/취소/에러 핸들러 설정
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
        });
      }
    });
    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
        });
      }
    });
    _flutterTts.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 보호자 번호 기기 로드 (마이그레이션 지원)
  Future<void> _loadGuardianNumbers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 하위 호환성: 기존 단일 등록 번호 가져와 마이그레이션
      final legacyNumber = prefs.getString('guardian_number') ?? '';
      List<String> loaded = prefs.getStringList('guardian_numbers') ?? [];

      if (legacyNumber.isNotEmpty) {
        if (!loaded.contains(legacyNumber)) {
          loaded.add(legacyNumber);
        }
        await prefs.setStringList('guardian_numbers', loaded);
        await prefs.remove('guardian_number'); // 마이그레이션 완료 후 이전 단일 키 제거
      }

      setState(() {
        _guardianNumbers = loaded;
      });
    } catch (e) {
      debugPrint("보호자 번호 로드 에러: $e");
    }
  }

  // 보호자 번호 기기 저장
  Future<void> _saveGuardianNumbers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('guardian_numbers', _guardianNumbers);
    } catch (e) {
      debugPrint("보호자 번호 저장 실패: $e");
    }
  }

  // 1. 이전 대화 내역 조회
  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = await ApiService.getHistory();
      setState(() {
        _messages.clear();
        _messages.addAll(history);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar("대화 내역을 불러오지 못했습니다. 백엔드 서버 상태를 확인해 주세요.");
    }
  }

  // 유튜브 링크 감지 헬퍼
  bool _isYoutubeUrl(String text) {
    final RegExp regExp = RegExp(
      r'(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/shorts\/|m\.youtube\.com\/watch\?v=)([a-zA-Z0-9_-]+)',
      caseSensitive: false,
    );
    return regExp.hasMatch(text);
  }

  // GPS 좌표 실시간 획득 헬퍼
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint("위치 정보 획득 실패: $e");
      return null;
    }
  }

  // 2. 메시지 전송
  Future<void> _sendMessage({String? customText}) async {
    final text = customText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (customText == null) {
      _textController.clear();
    }

    // UI에 사용자 메시지 선배치 (빠른 반응성 제공)
    final tempUserMessage = {
      'id': -1, // 임시 ID
      'sender': 'user',
      'message': text,
      'timestamp': DateTime.now().toString(),
      'msg_type': 'text',
    };

    final isYoutube = _isYoutubeUrl(text);

    setState(() {
      _messages.add(tempUserMessage);
      _isSending = true;
      _isHomeMode = false;
      if (isYoutube) {
        _isAnalyzingYoutube = true;
      }
    });
    _scrollToBottom();

    // 위치 관련 단어가 들어가거나 주변 시설 조회를 원할 때만 GPS 정보 로드
    Position? pos;
    final bool isLocationQuery =
        text.contains("주변") ||
        text.contains("근처") ||
        text.contains("병원") ||
        text.contains("약국") ||
        text.contains("날씨") ||
        text.contains("등산") ||
        text.contains("맛집") ||
        text.contains("위치");
    if (isLocationQuery) {
      pos = await _getCurrentLocation();
    }

    try {
      final response = await ApiService.sendChatMessage(
        text,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
      if (response['status'] == 'success') {
        setState(() {
          // 임시 사용자 메시지를 실제 DB 저장 완료된 메시지로 대체
          final int tempIdx = _messages.indexOf(tempUserMessage);
          if (tempIdx != -1) {
            _messages[tempIdx] = response['user_message'];
          }
          // AI 응답 추가
          _messages.add(response['ai_message']);
          _isSending = false;
          _isAnalyzingYoutube = false;
        });
        _scrollToBottom();

        // 일정 알람 정보가 반환된 경우 알림 설정
        if (response['schedule'] != null) {
          _scheduleLocalAlarm(Map<String, dynamic>.from(response['schedule']));
        }
      }
    } catch (e) {
      setState(() {
        _isSending = false;
        _isAnalyzingYoutube = false;
        // 실패 시 임시 메시지 삭제
        _messages.remove(tempUserMessage);
      });
      _showErrorSnackBar("서버 전송에 실패했습니다. 다시 시도해 주세요.");
    }
  }

  // 로컬 알람 예약 등록 헬퍼 함수
  void _scheduleLocalAlarm(Map<String, dynamic> schedule) {
    try {
      final id = schedule['id'] as int;
      final taskContent = schedule['task_content'] as String;
      final taskTimeStr = schedule['task_time'] as String;

      // taskTimeStr 형식: "YYYY-MM-DD HH:MM:SS" -> DateTime 파싱
      final DateTime scheduledTime = DateTime.parse(taskTimeStr);

      NotificationService.scheduleNotification(
        id: id,
        title: "⏰ 가온 비서 일정 알림",
        body: taskContent,
        scheduledDate: scheduledTime,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "🔔 알람 예약 완료: '$taskContent' (${taskTimeStr.substring(11, 16)})",
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF0F5A5C),
            duration: const Duration(seconds: 4),
          ),
        );

        if (_guardianNumbers.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _showGuardianSmsAlert("일정 및 알람 등록: $taskContent");
          });
        }
      }
    } catch (e) {
      debugPrint("로컬 알람 예약 등록 실패: $e");
    }
  }

  // 3. 대화 내역 초기화
  Future<void> _clearChatHistory() async {
    try {
      await ApiService.clearHistory();
      setState(() {
        _messages.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "대화 내역이 모두 초기화되었습니다.",
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar("초기화 실패: 백엔드 서버 상태를 확인해 주세요.");
    }
  }

  // 화면 스크롤 하단 이동
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

  // 에러 메시지 출력
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: "재시도",
          textColor: Colors.white,
          onPressed: _loadHistory,
        ),
      ),
    );
  }

  // 대화 비우기 확인 다이얼로그
  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "⚠️ 대화 비우기",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "이전 대화 내용이 모두 사라집니다.\n정말로 모든 대화를 지우시겠습니까?",
            style: TextStyle(fontSize: 18, height: 1.4),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "취소",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                _clearChatHistory();
              },
              child: const Text("지우기", style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  // 한국어 시간 도우미 함수 (2026-05-22 12:10:19 형식을 파싱)
  String _formatKoreanTime(String rawTimestamp) {
    try {
      final dateTime = DateTime.parse(rawTimestamp);
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final ampm = hour >= 12 ? "오후" : "오전";
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return "$ampm $displayHour:$minute";
    } catch (_) {
      // 파싱 실패시 날짜 제외하고 간략 출력 시도
      if (rawTimestamp.contains(" ")) {
        final parts = rawTimestamp.split(" ");
        if (parts.length > 1) {
          final timeParts = parts[1].split(":");
          if (timeParts.length > 1) {
            return "${timeParts[0]}:${timeParts[1]}";
          }
        }
      }
      return rawTimestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F5A5C),
        elevation: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "가온 (Gaon)",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              "나만의 다정한 AI 비서",
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (!_isHomeMode)
            IconButton(
              icon: const Icon(
                Icons.home_rounded,
                color: Colors.white,
                size: 28,
              ),
              tooltip: "처음 화면",
              onPressed: () {
                setState(() {
                  _isHomeMode = true;
                });
              },
            ),
          IconButton(
            icon: const Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: 28,
            ),
            tooltip: "보호자 등록",
            onPressed: _showGuardianRegisterDialog,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_sweep_rounded,
              color: Colors.white,
              size: 28,
            ),
            tooltip: "대화 비우기",
            onPressed: _showClearConfirmDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 보호자 연락처 항시 표시 바
          _buildGuardianBanner(),
          // 채팅 메시지 영역
          Expanded(child: _isHomeMode ? _buildPurposeHome() : _buildChatArea()),

          // 단축 질문 칩 영역
          if (!_isHomeMode) _buildQuickActionsRow(),

          // 하단 입력 & 마이크 & 카메라 영역 (단일 채팅 UI)
          if (!_isHomeMode) _buildBottomInputBar(),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0F5A5C)),
      );
    }

    if (_messages.isEmpty) {
      return _buildEmptyChatHint();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        // 대기 애니메이션 표시
        if (index == _messages.length) {
          return _buildTypingIndicator();
        }

        final msg = _messages[index];
        final isUser = msg['sender'] == 'user';
        final msgType = msg['msg_type'] ?? 'text';

        if (!isUser && msgType == 'fact_check') {
          return _buildFactCheckCard(
            messageJson: msg['message'] ?? '',
            timestamp: msg['timestamp'] ?? '',
          );
        }

        return _buildChatBubble(
          message: msg['message'] ?? '',
          isUser: isUser,
          timestamp: msg['timestamp'] ?? '',
        );
      },
    );
  }

  Widget _buildGuardianBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _guardianNumbers.isEmpty
            ? const Color(0xFFFFE4E6)
            : const Color(0xFFD1FAE5),
        border: Border(
          bottom: BorderSide(
            color: _guardianNumbers.isEmpty
                ? const Color(0xFFF43F5E)
                : const Color(0xFF10B981),
            width: 2.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  _guardianNumbers.isEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.verified_user_rounded,
                  color: _guardianNumbers.isEmpty
                      ? const Color(0xFFE11D48)
                      : const Color(0xFF047857),
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _guardianNumbers.isEmpty
                        ? "안심 문자를 받을 보호자 번호가 등록되지 않았습니다."
                        : _guardianNumbers.length == 1
                        ? "보호자 연락처: ${_guardianNumbers.first} 🛡️"
                        : "보호자 연락처: ${_guardianNumbers.first} 외 ${_guardianNumbers.length - 1}명 🛡️",
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      color: _guardianNumbers.isEmpty
                          ? const Color(0xFF9F1239)
                          : const Color(0xFF065F46),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _guardianNumbers.isEmpty
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF0F5A5C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _showGuardianRegisterDialog(),
            child: Text(
              _guardianNumbers.isEmpty ? "등록" : "관리",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: const [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFFE0F2F1),
                  child: Icon(
                    Icons.health_and_safety_rounded,
                    color: Color(0xFF0F5A5C),
                    size: 34,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "필요한 일을 바로 눌러주세요",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E272E),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildPurposeButton(
            icon: Icons.mic_rounded,
            title: "말로 물어보기",
            subtitle: "궁금한 것을 말하면 가온이 답해드립니다.",
            color: const Color(0xFF0F5A5C),
            bgColor: const Color(0xFFE0F2F1),
            onTap: _showVoiceDialog,
          ),
          _buildPurposeButton(
            icon: Icons.chat_bubble_rounded,
            title: "직접 질문하기",
            subtitle: "채팅 화면에서 자유롭게 질문합니다.",
            color: const Color(0xFF6D28D9),
            bgColor: const Color(0xFFF3E8FF),
            onTap: () {
              setState(() {
                _isHomeMode = false;
              });
              _scrollToBottom();
            },
          ),
          _buildPurposeButton(
            icon: Icons.alarm_rounded,
            title: "일정 알림",
            subtitle: "복용 시간이나 병원 일정을 알림으로 등록합니다.",
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
            onTap: _showScheduleHelpDialog,
          ),
          _buildPurposeButton(
            icon: Icons.family_restroom_rounded,
            title: "자녀 안심 알림",
            subtitle: "보호자에게 안부 문자를 보냅니다.",
            color: const Color(0xFF16A34A),
            bgColor: const Color(0xFFF0FDF4),
            onTap: _sendGuardianSafetyAlert,
          ),
          _buildPurposeButton(
            icon: Icons.document_scanner_rounded,
            title: "문서 읽기",
            subtitle: "안내문, 처방전, 약봉투를 사진으로 읽습니다.",
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFEF3C7),
            onTap: _pickAndSendImage,
          ),
          _buildPurposeButton(
            icon: Icons.ondemand_video_rounded,
            title: "영상 확인",
            subtitle: "유튜브 링크가 믿을 만한지 확인합니다.",
            color: const Color(0xFFE11D48),
            bgColor: const Color(0xFFFFF1F2),
            onTap: _showYoutubeCheckDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(60), width: 1.5),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E272E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 15.5,
                          color: Colors.black54,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withAlpha(170),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: Color(0xFF0F5A5C),
            ),
            SizedBox(height: 14),
            Text(
              "아래 입력창이나 마이크로\n편하게 물어보세요.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E272E),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showYoutubeCheckDialog() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "영상 확인",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: urlController,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: "유튜브 링크",
              hintText: "https://youtu.be/...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(fontSize: 18)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isEmpty) return;
                Navigator.pop(context);
                _sendMessage(
                  customText: "이 유튜브 영상이 어르신이 믿고 봐도 되는 영상인지 확인해줘: $url",
                );
              },
              child: const Text("확인하기", style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  void _showScheduleHelpDialog() {
    final scheduleController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "약과 일정 알림",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scheduleController,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: "예: 오늘 저녁 8시에 혈압약 알림",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text(
                      "1분 뒤 약 알림",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _sendMessage(customText: "1분 뒤에 약 먹기 알림 등록해줘");
                    },
                  ),
                  ActionChip(
                    label: const Text(
                      "오늘 저녁 8시",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _sendMessage(customText: "오늘 저녁 8시에 약 먹기 알림 등록해줘");
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  final text = scheduleController.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(context);
                  _sendMessage(customText: text);
                },
                child: const Text(
                  "알림 등록하기",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 환영 웰컴 스크린 (시니어 대시보드 구조 - 줄바꿈 방지를 위해 1열 목록으로 개선)
  // ignore: unused_element
  Widget _buildWelcomeWidget() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 로고 영역 (더 심플하고 고급스럽게)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F5A5C).withAlpha(12),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 56,
              color: Color(0xFF0F5A5C),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "반갑습니다, 아버님 어머님! 🌸",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E272E),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "말씀하시기 편하도록 자주 찾는 질문들을 모아두었어요.\n아래 카테고리 중 하나를 눌러 편하게 질문해 보세요! 😊",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16.5,
              color: Colors.blueGrey,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // 카테고리 대형 버튼 목록 (줄바꿈 원천 차단을 위해 가로 1열 카드 형태로 변경)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _shortcutCategories.length,
            itemBuilder: (context, index) {
              final cat = _shortcutCategories[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  onTap: () => _showShortcutQuestions(cat),
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: cat['bgColor'],
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cat['color'].withAlpha(40),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cat['color'].withAlpha(10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(cat['icon'], size: 36, color: cat['color']),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            cat['title'],
                            style: const TextStyle(
                              fontSize: 20, // 큰 글씨에서도 줄바꿈 걱정 없음
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E272E),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                          color: cat['color'].withAlpha(150),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 자녀 안심 알림 퀵 카드
          InkWell(
            onTap: () => _sendGuardianSafetyAlert(),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withAlpha(10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mail_outline_rounded,
                    size: 36,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "✉️ 자녀에게 안심 안부 보내기",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "부모님이 잘 계신다는 문자를 자녀분께 보내드립니다.",
                          style: TextStyle(
                            fontSize: 14.5,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF16A34A),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 단축 질문 목록 바텀 시트 열기
  void _showShortcutQuestions(Map<String, dynamic> category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(category['icon'], color: category['color'], size: 30),
                    const SizedBox(width: 8),
                    Text(
                      "${category['title']} 추천 질문",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E272E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  "가온 비서에게 물어보고 싶은 문장을 터치해 보세요.",
                  style: TextStyle(fontSize: 15.5, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: (category['questions'] as List).length,
                    itemBuilder: (context, index) {
                      final question = category['questions'][index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E272E),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            side: BorderSide(
                              color: category['color'].withAlpha(60),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _textController.text = question;
                            _sendMessage();
                          },
                          child: Text(
                            question,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 자녀 안심 안부 알림 전송 모의 처리
  void _sendGuardianSafetyAlert() {
    if (_guardianNumbers.isEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 28,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "보호자 등록 필요",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: const Text(
              "등록된 보호자(자녀) 번호가 없습니다.\n먼저 자녀분의 번호를 등록해 주세요.",
              style: TextStyle(fontSize: 17, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "닫기",
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5A5C),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showGuardianRegisterDialog();
                },
                child: const Text("등록하기", style: TextStyle(fontSize: 18)),
              ),
            ],
          );
        },
      );
      return;
    }

    final targetNames = _guardianNumbers.join(', ');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.mark_email_read_rounded,
                color: Color(0xFF16A34A),
                size: 28,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "안심 안부 문자 전송",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            "보호자 연락처 ($targetNames) 로 아래 안심 문자를 전송하시겠습니까?\n\n\"[가온 안심알림] 부모님께서 가온 비서를 사용 중이시며, 현재 건강하게 잘 계신다고 안부를 전하셨습니다. 😊\"",
            style: const TextStyle(
              fontSize: 17,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "취소",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _showGuardianSmsAlert("부모님 안심 안부 전송");
              },
              child: const Text("보내기", style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  // 가온 비서 생각중(대기) 표시
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0F5A5C),
            radius: 20,
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "가온 AI",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(8),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0F5A5C),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _isAnalyzingYoutube
                              ? "가온이가 유튜브 영상을 꼼꼼하게 팩트 체크하는 중입니다..."
                              : (_messages.isNotEmpty &&
                                        _messages.last['message']
                                            .toString()
                                            .contains("📷")
                                    ? "가온이가 사진을 읽고 분석하는 중입니다..."
                                    : "가온이가 생각하고 있습니다..."),
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4단계: 정보 방패 - 유튜브 팩트 체크 커스텀 카드 UI
  Widget _buildFactCheckCard({
    required String messageJson,
    required String timestamp,
  }) {
    Map<String, dynamic> data;
    try {
      data = json.decode(messageJson);
    } catch (e) {
      // JSON 파싱 실패시 폴백으로 일반 메시지 렌더링
      return _buildChatBubble(
        message: messageJson,
        isUser: false,
        timestamp: timestamp,
      );
    }

    final category = data['category'] ?? '기타';
    final status = data['status'] ?? 'safe'; // warning 또는 safe
    final summary = data['summary'] ?? '';
    final details = data['details'] ?? '';
    final formattedTime = _formatKoreanTime(timestamp);

    final isWarning = status == 'warning';

    // 카드 테마 색상 설정
    final cardBorderColor = isWarning
        ? const Color(0xFFE11D48)
        : const Color(0xFF10B981);
    final cardBgColor = isWarning
        ? const Color(0xFFFFF1F2)
        : const Color(0xFFECFDF5);
    final bannerBgColor = isWarning
        ? const Color(0xFFFFE4E6)
        : const Color(0xFFD1FAE5);
    final bannerTextColor = isWarning
        ? const Color(0xFF9F1239)
        : const Color(0xFF065F46);
    final iconColor = isWarning
        ? const Color(0xFFE11D48)
        : const Color(0xFF047857);
    final iconData = isWarning
        ? Icons.warning_amber_rounded
        : Icons.verified_user_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0F5A5C),
            radius: 22,
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "가온 비서 (정보 방패 🛡️)",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cardBorderColor,
                            width: isWarning ? 3.5 : 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. 상태 배너 및 카테고리 뱃지
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: bannerBgColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(14),
                                  topRight: Radius.circular(14),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(iconData, color: iconColor, size: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isWarning
                                          ? "⚠️ 경고: 의심스러운 정보!"
                                          : "✅ 검증 완료: 안전한 정보!",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: bannerTextColor,
                                      ),
                                    ),
                                  ),
                                  // 카테고리 표시
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isWarning
                                          ? const Color(0xFFFFC9C9)
                                          : const Color(0xFFBBF7D0),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: bannerTextColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 2. 요약 내용 영역
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "📋 가온이의 3줄 요약 및 분석",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E272E),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    summary,
                                    style: const TextStyle(
                                      fontSize: 19.2, // 시니어 1.2배 큰 글씨 적용
                                      color: Color(0xFF2C3E50),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 구분선
                            Divider(
                              color: cardBorderColor.withAlpha(100),
                              height: 1,
                              thickness: 1,
                            ),
                            // 3. 상세내용 펼치기 영역
                            FactCheckDetailsExpander(
                              details: details,
                              borderColor: cardBorderColor,
                              textColor: const Color(0xFF2C3E50),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formattedTime,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 카카오톡 스타일 말풍선 (가독성 극대화 및 깔끔한 대형 텍스트)
  Widget _buildChatBubble({
    required String message,
    required bool isUser,
    required String timestamp,
  }) {
    final formattedTime = _formatKoreanTime(timestamp);

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 14, color: Colors.black45),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7), // 아늑하고 높은 대비의 소프트 옐로우
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(1, 2),
                    ),
                  ],
                ),
                child: SelectableText(
                  message,
                  style: const TextStyle(
                    fontSize: 21.0, // 시니어 가독성을 위한 대형 글씨 (21px)
                    color: Color(0xFF1F2937),
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 가온 프로필 아바타
            CircleAvatar(
              backgroundColor: const Color(0xFF0F5A5C),
              radius: 24,
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "가온 비서",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SelectableText(
                          message,
                          style: const TextStyle(
                            fontSize: 21.0, // 시니어 가독성을 위한 대형 글씨 (21px)
                            color: Color(0xFF111827),
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // TTS 재생/중지 아이콘 버튼
                          _currentlySpeakingText == message
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.stop_circle_rounded,
                                    color: Colors.redAccent,
                                    size: 28,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: _stopTts,
                                  tooltip: "읽기 중지",
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.volume_up_rounded,
                                    color: Color(0xFF28B59E),
                                    size: 26,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _playSimulatedTts(message),
                                  tooltip: "음성으로 듣기",
                                ),
                          const SizedBox(width: 10),
                          Text(
                            formattedTime,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  // 화면 하단 싱글 UI 바 (대비 개선 및 글씨 확대)
  Widget _buildBottomInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 1. 카메라 버튼
            _buildCircularIconButton(
              icon: Icons.camera_alt_rounded,
              color: const Color(0xFF0F5A5C),
              tooltip: "카메라 찍기",
              onPressed: _pickAndSendImage,
            ),
            const SizedBox(width: 10),

            // 2. 마이크 버튼
            _buildCircularIconButton(
              icon: Icons.mic_rounded,
              color: const Color(0xFF0F5A5C),
              tooltip: "목소리로 말하기",
              onPressed: _showVoiceDialog,
            ),
            const SizedBox(width: 10),

            // 3. 텍스트 입력창
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: const Color(0xFFD1D5DB),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: "가온에게 물어보세요...",
                    hintStyle: TextStyle(fontSize: 20, color: Colors.black45),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // 4. 전송 버튼
            _buildCircularIconButton(
              icon: Icons.send_rounded,
              color: const Color(0xFF0F5A5C),
              tooltip: "보내기",
              onPressed: () => _sendMessage(),
            ),
          ],
        ),
      ),
    );
  }

  // 공용 동그란 아이콘 버튼 헬퍼
  Widget _buildCircularIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        textStyle: const TextStyle(fontSize: 16, color: Colors.white),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withAlpha(31),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
      ),
    );
  }

  // 5단계: 보호자 자녀 번호 등록 대화상자 (다중 보호자 등록 지원)
  void _showGuardianRegisterDialog() {
    final newNumberController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: const [
                  Icon(
                    Icons.family_restroom_rounded,
                    color: Color(0xFF0F5A5C),
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "보호자 연락처 관리",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "자녀분들의 연락처를 등록해 주세요. 일정이 예약되거나 안심 알림 시 등록된 모든 연락처로 문자가 발송됩니다.",
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 등록된 연락처 리스트
                    if (_guardianNumbers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            "등록된 보호자 연락처가 없습니다.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black38,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _guardianNumbers.length,
                          itemBuilder: (context, index) {
                            final number = _guardianNumbers[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    number,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _guardianNumbers.removeAt(index);
                                      });
                                      setDialogState(() {}); // 다이얼로그 상태 갱신
                                      _saveGuardianNumbers();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newNumberController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              labelText: "새 보호자 번호",
                              labelStyle: TextStyle(fontSize: 14),
                              hintText: "예: 010-1234-5678",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F5A5C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            final newNum = newNumberController.text.trim();
                            if (newNum.isNotEmpty) {
                              setState(() {
                                if (!_guardianNumbers.contains(newNum)) {
                                  _guardianNumbers.add(newNum);
                                }
                              });
                              setDialogState(() {});
                              newNumberController.clear();
                              _saveGuardianNumbers();
                            }
                          },
                          child: const Text(
                            "추가",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5A5C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("닫기", style: TextStyle(fontSize: 18)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 5단계: 보호자 안심문자 시각화 모달
  void _showGuardianSmsAlert(String alertType) async {
    if (_guardianNumbers.isEmpty) return;

    final targetNames = _guardianNumbers.join(', ');

    // 백엔드로 가상 SMS 전송 요청 발송 (비동기 호출)
    String smsContent = "[가온 안심알림] 부모님께서 가온 비서를 사용 중이십니다.";
    if (alertType.contains("안심 안부 전송")) {
      smsContent =
          "[가온 안심알림] 부모님께서 가온 비서를 사용 중이시며, 현재 건강하게 잘 계신다고 안부를 전하셨습니다. 😊";
    } else if (alertType.contains("사진 분석")) {
      smsContent =
          "[가온 안심알림] 부모님께서 약봉투/처방전 사진 분석을 완료하셨습니다. 건강을 잘 챙기고 계십니다. 🛡️";
    } else if (alertType.contains("등록:")) {
      smsContent =
          "[가온 안심알림] 부모님께서 새로운 일정을 등록하셨습니다: ${alertType.split(':').last.trim()} 🔔";
    } else {
      smsContent = "[가온 안심알림] 알림: $alertType";
    }

    String deliveryTitle = "안심 문자 요청 완료 ✉️";
    String deliveryMessage =
        "보호자 연락처 ($targetNames)로\n'$alertType' 안심 알림 문자를 요청했습니다.";
    try {
      final value = await ApiService.sendSms(_guardianNumbers, smsContent);
      final mode = value['mode'] ?? 'mock';
      debugPrint("SMS 백엔드 전송 성공: $value");
      if (mode == 'live') {
        deliveryTitle = "안심 문자 발송 완료 ✉️";
        deliveryMessage =
            "보호자 연락처 ($targetNames)로\n'$alertType' 안심 알림 문자를 실제 발송 요청했습니다.\n\n자녀분들이 부모님의 건강 활동 소식을 받고 안심하실 수 있어요! 😊";
      } else {
        deliveryTitle = "안심 문자 테스트 완료";
        deliveryMessage =
            "보호자 연락처 ($targetNames)로 보낼 문자가 테스트 모드로 기록되었습니다.\n\n실제 문자 발송은 서버에 문자 API 키와 발신번호를 설정하면 바로 사용할 수 있습니다.";
      }
    } catch (err) {
      debugPrint("SMS 백엔드 전송 에러: $err");
      deliveryTitle = "문자 발송 확인 필요";
      deliveryMessage = "안심 문자 요청 중 오류가 발생했습니다.\n\n보호자 연락처와 서버 문자 설정을 확인해 주세요.";
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                color: Color(0xFF28B59E),
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  deliveryTitle,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            deliveryMessage,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5A5C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("확인", style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  // 5단계: 선제 안부 로컬 알림 루틴 등록
  void _scheduleDailyReminders() {
    try {
      final now = DateTime.now();

      // 아침 9시 알림 예약
      var morningTime = DateTime(now.year, now.month, now.day, 9, 0, 0);
      if (morningTime.isBefore(now)) {
        morningTime = morningTime.add(const Duration(days: 1));
      }

      // 오후 2시 알림 예약
      var afternoonTime = DateTime(now.year, now.month, now.day, 14, 0, 0);
      if (afternoonTime.isBefore(now)) {
        afternoonTime = afternoonTime.add(const Duration(days: 1));
      }

      NotificationService.scheduleNotification(
        id: 9991,
        title: "🌸 가온 AI 안부 알림",
        body: "아버님 어머님, 좋은 아침이에요! 오늘 아침약 꼭 챙겨 드세요! 😊",
        scheduledDate: morningTime,
      );

      NotificationService.scheduleNotification(
        id: 9992,
        title: "🚶‍♂️ 가온 AI 안부 알림",
        body: "따뜻한 오후네요! 가벼운 산책으로 굳은 몸을 부드럽게 풀어주세요. 🌸",
        scheduledDate: afternoonTime,
      );
    } catch (e) {
      debugPrint("선제 안부 알림 설정 실패: $e");
    }
  }

  // 5단계: 가온이의 말 대리 읽기 시뮬레이션 ➡️ 실제 TTS 음성 출력으로 변경!
  void _playSimulatedTts(String text) async {
    try {
      await _flutterTts.stop(); // 먼저 재생 중인 것 중지

      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(
        0.5,
      ); // 시니어가 듣기 편하도록 속도를 약간 천천히 설정 (기본값 0.5가 적당)
      await _flutterTts.setPitch(1.0); // 표준 피치

      // 팩트체크용 JSON 문자열이 들어온 경우 요약문과 세부내용만 발음하도록 필터링
      String speakText = text;
      if (text.startsWith('{') && text.contains('category')) {
        try {
          final data = json.decode(text);
          final summary = data['summary'] ?? '';
          final details = data['details'] ?? '';
          speakText = "가온이의 분석 결과입니다. $summary. 상세 내용은 다음과 같습니다. $details";
          // 줄바꿈이나 기호 제거하여 읽기 좋게 정제
          speakText = speakText.replaceAll('\n', ' ');
        } catch (_) {}
      }

      setState(() {
        _currentlySpeakingText = text;
      });

      await _flutterTts.speak(speakText);

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.volume_up_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "🔊 가온이가 다정한 목소리로 읽어 드리고 있습니다... 🎧",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  _stopTts();
                },
                child: const Text(
                  "중지",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.yellowAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF28B59E),
          duration: const Duration(seconds: 15), // 넉넉하게 재생시간 보장
        ),
      );
    } catch (e) {
      debugPrint("TTS 재생 실패: $e");
    }
  }

  // TTS 읽기 중지 함수
  void _stopTts() async {
    try {
      await _flutterTts.stop();
      if (mounted) {
        setState(() {
          _currentlySpeakingText = null;
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.volume_off_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "🔇 음성 읽기를 중지했습니다.",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("TTS 중지 실패: $e");
    }
  }

  // 시니어용 단축 질문 바 (깔끔한 2버튼 형태로 화면 간소화)
  Widget _buildQuickActionsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFF0F4F4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5A5C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "🌟 가온 추천 질문 테마",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E272E),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _shortcutCategories.length,
                            itemBuilder: (context, index) {
                              final cat = _shortcutCategories[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showShortcutQuestions(cat);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Ink(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cat['bgColor'],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: cat['color'].withAlpha(40),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          cat['icon'],
                                          size: 28,
                                          color: cat['color'],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            cat['title'],
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E272E),
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 14,
                                          color: cat['color'].withAlpha(150),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.stars_rounded, size: 22),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "가온 추천 질문 🌟",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _sendGuardianSafetyAlert,
              icon: const Icon(Icons.mail_rounded, size: 22),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "자녀 안심 문자 ✉️",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 음성 인식 시작/종료 처리 함수
  void _toggleListening(StateSetter setModalState) async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          debugPrint("STT Status: $status");
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setModalState(() {
                _isListening = false;
              });
            }
          }
        },
        onError: (errorNotification) {
          debugPrint("STT Error: $errorNotification");
          if (mounted) {
            setModalState(() {
              _isListening = false;
            });
          }
        },
      );

      if (available) {
        setModalState(() {
          _isListening = true;
          _speechText = '';
        });
        _speech.listen(
          onResult: (result) {
            if (mounted) {
              setModalState(() {
                _speechText = result.recognizedWords;
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(localeId: "ko_KR"),
        );
      } else {
        debugPrint(
          "The user has denied the use of speech recognition or it's not available.",
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("음성 인식을 시작할 수 없습니다. 마이크 권한을 확인해 주세요."),
            ),
          );
        }
      }
    } else {
      _speech.stop();
      setModalState(() {
        _isListening = false;
      });
    }
  }

  // 실시간 음성 인식 연동 다이얼로그 (바텀시트 형식, 키보드 대응 및 오버플로우 방지)
  void _showVoiceDialog() {
    _speechText = '';
    _isListening = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 키보드 유연 반응
      isDismissible: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // 바텀시트가 열리면 마이크 음성인식 즉시 시작
            if (!_isListening && _speechText.isEmpty && !_speech.isListening) {
              Future.delayed(Duration.zero, () {
                _toggleListening(setModalState);
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // 키보드 대응 여백
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 드래그 핸들
                      Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 녹음 상태 및 파형 애니메이션
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isListening) ...[
                            const Icon(
                              Icons.graphic_eq_rounded,
                              size: 40,
                              color: Color(0xFF28B59E),
                            ),
                            const SizedBox(width: 8),
                          ],
                          GestureDetector(
                            onTap: () => _toggleListening(setModalState),
                            child: Ink(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: _isListening
                                    ? const Color(0xFF28B59E).withAlpha(40)
                                    : const Color(0xFF0F5A5C).withAlpha(30),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isListening
                                      ? const Color(0xFF28B59E)
                                      : const Color(0xFF0F5A5C),
                                  width: 3,
                                ),
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                size: 54,
                                color: _isListening
                                    ? const Color(0xFF28B59E)
                                    : const Color(0xFF0F5A5C),
                              ),
                            ),
                          ),
                          if (_isListening) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.graphic_eq_rounded,
                              size: 40,
                              color: Color(0xFF28B59E),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        _isListening
                            ? "아버님 어머님, 듣고 있어요! 편하게 말씀하세요 🎙️"
                            : "아래 마이크를 누르고 말씀해 보세요.",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F5A5C),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // 실시간 인식 내용 텍스트 박스
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          minHeight: 100,
                          maxHeight: 140,
                        ),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _speechText.isEmpty
                                ? "여기에 말씀하신 내용이 나옵니다."
                                : _speechText,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _speechText.isEmpty
                                  ? Colors.black38
                                  : const Color(0xFF1E272E),
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 액션 제어 버튼 (닫기, 다시 말하기, 보내기)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              if (_isListening) {
                                _speech.stop();
                              }
                              Navigator.pop(context);
                            },
                            child: const Text(
                              "닫기",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                          if (_speechText.isNotEmpty)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                setModalState(() {
                                  _speechText = '';
                                });
                                _toggleListening(setModalState);
                              },
                              child: const Text(
                                "다시 말하기",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF0F5A5C),
                                ),
                              ),
                            ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F5A5C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 30,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _speechText.isEmpty
                                ? null
                                : () {
                                    if (_isListening) {
                                      _speech.stop();
                                    }
                                    _textController.text = _speechText;
                                    Navigator.pop(context);
                                    _sendMessage();
                                  },
                            child: const Text(
                              "보내기",
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Divider(color: Colors.grey[200]),
                      const SizedBox(height: 10),

                      const Text(
                        "💡 자주 하시는 질문을 바로 선택하셔도 좋습니다:",
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ActionChip(
                            label: const Text(
                              "☀️ 오늘 날씨 어때?",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            onPressed: () {
                              if (_isListening) _speech.stop();
                              Navigator.pop(context);
                              _textController.text = "오늘 날씨 어때?";
                              _sendMessage();
                            },
                          ),
                          ActionChip(
                            label: const Text(
                              "💊 아침 약 복용 확인",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            onPressed: () {
                              if (_isListening) _speech.stop();
                              Navigator.pop(context);
                              _textController.text = "오늘 아침 약 먹은 기록 확인해줘";
                              _sendMessage();
                            },
                          ),
                          ActionChip(
                            label: const Text(
                              "⏰ 1분 뒤 약먹기 알람",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            onPressed: () {
                              if (_isListening) _speech.stop();
                              Navigator.pop(context);
                              _textController.text = "1분 뒤에 아침약 복용 알람 등록해줘";
                              _sendMessage();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // 바텀시트가 닫힐 때 음성인식이 계속 돌고 있다면 안전하게 정지
      if (_speech.isListening) {
        _speech.stop();
      }
    });
  }
}

// 4단계: 정보 방패 - 상세 분석 내용을 접고 펼칠 수 있는 인터랙티브 위젯
class FactCheckDetailsExpander extends StatefulWidget {
  final String details;
  final Color borderColor;
  final Color textColor;

  const FactCheckDetailsExpander({
    super.key,
    required this.details,
    required this.borderColor,
    required this.textColor,
  });

  @override
  State<FactCheckDetailsExpander> createState() =>
      _FactCheckDetailsExpanderState();
}

class _FactCheckDetailsExpanderState extends State<FactCheckDetailsExpander> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isExpanded ? "상세 분석 내용 접기 🔼" : "상세 분석 내용 전체 보기 🔽",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: widget.borderColor,
                  ),
                ),
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: widget.borderColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: SelectableText(
              widget.details,
              style: TextStyle(
                fontSize: 18,
                color: widget.textColor,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}
