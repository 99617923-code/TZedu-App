import 'package:flutter_test/flutter_test.dart';
import 'package:tz_ielts/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const TZIeltsApp());
    expect(find.text('途正英语'), findsWidgets);
  });
}
