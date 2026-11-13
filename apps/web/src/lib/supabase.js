import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.PUBLIC_SUPABASE_URL;
const anonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.warn('Faltan PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY en apps/web/.env');
}

// Cliente de Supabase Auth para el navegador.
// persistSession guarda la sesión en localStorage; detectSessionInUrl
// procesa automáticamente el redirect de OAuth (?code=...).
export const supabase = createClient(url || 'http://localhost', anonKey || 'anon', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});
