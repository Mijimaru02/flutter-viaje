import 'package:flutter_test/flutter_test.dart';
import 'package:viajeencomun/features/expenses/expense_calculator.dart';

void main() {
  group('ExpenseCalculator.splitEqually', () {
    test('assigns leftover cents in selection order', () {
      final allocations = ExpenseCalculator.splitEqually(1000, ['a', 'b', 'c']);

      expect(allocations.map((allocation) => allocation.amountCents), [
        334,
        333,
        333,
      ]);
      expect(allocations.map((allocation) => allocation.userId), [
        'a',
        'b',
        'c',
      ]);
    });

    test('rejects empty or repeated participants', () {
      expect(
        () => ExpenseCalculator.splitEqually(100, []),
        throwsArgumentError,
      );
      expect(
        () => ExpenseCalculator.splitEqually(100, ['a', 'a']),
        throwsArgumentError,
      );
    });
  });

  group('ExpenseCalculator.validateCustomSplit', () {
    test('accepts a split equal to the total', () {
      final result = ExpenseCalculator.validateCustomSplit(
        amountCents: 2000,
        amountsByUser: {'a': 1000, 'b': 1000},
      );

      expect(result.map((allocation) => allocation.amountCents), [1000, 1000]);
    });

    test('rejects a split that is off by one cent', () {
      expect(
        () => ExpenseCalculator.validateCustomSplit(
          amountCents: 2000,
          amountsByUser: {'a': 1000, 'b': 999},
        ),
        throwsStateError,
      );
    });
  });

  test('calculates balances for the Lisbon example and sums to zero', () {
    final balances = ExpenseCalculator.calculateBalances(
      memberIds: ['ana', 'marcos', 'lucia'],
      expenses: [
        ExpenseRecord(
          paidBy: 'ana',
          amountCents: 12000,
          allocations: const [
            ExpenseAllocation(userId: 'ana', amountCents: 4000),
            ExpenseAllocation(userId: 'marcos', amountCents: 4000),
            ExpenseAllocation(userId: 'lucia', amountCents: 4000),
          ],
        ),
        ExpenseRecord(
          paidBy: 'marcos',
          amountCents: 3000,
          allocations: const [
            ExpenseAllocation(userId: 'marcos', amountCents: 1500),
            ExpenseAllocation(userId: 'lucia', amountCents: 1500),
          ],
        ),
      ],
    );

    expect(balances['ana']!.balanceCents, 8000);
    expect(balances['marcos']!.balanceCents, -2500);
    expect(balances['lucia']!.balanceCents, -5500);
    expect(
      balances.values.fold<int>(
        0,
        (sum, balance) => sum + balance.balanceCents,
      ),
      0,
    );
  });
}
