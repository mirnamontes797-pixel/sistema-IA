import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';
import { balanceWorkload, balanceByInstructor } from '../services/balance.js';
import { buildTeamsInstructions } from '../services/teams.js';

const router = Router();
router.use(requireAuth);

// ---------- Vista agregada de planeación de un curso ----------
router.get('/courses/:id/plan', async (req, res) => {
  const courseId = req.params.id;
  const [course, units, activities, evaluations, rubrics] = await Promise.all([
    supabase.from('courses').select('*').eq('id', courseId).single(),
    supabase.from('units').select('*').eq('course_id', courseId).order('number'),
    supabase.from('activities').select('*, units!inner(course_id, number)').eq('units.course_id', courseId),
    supabase.from('evaluations').select('*, units!inner(course_id)').eq('units.course_id', courseId),
    supabase.from('rubrics').select('*, units!inner(course_id)').eq('units.course_id', courseId)
  ]);
  if (course.error) return res.status(404).json({ error: 'Curso no encontrado' });
  const unitIds = units.data.map((u) => u.id);
  const { data: outcomes } = await supabase.from('outcomes').select('*').in('unit_id', unitIds);

  const byUnit = (rows, key = 'unit_id') => {
    const m = new Map();
    for (const r of rows || []) {
      const k = r[key];
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(r);
    }
    return m;
  };

  res.json({
    course: course.data,
    units: units.data.map((u) => ({
      ...u,
      outcomes: byUnit(outcomes).get(u.id) || [],
      activities: byUnit(activities.data).get(u.id) || [],
      evaluations: byUnit(evaluations.data).get(u.id) || [],
      rubrics: byUnit(rubrics.data).get(u.id) || []
    }))
  });
});

// ---------- Cronograma semanal ----------
router.get('/courses/:id/schedule', async (req, res) => {
  const { data: course } = await supabase.from('courses').select('*').eq('id', req.params.id).single();
  if (!course) return res.status(404).json({ error: 'Curso no encontrado' });
  const weeks = Array.from({ length: course.cuatrimestre_weeks }, (_, i) => ({
    week: i + 1,
    activities: [],
    evaluations: []
  }));
  const { data: units } = await supabase.from('units').select('id').eq('course_id', course.id);
  const unitIds = (units || []).map((u) => u.id);
  if (!unitIds.length) return res.json({ course, weeks });

  const [{ data: activities }, { data: evaluations }] = await Promise.all([
    supabase.from('activities').select('*, units(number, title)').in('unit_id', unitIds),
    supabase.from('evaluations').select('*, units(number, title)').in('unit_id', unitIds)
  ]);
  for (const a of activities || []) {
    const w = weeks.find((x) => x.week === a.week) || weeks[a.week - 1];
    if (w) w.activities.push(a);
  }
  for (const e of evaluations || []) {
    const w = weeks.find((x) => x.week === e.week) || weeks[e.week - 1];
    if (w) w.evaluations.push(e);
  }
  res.json({ course, weeks });
});

// ---------- Balance de cargas ----------
router.post('/courses/:id/balance', async (req, res) => {
  const { data: course } = await supabase.from('courses').select('*').eq('id', req.params.id).single();
  if (!course) return res.status(404).json({ error: 'Curso no encontrado' });
  const { data: units } = await supabase.from('units').select('id, number').eq('course_id', course.id);
  const unitIds = (units || []).map((u) => u.id);
  const unitMap = new Map((units || []).map((u) => [u.id, u.number]));
  const { data: activities } = await supabase.from('activities').select('*').in('unit_id', unitIds);

  const weeklyCapacity = course.total_hours / course.cuatrimestre_weeks;
  const normalized = (activities || []).map((a) => ({
    ...a,
    unit_number: unitMap.get(a.unit_id) || 0
  }));
  const result = balanceWorkload(normalized, course.cuatrimestre_weeks, weeklyCapacity);

  // Persistir asignaciones propuestas (solo las que cambiaron o estaban vacías)
  const updates = [];
  for (const a of normalized) {
    const proposed = result.assignments.get(a.id);
    if (proposed && proposed !== a.week) {
      updates.push(supabase.from('activities').update({ week: proposed }).eq('id', a.id));
    }
  }
  await Promise.all(updates);

  res.json({
    weeklyCapacity: Number(weeklyCapacity.toFixed(2)),
    loadPerWeek: result.load,
    variance: Number(result.variance.toFixed(2)),
    warnings: result.warnings,
    assignments: Object.fromEntries(result.assignments)
  });
});

// Balance entre instructores (varias secciones)
router.get('/balance/instructors', async (req, res) => {
  const { data: courses } = await supabase.from('courses').select('id, instructor_id');
  const courseLoads = [];
  for (const c of courses || []) {
    const { data: units } = await supabase.from('units').select('id').eq('course_id', c.id);
    const unitIds = (units || []).map((u) => u.id);
    if (!unitIds.length) continue;
    const { data: acts } = await supabase.from('activities').select('hours, week').in('unit_id', unitIds);
    const weekly = {};
    for (const a of acts || []) if (a.week) weekly[a.week] = (weekly[a.week] || 0) + Number(a.hours || 0);
    const maxW = Math.max(0, ...Object.keys(weekly).map(Number));
    courseLoads.push({
      courseId: c.id,
      instructorId: c.instructor_id,
      weeklyHours: Array.from({ length: maxW }, (_, i) => weekly[i + 1] || 0)
    });
  }
  res.json({ data: balanceByInstructor(courseLoads) });
});

// ---------- Instrucciones para Teams ----------
router.post('/teams/instructions', async (req, res) => {
  const { activity_id, unit_id, evaluation_id } = req.body || {};
  let activity = null, unit = null, rubric = null;
  const outcomes = [];

  if (activity_id) {
    const { data } = await supabase.from('activities').select('*, units(*, courses(*))').eq('id', activity_id).single();
    if (!data) return res.status(404).json({ error: 'Actividad no encontrada' });
    activity = data;
    unit = data.units;
  } else if (unit_id || evaluation_id) {
    let uid = unit_id;
    if (evaluation_id) {
      const { data: ev } = await supabase.from('evaluations').select('*, units(*)').eq('id', evaluation_id).single();
      if (!ev) return res.status(404).json({ error: 'Evaluación no encontrada' });
      uid = ev.unit_id;
      unit = ev.units;
      activity = { title: ev.title, type: ev.type, modality: 'teams', hours: 0, start_date: ev.due_date };
      const { data: rb } = await supabase.from('rubrics').select('*').eq('evaluation_id', evaluation_id).limit(1);
      rubric = rb?.[0] || null;
    }
    if (!activity) activity = { title: 'Actividad', type: 'clase', modality: 'teams', hours: 0 };
    if (!unit && uid) {
      const { data } = await supabase.from('units').select('*, courses(*)').eq('id', uid).single();
      unit = data;
    }
  } else {
    return res.status(400).json({ error: 'activity_id, unit_id o evaluation_id requerido' });
  }

  if (unit?.id) {
    const { data: outs } = await supabase.from('outcomes').select('*').eq('unit_id', unit.id);
    outcomes.push(...(outs || []));
    if (!rubric) {
      const { data: rb } = await supabase.from('rubrics').select('*').eq('unit_id', unit.id).limit(1);
      rubric = rb?.[0] || null;
    }
  }

  const instructions = buildTeamsInstructions({
    activity,
    unit,
    outcomes,
    rubric,
    course: unit?.courses
  });
  res.json({ instructions });
});

export default router;
