import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { hashPassword, verifyPassword, signToken, requireAuth } from '../lib/auth.js';

const router = Router();

router.post('/register', async (req, res) => {
  const { email, password, full_name, role = 'instructor' } = req.body || {};
  if (!email || !password || !full_name) {
    return res.status(400).json({ error: 'email, password y full_name son requeridos' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });
  }
  const password_hash = await hashPassword(password);
  const { data, error } = await supabase
    .from('users')
    .insert({ email, password_hash, full_name, role })
    .select('id, email, full_name, role')
    .single();
  if (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'El correo ya está registrado' });
    return res.status(500).json({ error: error.message });
  }
  res.status(201).json({ user: data, token: signToken(data) });
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email y password requeridos' });
  const { data: user, error } = await supabase
    .from('users')
    .select('*')
    .eq('email', email)
    .single();
  if (error || !user) return res.status(401).json({ error: 'Credenciales inválidas' });
  const ok = await verifyPassword(password, user.password_hash);
  if (!ok) return res.status(401).json({ error: 'Credenciales inválidas' });
  const safe = { id: user.id, email: user.email, full_name: user.full_name, role: user.role };
  res.json({ user: safe, token: signToken(safe) });
});

router.get('/me', requireAuth, async (req, res) => {
  const { data } = await supabase
    .from('users')
    .select('id, email, full_name, role')
    .eq('id', req.user.sub)
    .single();
  res.json({ user: data });
});

export default router;
