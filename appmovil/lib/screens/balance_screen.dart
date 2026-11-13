import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

/// Balance de cargas: selecciona un curso y ejecuta POST /api/courses/:id/balance.
class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  List<dynamic> _courses = [];
  String? _selected;
  Map<String, dynamic>? _result;
  bool _loading = false;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      _courses = await Api.list('/api/courses');
      if (_courses.isNotEmpty && _selected == null) _selected = _courses.first['id'].toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runBalance() async {
    if (_selected == null) return;
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final res = await Api.request('POST', '/api/courses/$_selected/balance');
      _result = Map<String, dynamic>.from(res as Map);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance de cargas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Curso', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selected,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: _courses
                                .map((c) => DropdownMenuItem(
                                    value: c['id'].toString(),
                                    child: Text(s(c['name']), overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => setState(() => _selected = v),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: _running
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.balance),
                              label: const Text('Calcular balance'),
                              onPressed: _running ? null : _runBalance,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 4),
                      _summaryCard(),
                      const SizedBox(height: 8),
                      _loadCard(),
                      if ((_result!['warnings'] as List?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        _warningsCard(),
                      ],
                    ],
                  ],
                ),
    );
  }

  Widget _summaryCard() {
    final load = (_result!['loadPerWeek'] as List?) ?? const [];
    final max = load.fold<double>(0, (m, v) => n(v) > m ? n(v) : m);
    final min = load.fold<double>(double.infinity, (m, v) => n(v) < m ? n(v) : m);
    return SectionCard(
      title: 'Resumen',
      child: Row(children: [
        _stat('Capacidad/sem.', '${n(_result!['weeklyCapacity']).toStringAsFixed(1)} h'),
        _stat('Carga máx.', '${max.toStringAsFixed(1)} h'),
        _stat('Carga mín.', load.isEmpty ? '—' : '${min.toStringAsFixed(1)} h'),
        _stat('Varianza', '${n(_result!['variance']).toStringAsFixed(1)}'),
      ]),
    );
  }

  Widget _loadCard() {
    final load = (_result!['loadPerWeek'] as List?) ?? const [];
    return SectionCard(
      title: 'Carga por semana',
      child: SizedBox(
        height: 140,
        child: load.isEmpty
            ? const Center(child: Text('Sin actividades'))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: load.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, idx) {
                  final v = n(load[idx]);
                  final cap = n(_result!['weeklyCapacity']);
                  final ratio = cap > 0 ? (v / cap).clamp(0.0, 1.5) : 0.0;
                  final color = ratio <= 1 ? Colors.teal : Colors.orange;
                  return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 2),
                    Container(
                      width: 34,
                      height: (ratio * 90).clamp(4, 120).toDouble(),
                      decoration: BoxDecoration(color: color.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 2),
                    Text('S${idx + 1}', style: const TextStyle(fontSize: 11)),
                  ]);
                },
              ),
      ),
    );
  }

  Widget _warningsCard() {
    final warnings = (_result!['warnings'] as List?) ?? const [];
    return SectionCard(
      title: 'Advertencias (${warnings.length})',
      child: Column(children: warnings.map((w) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(child: Text(s(w))),
            ]),
          )).toList()),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}
