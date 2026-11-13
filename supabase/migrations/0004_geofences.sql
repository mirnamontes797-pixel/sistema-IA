-- ============================================================
-- Migración: Geocercas (dibujo de polígonos y registro de
-- entradas/salidas de personas)
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

-- ---------- Geocercas ----------
create table if not exists public.geofences (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  -- polygon: array de vértices [[lat, lng], ...] en orden
  polygon jsonb not null,
  color text not null default '#0d9488',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Estado actual por sujeto (para detectar transiciones) ----------
create table if not exists public.geofence_states (
  geofence_id uuid not null references public.geofences(id) on delete cascade,
  subject text not null,
  inside boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (geofence_id, subject)
);

-- ---------- Eventos de entrada/salida ----------
create table if not exists public.geofence_events (
  id uuid primary key default gen_random_uuid(),
  geofence_id uuid not null references public.geofences(id) on delete cascade,
  subject text not null,
  event_type text not null check (event_type in ('enter', 'exit')),
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_geofences_active on public.geofences(active);
create index if not exists idx_geofence_states_subject on public.geofence_states(subject);
create index if not exists idx_geofence_events_fence on public.geofence_events(geofence_id, occurred_at desc);
create index if not exists idx_geofence_events_subject on public.geofence_events(subject, occurred_at desc);

-- ---------- RLS ----------
alter table public.geofences enable row level security;
alter table public.geofence_states enable row level security;
alter table public.geofence_events enable row level security;

create policy "service role full access" on public.geofences
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.geofence_states
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.geofence_events
  for all using (auth.role() = 'service_role');
