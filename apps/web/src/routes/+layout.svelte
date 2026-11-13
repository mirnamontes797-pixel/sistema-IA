<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { clearSession } from '$lib/api.js';

  let { children } = $props();
  let user = $state(null);
  let sidebarOpen = $state(false);

  onMount(() => {
    const raw = localStorage.getItem('user');
    if (raw) user = JSON.parse(raw);
    if (!localStorage.getItem('token') && page.url.pathname !== '/login') {
      goto('/login');
    }
  });

  const links = [
    { href: '/', label: 'Inicio', icon: 'home' },
    { href: '/cursos', label: 'Cursos', icon: 'book' },
    { href: '/balance', label: 'Balance de cargas', icon: 'chart' },
    { href: '/mapa', label: 'Mapa de Instituciones', icon: 'map' },
    { href: '/geocercas', label: 'Geocercas', icon: 'pin' },
    { href: '/equipos', label: 'Teams', icon: 'users' }
  ];

  const icons = {
    home: 'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1v-9.5Z',
    book: 'M4 19.5A2.5 2.5 0 0 1 6.5 17H20M4 19.5A2.5 2.5 0 0 0 6.5 22H20V2H6.5A2.5 2.5 0 0 0 4 4.5v15Z',
    chart: 'M4 20V10m6 10V4m6 16v-7m4 7H2',
    map: 'M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Zm0 0v14m6-12v14',
    pin: 'M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m16-10a4 4 0 1 0-8 0m-4 0a4 4 0 1 0-8 0M16 3.13a4 4 0 0 1 0 7.75M12 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z'
  };

  const isLogin = $derived(page.url.pathname === '/login');
  const currentLabel = $derived(
    links.find((l) => (l.href === '/' ? page.url.pathname === '/' : page.url.pathname.startsWith(l.href)))?.label || ''
  );

  function logout() {
    clearSession();
    goto('/login');
  }

  function closeSidebar() { sidebarOpen = false; }
</script>

{#if isLogin}
  <main class="login-main">{@render children?.()}</main>
{:else}
  <div class="shell">
    <aside class="sidebar" class:open={sidebarOpen}>
      <a href="/" class="brand" onclick={closeSidebar}>
        <span class="brand-mark">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d={icons.book}/></svg>
        </span>
        <span class="brand-text">
          <strong>Planeación Académica</strong>
        </span>
      </a>
      <nav>
        {#each links as l (l.href)}
          <a
            href={l.href}
            class="nav-item"
            class:active={l.href === '/' ? page.url.pathname === '/' : page.url.pathname.startsWith(l.href)}
            onclick={closeSidebar}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={icons[l.icon]}/></svg>
            <span>{l.label}</span>
          </a>
        {/each}
      </nav>
      <div class="sidebar-foot">Sistema de gestión académica</div>
    </aside>
    {#if sidebarOpen}
      <button class="backdrop" aria-label="Cerrar menú" onclick={closeSidebar}></button>
    {/if}

    <div class="main-col">
      <header class="topbar">
        <button class="hamburger icon-btn" aria-label="Abrir menú" onclick={() => (sidebarOpen = true)}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
        </button>
        <div class="crumbs">
          <span class="crumb-root">Plataforma</span>
          {#if currentLabel}<span class="crumb-sep">/</span><strong>{currentLabel}</strong>{/if}
        </div>
        <div class="topbar-right">
          {#if user}
            <div class="user-chip">
              <span class="avatar">{(user.full_name || user.email || 'U').trim().charAt(0).toUpperCase()}</span>
              <span class="user-name">{user.full_name || user.email}</span>
            </div>
          {/if}
          <button class="btn-ghost btn btn-sm" onclick={logout}>Salir</button>
        </div>
      </header>
      <main class="content">
        {@render children?.()}
      </main>
    </div>
  </div>
{/if}

<style>
  .login-main { min-height: 100vh; }

  .shell { display: flex; min-height: 100vh; }

  /* ---------- Sidebar ---------- */
  .sidebar {
    width: 264px; flex-shrink: 0;
    background: linear-gradient(180deg, var(--navy-900) 0%, var(--navy-800) 60%, var(--navy-700) 100%);
    color: #cbd5e1; display: flex; flex-direction: column;
    position: fixed; inset: 0 auto 0 0; z-index: 40;
    transition: transform .25s ease;
  }
  .brand {
    display: flex; align-items: center; gap: 0.8rem;
    padding: 1.3rem 1.25rem; color: #fff; text-decoration: none;
    border-bottom: 1px solid rgba(255,255,255,.08);
  }
  .brand:hover { text-decoration: none; }
  .brand-mark {
    width: 40px; height: 40px; border-radius: 11px; flex-shrink: 0;
    background: linear-gradient(135deg, var(--turquoise), var(--turquoise-light));
    display: flex; align-items: center; justify-content: center; color: #fff;
    box-shadow: 0 4px 12px rgba(13,148,136,.4);
  }
  .brand-mark svg { width: 22px; height: 22px; }
  .brand-text { display: flex; flex-direction: column; line-height: 1.25; }
  .brand-text strong { font-size: 0.98rem; letter-spacing: .01em; }
  nav { display: flex; flex-direction: column; gap: 0.25rem; padding: 1rem 0.85rem; flex: 1; }
  .nav-item {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.7rem 0.85rem; border-radius: 10px;
    color: #cbd5e1; font-size: 0.9rem; font-weight: 500;
    transition: background .15s ease, color .15s ease;
  }
  .nav-item:hover { background: rgba(255,255,255,.08); color: #fff; text-decoration: none; }
  .nav-item.active {
    background: linear-gradient(135deg, rgba(20,184,166,.25), rgba(20,184,166,.12));
    color: #fff; box-shadow: inset 3px 0 0 var(--turquoise-light);
  }
  .nav-item svg { width: 20px; height: 20px; flex-shrink: 0; }
  .sidebar-foot {
    padding: 1rem 1.25rem; font-size: 0.72rem; color: #64748b;
    border-top: 1px solid rgba(255,255,255,.08);
  }

  /* ---------- Topbar ---------- */
  .main-col { flex: 1; margin-left: 264px; display: flex; flex-direction: column; min-width: 0; }
  .topbar {
    display: flex; align-items: center; gap: 1rem;
    padding: 0 1.5rem; height: 64px;
    background: rgba(255,255,255,.9); backdrop-filter: blur(8px);
    border-bottom: 1px solid var(--border);
    position: sticky; top: 0; z-index: 30;
  }
  .icon-btn {
    display: none; width: 38px; height: 38px; border-radius: 10px;
    align-items: center; justify-content: center; border: 1px solid var(--border);
    background: var(--panel); color: var(--navy-800); cursor: pointer;
  }
  .icon-btn svg { width: 20px; height: 20px; }
  .crumbs { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; color: var(--muted); }
  .crumbs strong { color: var(--navy-900); font-weight: 700; }
  .crumb-sep { color: #cbd5e1; }
  .topbar-right { margin-left: auto; display: flex; align-items: center; gap: 0.9rem; }
  .user-chip { display: flex; align-items: center; gap: 0.6rem; }
  .avatar {
    width: 34px; height: 34px; border-radius: 50%;
    background: linear-gradient(135deg, var(--turquoise), var(--turquoise-light));
    color: #fff; font-weight: 700; font-size: 0.85rem;
    display: flex; align-items: center; justify-content: center;
  }
  .user-name { font-size: 0.85rem; font-weight: 600; color: var(--navy-900); }
  .btn-sm { padding: 0.4rem 0.85rem; font-size: 0.82rem; }

  .content { padding: 1.75rem 1.5rem 3rem; max-width: 1280px; width: 100%; margin: 0 auto; }

  .backdrop {
    display: none; position: fixed; inset: 0; z-index: 35;
    background: rgba(11,37,69,.45); border: 0; cursor: pointer;
  }

  /* ---------- Responsive ---------- */
  @media (max-width: 900px) {
    .sidebar { transform: translateX(-100%); }
    .sidebar.open { transform: translateX(0); box-shadow: 0 0 40px rgba(0,0,0,.3); }
    .main-col { margin-left: 0; }
    .icon-btn { display: inline-flex; }
    .backdrop { display: block; }
    .user-name { display: none; }
    .content { padding: 1.25rem 1rem 2.5rem; }
  }
</style>
