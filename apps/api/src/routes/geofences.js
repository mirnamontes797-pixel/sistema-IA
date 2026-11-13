import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

const router = Router();
router.use(requireAuth);

// ---------- Geocercas ----------
router.get('/geofences', async (req, res) => {
  const { data, error } = await supabase.from('geofences').select('*').order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/geofences', async (req, res) => {
  const { name, description, polygon, color, active = true } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name es requerido' });
  if (!Array.isArray(polygon) || polygon.length < 3) {
    return res.status(400).json({ error: 'polygon debe tener al menos 3 vértices [[lat, lng], ...]' });
  }
  const clean = [];
  for (const v of polygon) {
    const lat = Number(v?.[0]);
    const lng = Number(v?.[1]);
    if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
      return res.status(400).json({ error: 'Vértices del polígono inválidos' });
    }
    clean.push([lat, lng]);
  }
  const { data, error } = await supabase
    .from('geofences')
    .insert({ name, description: description || null, polygon: clean, color: color || '#0d9488', active })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.patch('/geofences/:id', async (req, res) => {
  const allowed = {};
  for (const k of ['name', 'description', 'color', 'active']) {
    if (req.body[k] !== undefined) allowed[k] = req.body[k];
  }
  if (req.body.polygon !== undefined) {
    const p = req.body.polygon;
    if (!Array.isArray(p) || p.length < 3) {
      return res.status(400).json({ error: 'polygon debe tener al menos 3 vértices [[lat, lng], ...]' });
    }
    allowed.polygon = p.map((v) => [Number(v?.[0]), Number(v?.[1])]);
  }
  const { data, error } = await supabase
    .from('geofences')
    .update(allowed)
    .eq('id', req.params.id)
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/geofences/:id', async (req, res) => {
  const { error } = await supabase.from('geofences').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Eventos ----------
router.get('/geofence-events', async (req, res) => {
  let q = supabase
    .from('geofence_events')
    .select('*, geofences(name, color)')
    .order('occurred_at', { ascending: false })
    .limit(200);
  if (req.query.geofence_id) q = q.eq('geofence_id', req.query.geofence_id);
  if (req.query.subject) q = q.eq('subject', req.query.subject);
  const { data, error } = await q;
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.delete('/geofence-events/:id', async (req, res) => {
  const { error } = await supabase.from('geofence_events').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

// ---------- Verificación de posición (detecta entradas/salidas) ----------
function pointInPolygon(lat, lng, polygon) {
  // Ray casting; polygon = [[lat, lng], ...]
  let inside = false;
  const n = polygon.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const [yi, xi] = polygon[i];
    const [yj, xj] = polygon[j];
    const intersects = xi > lng !== xj > lng &&
      lat < ((yj - yi) * (lng - xi)) / (xj - xi) + yi;
    if (intersects) inside = !inside;
  }
  return inside;
}

router.post('/geofences/check', async (req, res) => {
  const { subject, latitude, longitude } = req.body || {};
  if (!subject || typeof subject !== 'string') {
    return res.status(400).json({ error: 'subject es requerido' });
  }
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    return res.status(400).json({ error: 'latitude y longitude válidas son requeridas' });
  }

  const { data: fences, error: fErr } = await supabase
    .from('geofences')
    .select('*')
    .eq('active', true);
  if (fErr) return res.status(500).json({ error: fErr.message });
  if (!fences.length) return res.json({ data: [] });

  const { data: states, error: sErr } = await supabase
    .from('geofence_states')
    .select('*')
    .eq('subject', subject)
    .in('geofence_id', fences.map((f) => f.id));
  if (sErr) return res.status(500).json({ error: sErr.message });

  const stateMap = new Map((states || []).map((s) => [s.geofence_id, s.inside]));
  const results = [];
  const newStates = [];
  const newEvents = [];

  for (const fence of fences) {
    const polygon = (fence.polygon || []).map((v) => [Number(v[0]), Number(v[1])]);
    const inside = polygon.length >= 3 && pointInPolygon(lat, lng, polygon);
    const wasInside = stateMap.get(fence.id) === true;
    results.push({ geofence_id: fence.id, name: fence.name, color: fence.color, inside });

    if (inside !== wasInside) {
      newEvents.push({
        geofence_id: fence.id,
        subject,
        event_type: inside ? 'enter' : 'exit',
        latitude: lat,
        longitude: lng
      });
    }
    newStates.push({ geofence_id: fence.id, subject, inside, updated_at: new Date().toISOString() });
  }

  if (newStates.length) {
    const { error: upErr } = await supabase
      .from('geofence_states')
      .upsert(newStates, { onConflict: 'geofence_id,subject' });
    if (upErr) return res.status(500).json({ error: upErr.message });
  }
  if (newEvents.length) {
    const { error: evErr } = await supabase.from('geofence_events').insert(newEvents);
    if (evErr) return res.status(500).json({ error: evErr.message });
  }

  res.json({ data: results });
});

export default router;
