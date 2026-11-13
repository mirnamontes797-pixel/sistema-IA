import { createClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/public';

const url = env.PUBLIC_SUPABASE_URL;
const anonKey = env.PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.warn('Faltan PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY en apps/web/.env');
}

// Cliente de Supabase Auth para el navegador.
// persistSession guarda la sesión en localStorage. La detección automática de
// URL está desactivada: el code PKCE se canjea manualmente en /login para no
// usar history.replaceState (SvelteKit ya lo gestiona).
export const supabase = createClient(url || 'http://localhost', anonKey || 'anon', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    flowType: 'pkce'
  }
});
