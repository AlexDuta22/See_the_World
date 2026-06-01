import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:see_the_world/components/my_button.dart';

void main() {
  testWidgets('MyButton shows its label and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyButton(text: 'Sign In', onTap: () => taps++),
        ),
      ),
    );

    expect(find.text('Sign In'), findsOneWidget);

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(taps, 1);
  });
}
