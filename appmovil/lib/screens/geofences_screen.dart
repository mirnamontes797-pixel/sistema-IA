import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../ui.dart';

/// Geocercas: lista, activación, eliminación y verificación de posición GPS.
class GeofencesScreen extends StatefulWidget {
  const GeofencesScreen({super.key});

  @override
  State<GeofencesScreen> createState() => _GeofencesScreenState();
}

class _GeofencesScreenState extends State<GeofencesScreen> {
  List<dynamic> _geofences = [];
  bool _loading = true;
  bool _checking = false;
  String? _error;

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
      _geofences = await Api.list('/api/geofences');
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkLocation() async {
    setState(() => _checking = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw const ApiException('Permiso de ubicación denegado');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final res = await Api.request('POST', '/api/geofences/check', body: {
        'subject': 'movil:${Api.user?['id'] ?? 'anon'}',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
      final results = (res['data'] as List?) ?? const [];
      if (!mounted) return;
      final inside = results.where((r) => r['inside'] == true).toList();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verificación de geocercas'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Posición: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'),
            const SizedBox(height: 8),
            if (inside.isEmpty)
              const Text('No estás dentro de ninguna geocerca activa.')
            else
              ...inside.map((r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.place, color: Color(int.parse('FF${s(r['color'], '0d9488').replaceFirst('#', '')}', radix: 16))),
                    title: Text(s(r['name'])),
                    subtitle: const Text('Estás dentro'),
                  )),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final vertices = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva geocerca'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
          const SizedBox(height: 8),
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 8),
          TextField(
            controller: vertices,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Vértices (lat,lng por línea)',
              helperText: 'Mínimo 3 líneas, ej: 31.6904,-106.4245',
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true) return;
    final polygon = vertices.text
        .split('\n')
        .map((l) => l.trim().split(','))
        .where((p) => p.length >= 2)
        .map((p) => [double.tryParse(p[0]), double.tryParse(p[1])])
        .where((p) => p[0] != null && p[1] != null)
        .map((p) => [p[0], p[1]])
        .toList();
    if (polygon.length < 3) {
      if (mounted) showSnack(context, 'Se requieren al menos 3 vértices válidos', error: true);
      return;
    }
    final done = await runAction(context, () async {
      await Api.request('POST', '/api/geofences', body: {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'polygon': polygon,
      });
    }, success: 'Geocerca creada');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geocercas'),
        actions: [
          IconButton(
            tooltip: 'Verificar mi ubicación',
            icon: _checking
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            onPressed: _checking ? null : _checkLocation,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Geocerca'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _geofences.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No hay geocercas registradas.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _geofences.length,
                          itemBuilder: (_, idx) {
                            final g = _geofences[idx];
                            final colorHex = s(g['color'], '#0d9488').replaceFirst('#', '');
                            final color = Color(int.parse('FF$colorHex', radix: 16));
                            final verts = (g['polygon'] as List?)?.length ?? 0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(Icons.place, color: color),
                                title: Text(s(g['name'])),
                                subtitle: Text([
                                  if (s(g['description']).isNotEmpty) s(g['description']),
                                  '$verts vértices',
                                ].join(' · ')),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Switch(
                                    value: g['active'] == true,
                                    onChanged: (v) async {
                                      await runAction(context, () async {
                                        await Api.request('PATCH', '/api/geofences/${g['id']}',
                                            body: {'active': v});
                                      });
                                      _load();
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                                    onPressed: () async {
                                      if (await confirmDelete(context, 'la geocerca "${s(g['name'])}"')) {
                                        final done = await runAction(context, () async {
                                          await Api.request('DELETE', '/api/geofences/${g['id']}');
                                        }, success: 'Eliminada');
                                        if (done) _load();
                                      }
                                    },
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
