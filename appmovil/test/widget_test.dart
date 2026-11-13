import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planeacion_academica/main.dart';

void main() {
  testWidgets('La app arranca mostrando login o shell', (WidgetTester tester) async {
    await tester.pumpWidget(const PlaneacionApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
