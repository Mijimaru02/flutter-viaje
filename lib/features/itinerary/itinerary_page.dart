import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ItineraryPage extends StatefulWidget {
  const ItineraryPage({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<ItineraryPage> createState() => _ItineraryPageState();
}

class _ItineraryPageState extends State<ItineraryPage>
    with WidgetsBindingObserver {
  static const _categories = {
    'transporte': 'Transporte',
    'alojamiento': 'Alojamiento',
    'comida': 'Comida',
    'visita': 'Visita',
    'tiempo_libre': 'Tiempo libre',
  };
  final _dateFormat = DateFormat('EEEE, d MMMM', 'es');
  List<Map<String, dynamic>> _activities = [];
  bool _loading = true;
  Object? _error;
  String? _category;
  RealtimeChannel? _channel;
  SupabaseClient get _client => Supabase.instance.client;
  bool get _archived => widget.trip['archived_at'] != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _channel = _client
        .channel('trip-activities-${widget.trip['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: widget.trip['id'],
          ),
          callback: (_) => _load(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_load());
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _client
          .from('activities')
          .select()
          .eq('trip_id', widget.trip['id'])
          .order('activity_date')
          .order('start_time');
      if (mounted) {
        setState(() {
          _activities = rows.map(Map<String, dynamic>.from).toList();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editActivity([Map<String, dynamic>? activity]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ActivityDialog(
        trip: widget.trip,
        activity: activity,
        categories: _categories,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteActivity(Map<String, dynamic> activity) async {
    try {
      await _client.from('activities').delete().eq('id', activity['id']);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la actividad: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _activities
        .where(
          (activity) => _category == null || activity['category'] == _category,
        )
        .toList();
    final days = <String, List<Map<String, dynamic>>>{};
    for (final activity in filtered) {
      (days[activity['activity_date'] as String] ??= []).add(activity);
    }
    final canCreate =
        !_archived &&
        (widget.trip['role'] == 'owner' || widget.trip['role'] == 'editor');
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _editActivity(),
              tooltip: 'Añadir actividad',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: _category ?? '',
              decoration: const InputDecoration(labelText: 'Filtrar categoría'),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Todas las categorías'),
                ),
                ..._categories.entries.map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                ),
              ],
              onChanged: (value) => setState(
                () => _category = value == null || value.isEmpty ? null : value,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView()
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      _category == null
                          ? 'No hay actividades. Selecciona un día para planificar.'
                          : 'No hay actividades de esta categoría.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      children: [
                        for (final entry in days.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                            child: Text(
                              toBeginningOfSentenceCase(
                                    _dateFormat.format(
                                      DateTime.parse(entry.key),
                                    ),
                                  ) ??
                                  entry.key,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          ...entry.value.map(_activityTile),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No se pudo cargar la agenda.'),
          Text('$_error', textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );

  Widget _activityTile(Map<String, dynamic> activity) {
    final canEdit =
        !_archived &&
        (widget.trip['role'] == 'owner' ||
            activity['created_by'] == _client.auth.currentUser?.id);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(activity['title'] as String),
        subtitle: Text(
          '${(activity['start_time'] as String).substring(0, 5)}'
          '${activity['end_time'] == null ? '' : ' - ${(activity['end_time'] as String).substring(0, 5)}'}'
          ' · ${_categories[activity['category']] ?? activity['category']}'
          '${activity['address'] == null ? '' : '\n${activity['address']}'}',
        ),
        isThreeLine: activity['address'] != null,
        onTap: canEdit ? () => _editActivity(activity) : null,
        trailing: canEdit
            ? IconButton(
                tooltip: 'Eliminar actividad',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteActivity(activity),
              )
            : null,
      ),
    );
  }
}

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog({
    required this.trip,
    required this.activity,
    required this.categories,
  });

  final Map<String, dynamic> trip;
  final Map<String, dynamic>? activity;
  final Map<String, String> categories;

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.activity?['title'] as String? ?? '',
  );
  late final _address = TextEditingController(
    text: widget.activity?['address'] as String? ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.activity?['notes'] as String? ?? '',
  );
  late DateTime _date = widget.activity == null
      ? DateTime.parse(widget.trip['start_date'] as String)
      : DateTime.parse(widget.activity!['activity_date'] as String);
  late TimeOfDay _start = widget.activity == null
      ? const TimeOfDay(hour: 9, minute: 0)
      : _parseTime(widget.activity!['start_time'] as String);
  TimeOfDay? _end;
  late String _category = widget.activity?['category'] as String? ?? 'visita';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final end = widget.activity?['end_time'] as String?;
    if (end != null) _end = _parseTime(end);
  }

  static TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  void dispose() {
    _title.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.parse(widget.trip['start_date'] as String),
      lastDate: DateTime.parse(widget.trip['end_date'] as String),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<TimeOfDay?> _chooseTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  String _timeString(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_end != null &&
        (_end!.hour < _start.hour ||
            (_end!.hour == _start.hour && _end!.minute <= _start.minute))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora de fin debe ser posterior al inicio.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'title': _title.text.trim(),
        'activity_date': _date.toIso8601String().substring(0, 10),
        'start_time': _timeString(_start),
        'end_time': _end == null ? null : _timeString(_end!),
        'category': _category,
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      };
      final table = Supabase.instance.client.from('activities');
      if (widget.activity == null) {
        await table.insert({
          ...payload,
          'trip_id': widget.trip['id'],
          'created_by': Supabase.instance.client.auth.currentUser!.id,
        });
      } else {
        await table.update(payload).eq('id', widget.activity!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la actividad: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy', 'es');
    return AlertDialog(
      title: Text(
        widget.activity == null ? 'Nueva actividad' : 'Editar actividad',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo obligatorio'
                      : null,
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _chooseDate,
                        child: Text(dateFormat.format(_date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final time = await _chooseTime(_start);
                                if (time != null) setState(() => _start = time);
                              },
                        child: Text('Inicio ${_start.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (_end == null) {
                                  setState(() => _end = _start);
                                }
                                final time = await _chooseTime(_end ?? _start);
                                if (time != null) setState(() => _end = time);
                              },
                        child: Text(
                          _end == null
                              ? 'Fin opcional'
                              : 'Fin ${_end!.format(context)}',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_end != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _end = null),
                      child: const Text('Quitar hora de fin'),
                    ),
                  ),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (opcional)',
                  ),
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
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
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
