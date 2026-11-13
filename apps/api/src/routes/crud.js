import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

const router = Router();
router.use(requireAuth);

// ---------- Cursos ----------
router.get('/courses', async (req, res) => {
  const { data, error } = await supabase.from('courses').select('*').order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/courses', async (req, res) => {
  const { name, description, cuatrimestre_weeks = 16, total_hours = 64 } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name es requerido' });
  const { data, error } = await supabase
    .from('courses')
    .insert({ name, description, cuatrimestre_weeks, total_hours, instructor_id: req.user.sub })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/courses/:id', async (req, res) => {
  const { data, error } = await supabase
    .from('courses')
    .update(req.body)
    .eq('id', req.params.id)
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/courses/:id', async (req, res) => {
  const { error } = await supabase.from('courses').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Unidades ----------
router.get('/units', async (req, res) => {
  let q = supabase.from('units').select('*').order('number');
  if (req.query.course_id) q = q.eq('course_id', req.query.course_id);
  const { data, error } = await q;
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/units', async (req, res) => {
  const { course_id, number, title, objectives } = req.body || {};
  if (!course_id || !number || !title) return res.status(400).json({ error: 'course_id, number y title son requeridos' });
  const { data, error } = await supabase.from('units').insert({ course_id, number, title, objectives }).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/units/:id', async (req, res) => {
  const { data, error } = await supabase.from('units').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/units/:id', async (req, res) => {
  const { error } = await supabase.from('units').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Resultados de aprendizaje ----------
router.get('/outcomes', async (req, res) => {
  let q = supabase.from('outcomes').select('*');
  if (req.query.unit_id) q = q.eq('unit_id', req.query.unit_id);
  const { data, error } = await q.order('created_at');
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/outcomes', async (req, res) => {
  const { unit_id, code, title, bloom_level } = req.body || {};
  if (!unit_id || !title) return res.status(400).json({ error: 'unit_id y title son requeridos' });
  const { data, error } = await supabase.from('outcomes').insert({ unit_id, code, title, bloom_level }).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/outcomes/:id', async (req, res) => {
  const { data, error } = await supabase.from('outcomes').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/outcomes/:id', async (req, res) => {
  const { error } = await supabase.from('outcomes').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Actividades ----------
router.get('/activities', async (req, res) => {
  let q = supabase.from('activities').select('*, units(number, title, course_id)').order('week', { nullsFirst: true });
  if (req.query.unit_id) q = q.eq('unit_id', req.query.unit_id);
  if (req.query.course_id) q = q.eq('units.course_id', req.query.course_id);
  const { data, error } = await q;
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/activities', async (req, res) => {
  const { unit_id, title, type = 'clase', hours = 0, modality = 'presencial', week, start_date } = req.body || {};
  if (!unit_id || !title) return res.status(400).json({ error: 'unit_id y title son requeridos' });
  const { data, error } = await supabase
    .from('activities')
    .insert({ unit_id, title, type, hours, modality, week, start_date })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/activities/:id', async (req, res) => {
  const { data, error } = await supabase.from('activities').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/activities/:id', async (req, res) => {
  const { error } = await supabase.from('activities').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Evaluaciones ----------
router.get('/evaluations', async (req, res) => {
  let q = supabase.from('evaluations').select('*').order('week', { nullsFirst: true });
  if (req.query.unit_id) q = q.eq('unit_id', req.query.unit_id);
  const { data, error } = await q;
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/evaluations', async (req, res) => {
  const { unit_id, title, type = 'parcial', weight = 0, week, due_date } = req.body || {};
  if (!unit_id || !title) return res.status(400).json({ error: 'unit_id y title son requeridos' });
  const { data, error } = await supabase
    .from('evaluations')
    .insert({ unit_id, title, type, weight, week, due_date })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/evaluations/:id', async (req, res) => {
  const { data, error } = await supabase.from('evaluations').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/evaluations/:id', async (req, res) => {
  const { error } = await supabase.from('evaluations').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Rúbricas ----------
router.get('/rubrics', async (req, res) => {
  let q = supabase.from('rubrics').select('*');
  if (req.query.unit_id) q = q.eq('unit_id', req.query.unit_id);
  if (req.query.evaluation_id) q = q.eq('evaluation_id', req.query.evaluation_id);
  const { data, error } = await q.order('created_at');
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/rubrics', async (req, res) => {
  const { evaluation_id, unit_id, title, criteria = [] } = req.body || {};
  if (!title || (!evaluation_id && !unit_id)) {
    return res.status(400).json({ error: 'title y evaluation_id o unit_id son requeridos' });
  }
  const { data, error } = await supabase
    .from('rubrics')
    .insert({ evaluation_id, unit_id, title, criteria })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/rubrics/:id', async (req, res) => {
  const { data, error } = await supabase.from('rubrics').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/rubrics/:id', async (req, res) => {
  const { error } = await supabase.from('rubrics').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

export default router;
