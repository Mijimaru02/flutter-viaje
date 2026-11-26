class ExpenseAllocation {
  const ExpenseAllocation({required this.userId, required this.amountCents});

  final String userId;
  final int amountCents;
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.paidBy,
    required this.amountCents,
    required this.allocations,
  });

  final String paidBy;
  final int amountCents;
  final List<ExpenseAllocation> allocations;
}

class MemberBalance {
  const MemberBalance({required this.paidCents, required this.assignedCents});

  final int paidCents;
  final int assignedCents;

  int get balanceCents => paidCents - assignedCents;
}

class ExpenseCalculator {
  const ExpenseCalculator._();

  static List<ExpenseAllocation> splitEqually(
    int amountCents,
    List<String> selectedUserIds,
  ) {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'Must be positive');
    }
    if (selectedUserIds.isEmpty ||
        selectedUserIds.toSet().length != selectedUserIds.length) {
      throw ArgumentError.value(
        selectedUserIds,
        'selectedUserIds',
        'Select at least one unique participant',
      );
    }

    final quotient = amountCents ~/ selectedUserIds.length;
    final remainder = amountCents % selectedUserIds.length;
    return List.generate(
      selectedUserIds.length,
      (index) => ExpenseAllocation(
        userId: selectedUserIds[index],
        amountCents: quotient + (index < remainder ? 1 : 0),
      ),
      growable: false,
    );
  }

  static List<ExpenseAllocation> validateCustomSplit({
    required int amountCents,
    required Map<String, int> amountsByUser,
  }) {
    if (amountCents <= 0 || amountsByUser.isEmpty) {
      throw ArgumentError('The amount and participant list must be positive.');
    }
    if (amountsByUser.values.any((amount) => amount < 0)) {
      throw ArgumentError('Participant amounts cannot be negative.');
    }
    final sum = amountsByUser.values.fold<int>(
      0,
      (total, value) => total + value,
    );
    if (sum != amountCents) {
      throw StateError('The split must equal the expense total.');
    }
    return amountsByUser.entries
        .map(
          (entry) =>
              ExpenseAllocation(userId: entry.key, amountCents: entry.value),
        )
        .toList(growable: false);
  }

  static Map<String, MemberBalance> calculateBalances({
    required Iterable<String> memberIds,
    required Iterable<ExpenseRecord> expenses,
  }) {
    final totals = {
      for (final id in memberIds) id: [0, 0],
    };
    for (final expense in expenses) {
      if (expense.amountCents <= 0 || !totals.containsKey(expense.paidBy)) {
        throw FormatException('Expense contains an invalid payer or total.');
      }
      final assigned = expense.allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.amountCents,
      );
      if (assigned != expense.amountCents ||
          expense.allocations.any(
            (allocation) =>
                allocation.amountCents < 0 ||
                !totals.containsKey(allocation.userId),
          )) {
        throw FormatException('Expense contains an invalid split.');
      }
      totals[expense.paidBy]![0] += expense.amountCents;
      for (final allocation in expense.allocations) {
        totals[allocation.userId]![1] += allocation.amountCents;
      }
    }

    final balances = {
      for (final entry in totals.entries)
        entry.key: MemberBalance(
          paidCents: entry.value[0],
          assignedCents: entry.value[1],
        ),
    };
    if (balances.values.fold<int>(
          0,
          (sum, balance) => sum + balance.balanceCents,
        ) !=
        0) {
      throw FormatException('The total balance must be zero.');
    }
    return balances;
  }
}
