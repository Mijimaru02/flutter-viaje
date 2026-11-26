import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'expense_calculator.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  static const _categories = {
    'transporte': 'Transporte',
    'alojamiento': 'Alojamiento',
    'comida': 'Comida',
    'visita': 'Visita',
    'otros': 'Otros',
  };
  final _currency = NumberFormat.currency(locale: 'es_ES', symbol: '€');
  final _dateFormat = DateFormat('d MMM yyyy', 'es');
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  Object? _error;
  String? _categoryFilter;
  String? _payerFilter;
  SupabaseClient get _client => Supabase.instance.client;
  bool get _archived => widget.trip['archived_at'] != null;

  Map<String, String> get _memberNames => {
    for (final member in _members)
      member['user_id'] as String:
          (member['profiles'] as Map<String, dynamic>?)?['display_name']
              as String? ??
          'Viajero',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _client
            .from('trip_members')
            .select('user_id,role,profiles(display_name)')
            .eq('trip_id', widget.trip['id'])
            .order('joined_at'),
        _client
            .from('expenses')
            .select(
              'id,title,amount_cents,expense_date,category,paid_by,created_by,expense_splits(user_id,amount_cents,split_order)',
            )
            .eq('trip_id', widget.trip['id'])
            .order('expense_date', ascending: false),
      ]);
      if (mounted) {
        setState(() {
          _members = (values[0] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          _expenses = (values[1] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ExpenseRecord> get _records => _expenses.map((expense) {
    final splitRows =
        (expense['expense_splits'] as List)
            .map((split) => Map<String, dynamic>.from(split as Map))
            .toList()
          ..sort(
            (a, b) =>
                (a['split_order'] as int).compareTo(b['split_order'] as int),
          );
    final splits = splitRows
        .map(
          (split) => ExpenseAllocation(
            userId: split['user_id'] as String,
            amountCents: split['amount_cents'] as int,
          ),
        )
        .toList();
    return ExpenseRecord(
      paidBy: expense['paid_by'] as String,
      amountCents: expense['amount_cents'] as int,
      allocations: splits,
    );
  }).toList();

  Future<void> _addExpense() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ExpenseDialog(
        tripId: widget.trip['id'] as String,
        members: _members,
        categories: _categories,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _editExpense(Map<String, dynamic> expense) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ExpenseDialog(
        tripId: widget.trip['id'] as String,
        members: _members,
        categories: _categories,
        expense: expense,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text('¿Quieres eliminar «${expense['title']}» y su reparto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.rpc(
        'delete_expense',
        params: {'p_expense_id': expense['id'], 'p_trip_id': widget.trip['id']},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar el gasto: $error')),
        );
      }
    }
  }

  Future<void> _showDetails(Map<String, dynamic> expense) async {
    final splits =
        (expense['expense_splits'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList()
          ..sort(
            (a, b) =>
                (a['split_order'] as int).compareTo(b['split_order'] as int),
          );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(expense['title'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pagó: ${_memberNames[expense['paid_by']]}'),
            Text(
              'Fecha: ${_dateFormat.format(DateTime.parse(expense['expense_date'] as String))}',
            ),
            Text(
              'Total: ${_currency.format((expense['amount_cents'] as int) / 100)}',
            ),
            const SizedBox(height: 12),
            const Text('Reparto'),
            ...splits.map(
              (split) => Text(
                '${_memberNames[split['user_id']]}: '
                '${_currency.format((split['amount_cents'] as int) / 100)}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _expenses.where((expense) {
      return (_categoryFilter == null ||
              expense['category'] == _categoryFilter) &&
          (_payerFilter == null || expense['paid_by'] == _payerFilter);
    }).toList();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No se pudieron cargar los gastos: $_error'),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    final balances = ExpenseCalculator.calculateBalances(
      memberIds: _memberNames.keys,
      expenses: _records,
    );
    final totalCents = _expenses.fold<int>(
      0,
      (total, expense) => total + (expense['amount_cents'] as int),
    );
    final canCreate =
        !_archived &&
        (widget.trip['role'] == 'owner' || widget.trip['role'] == 'editor');

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Añadir gasto'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total registrado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _currency.format(totalCents / 100),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Divider(),
                    for (final entry in balances.entries)
                      _balanceTile(entry.key, entry.value),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Filtrar gastos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                DropdownButton<String?>(
                  hint: const Text('Categoría'),
                  value: _categoryFilter,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ..._categories.entries.map(
                      (entry) => DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _categoryFilter = value),
                ),
                DropdownButton<String?>(
                  hint: const Text('Pagó'),
                  value: _payerFilter,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ..._memberNames.entries.map(
                      (entry) => DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _payerFilter = value),
                ),
              ],
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('No hay gastos para mostrar.')),
              ),
            ...visible.map((expense) {
              final canEdit =
                  !_archived &&
                  (widget.trip['role'] == 'owner' ||
                      expense['created_by'] == _client.auth.currentUser?.id);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.euro)),
                  title: Text(expense['title'] as String),
                  subtitle: Text(
                    '${_categories[expense['category']]} · '
                    'Pagó ${_memberNames[expense['paid_by']]} · '
                    '${_dateFormat.format(DateTime.parse(expense['expense_date'] as String))}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currency.format(
                          (expense['amount_cents'] as int) / 100,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (canEdit) ...[
                        IconButton(
                          tooltip: 'Editar gasto',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editExpense(expense),
                        ),
                        IconButton(
                          tooltip: 'Eliminar gasto',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteExpense(expense),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => _showDetails(expense),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _balanceTile(String userId, MemberBalance balance) {
    final amount = _currency.format(balance.balanceCents.abs() / 100);
    final label = balance.balanceCents > 0
        ? 'Debe recibir $amount'
        : balance.balanceCents < 0
        ? 'Debe aportar $amount'
        : 'Al día';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(_memberNames[userId] ?? 'Viajero'),
      subtitle: Text(
        'Pagado ${_currency.format(balance.paidCents / 100)} · '
        'Le corresponde ${_currency.format(balance.assignedCents / 100)}',
      ),
      trailing: Text(label),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.tripId,
    required this.members,
    required this.categories,
    this.expense,
  });

  final String tripId;
  final List<Map<String, dynamic>> members;
  final Map<String, String> categories;
  final Map<String, dynamic>? expense;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _customAmounts = <String, TextEditingController>{};
  final _customErrors = <String, String>{};
  late final _userIds = widget.members
      .map((member) => member['user_id'] as String)
      .toList(growable: false);
  late final _names = {
    for (final member in widget.members)
      member['user_id'] as String:
          (member['profiles'] as Map<String, dynamic>?)?['display_name']
              as String? ??
          'Viajero',
  };
  late String _payer = widget.expense?['paid_by'] as String? ?? _userIds.first;
  final Set<String> _selected = {};
  late String _category = widget.expense?['category'] as String? ?? 'comida';
  bool _custom = false;
  String? _splitError;
  bool _busy = false;
  late DateTime _date = widget.expense == null
      ? DateTime.now()
      : DateTime.parse(widget.expense!['expense_date'] as String);

  @override
  void initState() {
    super.initState();
    final existing = widget.expense;
    if (existing == null) {
      _selected.addAll(_userIds);
    } else {
      _title.text = existing['title'] as String;
      final amount = existing['amount_cents'] as int;
      _amount.text =
          '${amount ~/ 100},${(amount % 100).toString().padLeft(2, '0')}';
      final splits =
          (existing['expense_splits'] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList()
            ..sort(
              (a, b) =>
                  (a['split_order'] as int).compareTo(b['split_order'] as int),
            );
      for (final split in splits) {
        _selected.add(split['user_id'] as String);
      }
      final equal = ExpenseCalculator.splitEqually(amount, _selected.toList());
      _custom = splits.any(
        (split) =>
            equal
                .firstWhere(
                  (allocation) => allocation.userId == split['user_id'],
                )
                .amountCents !=
            split['amount_cents'],
      );
      if (_custom) {
        for (final split in splits) {
          final cents = split['amount_cents'] as int;
          _customAmounts[split['user_id'] as String] = TextEditingController(
            text: '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}',
          );
        }
      }
    }
    _amount.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() => _splitError = null);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    for (final controller in _customAmounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static int _parseCents(String input) {
    final value = input.trim().replaceAll(' ', '');
    if (!RegExp(r'^\d+(?:[,.]\d{1,2})?$').hasMatch(value)) {
      throw const FormatException(
        'Introduce un importe válido con hasta dos decimales.',
      );
    }
    final parts = value.replaceFirst(',', '.').split('.');
    return int.parse(parts[0]) * 100 +
        int.parse((parts.length == 1 ? '' : parts[1]).padRight(2, '0'));
  }

  int? get _amountCents {
    try {
      return _parseCents(_amount.text);
    } on FormatException {
      return null;
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos una persona para el reparto.'),
        ),
      );
      return;
    }
    final cents = _amountCents;
    if (cents == null || cents <= 0) return;
    late final List<ExpenseAllocation> allocations;
    if (_custom) {
      final amounts = <String, int>{};
      _customErrors.clear();
      for (final id in _selected) {
        try {
          amounts[id] = _parseCents(_customAmounts[id]?.text ?? '');
        } on FormatException {
          _customErrors[id] = 'Importe no válido';
        }
      }
      if (_customErrors.isNotEmpty) {
        setState(() => _splitError = null);
        return;
      }
      if (amounts.values.fold<int>(0, (sum, amount) => sum + amount) != cents) {
        setState(
          () => _splitError = 'Los importes deben sumar exactamente el total.',
        );
        return;
      }
      allocations = ExpenseCalculator.validateCustomSplit(
        amountCents: cents,
        amountsByUser: amounts,
      );
    } else {
      allocations = ExpenseCalculator.splitEqually(cents, _selected.toList());
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'save_expense',
        params: {
          'p_expense_id': widget.expense?['id'],
          'p_trip_id': widget.tripId,
          'p_title': _title.text.trim(),
          'p_amount_cents': cents,
          'p_expense_date': _date.toIso8601String().substring(0, 10),
          'p_category': _category,
          'p_paid_by': _payer,
          'p_splits': [
            for (var index = 0; index < allocations.length; index++)
              {
                'user_id': allocations[index].userId,
                'amount_cents': allocations[index].amountCents,
                'split_order': index,
              },
          ],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el gasto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    List<ExpenseAllocation> preview = [];
    final cents = _amountCents;
    if (!_custom && cents != null && cents > 0 && _selected.isNotEmpty) {
      preview = ExpenseCalculator.splitEqually(cents, _selected.toList());
    }
    return AlertDialog(
      title: Text(widget.expense == null ? 'Nuevo gasto' : 'Editar gasto'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Concepto'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo obligatorio'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Importe (€)',
                    hintText: '10,00',
                  ),
                  validator: (value) {
                    try {
                      if (_parseCents(value ?? '') <= 0) {
                        return 'El importe debe ser positivo';
                      }
                    } on FormatException {
                      return 'Introduce un importe con hasta dos decimales';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: widget.categories.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _payer,
                  decoration: const InputDecoration(labelText: 'Pagado por'),
                  items: _userIds
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text(_names[id]!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _payer = value);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _chooseDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(DateFormat('d MMM yyyy', 'es').format(_date)),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Repartir entre'),
                ),
                ..._userIds.map((id) {
                  final selected = _selected.contains(id);
                  return Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_names[id]!),
                          value: selected,
                          onChanged: _busy
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                        ),
                      ),
                      if (_custom && selected)
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _customAmounts.putIfAbsent(
                              id,
                              TextEditingController.new,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: '€',
                              isDense: true,
                              errorText: _customErrors[id],
                            ),
                            onChanged: (_) {
                              setState(() {
                                _customErrors.remove(id);
                                _splitError = null;
                              });
                            },
                          ),
                        ),
                    ],
                  );
                }),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Importes personalizados'),
                  value: _custom,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _custom = value),
                ),
                if (_splitError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _splitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!_custom && preview.isNotEmpty)
                  ...preview.map(
                    (allocation) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_names[allocation.userId]}: '
                        '${currency.format(allocation.amountCents / 100)}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  widget.expense == null ? 'Guardar gasto' : 'Actualizar gasto',
                ),
        ),
      ],
    );
  }
}
