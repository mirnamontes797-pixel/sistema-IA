import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

const router = Router();
router.use(requireAuth);

// ---------- Instituciones (Mapa de Instituciones) ----------
router.get('/institutions', async (req, res) => {
  const { data, error } = await supabase.from('institutions').select('*').order('name');
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.post('/institutions', async (req, res) => {
  const { name, address, latitude, longitude } = req.body || {};
  if (!name || !address) return res.status(400).json({ error: 'name y address son requeridos' });
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    return res.status(400).json({ error: 'latitude y longitude válidas son requeridas' });
  }
  const { data, error } = await supabase
    .from('institutions')
    .insert({ name, address, latitude: lat, longitude: lng })
    .select()
    .single();
  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json({ data });
});

router.delete('/institutions/:id', async (req, res) => {
  const { error } = await supabase.from('institutions').delete().eq('id', req.params.id);
  if (error) return res.status(500).json({ error: error.message });
  res.json({ ok: true });
});

export default router;
