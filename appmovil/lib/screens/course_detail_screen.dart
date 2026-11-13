import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'schedule_screen.dart';
import 'teams_sheet.dart';

class CourseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> course;
  const CourseDetailScreen({super.key, required this.course});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  Map<String, dynamic>? _plan;
  bool _loading = true;
  String? _error;

  String get _courseId => widget.course['id'].toString();

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
      final res = await Api.request('GET', '/api/courses/$_courseId/plan');
      _plan = Map<String, dynamic>.from(res as Map);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<dynamic> get _units => (_plan?['units'] as List?) ?? const [];

  @override
  Widget build(BuildContext context) {
    final course = _plan?['course'] ?? widget.course;
    return Scaffold(
      appBar: AppBar(
        title: Text(s(course['name'], 'Curso'), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Cronograma',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ScheduleScreen(courseId: _courseId, courseName: s(course['name'])))),
          ),
          IconButton(
            tooltip: 'Editar curso',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editCourse,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _deleteCourse();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Eliminar curso')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _courseHeader(course),
                      const SizedBox(height: 12),
                      ..._units.map((u) => _unitCard(u)),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUnit,
        icon: const Icon(Icons.add),
        label: const Text('Unidad'),
      ),
    );
  }

  Widget _courseHeader(dynamic c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s(c['name']), style: Theme.of(context).textTheme.titleLarge),
          if (s(c['description']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s(c['description']), style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            Chip(avatar: const Icon(Icons.calendar_month, size: 16),
                label: Text('${i(c['cuatrimestre_weeks'])} semanas')),
            Chip(avatar: const Icon(Icons.schedule, size: 16),
                label: Text('${n(c['total_hours']).toStringAsFixed(0)} horas')),
            ActionChip(
              avatar: const Icon(Icons.groups, size: 16),
              label: const Text('Instrucciones Teams'),
              onPressed: () => showTeamsSheet(context, _courseId),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _unitCard(dynamic u) {
    final outcomes = (u['outcomes'] as List?) ?? const [];
    final activities = (u['activities'] as List?) ?? const [];
    final evaluations = (u['evaluations'] as List?) ?? const [];
    final rubrics = (u['rubrics'] as List?) ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text('U${i(u['number'])}')),
        title: Text(s(u['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${outcomes.length} RA · ${activities.length} act. · ${evaluations.length} eval.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _entitySection(
            'Resultados de aprendizaje', outcomes,
            addLabel: 'RA',
            onAdd: () => _editOutcome(u, null),
            tile: (o) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined, size: 18),
              title: Text(s(o['title'])),
              subtitle: Text([s(o['code']), s(o['bloom_level'])].where((x) => x.isNotEmpty).join(' · ')),
              trailing: _rowActions(() => _editOutcome(u, o), () => _deleteEntity('outcomes', o)),
            ),
          ),
          _entitySection(
            'Actividades', activities,
            addLabel: 'Actividad',
            onAdd: () => _editActivity(u, null),
            tile: (a) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_circle_outline, size: 18),
              title: Text(s(a['title'])),
              subtitle: Text([
                s(a['type']), s(a['modality']),
                if (a['week'] != null) 'sem. ${i(a['week'])}',
                if (n(a['hours']) > 0) '${n(a['hours']).toStringAsFixed(0)} h',
              ].join(' · ')),
              trailing: _rowActions(() => _editActivity(u, a), () => _deleteEntity('activities', a)),
            ),
          ),
          _entitySection(
            'Evaluaciones', evaluations,
            addLabel: 'Evaluación',
            onAdd: () => _editEvaluation(u, null),
            tile: (e) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.assignment_outlined, size: 18),
              title: Text(s(e['title'])),
              subtitle: Text([
                s(e['type']),
                if (n(e['weight']) > 0) '${n(e['weight']).toStringAsFixed(0)}%',
                if (e['week'] != null) 'sem. ${i(e['week'])}',
                if (s(e['due_date']).isNotEmpty) s(e['due_date']).substring(0, 10),
              ].join(' · ')),
              trailing: _rowActions(() => _editEvaluation(u, e), () => _deleteEntity('evaluations', e)),
            ),
          ),
          _entitySection(
            'Rúbricas', rubrics,
            addLabel: 'Rúbrica',
            onAdd: () => _editRubric(u, null),
            tile: (r) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fact_check_outlined, size: 18),
              title: Text(s(r['title'])),
              subtitle: Text('${(r['criteria'] as List?)?.length ?? 0} criterios'),
              trailing: _rowActions(() => _editRubric(u, r), () => _deleteEntity('rubrics', r)),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar unidad'),
                onPressed: () => _editUnit(u),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                onPressed: () async {
                  if (await confirmDelete(context, 'la unidad ${i(u['number'])}')) {
                    final done = await runAction(context, () async {
                      await Api.request('DELETE', '/api/units/${u['id']}');
                    }, success: 'Unidad eliminada');
                    if (done) _load();
                  }
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _entitySection(String title, List<dynamic> items,
      {required String addLabel, required VoidCallback onAdd, required Widget Function(dynamic) tile}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(addLabel),
            onPressed: onAdd,
          ),
        ]),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Sin registros', style: TextStyle(color: Colors.grey)),
          )
        else
          ...items.map(tile),
        const Divider(height: 16),
      ]),
    );
  }

  Widget _rowActions(VoidCallback edit, VoidCallback del) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: edit, visualDensity: VisualDensity.compact),
      IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: del, visualDensity: VisualDensity.compact),
    ]);
  }

  // ---------- CRUD ----------

  Future<void> _addUnit() async {
    final number = TextEditingController();
    final title = TextEditingController();
    final objectives = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva unidad'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Número *')),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título *')),
          TextField(controller: objectives, maxLines: 3, decoration: const InputDecoration(labelText: 'Objetivos')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty && number.text.trim().isNotEmpty), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final done = await runAction(context, () async {
        await Api.request('POST', '/api/units', body: {
          'course_id': _courseId,
          'number': int.tryParse(number.text) ?? 1,
          'title': title.text.trim(),
          'objectives': objectives.text.trim(),
        });
      }, success: 'Unidad creada');
      if (done) _load();
    }
  }

  Future<void> _editUnit(dynamic u) async {
    final title = TextEditingController(text: s(u['title']));
    final objectives = TextEditingController(text: s(u['objectives']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar unidad'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título')),
          const SizedBox(height: 8),
          TextField(controller: objectives, maxLines: 3, decoration: const InputDecoration(labelText: 'Objetivos')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final done = await runAction(context, () async {
        await Api.request('PATCH', '/api/units/${u['id']}', body: {
          'title': title.text.trim(),
          'objectives': objectives.text.trim(),
        });
      }, success: 'Unidad actualizada');
      if (done) _load();
    }
  }

  Future<void> _editOutcome(dynamic u, dynamic o) async {
    final code = TextEditingController(text: o == null ? '' : s(o['code']));
    final title = TextEditingController(text: o == null ? '' : s(o['title']));
    final bloom = TextEditingController(text: o == null ? '' : s(o['bloom_level']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(o == null ? 'Nuevo resultado de aprendizaje' : 'Editar resultado'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, decoration: const InputDecoration(labelText: 'Código')),
          const SizedBox(height: 8),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título *')),
          const SizedBox(height: 8),
          TextField(controller: bloom, decoration: const InputDecoration(labelText: 'Nivel Bloom (p. ej. aplicar)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final body = {'code': code.text.trim(), 'title': title.text.trim(), 'bloom_level': bloom.text.trim()};
      final done = await runAction(context, () async {
        if (o == null) {
          await Api.request('POST', '/api/outcomes', body: {'unit_id': u['id'], ...body});
        } else {
          await Api.request('PATCH', '/api/outcomes/${o['id']}', body: body);
        }
      }, success: 'Guardado');
      if (done) _load();
    }
  }

  Future<void> _editActivity(dynamic u, dynamic a) async {
    final title = TextEditingController(text: a == null ? '' : s(a['title']));
    final type = TextEditingController(text: a == null ? 'clase' : s(a['type']));
    final modality = TextEditingController(text: a == null ? 'presencial' : s(a['modality']));
    final hours = TextEditingController(text: a == null ? '0' : n(a['hours']).toStringAsFixed(0));
    final week = TextEditingController(text: a == null || a['week'] == null ? '' : '${i(a['week'])}');
    final startDate = TextEditingController(text: a == null ? '' : s(a['start_date']).substring(0, s(a['start_date']).length > 10 ? 10 : s(a['start_date']).length));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a == null ? 'Nueva actividad' : 'Editar actividad'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: type, decoration: const InputDecoration(labelText: 'Tipo'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: modality, decoration: const InputDecoration(labelText: 'Modalidad'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: week, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Semana'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: startDate, decoration: const InputDecoration(labelText: 'Fecha inicio (AAAA-MM-DD)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final body = {
        'title': title.text.trim(),
        'type': type.text.trim(),
        'modality': modality.text.trim(),
        'hours': double.tryParse(hours.text) ?? 0,
        'week': int.tryParse(week.text),
        'start_date': startDate.text.trim().isEmpty ? null : startDate.text.trim(),
      };
      final done = await runAction(context, () async {
        if (a == null) {
          await Api.request('POST', '/api/activities', body: {'unit_id': u['id'], ...body});
        } else {
          await Api.request('PATCH', '/api/activities/${a['id']}', body: body);
        }
      }, success: 'Guardado');
      if (done) _load();
    }
  }

  Future<void> _editEvaluation(dynamic u, dynamic e) async {
    final title = TextEditingController(text: e == null ? '' : s(e['title']));
    final type = TextEditingController(text: e == null ? 'parcial' : s(e['type']));
    final weight = TextEditingController(text: e == null ? '0' : n(e['weight']).toStringAsFixed(0));
    final week = TextEditingController(text: e == null || e['week'] == null ? '' : '${i(e['week'])}');
    final dueDate = TextEditingController(text: e == null ? '' : s(e['due_date']).substring(0, s(e['due_date']).length > 10 ? 10 : s(e['due_date']).length));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e == null ? 'Nueva evaluación' : 'Editar evaluación'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: type, decoration: const InputDecoration(labelText: 'Tipo'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Peso %'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: week, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Semana'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: dueDate, decoration: const InputDecoration(labelText: 'Entrega (AAAA-MM-DD)'))),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final body = {
        'title': title.text.trim(),
        'type': type.text.trim(),
        'weight': double.tryParse(weight.text) ?? 0,
        'week': int.tryParse(week.text),
        'due_date': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
      };
      final done = await runAction(context, () async {
        if (e == null) {
          await Api.request('POST', '/api/evaluations', body: {'unit_id': u['id'], ...body});
        } else {
          await Api.request('PATCH', '/api/evaluations/${e['id']}', body: body);
        }
      }, success: 'Guardado');
      if (done) _load();
    }
  }

  Future<void> _editRubric(dynamic u, dynamic r) async {
    final title = TextEditingController(text: r == null ? '' : s(r['title']));
    final criteria = TextEditingController(
      text: r == null ? '' : ((r['criteria'] as List?) ?? const []).map((c) => c is Map ? s(c['name'] ?? c['description'] ?? c) : s(c)).join('\n'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? 'Nueva rúbrica' : 'Editar rúbrica'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Título *')),
          const SizedBox(height: 8),
          TextField(
            controller: criteria,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Criterios (uno por línea)',
              helperText: 'Se guarda como lista de {name, weight}',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final lines = criteria.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final body = {
        'title': title.text.trim(),
        'criteria': lines.map((l) => {'name': l, 'weight': 100 / (lines.isEmpty ? 1 : lines.length)}).toList(),
      };
      final done = await runAction(context, () async {
        if (r == null) {
          await Api.request('POST', '/api/rubrics', body: {'unit_id': u['id'], ...body});
        } else {
          await Api.request('PATCH', '/api/rubrics/${r['id']}', body: body);
        }
      }, success: 'Guardado');
      if (done) _load();
    }
  }

  Future<void> _deleteEntity(String resource, dynamic item) async {
    if (await confirmDelete(context, '"${s(item['title'])}"')) {
      final done = await runAction(context, () async {
        await Api.request('DELETE', '/api/$resource/${item['id']}');
      }, success: 'Eliminado');
      if (done) _load();
    }
  }

  Future<void> _editCourse() async {
    final name = TextEditingController(text: s(widget.course['name']));
    final desc = TextEditingController(text: s(widget.course['description']));
    final weeks = TextEditingController(text: '${i(widget.course['cuatrimestre_weeks'], 16)}');
    final hours = TextEditingController(text: '${n(widget.course['total_hours'], 64).toStringAsFixed(0)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar curso'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 8),
          TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: weeks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Semanas'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas'))),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final done = await runAction(context, () async {
        await Api.request('PATCH', '/api/courses/$_courseId', body: {
          'name': name.text.trim(),
          'description': desc.text.trim(),
          'cuatrimestre_weeks': int.tryParse(weeks.text),
          'total_hours': double.tryParse(hours.text),
        });
      }, success: 'Curso actualizado');
      if (done) _load();
    }
  }

  Future<void> _deleteCourse() async {
    if (await confirmDelete(context, 'el curso')) {
      final done = await runAction(context, () async {
        await Api.request('DELETE', '/api/courses/$_courseId');
      }, success: 'Curso eliminado');
      if (done && mounted) Navigator.of(context).pop();
    }
  }
}
