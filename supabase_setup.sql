-- Kieltec shared database setup. Paste all of this into Supabase > SQL Editor > Run.

create table if not exists public.records (
  id text primary key,
  kind text not null,
  data jsonb not null,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);
create index if not exists records_updated_idx on public.records (updated_at);

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := clock_timestamp(); return new; end $$;
drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
  for each row execute function public.touch_updated_at();

alter table public.records enable row level security;
drop policy if exists "team access" on public.records;
create policy "team access" on public.records for all to authenticated
  using (true) with check (true);

-- shared invoice / quote / booking numbers (no clashes between phones)
create table if not exists public.counters (kind text primary key, last integer not null default 0);
alter table public.counters enable row level security;
insert into public.counters (kind,last) values ('bookings',0),('quotes',0),('invoices',0)
  on conflict do nothing;

create or replace function public.next_number(k text) returns integer
language plpgsql security definer set search_path = public as $$
declare v integer;
begin update counters set last = last + 1 where kind = k returning last into v; return v; end $$;

create or replace function public.bump_counter(k text, n integer) returns void
language plpgsql security definer set search_path = public as $$
begin update counters set last = greatest(last, n) where kind = k; end $$;

revoke all on function public.next_number(text) from public, anon;
revoke all on function public.bump_counter(text, integer) from public, anon;
grant execute on function public.next_number(text) to authenticated;
grant execute on function public.bump_counter(text, integer) to authenticated;

-- photo storage
insert into storage.buckets (id, name, public) values ('photos','photos',true)
  on conflict (id) do nothing;
drop policy if exists "team uploads" on storage.objects;
create policy "team uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos');
