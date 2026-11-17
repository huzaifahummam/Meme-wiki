-- Meme Wiki: accounts. Paste this whole file into Supabase > SQL Editor > Run.
-- Passwords are NOT stored here. Supabase Auth hashes and stores them for you.

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nickname   text not null check (char_length(nickname) between 1 and 20),
  created_at timestamptz not null default now()
);

-- Row Level Security: nobody can touch rows unless a rule below allows it.
alter table public.profiles enable row level security;

drop policy if exists "signed-in users can read profiles" on public.profiles;
create policy "signed-in users can read profiles"
  on public.profiles for select to authenticated using (true);

drop policy if exists "users can edit only their own profile" on public.profiles;
create policy "users can edit only their own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- No insert or delete policy on purpose: profiles are created by the trigger
-- below and removed automatically when the account is deleted.

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    coalesce(nullif(left(new.raw_user_meta_data->>'nickname', 20), ''),
             left(split_part(new.email, '@', 1), 20))
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- PART 2: shared memes, pictures and reactions (safe to re-run)
-- ============================================================

create table if not exists public.memes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nickname    text not null default '',
  title       text not null check (char_length(title) between 1 and 40),
  caption     text not null default '' check (char_length(caption) <= 120),
  color       text not null default 'y' check (color in ('y','b','p')),
  emoji       text not null default '😂' check (char_length(emoji) <= 16),
  image_path  text check (image_path is null or char_length(image_path) <= 200),
  created_at  timestamptz not null default now()
);
create index if not exists memes_created_idx on public.memes (created_at desc);

create table if not exists public.reactions (
  meme_id    uuid not null references public.memes(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (meme_id, user_id, emoji)
);

alter table public.memes     enable row level security;
alter table public.reactions enable row level security;

drop policy if exists "anyone can read memes" on public.memes;
create policy "anyone can read memes" on public.memes
  for select to anon, authenticated using (true);
drop policy if exists "users post as themselves" on public.memes;
create policy "users post as themselves" on public.memes
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "users delete their own memes" on public.memes;
create policy "users delete their own memes" on public.memes
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "anyone can read reactions" on public.reactions;
create policy "anyone can read reactions" on public.reactions
  for select to anon, authenticated using (true);
drop policy if exists "users react as themselves" on public.reactions;
create policy "users react as themselves" on public.reactions
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "users remove their own reactions" on public.reactions;
create policy "users remove their own reactions" on public.reactions
  for delete to authenticated using (user_id = auth.uid());

-- The server (not the browser) decides the nickname and limits posting speed,
-- so nobody can post as someone else or flood the site.
create or replace function public.before_meme_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select p.nickname into new.nickname from public.profiles p where p.id = auth.uid();
  if new.nickname is null or new.nickname = '' then new.nickname := 'Member'; end if;
  if (select count(*) from public.memes m
       where m.user_id = auth.uid() and m.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Posting limit reached. Try again later.';
  end if;
  return new;
end $$;
drop trigger if exists memes_before_insert on public.memes;
create trigger memes_before_insert before insert on public.memes
  for each row execute function public.before_meme_insert();

-- Picture storage: public to view, but people can only add or delete inside their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('meme-images', 'meme-images', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "users upload to their own folder" on storage.objects;
create policy "users upload to their own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'meme-images' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "users delete their own pictures" on storage.objects;
create policy "users delete their own pictures" on storage.objects
  for delete to authenticated
  using (bucket_id = 'meme-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- Live updates: new memes and reactions appear for everyone without refreshing.
do $$ begin alter publication supabase_realtime add table public.memes;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.reactions;
exception when duplicate_object then null; end $$;


-- ============================================================
-- PART 3: admin role (only people listed in public.admins)
-- ============================================================
-- Nobody can add themselves from the website. The list can only be edited here
-- in the SQL Editor by the project owner. See SETUP.md, "Make yourself the admin".

create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;   -- the website can never read or edit this list

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Admins may delete any meme, reaction and picture. Everyone else: only their own.
drop policy if exists "users delete their own memes" on public.memes;
drop policy if exists "owners or admin delete memes" on public.memes;
create policy "owners or admin delete memes" on public.memes
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "users remove their own reactions" on public.reactions;
drop policy if exists "owners or admin delete reactions" on public.reactions;
create policy "owners or admin delete reactions" on public.reactions
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "users delete their own pictures" on storage.objects;
drop policy if exists "owners or admin delete pictures" on storage.objects;
create policy "owners or admin delete pictures" on storage.objects
  for delete to authenticated
  using (bucket_id = 'meme-images'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));


-- ============================================================
-- PART 4: device recognition ("Trust this device")
-- ============================================================
create table if not exists public.user_devices (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  device_id  text not null check (char_length(device_id) between 8 and 64),
  label      text not null check (char_length(label) between 1 and 60),
  trusted    boolean not null default false,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.user_devices enable row level security;

drop policy if exists "see own devices" on public.user_devices;
create policy "see own devices" on public.user_devices
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "change trust on own devices" on public.user_devices;
create policy "change trust on own devices" on public.user_devices
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "remove own devices" on public.user_devices;
create policy "remove own devices" on public.user_devices
  for delete to authenticated using (user_id = auth.uid());

-- The website may only flip the "trusted" switch. Rows are created by register_device below.
revoke insert, update on public.user_devices from anon, authenticated;
grant update (trusted) on public.user_devices to authenticated;

create or replace function public.register_device(p_device text, p_label text, p_trust boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare existed boolean;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_device is null or char_length(p_device) not between 8 and 64 then raise exception 'bad device id'; end if;
  select exists (select 1 from public.user_devices d
                 where d.user_id = auth.uid() and d.device_id = p_device) into existed;
  insert into public.user_devices (user_id, device_id, label, trusted)
  values (auth.uid(), p_device, left(coalesce(nullif(trim(p_label), ''), 'Unknown device'), 60), coalesce(p_trust, false))
  on conflict (user_id, device_id)
  do update set last_seen = now(), label = excluded.label, trusted = excluded.trusted;
  -- keep only the 20 most recent devices per person
  delete from public.user_devices d
   where d.user_id = auth.uid()
     and d.device_id in (select x.device_id from public.user_devices x
                          where x.user_id = auth.uid() order by x.last_seen desc offset 20);
  return jsonb_build_object('known', existed, 'trusted', coalesce(p_trust, false));
end $$;
revoke all on function public.register_device(text, text, boolean) from public, anon;
grant execute on function public.register_device(text, text, boolean) to authenticated;


-- ============================================================
-- PART 5: make 2-step login real (enforced by the database, not only the page)
-- ============================================================
-- If an account has 2FA turned on, the database refuses writes unless the person
-- has completed the 2FA step (assurance level "aal2"). A stolen password alone is not enough.
create or replace function public.mfa_ok()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f
                      where f.user_id = auth.uid() and f.status = 'verified');
$$;
revoke all on function public.mfa_ok() from public, anon;
grant execute on function public.mfa_ok() to authenticated;

drop policy if exists "2fa required to post"        on public.memes;
create policy "2fa required to post"        on public.memes
  as restrictive for insert to authenticated with check (public.mfa_ok());
drop policy if exists "2fa required to delete memes" on public.memes;
create policy "2fa required to delete memes" on public.memes
  as restrictive for delete to authenticated using (public.mfa_ok());

drop policy if exists "2fa required to react"       on public.reactions;
create policy "2fa required to react"       on public.reactions
  as restrictive for insert to authenticated with check (public.mfa_ok());
drop policy if exists "2fa required to unreact"     on public.reactions;
create policy "2fa required to unreact"     on public.reactions
  as restrictive for delete to authenticated using (public.mfa_ok());

drop policy if exists "2fa required for devices"    on public.user_devices;
create policy "2fa required for devices"    on public.user_devices
  as restrictive for update to authenticated using (public.mfa_ok()) with check (public.mfa_ok());
drop policy if exists "2fa required to remove devices" on public.user_devices;
create policy "2fa required to remove devices" on public.user_devices
  as restrictive for delete to authenticated using (public.mfa_ok());

drop policy if exists "2fa required to upload pictures" on storage.objects;
create policy "2fa required to upload pictures" on storage.objects
  as restrictive for insert to authenticated
  with check (bucket_id <> 'meme-images' or public.mfa_ok());
drop policy if exists "2fa required to delete pictures" on storage.objects;
create policy "2fa required to delete pictures" on storage.objects
  as restrictive for delete to authenticated
  using (bucket_id <> 'meme-images' or public.mfa_ok());
