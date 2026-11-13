-- ============================================================
-- Migración: Configuración académica del cuatrimestre (Etapa 3)
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

-- ---------- Configuraciones predeterminadas de periodo ----------
create table if not exists public.period_presets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  modality text check (modality in ('presencial', 'virtual', 'mixta')),
  institution text,
  weeks int check (weeks between 1 and 30),
  academic_hour_minutes numeric(5,1) not null default 50,
  autonomous_hours_per_week numeric(4,1) not null default 0,
  created_at timestamptz not null default now()
);

-- ---------- Configuración del periodo por curso (una fila por curso) ----------
create table if not exists public.course_academic_configs (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null unique references public.courses(id) on delete cascade,
  period_name text,
  start_date date,
  end_date date,
  weeks int check (weeks between 1 and 30), -- editable; si es null se deriva de las fechas
  modality text check (modality in ('presencial', 'virtual', 'mixta')),
  institution text,
  academic_hour_minutes numeric(5,1) not null default 50, -- minutos de reloj por hora académica
  autonomous_hours_per_week numeric(4,1) not null default 0,
  required_theory_hours numeric(6,1),   -- opcional; si es null se usa lo de la carta descriptiva
  required_practice_hours numeric(6,1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Sesiones de horario (varias por día de la semana) ----------
create table if not exists public.schedule_sessions (
  id uuid primary key default gen_random_uuid(),
  config_id uuid not null references public.course_academic_configs(id) on delete cascade,
  weekday int not null check (weekday between 0 and 6), -- 0 = lunes ... 6 = domingo
  start_time text not null,   -- 'HH:MM' hora de reloj
  end_time text not null,
  session_type text not null default 'presencial'
    check (session_type in ('presencial', 'virtual_sincrona', 'autonomo')),
  academic_hours numeric(4,1), -- null = derivar de la duración y academic_hour_minutes
  active boolean not null default true,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_schedule_sessions_config on public.schedule_sessions(config_id);

-- ---------- Eventos del calendario académico ----------
create table if not exists public.academic_events (
  id uuid primary key default gen_random_uuid(),
  config_id uuid not null references public.course_academic_configs(id) on delete cascade,
  type text not null default 'evento'
    check (type in ('inhabil', 'suspension', 'eval_ordinaria', 'eval_extraordinaria', 'evento')),
  title text,
  start_date date not null,
  end_date date,             -- null = un solo día
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_academic_events_config on public.academic_events(config_id);

-- ---------- RLS ----------
alter table public.period_presets enable row level security;
alter table public.course_academic_configs enable row level security;
alter table public.schedule_sessions enable row level security;
alter table public.academic_events enable row level security;

create policy "service role full access" on public.period_presets
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.course_academic_configs
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.schedule_sessions
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.academic_events
  for all using (auth.role() = 'service_role');
