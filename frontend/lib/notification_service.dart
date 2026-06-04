import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart' show debugPrint;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 초기화 함수
  static Future<void> init() async {
    // 1) 타임존 데이터 로드 및 로컬 타임존 설정 (기본값 서울)
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (e) {
      debugPrint("타임존 설정 실패: $e");
    }

    try {
      // 2) 안드로이드 초기화 설정
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // 3) iOS 초기화 설정
      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      // 4) 플러그인 초기화 실행 (v21.0.0에서 settings 파라미터는 named parameter임)
      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // 알림 클릭 시 추가 작업이 필요할 경우 여기에 구현
        },
      );

      // 5) Android 13 이상 권한 명시적 요청
      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        try {
          await androidPlugin.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint("정확한 알람 권한 요청 실패: $e");
        }
      }
    } catch (e) {
      debugPrint("알림 서비스 초기화 실패: $e");
    }
  }

  // 지정된 시간에 알림 예약 등록 함수
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // DateTime을 Timezone 패키지 전용 TZDateTime 객체로 변환
    final tz.TZDateTime tzDateTime = tz.TZDateTime.from(scheduledDate, tz.local);

    // 이미 지난 시간이면 등록하지 않고 리턴
    if (tzDateTime.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'schedule_channel_id', // 채널 ID
      '가온 일정 알림', // 채널 이름
      channelDescription: '가온 AI 비서의 일정 알림 채널입니다.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    // 알림 예약 실행 (v21.0.0에서는 모든 인자가 named parameter임)
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzDateTime,
      notificationDetails: platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // 예약된 특정 알림 취소 함수
  static Future<void> cancelNotification(int id) async {
    // v21.0.0에서 cancel도 named parameter를 사용함
    await _notificationsPlugin.cancel(id: id);
  }

  // 모든 예약 알림 취소 함수
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}
