import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

/// Cronograma semanal del curso: GET /api/courses/:id/schedule.
class ScheduleScreen extends StatefulWidget {
  final String courseId;
  final String courseName;
  const ScheduleScreen({super.key, required this.courseId, required this.courseName});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Map<String, dynamic>? _data;
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
      final res = await Api.request('GET', '/api/courses/${widget.courseId}/schedule');
      _data = Map<String, dynamic>.from(res as Map);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cronograma · ${widget.courseName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: ((_data?['weeks'] as List?) ?? const []).length,
                    itemBuilder: (_, idx) {
                      final w = (_data!['weeks'] as List)[idx];
                      final acts = (w['activities'] as List?) ?? const [];
                      final evals = (w['evaluations'] as List?) ?? const [];
                      if (acts.isEmpty && evals.isEmpty) return const SizedBox.shrink();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Semana ${i(w['week'])}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ...acts.map((a) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(children: [
                                    const Icon(Icons.play_circle_outline, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('${s(a['title'])} · ${s(a['type'])}')),
                                    Text('${n(a['hours']).toStringAsFixed(0)} h',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ]),
                                )),
                            ...evals.map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(children: [
                                    const Icon(Icons.assignment_outlined, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('${s(e['title'])} · ${s(e['type'])}')),
                                    if (n(e['weight']) > 0)
                                      Text('${n(e['weight']).toStringAsFixed(0)}%',
                                          style: Theme.of(context).textTheme.bodySmall),
                                  ]),
                                )),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
