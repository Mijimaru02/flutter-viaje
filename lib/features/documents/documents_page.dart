import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../supabase_config.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<Map<String, dynamic>> _documents = [];
  bool _loading = true;
  bool _uploading = false;
  double _uploadProgress = 0;
  Object? _error;
  SupabaseClient get _client => Supabase.instance.client;
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
      final rows = await _client
          .from('trip_documents')
          .select()
          .eq('trip_id', widget.trip['id'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _documents = rows.map(Map<String, dynamic>.from).toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (!mounted || file == null) return;
    int? fileSize;
    late final List<int> bytes;
    try {
      fileSize = await file.length();
      if (fileSize != null && fileSize > 0 && fileSize <= 10 * 1024 * 1024) {
        bytes = await file.readAsBytes();
      } else {
        bytes = const [];
      }
    } catch (error) {
      _showMessage('No se pudo leer el archivo seleccionado: $error');
      return;
    }
    if (!mounted) return;
    if (fileSize == null || fileSize < 1 || fileSize > 10 * 1024 * 1024) {
      _showMessage('El archivo debe ocupar como máximo 10 MB.');
      return;
    }

    final titleController = TextEditingController(
      text: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Título del documento'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, titleController.text.trim()),
            child: const Text('Subir'),
          ),
        ],
      ),
    );
    titleController.dispose();
    if (!mounted || title == null || title.isEmpty) return;

    final extension = file.extension?.toLowerCase();
    final mimeType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
    if (mimeType == null) {
      _showMessage('Formato no permitido. Usa PDF, JPEG o PNG.');
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    final userId = _client.auth.currentUser!.id;
    final path =
        '${widget.trip['id']}/$userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    var fileUploaded = false;
    try {
      await _uploadToStorage(path, bytes, mimeType);
      fileUploaded = true;
      try {
        await _client.from('trip_documents').insert({
          'trip_id': widget.trip['id'],
          'created_by': userId,
          'title': title,
          'storage_path': path,
          'mime_type': mimeType,
          'size_bytes': fileSize,
        });
      } catch (metadataError) {
        try {
          await _client.storage.from('trip-documents').remove([path]);
        } catch (cleanupError) {
          throw StateError(
            'No se guardaron los metadatos ($metadataError) y no se pudo '
            'limpiar el archivo ($cleanupError). Ruta pendiente: $path',
          );
        }
        rethrow;
      }
      await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(
          fileUploaded
              ? 'No se pudo completar la subida: $error'
              : 'No se pudo subir el archivo: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _uploadToStorage(
    String path,
    List<int> bytes,
    String mimeType,
  ) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError(
        'Falta una sesión de Supabase.',
      );
    }

    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final url = Uri.parse(
      '${supabaseUrl.replaceFirst(RegExp(r'/$'), '')}'
      '/storage/v1/object/trip-documents/$encodedPath',
    );
    final dio = Dio();
    try {
      await dio.postUri<void>(
        url,
        data: bytes,
        options: Options(
          contentType: mimeType,
          headers: {
            'apikey': supabasePublishableKey,
            'Authorization': 'Bearer ${session.accessToken}',
            'x-upsert': 'false',
          },
        ),
        onSendProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
    } finally {
      dio.close();
    }
  }

  Future<void> _open(Map<String, dynamic> document) async {
    try {
      final url = await _client.storage
          .from('trip-documents')
          .createSignedUrl(document['storage_path'] as String, 60);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('No hay una aplicación disponible para abrirlo.');
      }
    } catch (error) {
      _showMessage('No se pudo abrir el documento: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Quieres eliminar «${document['title']}»?'),
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
    if (confirmed != true || !mounted) return;
    final path = document['storage_path'] as String;
    try {
      await _client.from('trip_documents').delete().eq('id', document['id']);
      try {
        await _client.storage.from('trip-documents').remove([path]);
      } catch (error) {
        await _load();
        throw StateError(
          'El documento dejó de estar visible, pero el archivo no se pudo '
          'eliminar. Ruta pendiente: $path ($error)',
        );
      }
      await _load();
    } catch (error) {
      _showMessage('No se pudo completar el borrado: $error');
    }
  }

  Future<void> _rename(Map<String, dynamic> document) async {
    final controller = TextEditingController(text: document['title'] as String);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar título'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Título'),
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
    controller.dispose();
    if (!mounted || title == null) return;
    if (title.isEmpty) {
      _showMessage('El título no puede estar vacío.');
      return;
    }
    try {
      await _client
          .from('trip_documents')
          .update({'title': title})
          .eq('id', document['id']);
      await _load();
    } catch (error) {
      _showMessage('No se pudo actualizar el título: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canUpload =
        !_archived &&
        (widget.trip['role'] == 'owner' || widget.trip['role'] == 'editor');
    return Scaffold(
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Subir documento'),
            )
          : null,
      body: Column(
        children: [
          if (_uploading) ...[
            LinearProgressIndicator(value: _uploadProgress),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Subiendo documento… ${(_uploadProgress * 100).round()}%',
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No se pudieron cargar los documentos: $_error'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : _documents.isEmpty
                ? const Center(child: Text('Aún no hay documentos.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final document = _documents[index];
                        final createdBy =
                            document['created_by'] ==
                            _client.auth.currentUser?.id;
                        final canDelete =
                            !_archived &&
                            (widget.trip['role'] == 'owner' || createdBy);
                        return ListTile(
                          leading: Icon(
                            document['mime_type'] == 'application/pdf'
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                          ),
                          title: Text(document['title'] as String),
                          subtitle: Text(
                            '${DateFormat('d MMM yyyy HH:mm', 'es').format(DateTime.parse(document['created_at'] as String).toLocal())}'
                            ' · ${((document['size_bytes'] as int) / 1024).ceil()} KB',
                          ),
                          onTap: () => _open(document),
                          trailing: canDelete
                              ? PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'rename') {
                                      _rename(document);
                                    } else {
                                      _delete(document);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Editar título'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Eliminar'),
                                    ),
                                  ],
                                )
                              : null,
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
