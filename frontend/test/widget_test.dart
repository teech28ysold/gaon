import 'package:flutter_test/flutter_test.dart';

import 'package:gaon_frontend/main.dart';

void main() {
  testWidgets('GaonApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GaonApp());
    await tester.pumpAndSettle();

    // '가온 (Gaon)' 앱바 제목이 화면에 정상적으로 노출되는지 확인
    expect(find.text('가온 (Gaon)'), findsOneWidget);
  });
}
