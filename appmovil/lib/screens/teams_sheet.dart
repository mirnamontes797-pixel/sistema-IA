import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../ui.dart';

/// Muestra un selector de actividad/evaluación del curso y genera las
/// instrucciones para Teams vía POST /api/teams/instructions.
Future<void> showTeamsSheet(BuildContext context, String courseId) async {
  Map<String, dynamic>? plan;
  try {
    final res = await Api.request('GET', '/api/courses/$courseId/plan');
    plan = Map<String, dynamic>.from(res as Map);
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString(), error: true);
    return;
  }

  final units = (plan['units'] as List?) ?? const [];
  final options = <Map<String, dynamic>>[];
  for (final u in units) {
    for (final a in (u['activities'] as List? ?? const [])) {
      options.add({'kind': 'activity', 'id': a['id'], 'label': '🎯 ${a['title']} (sem. ${i(a['week'], 0)})'});
    }
    for (final e in (u['evaluations'] as List? ?? const [])) {
      options.add({'kind': 'evaluation', 'id': e['id'], 'label': '📝 ${e['title']} (sem. ${i(e['week'], 0)})'});
    }
  }
  if (options.isEmpty) {
    if (context.mounted) {
      showSnack(context, 'El curso no tiene actividades ni evaluaciones', error: true);
    }
    return;
  }

  if (!context.mounted) return;
  final selected = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Generar instrucciones para Teams',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...options.map((o) => ListTile(
                title: Text(o['label'] as String),
                onTap: () => Navigator.pop(ctx, o),
              )),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;

  final kind = selected['kind'] as String;
  final body = kind == 'activity'
      ? {'activity_id': selected['id']}
      : {'evaluation_id': selected['id']};

  String? instructions;
  final done = await runAction(context, () async {
    final res = await Api.request('POST', '/api/teams/instructions', body: body);
    instructions = s(res['instructions']);
  }, success: 'Instrucciones generadas');
  if (!done || !context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Instrucciones para Teams'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(instructions ?? '')),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: instructions ?? ''));
            showSnack(context, 'Copiado al portapapeles');
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}
