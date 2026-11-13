import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'teams_sheet.dart';

/// Pestaña "Equipos": lista los cursos y permite generar instrucciones
/// para tareas de Microsoft Teams por actividad o evaluación.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  List<dynamic> _courses = [];
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
      _courses = await Api.list('/api/courses');
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instrucciones Teams')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _courses.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No hay cursos registrados.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _courses.length,
                          itemBuilder: (_, idx) {
                            final c = _courses[idx];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.groups_outlined, color: Colors.teal),
                                title: Text(s(c['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${i(c['cuatrimestre_weeks'])} semanas · ${n(c['total_hours']).toStringAsFixed(0)} h'),
                                trailing: FilledButton.tonalIcon(
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                  label: const Text('Generar'),
                                  onPressed: () => showTeamsSheet(context, c['id'].toString()),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
