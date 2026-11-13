<script>
  import { api, setSession } from '$lib/api.js';
  import { supabase } from '$lib/supabase.js';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';

  let mode = $state('login'); // login | register
  let email = $state('');
  let password = $state('');
  let full_name = $state('');
  let error = $state('');
  let loading = $state(false);
  let googleLoading = $state(false);
  const OAUTH_FLOW_KEY = 'supabase_oauth_flow_id';

  function saveGoogleSession(session) {
    const u = session.user;
    const name =
      u.user_metadata?.full_name ||
      u.user_metadata?.name ||
      u.email?.split('@')[0] ||
      'Usuario';
    // Reutiliza las claves que espera el layout ('token'/'user').
    // Nota: el access_token de Supabase no es válido para la API propia;
    // sirve para probar el alta de usuarios en auth.users de Supabase.
    setSession(session.access_token, { id: u.id, email: u.email, full_name: name });
    goto('/cursos');
  }

  async function loginWithGoogle() {
    error = '';
    googleLoading = true;
    try {
      const { data, error: oauthError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/login`,
          queryParams: { access_type: 'offline', prompt: 'consent' },
          skipBrowserRedirect: true
        }
      });
      if (oauthError) throw oauthError;
      if (!data?.url) throw new Error('No se pudo obtener la URL de Google');
      sessionStorage.removeItem(OAUTH_FLOW_KEY);
      if (data.flowId) sessionStorage.setItem(OAUTH_FLOW_KEY, data.flowId);
      window.location.assign(data.url);
    } catch (err) {
      error = err.message;
      googleLoading = false;
    }
  }

  async function submit(e) {
    e.preventDefault();
    error = '';
    loading = true;
    try {
      const path = mode === 'login' ? '/auth/login' : '/auth/register';
      const body = mode === 'login' ? { email, password } : { email, password, full_name };
      const { user, token } = await api(path, { method: 'POST', body, auth: false });
      setSession(token, user);
      goto('/cursos');
    } catch (err) {
      error = err.message;
    } finally {
      loading = false;
    }
  }

  onMount(async () => {
    const code = new URLSearchParams(window.location.search).get('code');
    if (code) {
      googleLoading = true;
      const flowId = sessionStorage.getItem(OAUTH_FLOW_KEY);
      sessionStorage.removeItem(OAUTH_FLOW_KEY);
      const { data, error: exchangeError } = await supabase.auth.exchangeCodeForSession(
        code,
        flowId ? { flowId } : undefined
      );
      googleLoading = false;
      if (!exchangeError && data?.session) {
        saveGoogleSession(data.session);
        return;
      }
      error = exchangeError?.message || 'No se pudo completar el inicio con Google';
      return;
    }

    const { data } = await supabase.auth.getSession();
    if (data.session) {
      saveGoogleSession(data.session);
      return;
    }
    const { data: sub } = supabase.auth.onAuthStateChange((_, session) => {
      if (session) saveGoogleSession(session);
    });
    return () => sub.subscription.unsubscribe();
  });
</script>

<div class="login-wrap">
  <div class="brand-block">
    <span class="brand-mark">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="26" height="26"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20M4 19.5A2.5 2.5 0 0 0 6.5 22H20V2H6.5A2.5 2.5 0 0 0 4 4.5v15Z"/></svg>
    </span>
    <h1>Planeación Académica</h1>
  </div>

  <div class="card">
    <p class="subtitle">{mode === 'login' ? 'Inicia sesión para continuar' : 'Crea tu cuenta para continuar'}</p>

    <button class="google" type="button" onclick={loginWithGoogle} disabled={googleLoading}>
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
        <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"/>
        <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z"/>
        <path fill="#FBBC05" d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33z"/>
        <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z"/>
      </svg>
      {googleLoading ? 'Redirigiendo…' : 'Continuar con Google'}
    </button>
    <p class="hint">El mismo botón sirve para iniciar sesión y registrarse: Supabase crea el usuario automáticamente en <code>auth.users</code>.</p>

    <div class="divider"><span>o con correo</span></div>

    <form onsubmit={submit}>
      {#if mode === 'register'}
        <label class="field">Nombre completo
          <input bind:value={full_name} required minlength="3" placeholder="Tu nombre completo" />
        </label>
      {/if}
      <label class="field">Correo
        <input type="email" bind:value={email} required placeholder="tu@correo.com" />
      </label>
      <label class="field">Contraseña
        <input type="password" bind:value={password} required minlength="8" placeholder="Mínimo 8 caracteres" />
      </label>
      {#if error}<p class="err">{error}</p>{/if}
      <button class="primary" type="submit" disabled={loading}>{loading ? '…' : mode === 'login' ? 'Entrar' : 'Registrarse'}</button>
    </form>
    <p class="switch">
      {mode === 'login' ? '¿Sin cuenta?' : '¿Ya tienes cuenta?'}
      <button type="button" class="link switch-link" onclick={() => { mode = mode === 'login' ? 'register' : 'login'; }}>
        {mode === 'login' ? 'Regístrate' : 'Inicia sesión'}
      </button>
    </p>
  </div>
</div>

<style>
  .login-wrap {
    min-height: 100vh; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    padding: 2rem 1rem;
    background:
      radial-gradient(600px 300px at 15% 0%, rgba(20,184,166,.12), transparent 60%),
      radial-gradient(700px 350px at 85% 100%, rgba(29,78,137,.12), transparent 60%),
      var(--bg);
  }
  .brand-block { text-align: center; margin-bottom: 1.5rem; }
  .brand-mark {
    width: 56px; height: 56px; border-radius: 16px; margin: 0 auto 0.75rem;
    background: linear-gradient(135deg, var(--turquoise), var(--turquoise-light));
    color: #fff; display: flex; align-items: center; justify-content: center;
    box-shadow: 0 8px 20px rgba(13,148,136,.35);
  }
  .brand-block h1 { margin: 0; font-size: 1.5rem; color: var(--navy-900); }

  .card {
    width: 100%; max-width: 420px;
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 16px; padding: 1.75rem;
    box-shadow: 0 10px 40px rgba(15,23,42,.08);
  }
  .subtitle { color: var(--muted); font-size: 0.88rem; text-align: center; margin: 0 0 1rem; }
  .hint { color: var(--muted); font-size: 0.75rem; text-align: center; margin: 0.6rem 0 0; }
  .hint code { background: var(--panel-2); border: 1px solid var(--border); padding: 0 0.3rem; border-radius: 5px; }

  .google {
    width: 100%; display: flex; align-items: center; justify-content: center; gap: 0.6rem;
    padding: 0.65rem; margin-top: 0.25rem;
    background: #fff; color: #1f2937; border: 1px solid var(--border);
    border-radius: 10px; font-weight: 600; cursor: pointer; font-size: 0.9rem;
    transition: border-color .15s ease, box-shadow .15s ease;
  }
  .google:hover { border-color: #cbd5e1; box-shadow: 0 2px 8px rgba(15,23,42,.08); }
  .google:disabled { opacity: 0.6; cursor: default; }

  .divider {
    display: flex; align-items: center; gap: 0.75rem;
    color: var(--muted); font-size: 0.78rem; margin: 1.25rem 0;
  }
  .divider::before, .divider::after { content: ''; flex: 1; border-top: 1px solid var(--border); }

  .field { display: block; margin: 0.85rem 0 0.15rem; }

  .primary {
    width: 100%; margin-top: 1.1rem; padding: 0.7rem;
    background: linear-gradient(135deg, var(--navy-800), var(--navy-700));
    border: 0; border-radius: 10px; color: #fff;
    font-weight: 700; font-size: 0.9rem; cursor: pointer;
    transition: filter .15s ease;
  }
  .primary:hover { filter: brightness(1.15); }
  .primary[disabled] { opacity: 0.55; cursor: not-allowed; }

  .err {
    color: var(--danger); background: var(--danger-soft);
    border: 1px solid #fecaca; border-radius: 10px;
    padding: 0.6rem 0.85rem; font-size: 0.85rem; margin: 0.9rem 0 0;
  }
  .switch { color: var(--muted); font-size: 0.85rem; text-align: center; margin: 1.1rem 0 0; }
  .switch-link {
    background: none; border: 0; padding: 0; cursor: pointer;
    color: var(--turquoise); font-weight: 700; font-size: inherit;
  }
  .switch-link:hover { text-decoration: underline; filter: none; }
</style>
