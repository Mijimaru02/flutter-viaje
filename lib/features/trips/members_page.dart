import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  bool _loading = true;
  bool _inviting = false;
  Object? _error;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _invitations = [];

  SupabaseClient get _client => Supabase.instance.client;
  bool get _isOwner => widget.trip['role'] == 'owner';
  bool get _archived => widget.trip['archived_at'] != null;

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
      final members = await _client
          .from('trip_members')
          .select('user_id,role,joined_at,profiles(display_name)')
          .eq('trip_id', widget.trip['id']);
      final invitations = _isOwner
          ? await _client
                .from('trip_invitations')
                .select('id,email,role,expires_at,used_at,revoked_at')
                .eq('trip_id', widget.trip['id'])
                .order('created_at', ascending: false)
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _members = members.map(Map<String, dynamic>.from).toList();
          _invitations = invitations.map(Map<String, dynamic>.from).toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    var role = 'editor';
    final invite = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invitar miembro'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (value) =>
                      value == null ||
                          !RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                              .hasMatch(value.trim())
                      ? 'Introduce un correo válido'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Permiso'),
                  items: const [
                    DropdownMenuItem(value: 'editor', child: Text('Editor')),
                    DropdownMenuItem(value: 'reader', child: Text('Lector')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, {
                    'email': emailController.text.trim(),
                    'role': role,
                  });
                }
              },
              child: const Text('Crear invitación'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (invite == null) return;
    if (mounted) setState(() => _inviting = true);
    try {
      final response = await _client.rpc(
        'create_trip_invitation',
        params: {
          'p_trip_id': widget.trip['id'],
          'p_email': invite['email'],
          'p_role': invite['role'],
        },
      );
      final result = Map<String, dynamic>.from((response as List).first as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invitación creada'),
          content: SelectableText(
            'Comparte este código con ${invite['email']}:\n\n${result['token']}\n\n'
            'Caduca: ${DateFormat('d MMM yyyy HH:mm', 'es').format(DateTime.parse(result['expires_at'] as String).toLocal())}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la invitación: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _changeRole(String userId, String role) async {
    try {
      await _client
          .from('trip_members')
          .update({'role': role})
          .eq('trip_id', widget.trip['id'])
          .eq('user_id', userId);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el permiso: $error')),
        );
      }
    }
  }

  Future<void> _revoke(String invitationId) async {
    try {
      await _client.rpc(
        'revoke_trip_invitation',
        params: {'p_invitation_id': invitationId},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo revocar la invitación: $error')),
        );
      }
    }
  }

  String _invitationStatus(Map<String, dynamic> invitation) {
    if (invitation['revoked_at'] != null) return 'Revocada';
    if (invitation['used_at'] != null) return 'Aceptada';
    if (DateTime.parse(invitation['expires_at'] as String)
        .isBefore(DateTime.now())) {
      return 'Caducada';
    }
    return 'Pendiente';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No se pudieron cargar los miembros: $_error'),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Scaffold(
      floatingActionButton: _isOwner && !_archived
          ? FloatingActionButton.extended(
              onPressed: _inviting ? null : _invite,
              icon: const Icon(Icons.person_add_alt),
              label: Text(_inviting ? 'Creando…' : 'Invitar'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Text('Miembros', style: Theme.of(context).textTheme.titleLarge),
            ..._members.map((member) {
              final profile = member['profiles'] as Map<String, dynamic>?;
              final role = member['role'] as String;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(profile?['display_name'] as String? ?? 'Viajero'),
                subtitle: Text('Rol: $role'),
                trailing: _isOwner && !_archived && role != 'owner'
                    ? DropdownButton<String>(
                        value: role,
                        items: const [
                          DropdownMenuItem(
                            value: 'editor',
                            child: Text('Editor'),
                          ),
                          DropdownMenuItem(
                            value: 'reader',
                            child: Text('Lector'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null && value != role) {
                            _changeRole(member['user_id'] as String, value);
                          }
                        },
                      )
                    : null,
              );
            }),
            if (_isOwner) ...[
              const Divider(height: 32),
              Text(
                'Invitaciones',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_invitations.isEmpty)
                const ListTile(title: Text('No hay invitaciones.')),
              ..._invitations.map((invitation) {
                final status = _invitationStatus(invitation);
                final canRevoke = status == 'Pendiente' && !_archived;
                return ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(invitation['email'] as String),
                  subtitle: Text('${invitation['role']} · $status'),
                  trailing: canRevoke
                      ? IconButton(
                          tooltip: 'Revocar',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () => _revoke(invitation['id'] as String),
                        )
                      : null,
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
