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


-- Krillion: lock scores. Run once in Supabase → SQL Editor → New query (safe to run again).
-- Enforced by the database, so it holds even if someone bypasses the website:
--   • a logged score (and its emoji row) can never be changed or removed
--   • a new score can only be for the current day (with a few hours' slack for other time zones)
--   • players can't delete their own profile (which would wipe their scores)
-- The site admin (public.admins) and the SQL Editor itself are exempt, so you can still fix mistakes.
create or replace function public.lock_scores() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k text; old_s jsonb := '{}'; old_g jsonb := '{}'; new_s jsonb; new_g jsonb;
  lo date := ((now() at time zone 'utc') - interval '12 hours')::date;
  hi date := ((now() at time zone 'utc') + interval '14 hours')::date;
begin
  if coalesce(new.coll, old.coll) <> 'players' then return coalesce(new, old); end if;
  if auth.uid() is null or public.is_admin() then return coalesce(new, old); end if;

  if tg_op = 'DELETE' then
    raise exception 'Profiles can''t be deleted. Ask the admin.';
  end if;

  if tg_op = 'INSERT' then
    -- an upsert onto an existing row is checked by the UPDATE trigger
    if exists (select 1 from public.docs where coll = new.coll and id = new.id) then return new; end if;
  else
    old_s := coalesce(old.data -> 'scores', '{}'); old_g := coalesce(old.data -> 'games', '{}');
  end if;
  new_s := coalesce(new.data -> 'scores', '{}'); new_g := coalesce(new.data -> 'games', '{}');
  if jsonb_typeof(new_s) <> 'object' or jsonb_typeof(new_g) <> 'object' then
    raise exception 'Invalid score data.';
  end if;

  for k in select jsonb_object_keys(old_s) loop
    if (new_s -> k) is distinct from (old_s -> k) then
      raise exception 'Scores can''t be changed or removed once they''re logged.';
    end if;
  end loop;
  for k in select jsonb_object_keys(old_g) loop
    if (new_g -> k) is distinct from (old_g -> k) then
      raise exception 'Scores can''t be changed or removed once they''re logged.';
    end if;
  end loop;

  for k in select jsonb_object_keys(new_s) loop
    if not (old_s ? k) then
      if k !~ '^\d{4}-\d{2}-\d{2}$' or k::date < lo or k::date > hi then
        raise exception 'You can only log today''s result, on the day.';
      end if;
      if jsonb_typeof(new_s -> k) <> 'number' or (new_s ->> k)::numeric < 0 or (new_s ->> k)::numeric > 1000000
         or (new_s ->> k)::numeric <> trunc((new_s ->> k)::numeric) then
        raise exception 'That score isn''t valid.';
      end if;
    end if;
  end loop;
  for k in select jsonb_object_keys(new_g) loop
    if not (old_g ? k) and not (new_s ? k and not (old_s ? k)) then
      raise exception 'You can only log today''s result, on the day.';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists lock_scores on public.docs;
create trigger lock_scores before insert or update or delete on public.docs
  for each row execute function public.lock_scores();
