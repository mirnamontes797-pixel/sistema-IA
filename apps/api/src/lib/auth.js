import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { supabase } from './supabase.js';

export async function hashPassword(password) {
  return bcrypt.hash(password, env.bcryptRounds);
}

export async function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash);
}

export function signToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role },
    env.jwtSecret,
    { expiresIn: env.jwtExpiresIn }
  );
}

export async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token requerido' });
  let payload;
  try {
    payload = jwt.verify(token, env.jwtSecret);
  } catch {
    return res.status(401).json({ error: 'Token inválido o expirado' });
  }
  try {
    const { data: user, error } = await supabase.from('users').select('id, role').eq('id', payload.sub).maybeSingle();
    if (error) return res.status(500).json({ error: error.message });
    if (!user) return res.status(401).json({ error: 'Token inválido o expirado' });
    req.user = { ...payload, role: user.role };
    next();
  } catch {
    return res.status(500).json({ error: 'No se pudo validar la sesión' });
  }
}
