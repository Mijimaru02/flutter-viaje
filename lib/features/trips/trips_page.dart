import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trip_detail_page.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  bool _showArchived = false;
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _trips = [];
  final _dateFormat = DateFormat('d MMM yyyy', 'es');

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _client
          .from('trip_members')
          .select(
            'role, trips(id,title,destination,start_date,end_date,description,archived_at)',
          )
          .eq('user_id', _client.auth.currentUser!.id);
      final trips =
          rows
              .map(
                (row) => {
                  ...Map<String, dynamic>.from(row['trips'] as Map),
                  'role': row['role'],
                },
              )
              .toList()
            ..sort(
              (a, b) => (a['start_date'] as String).compareTo(
                b['start_date'] as String,
              ),
            );
      if (mounted) setState(() => _trips = trips);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTrip() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _CreateTripDialog(),
    );
    if (created == true) await _loadTrips();
  }

  Future<void> _acceptInvitation() async {
    final tokenController = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceptar invitación'),
        content: TextField(
          controller: tokenController,
          decoration: const InputDecoration(labelText: 'Código de invitación'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, tokenController.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    tokenController.dispose();
    if (token == null || token.isEmpty) return;
    try {
      final result = await _client.rpc(
        'accept_trip_invitation',
        params: {'p_token': token},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'already_member'
                ? 'Ya formas parte de este viaje.'
                : 'Te has unido al viaje.',
          ),
        ),
      );
      await _loadTrips();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar la invitación: $error')),
      );
    }
  }

  Future<void> _editProfile() async {
    final userId = _client.auth.currentUser!.id;
    final controller = TextEditingController();
    try {
      final profile = await _client
          .from('profiles')
          .select('display_name')
          .eq('id', userId)
          .single();
      if (!mounted) return;
      controller.text = profile['display_name'] as String;
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tu perfil'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nombre visible'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (!mounted || name == null) return;
      if (name.isEmpty) {
        throw const FormatException('El nombre visible no puede estar vacío.');
      }
      await _client
          .from('profiles')
          .update({'display_name': name})
          .eq('id', userId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el perfil: $error')),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _signOut() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar la sesión: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTrips = _trips
        .where((trip) => (trip['archived_at'] != null) == _showArchived)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis viajes'),
        actions: [
          IconButton(
            tooltip: 'Editar perfil',
            onPressed: _editProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Aceptar invitación',
            onPressed: _acceptInvitation,
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTrip,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo viaje'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Activos')),
                ButtonSegment(value: true, label: Text('Archivados')),
              ],
              selected: {_showArchived},
              onSelectionChanged: (selection) =>
                  setState(() => _showArchived = selection.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _LoadError(error: _error!, onRetry: _loadTrips)
                : visibleTrips.isEmpty
                ? Center(
                    child: Text(
                      _showArchived
                          ? 'No hay viajes archivados.'
                          : 'Aún no participas en ningún viaje.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadTrips,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      itemCount: visibleTrips.length,
                      itemBuilder: (context, index) {
                        final trip = visibleTrips[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.flight_takeoff),
                            ),
                            title: Text(trip['title'] as String),
                            subtitle: Text(
                              '${trip['destination']} · '
                              '${_dateFormat.format(DateTime.parse(trip['start_date'] as String))} - '
                              '${_dateFormat.format(DateTime.parse(trip['end_date'] as String))}\n'
                              'Rol: ${trip['role']}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TripDetailPage(trip: trip),
                                ),
                              );
                              await _loadTrips();
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateTripDialog extends StatefulWidget {
  const _CreateTripDialog();

  @override
  State<_CreateTripDialog> createState() => _CreateTripDialogState();
}

class _CreateTripDialogState extends State<_CreateTripDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _destination = TextEditingController();
  final _description = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _destination.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? _start ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
          if (_end != null && _end!.isBefore(picked)) _end = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _start == null || _end == null) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'create_trip',
        params: {
          'p_title': _title.text.trim(),
          'p_destination': _destination.text.trim(),
          'p_start_date': _start!.toIso8601String().substring(0, 10),
          'p_end_date': _end!.toIso8601String().substring(0, 10),
          'p_description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el viaje: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMM yyyy', 'es');
    return AlertDialog(
      title: const Text('Crear viaje'),
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
                      ? 'Introduce un título'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _destination,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Introduce un destino'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _pickDate(start: true),
                        child: Text(
                          _start == null
                              ? 'Inicio *'
                              : formatter.format(_start!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _pickDate(start: false),
                        child: Text(
                          _end == null ? 'Fin *' : formatter.format(_end!),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_start == null || _end == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Selecciona las fechas del viaje.'),
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
              : const Text('Crear'),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No se pudieron cargar los viajes.'),
          const SizedBox(height: 4),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
