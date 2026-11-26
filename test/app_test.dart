import 'package:flutter_test/flutter_test.dart';
import 'package:viajeencomun/app.dart';

void main() {
  testWidgets('shows setup guidance when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const ViajeEnComunApp());

    expect(find.text('Falta configurar Supabase'), findsOneWidget);
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
  });
}
