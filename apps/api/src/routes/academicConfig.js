import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';
import { computeAcademicSummary } from '../services/academicCalc.js';

const router = Router();
router.use(requireAuth);

function canManage(req, course) {
  return req.user.role === 'admin' || course.instructor_id === req.user.sub;
}

async function requireCourse(req, res, { manage = false } = {}) {
  const { data: course, error } = await supabase
    .from('courses').select('id, name, instructor_id, cuatrimestre_weeks, total_hours')
    .eq('id', req.params.id).maybeSingle();
  if (error) { res.status(500).json({ error: error.message }); return null; }
  if (!course) { res.status(404).json({ error: 'Curso no encontrado' }); return null; }
  if (manage && !canManage(req, course)) {
    res.status(403).json({ error: 'No tienes permiso para modificar la configuración de este curso' });
    return null;
  }
  return course;
}

async function getConfigRow(courseId) {
  const { data } = await supabase
    .from('course_academic_configs').select('*').eq('course_id', courseId).maybeSingle();
  return data || null;
}

async function getChildRows(configId) {
  if (!configId) return { sessions: [], events: [] };
  const [sessions, events] = await Promise.all([
    supabase.from('schedule_sessions').select('*').eq('config_id', configId).order('weekday').order('position'),
    supabase.from('academic_events').select('*').eq('config_id', configId).order('start_date')
  ]);
  return { sessions: sessions.data || [], events: events.data || [] };
}

// Horas teóricas/prácticas según la carta descriptiva (actividades generadas en etapa 2)
async function getRequiredHours(courseId, course) {
  const { data: units } = await supabase.from('units').select('id').eq('course_id', courseId);
  const unitIds = (units || []).map((u) => u.id);
  let theory = 0, practice = 0;
  if (unitIds.length) {
    const { data: acts } = await supabase
      .from('activities').select('title, hours').in('unit_id', unitIds);
    for (const a of acts || []) {
      const t = (a.title || '').toLowerCase();
      if (!/carta descriptiva/.test(t)) continue;
      const h = Number(a.hours) || 0;
      if (/pr[aá]ctica/.test(t)) practice += h;
      else theory += h;
    }
  }
  const total = theory + practice || Number(course.total_hours) || 0;
  return { theory, practice, total };
}

function emptyConfig(course) {
  return {
    course_id: course.id,
    period_name: '',
    start_date: null,
    end_date: null,
    weeks: course.cuatrimestre_weeks || null,
    modality: null,
    institution: null,
    academic_hour_minutes: 50,
    autonomous_hours_per_week: 0,
    required_theory_hours: null,
    required_practice_hours: null
  };
}

// GET /courses/:id/academic-config — config + horarios + eventos + resumen calculado
router.get('/courses/:id/academic-config', async (req, res) => {
  const course = await requireCourse(req, res);
  if (!course) return;

  const configRow = await getConfigRow(course.id);
  const { sessions, events } = await getChildRows(configRow?.id);
  const required = await getRequiredHours(course.id, course);
  const config = { ...emptyConfig(course), ...(configRow || {}) };

  const [presetsRes, previousRes] = await Promise.all([
    supabase.from('period_presets').select('*').order('created_at', { ascending: false }),
    supabase.from('course_academic_configs').select('id, period_name, start_date, end_date, weeks, modality, institution, academic_hour_minutes, autonomous_hours_per_week, course_id, courses(name)')
      .neq('course_id', course.id).order('updated_at', { ascending: false }).limit(20)
  ]);

  const summary = computeAcademicSummary({ config, sessions, events, required });
  res.json({
    data: {
      course: { id: course.id, name: course.name, cuatrimestre_weeks: course.cuatrimestre_weeks, total_hours: course.total_hours },
      config,
      sessions,
      events,
      presets: presetsRes.data || [],
      previous: (previousRes.data || []).map((p) => ({ ...p, course_name: p.courses?.name || '' })),
      required,
      summary
    }
  });
});

// PUT /courses/:id/academic-config — guarda config + horarios + eventos.
// Solo reemplaza las filas de este módulo; no toca unidades, actividades ni evaluaciones.
router.put('/courses/:id/academic-config', async (req, res) => {
  const course = await requireCourse(req, res, { manage: true });
  if (!course) return;

  const body = req.body || {};
  const c = body.config || {};
  const sessions = Array.isArray(body.sessions) ? body.sessions : [];
  const events = Array.isArray(body.events) ? body.events : [];

  const configPayload = {
    course_id: course.id,
    period_name: c.period_name || null,
    start_date: c.start_date || null,
    end_date: c.end_date || null,
    weeks: c.weeks === '' || c.weeks == null ? null : Number(c.weeks),
    modality: ['presencial', 'virtual', 'mixta'].includes(c.modality) ? c.modality : null,
    institution: c.institution || null,
    academic_hour_minutes: Number(c.academic_hour_minutes) > 0 ? Number(c.academic_hour_minutes) : 50,
    autonomous_hours_per_week: Number(c.autonomous_hours_per_week) || 0,
    required_theory_hours: c.required_theory_hours === '' || c.required_theory_hours == null ? null : Number(c.required_theory_hours),
    required_practice_hours: c.required_practice_hours === '' || c.required_practice_hours == null ? null : Number(c.required_practice_hours)
  };

  const existing = await getConfigRow(course.id);
  let configId;
  if (existing) {
    const { data, error } = await supabase
      .from('course_academic_configs').update({ ...configPayload, updated_at: new Date().toISOString() })
      .eq('id', existing.id).select().single();
    if (error) return res.status(500).json({ error: error.message });
    configId = data.id;
  } else {
    const { data, error } = await supabase
      .from('course_academic_configs').insert(configPayload).select().single();
    if (error) return res.status(500).json({ error: error.message });
    configId = data.id;
  }

  // Reemplazar sesiones y eventos de este curso (son datos de este módulo)
  const delSessions = await supabase.from('schedule_sessions').delete().eq('config_id', configId);
  if (delSessions.error) return res.status(500).json({ error: delSessions.error.message });
  const delEvents = await supabase.from('academic_events').delete().eq('config_id', configId);
  if (delEvents.error) return res.status(500).json({ error: delEvents.error.message });

  const sessionRows = sessions
    .filter((s) => s && s.weekday != null && s.start_time && s.end_time)
    .map((s, i) => ({
      config_id: configId,
      weekday: Number(s.weekday),
      start_time: s.start_time,
      end_time: s.end_time,
      session_type: ['presencial', 'virtual_sincrona', 'autonomo'].includes(s.session_type) ? s.session_type : 'presencial',
      academic_hours: s.academic_hours === '' || s.academic_hours == null ? null : Number(s.academic_hours),
      active: s.active !== false,
      position: Number(s.position ?? i)
    }));
  if (sessionRows.length) {
    const { error } = await supabase.from('schedule_sessions').insert(sessionRows);
    if (error) return res.status(500).json({ error: error.message });
  }

  const eventRows = events
    .filter((e) => e && e.type && e.start_date)
    .map((e) => ({
      config_id: configId,
      type: ['inhabil', 'suspension', 'eval_ordinaria', 'eval_extraordinaria', 'evento'].includes(e.type) ? e.type : 'evento',
      title: e.title || null,
      start_date: e.start_date,
      end_date: e.end_date || e.start_date,
      note: e.note || null
    }));
  if (eventRows.length) {
    const { error } = await supabase.from('academic_events').insert(eventRows);
    if (error) return res.status(500).json({ error: error.message });
  }

  const required = await getRequiredHours(course.id, course);
  const summary = computeAcademicSummary({ config: { ...emptyConfig(course), ...configPayload }, sessions: sessionRows, events: eventRows, required });
  res.json({ ok: true, message: 'Configuración del cuatrimestre guardada', summary });
});

// ---------- Configuraciones predeterminadas de periodo ----------
router.get('/period-presets', async (req, res) => {
  const { data, error } = await supabase.from('period_presets').select('*').order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/period-presets', async (req, res) => {
  const b = req.body || {};
  if (!b.name) return res.status(400).json({ error: 'name es requerido' });
  const { data, error } = await supabase.from('period_presets').insert({
    name: b.name,
    modality: ['presencial', 'virtual', 'mixta'].includes(b.modality) ? b.modality : null,
    institution: b.institution || null,
    weeks: b.weeks ? Number(b.weeks) : null,
    academic_hour_minutes: Number(b.academic_hour_minutes) > 0 ? Number(b.academic_hour_minutes) : 50,
    autonomous_hours_per_week: Number(b.autonomous_hours_per_week) || 0
  }).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.delete('/period-presets/:id', async (req, res) => {
  const { error } = await supabase.from('period_presets').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

export default router;
