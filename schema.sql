-- Krillion League & Cup: run this once in Supabase → SQL Editor → New query.

-- Every piece of data is one JSON document, addressed by collection + id.
--   players/<user id>      your profile and scores (only you can change it)
--   leaguedefs/<user id>   the leagues you created (only you can change them)
--   cupdefs/<user id>      the tournaments you created (only you can change them)
--   memberships/<user id>  which leagues/tournaments you joined (only you)
--   meta/calendar          puzzle number ↔ date anchor (anyone signed in)
create table if not exists public.docs (
  coll text not null check (coll in ('players', 'leaguedefs', 'cupdefs', 'memberships', 'meta')),
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (coll, id)
);

-- Deletes must carry the whole row so live updates know what was removed.
alter table public.docs replica identity full;

-- Unique display names, enforced by the database itself.
create unique index if not exists players_unique_name
  on public.docs ((data ->> 'nameKey'))
  where coll = 'players' and data ? 'nameKey';

-- Site admins can fix or delete anyone's data.
create table if not exists public.admins (email text primary key);
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where lower(email) = lower(auth.jwt() ->> 'email'));
$$;
grant execute on function public.is_admin() to authenticated;

alter table public.docs enable row level security;

drop policy if exists "signed-in users read everything" on public.docs;
create policy "signed-in users read everything" on public.docs
  for select to authenticated using (true);

drop policy if exists "write your own documents" on public.docs;
create policy "write your own documents" on public.docs
  for insert to authenticated
  with check (public.is_admin() or coll = 'meta' or id = auth.uid()::text);

drop policy if exists "update your own documents" on public.docs;
create policy "update your own documents" on public.docs
  for update to authenticated
  using (public.is_admin() or coll = 'meta' or id = auth.uid()::text)
  with check (public.is_admin() or coll = 'meta' or id = auth.uid()::text);

drop policy if exists "delete your own documents" on public.docs;
create policy "delete your own documents" on public.docs
  for delete to authenticated
  using (public.is_admin() or id = auth.uid()::text);

-- Live updates (tables refresh for everyone the moment someone logs a score).
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- Puzzle #122 was the puzzle on 14 Nov 2026; later numbers count forward a day each.
insert into public.docs (coll, id, data) values ('meta', 'calendar', '{"n":122,"date":"2026-11-14"}')
on conflict do nothing;

-- Make yourself admin: replace the address with the one you'll sign up with, then run this line.
-- insert into public.admins (email) values ('you@example.com');
