import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../ui.dart';

/// Mapa de instituciones: lista, alta con GPS y eliminación.
class InstitutionsScreen extends StatefulWidget {
  const InstitutionsScreen({super.key});

  @override
  State<InstitutionsScreen> createState() => _InstitutionsScreenState();
}

class _InstitutionsScreenState extends State<InstitutionsScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
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
      _items = await Api.list('/api/institutions');
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position?> _gps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (_) {
      return null;
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final pos = await _gps();
    if (pos != null) {
      lat.text = pos.latitude.toStringAsFixed(6);
      lng.text = pos.longitude.toStringAsFixed(6);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva institución'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
          const SizedBox(height: 8),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: lat, keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitud'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: lng, keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitud'))),
          ]),
          const SizedBox(height: 4),
          Text(pos != null ? 'Coordenadas tomadas del GPS' : 'Sin ubicación GPS; captura manual',
              style: Theme.of(ctx).textTheme.bodySmall),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx,
                name.text.trim().isNotEmpty &&
                    address.text.trim().isNotEmpty &&
                    double.tryParse(lat.text) != null &&
                    double.tryParse(lng.text) != null),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await runAction(context, () async {
        await Api.request('POST', '/api/institutions', body: {
          'name': name.text.trim(),
          'address': address.text.trim(),
          'latitude': double.parse(lat.text),
          'longitude': double.parse(lng.text),
        });
      }, success: 'Institución registrada');
      if (done) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instituciones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Institución'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No hay instituciones registradas.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          itemBuilder: (_, idx) {
                            final inst = _items[idx];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.account_balance, color: Colors.teal),
                                title: Text(s(inst['name'])),
                                subtitle: Text('${s(inst['address'])}\n${n(inst['latitude']).toStringAsFixed(5)}, ${n(inst['longitude']).toStringAsFixed(5)}'),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                                  onPressed: () async {
                                    if (await confirmDelete(context, '"${s(inst['name'])}"')) {
                                      final done = await runAction(context, () async {
                                        await Api.request('DELETE', '/api/institutions/${inst['id']}');
                                      }, success: 'Eliminada');
                                      if (done) _load();
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
