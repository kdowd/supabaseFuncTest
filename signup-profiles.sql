-- ============================================================================
--  countries + profiles
--
--  Run this once in the Supabase SQL editor (project: pkpbzthkwskkudqogyrl).
--
--  Two tables:
--    countries  — the list in the dropdown. A real table, so the page loads it
--                 instead of having the list hardcoded in the HTML.
--    profiles   — one row per person, holding the country they live in.
--
--  Plus a trigger that creates the profile row automatically the moment an
--  account is made, so the page never has to remember to do it.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  1. COUNTRIES — the dropdown list
-- ---------------------------------------------------------------------------
create table if not exists public.countries (
  code text primary key check (length(code) = 2),   -- ISO code: NZ, AU, US...
  name text not null unique
);

insert into public.countries (code, name) values
  ('NZ', 'New Zealand'),
  ('AU', 'Australia'),
  ('FJ', 'Fiji'),
  ('WS', 'Samoa'),
  ('TO', 'Tonga'),
  ('PG', 'Papua New Guinea'),
  ('CK', 'Cook Islands'),
  ('SG', 'Singapore'),
  ('JP', 'Japan'),
  ('CN', 'China'),
  ('IN', 'India'),
  ('PH', 'Philippines'),
  ('GB', 'United Kingdom'),
  ('IE', 'Ireland'),
  ('DE', 'Germany'),
  ('FR', 'France'),
  ('US', 'United States'),
  ('CA', 'Canada'),
  ('BR', 'Brazil'),
  ('ZA', 'South Africa')
on conflict (code) do nothing;

alter table public.countries enable row level security;

-- The signup form needs this list BEFORE anybody has logged in, so strangers
-- ("anon") have to be able to read it. This is the one policy here that is
-- open on purpose.
create policy "countries are public to read"
on public.countries
for select
to anon, authenticated
using ( true );


-- ---------------------------------------------------------------------------
--  2. PROFILES — one row per person
--
--  country_code is deliberately allowed to be empty. If it were "not null",
--  a signup that arrived without a country would blow up and the account
--  would never be created. Better to have a profile with no country than no
--  account at all.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid        primary key references auth.users (id) on delete cascade,
  country_code text        references public.countries (code),
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- You may read your own profile...
create policy "read your own profile"
on public.profiles
for select
to authenticated
using ( auth.uid() = id );

-- ...and change your own country later. Nobody can touch anyone else's row.
create policy "update your own profile"
on public.profiles
for update
to authenticated
using ( auth.uid() = id )
with check ( auth.uid() = id );

-- NOTE: there is no INSERT policy on purpose. The trigger below creates the
-- row, and a trigger runs with enough permission to bypass these policies.
-- So profiles can only ever be born through a real signup.


-- ---------------------------------------------------------------------------
--  3. THE TRIGGER — makes the profile row automatically
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer                      -- runs as the owner, so RLS can't block it
set search_path = public
as $$
begin
  insert into public.profiles (id, country_code)
  values (
    new.id,

    -- The country arrives as signup "metadata" from the form. This subquery
    -- looks the code up in countries: anything unrecognised quietly becomes
    -- NULL, so a bad value can never stop an account being created.
    (select code
       from public.countries
      where code = nullif(new.raw_user_meta_data ->> 'country_code', ''))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
--  4. Check it worked
-- ---------------------------------------------------------------------------
select code, name from public.countries order by name;

select id, country_code, created_at from public.profiles;
