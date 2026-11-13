import 'package:flutter_test/flutter_test.dart';

import 'package:velocimetro/main.dart';

void main() {
  testWidgets('Velocímetro muestra la app', (WidgetTester tester) async {
    await tester.pumpWidget(const VelocimetroApp());
    await tester.pump();

    expect(find.text('Velocímetro Pro'), findsOneWidget);
    expect(find.text('INICIAR VELOCÍMETRO'), findsOneWidget);
    expect(find.text('KM/H'), findsOneWidget);
  });
}
