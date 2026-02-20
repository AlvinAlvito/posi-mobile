import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posi_mobile/main.dart';

void main() {
  testWidgets('NewChatPage renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewChatPage(
        initialTopic: 'Pendaftaran',
        initialCompetition: 'Pilih kompetisi',
        onCreate: (_, __, ___) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Chat Admin'), findsOneWidget);
    expect(find.text('Nama kompetisi'), findsOneWidget);
    expect(find.text('Perihal'), findsOneWidget);
    expect(find.text('Ringkasan masalah'), findsOneWidget);
  });
}
