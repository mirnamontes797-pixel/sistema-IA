import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'course_detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  Future<void> _createCourse() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final weeks = TextEditingController(text: '16');
    final hours = TextEditingController(text: '64');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo curso'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del curso *')),
              const SizedBox(height: 8),
              TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 2),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: weeks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Semanas'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas totales'))),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await runAction(context, () async {
        await Api.request('POST', '/api/courses', body: {
          'name': name.text.trim(),
          'description': desc.text.trim(),
          'cuatrimestre_weeks': int.tryParse(weeks.text) ?? 16,
          'total_hours': int.tryParse(hours.text) ?? 64,
        });
      }, success: 'Curso creado');
      if (done) _load();
    }
  }

  Future<void> _logout() async {
    await Api.clearSession();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planeación Académica'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(user?['full_name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCourse,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo curso'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
                    const SizedBox(height: 8),
                    Center(child: FilledButton(onPressed: _load, child: const Text('Reintentar'))),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _kpiRow(context),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: Text('Cursos', style: Theme.of(context).textTheme.titleMedium),
                        ),
                        Text('${_courses.length} registrados'),
                      ]),
                      const SizedBox(height: 8),
                      if (_courses.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('Aún no hay cursos. Crea el primero.')),
                          ),
                        )
                      else
                        ..._courses.map((c) => _courseCard(c)),
                    ],
                  ),
      ),
    );
  }

  Widget _kpiRow(BuildContext context) {
    final totalHours = _courses.fold<double>(0, (sum, c) => sum + n(c['total_hours']));
    final maxWeeks = _courses.fold<int>(0, (m, c) =>
        i(c['cuatrimestre_weeks']) > m ? i(c['cuatrimestre_weeks']) : m);
    final items = [
      ('Cursos', '${_courses.length}'),
      ('Horas', '${totalHours.toStringAsFixed(0)} h'),
      ('Semanas', '$maxWeeks'),
    ];
    return Row(
      children: items
          .map((e) => Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    child: Column(children: [
                      Text(e.$2, style: Theme.of(context).textTheme.titleLarge),
                      Text(e.$1, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _courseCard(dynamic c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Text('${i(c['cuatrimestre_weeks'], 0)}w')),
        title: Text(s(c['name'], 'Curso'), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (s(c['description']).isNotEmpty) s(c['description']),
          '${i(c['cuatrimestre_weeks'])} semanas · ${n(c['total_hours']).toStringAsFixed(0)} h',
        ].join('\n')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CourseDetailScreen(course: c)));
          _load();
        },
        onLongPress: () async {
          if (await confirmDelete(context, 'el curso "${s(c['name'])}"')) {
            final done = await runAction(context, () async {
              await Api.request('DELETE', '/api/courses/${c['id']}');
            }, success: 'Curso eliminado');
            if (done) _load();
          }
        },
      ),
    );
  }
}
