import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../documents/documents_page.dart';
import '../expenses/expenses_page.dart';
import '../itinerary/itinerary_page.dart';
import 'members_page.dart';

class TripDetailPage extends StatefulWidget {
  const TripDetailPage({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late final Map<String, dynamic> _trip = Map.of(widget.trip);
  late bool _archived = _trip['archived_at'] != null;
  bool _busy = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleArchive() async {
    setState(() => _busy = true);
    try {
      await _client
          .from('trips')
          .update({
            'archived_at': _archived
                ? null
                : DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _trip['id']);
      if (mounted) {
        setState(() {
          _archived = !_archived;
          _trip['archived_at'] = _archived ? 'archived' : null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el viaje: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editTrip() async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditTripDialog(trip: _trip),
    );
    if (updated != null && mounted) {
      setState(() => _trip.addAll(updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = _trip['role'] == 'owner';
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip['title'] as String),
        actions: [
          if (isOwner && !_archived)
            IconButton(
              tooltip: 'Editar viaje',
              onPressed: _busy ? null : _editTrip,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (isOwner)
            IconButton(
              tooltip: _archived ? 'Reactivar viaje' : 'Archivar viaje',
              onPressed: _busy ? null : _toggleArchive,
              icon: Icon(
                _archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.event_note), text: 'Agenda'),
            Tab(icon: Icon(Icons.euro), text: 'Gastos'),
            Tab(icon: Icon(Icons.folder_outlined), text: 'Documentos'),
            Tab(icon: Icon(Icons.people_outline), text: 'Miembros'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_archived)
            const MaterialBanner(
              content: Text(
                'Viaje archivado: solo se permite consultar el contenido.',
              ),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ItineraryPage(trip: _trip),
                ExpensesPage(trip: _trip),
                DocumentsPage(trip: _trip),
                MembersPage(trip: _trip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditTripDialog extends StatefulWidget {
  const _EditTripDialog({required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<_EditTripDialog> createState() => _EditTripDialogState();
}

class _EditTripDialogState extends State<_EditTripDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.trip['title'] as String,
  );
  late final _destination = TextEditingController(
    text: widget.trip['destination'] as String,
  );
  late final _description = TextEditingController(
    text: widget.trip['description'] as String? ?? '',
  );
  late DateTime _start = DateTime.parse(widget.trip['start_date'] as String);
  late DateTime _end = DateTime.parse(widget.trip['end_date'] as String);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _destination.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_end.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha de fin debe ser posterior al inicio.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final updates = {
      'title': _title.text.trim(),
      'destination': _destination.text.trim(),
      'start_date': _start.toIso8601String().substring(0, 10),
      'end_date': _end.toIso8601String().substring(0, 10),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
    };
    try {
      await Supabase.instance.client
          .from('trips')
          .update(updates)
          .eq('id', widget.trip['id']);
      if (mounted) Navigator.pop(context, updates);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el viaje: $error')),
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
      title: const Text('Editar viaje'),
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
                TextFormField(
                  controller: _destination,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo obligatorio'
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _chooseDate(start: true),
                        child: Text(dateFormat.format(_start)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _chooseDate(start: false),
                        child: Text(dateFormat.format(_end)),
                      ),
                    ),
                  ],
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
