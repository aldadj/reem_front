
import 'package:flutter_test/flutter_test.dart';
import 'package:reem_front/screens/main.dart';

void main() {
  testWidgets('REEM application builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ReemApp());

    // Vérifier que l'application démarre.
    expect(find.text('REEM'), findsOneWidget);

    // Laisser le délai du SplashScreen s'écouler.
    await tester.pump(const Duration(milliseconds: 1900));

    // Terminer la transition vers le fil d'actualité.
    await tester.pump(const Duration(milliseconds: 450));

    // Vérifier que l'application est toujours construite.
    expect(find.byType(ReemApp), findsOneWidget);
  });
}
