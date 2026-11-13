create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null unique references auth.users(id) on delete cascade,
	username text not null check (char_length(btrim(username)) between 1 and 30),
	role text not null default 'listener' check (role in ('listener', 'musician')),
	avatar_url text,
	created_at timestamptz not null default now()
);

create table if not exists public.tracks (
	id uuid primary key default gen_random_uuid(),
	artist_id uuid not null references public.profiles(id) on delete cascade,
	title text not null check (char_length(btrim(title)) between 1 and 100),
	genre text not null default '',
	description text not null default '',
	audio_url text not null,
	cover_url text not null default '',
	duration_seconds numeric check (duration_seconds is null or duration_seconds between 30 and 360),
	storage_path text,
	file_size bigint,
	mime_type text,
	views_count bigint not null default 0 check (views_count >= 0),
	likes_count bigint not null default 0 check (likes_count >= 0),
	created_at timestamptz not null default now()
);

create table if not exists public.clips (
	id uuid primary key default gen_random_uuid(),
	artist_id uuid not null references public.profiles(id) on delete cascade,
	title text not null check (char_length(btrim(title)) between 1 and 100),
	genre text not null default '',
	description text not null default '',
	video_url text not null,
	storage_path text,
	file_size bigint,
	mime_type text,
	likes_count bigint not null default 0 check (likes_count >= 0),
	created_at timestamptz not null default now()
);

create table if not exists public.music_videos (
	id uuid primary key default gen_random_uuid(),
	artist_id uuid not null references public.profiles(id) on delete cascade,
	title text not null check (char_length(btrim(title)) between 1 and 100),
	genre text not null default '',
	description text not null default '',
	video_url text not null,
	cover_url text not null default '',
	storage_path text,
	file_size bigint,
	mime_type text,
	views_count bigint not null default 0 check (views_count >= 0),
	likes_count bigint not null default 0 check (likes_count >= 0),
	created_at timestamptz not null default now()
);

create table if not exists public.artist_follows (
	id uuid primary key default gen_random_uuid(),
	artist_id uuid not null references public.profiles(id) on delete cascade,
	follower_id uuid not null references auth.users(id) on delete cascade,
	created_at timestamptz not null default now(),
	unique (artist_id, follower_id)
);

create table if not exists public.content_likes (
	id uuid primary key default gen_random_uuid(),
	content_type text not null check (content_type in ('track', 'clip', 'music_video')),
	content_id uuid not null,
	visitor_id uuid not null references auth.users(id) on delete cascade,
	created_at timestamptz not null default now(),
	unique (content_type, content_id, visitor_id)
);

create table if not exists public.comments (
	id uuid primary key default gen_random_uuid(),
	content_type text not null check (content_type in ('track', 'clip', 'music_video')),
	content_id uuid not null,
	visitor_id uuid not null references auth.users(id) on delete cascade,
	display_name text not null default 'Listener'
		check (char_length(btrim(display_name)) between 1 and 40),
	body text not null
		check (char_length(btrim(body)) between 1 and 500),
	created_at timestamptz not null default now()
);

create table if not exists public.track_streams (
	id uuid primary key default gen_random_uuid(),
	track_id uuid not null references public.tracks(id) on delete cascade,
	visitor_id uuid not null references auth.users(id) on delete cascade,
	played_on date not null default current_date,
	created_at timestamptz not null default now(),
	unique (track_id, visitor_id, played_on)
);

alter table public.tracks
	add column if not exists description text not null default '';
alter table public.tracks
	add column if not exists storage_path text,
	add column if not exists file_size bigint,
	add column if not exists mime_type text;
alter table public.music_videos
	add column if not exists storage_path text,
	add column if not exists file_size bigint,
	add column if not exists mime_type text;
alter table public.content_likes
	drop constraint if exists content_likes_content_type_check,
	add constraint content_likes_content_type_check check (content_type in ('track', 'clip', 'music_video'));
alter table public.comments
	drop constraint if exists comments_content_type_check,
	add constraint comments_content_type_check check (content_type in ('track', 'clip', 'music_video'));
alter table public.clips
	add column if not exists genre text not null default '',
	add column if not exists description text not null default '',
	add column if not exists storage_path text,
	add column if not exists file_size bigint,
	add column if not exists mime_type text;
alter table public.tracks
	drop constraint if exists tracks_title_length_check,
	drop constraint if exists tracks_genre_length_check,
	drop constraint if exists tracks_description_length_check,
	add constraint tracks_title_length_check check (char_length(btrim(title)) between 1 and 100),
	add constraint tracks_genre_length_check check (char_length(coalesce(genre, '')) <= 40),
	add constraint tracks_description_length_check check (char_length(coalesce(description, '')) <= 500);
alter table public.clips
	drop constraint if exists clips_title_length_check,
	drop constraint if exists clips_genre_length_check,
	drop constraint if exists clips_description_length_check,
	add constraint clips_title_length_check check (char_length(btrim(title)) between 1 and 100),
	add constraint clips_genre_length_check check (char_length(coalesce(genre, '')) <= 40),
	add constraint clips_description_length_check check (char_length(coalesce(description, '')) <= 500);
alter table public.music_videos
	drop constraint if exists music_videos_title_length_check,
	drop constraint if exists music_videos_genre_length_check,
	drop constraint if exists music_videos_description_length_check,
	add constraint music_videos_title_length_check check (char_length(btrim(title)) between 1 and 100),
	add constraint music_videos_genre_length_check check (char_length(coalesce(genre, '')) <= 40),
	add constraint music_videos_description_length_check check (char_length(coalesce(description, '')) <= 500);

create index if not exists tracks_created_at_idx on public.tracks (created_at desc);
create index if not exists clips_created_at_idx on public.clips (created_at desc);
create index if not exists music_videos_created_at_idx on public.music_videos (created_at desc);
create index if not exists tracks_artist_id_idx on public.tracks (artist_id);
create index if not exists clips_artist_id_idx on public.clips (artist_id);
create index if not exists music_videos_artist_id_idx on public.music_videos (artist_id);
create index if not exists artist_follows_artist_id_idx on public.artist_follows (artist_id);
create index if not exists comments_content_created_at_idx on public.comments (content_type, content_id, created_at desc);
create unique index if not exists profiles_user_id_unique_idx on public.profiles (user_id);

alter table public.profiles enable row level security;
alter table public.tracks enable row level security;
alter table public.clips enable row level security;
alter table public.music_videos enable row level security;
alter table public.artist_follows enable row level security;
alter table public.content_likes enable row level security;
alter table public.comments enable row level security;
alter table public.track_streams enable row level security;

revoke all on public.profiles, public.tracks, public.clips, public.music_videos from public, anon, authenticated;
grant select on public.profiles, public.tracks, public.clips, public.music_videos to anon, authenticated;
grant usage on schema public to service_role;
grant all on public.profiles, public.tracks, public.clips, public.music_videos to service_role;
grant update (username, avatar_url) on public.profiles to authenticated;
revoke insert, update, delete on public.tracks, public.clips, public.music_videos from authenticated;
grant update (title, genre, description, audio_url, cover_url) on public.tracks to authenticated;
grant delete on public.tracks to authenticated;
grant update (title, genre, description, video_url) on public.clips to authenticated;
grant delete on public.clips to authenticated;
grant update (title, genre, description, video_url, cover_url) on public.music_videos to authenticated;
grant delete on public.music_videos to authenticated;
revoke all on public.artist_follows, public.content_likes, public.track_streams from public, anon, authenticated;
revoke all on public.comments from public, anon, authenticated;
grant select (id, content_type, content_id, display_name, body, created_at) on public.comments to anon, authenticated;
grant insert (content_type, content_id, visitor_id, display_name, body) on public.comments to authenticated;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	chosen_role text := coalesce(new.raw_user_meta_data->>'role', 'listener');
	chosen_username text := nullif(btrim(new.raw_user_meta_data->>'username'), '');
begin
	if chosen_role not in ('listener', 'musician') then
		chosen_role := 'listener';
	end if;
	if chosen_username is null then
		chosen_username := split_part(coalesce(new.email, 'listener'), '@', 1);
	end if;
	insert into public.profiles (user_id, username, role)
	values (new.id, left(chosen_username, 30), chosen_role)
	on conflict (user_id) do nothing;
	return new;
end;
$$;

revoke all on function public.create_profile_for_new_user() from public, anon, authenticated;
drop trigger if exists create_profile_after_signup on auth.users;
create trigger create_profile_after_signup
	after insert on auth.users
	for each row execute function public.create_profile_for_new_user();

insert into public.profiles (user_id, username, role)
select u.id,
	left(coalesce(nullif(btrim(u.raw_user_meta_data->>'username'), ''), split_part(coalesce(u.email, 'listener'), '@', 1)), 30),
	case when u.raw_user_meta_data->>'role' = 'musician' then 'musician' else 'listener' end
from auth.users as u
on conflict (user_id) do nothing;

drop policy if exists "Profiles are publicly readable" on public.profiles;
create policy "Profiles are publicly readable" on public.profiles
	for select to anon, authenticated using (true);

drop policy if exists "Users can update their profile" on public.profiles;
create policy "Users can update their profile" on public.profiles
	for update to authenticated
	using (user_id = (select auth.uid()))
	with check (user_id = (select auth.uid()));

drop policy if exists "Tracks are publicly readable" on public.tracks;
create policy "Tracks are publicly readable" on public.tracks
	for select to anon, authenticated using (true);

drop policy if exists "Musicians can publish tracks" on public.tracks;

drop policy if exists "Musicians can edit tracks" on public.tracks;
create policy "Musicians can edit tracks" on public.tracks
	for update to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	))
	with check (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Musicians can delete tracks" on public.tracks;
create policy "Musicians can delete tracks" on public.tracks
	for delete to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Clips are publicly readable" on public.clips;
create policy "Clips are publicly readable" on public.clips
	for select to anon, authenticated using (true);

drop policy if exists "Musicians can publish clips" on public.clips;
drop policy if exists "Musicians can edit clips" on public.clips;
create policy "Musicians can edit clips" on public.clips
	for update to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	))
	with check (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Musicians can delete clips" on public.clips;
create policy "Musicians can delete clips" on public.clips
	for delete to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Music videos are publicly readable" on public.music_videos;
create policy "Music videos are publicly readable" on public.music_videos
	for select to anon, authenticated using (true);

drop policy if exists "Musicians can edit music videos" on public.music_videos;
create policy "Musicians can edit music videos" on public.music_videos
	for update to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	))
	with check (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Musicians can delete music videos" on public.music_videos;
create policy "Musicians can delete music videos" on public.music_videos
	for delete to authenticated
	using (exists (
		select 1 from public.profiles
		where id = artist_id and user_id = (select auth.uid()) and role = 'musician'
	));

drop policy if exists "Anyone can read follows" on public.artist_follows;
drop policy if exists "Signed-in listeners can follow artists" on public.artist_follows;
drop policy if exists "Listeners can unfollow artists" on public.artist_follows;
drop policy if exists "Anyone can read likes" on public.content_likes;
drop policy if exists "Anyone can read content likes" on public.content_likes;
drop policy if exists "Authenticated visitors can like as themselves" on public.content_likes;
drop policy if exists "Visitors can like existing content as themselves" on public.content_likes;
drop policy if exists "Visitors can remove their own likes" on public.content_likes;

create or replace function public.toggle_content_like(p_content_type text, p_content_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	visitor uuid := auth.uid();
	like_id uuid;
begin
	if visitor is null then
		raise exception 'An authenticated visitor is required';
	end if;
	if p_content_type not in ('track', 'clip', 'music_video') then
		raise exception 'Unsupported content type';
	end if;
	if (p_content_type = 'track' and not exists (select 1 from public.tracks where id = p_content_id))
		or (p_content_type = 'clip' and not exists (select 1 from public.clips where id = p_content_id))
		or (p_content_type = 'music_video' and not exists (select 1 from public.music_videos where id = p_content_id)) then
		raise exception 'Content was not found';
	end if;
	perform pg_advisory_xact_lock(hashtext(visitor::text || ':' || p_content_type || ':' || p_content_id::text));

	select id into like_id
	from public.content_likes
	where content_type = p_content_type
		and content_id = p_content_id
		and visitor_id = visitor;

	if like_id is not null then
		delete from public.content_likes where id = like_id;
		return false;
	end if;

	insert into public.content_likes (content_type, content_id, visitor_id)
	values (p_content_type, p_content_id, visitor)
	on conflict (content_type, content_id, visitor_id) do nothing;
	return exists (
		select 1 from public.content_likes
		where content_type = p_content_type
			and content_id = p_content_id
			and visitor_id = visitor
	);
end;
$$;

create or replace function public.get_content_reactions(p_content_ids uuid[])
returns table (content_type text, content_id uuid, likes_count bigint, liked_by_me boolean)
language sql
security definer
set search_path = public, pg_temp
as $$
	select l.content_type, l.content_id, count(*)::bigint,
		bool_or(l.visitor_id = auth.uid())
	from public.content_likes as l
	where l.content_id = any(coalesce(p_content_ids, array[]::uuid[]))
	group by l.content_type, l.content_id;
$$;

revoke all on function public.toggle_content_like(text, uuid) from public, anon, authenticated;
revoke all on function public.get_content_reactions(uuid[]) from public, anon, authenticated;
grant execute on function public.toggle_content_like(text, uuid) to authenticated;
grant execute on function public.get_content_reactions(uuid[]) to authenticated;

create or replace function public.get_artist_follow_state(p_artist_ids uuid[])
returns table (artist_id uuid, is_following boolean, follower_count bigint)
language sql
security definer
set search_path = public, pg_temp
as $$
	select artists.id,
		exists (
			select 1 from public.artist_follows f
			where f.artist_id = artists.id and f.follower_id = auth.uid()
		),
		(select count(*)::bigint from public.artist_follows f where f.artist_id = artists.id)
	from unnest(coalesce(p_artist_ids, array[]::uuid[])) as artists(id);
$$;

create or replace function public.toggle_artist_follow(p_artist_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	visitor uuid := auth.uid();
	follow_id uuid;
begin
	if visitor is null
		or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
		raise exception 'A signed-in listener account is required';
	end if;
	if not exists (select 1 from public.profiles where id = p_artist_id) then
		raise exception 'Artist was not found';
	end if;
	perform pg_advisory_xact_lock(hashtext(visitor::text || ':follow:' || p_artist_id::text));

	select id into follow_id from public.artist_follows
	where artist_id = p_artist_id and follower_id = visitor;
	if follow_id is not null then
		delete from public.artist_follows where id = follow_id;
		return false;
	end if;
	insert into public.artist_follows (artist_id, follower_id)
	values (p_artist_id, visitor)
	on conflict (artist_id, follower_id) do nothing;
	return exists (
		select 1 from public.artist_follows
		where artist_id = p_artist_id and follower_id = visitor
	);
end;
$$;

revoke all on function public.get_artist_follow_state(uuid[]) from public, anon, authenticated;
revoke all on function public.toggle_artist_follow(uuid) from public, anon, authenticated;
grant execute on function public.get_artist_follow_state(uuid[]) to authenticated;
grant execute on function public.toggle_artist_follow(uuid) to authenticated;

create or replace function public.sync_content_like_count()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
	if tg_op = 'INSERT' then
		if new.content_type = 'track' then
			update public.tracks set likes_count = likes_count + 1 where id = new.content_id;
		elsif new.content_type = 'clip' then
			update public.clips set likes_count = likes_count + 1 where id = new.content_id;
		else
			update public.music_videos set likes_count = likes_count + 1 where id = new.content_id;
		end if;
		return new;
	end if;
	if old.content_type = 'track' then
		update public.tracks set likes_count = greatest(likes_count - 1, 0) where id = old.content_id;
	elsif old.content_type = 'clip' then
		update public.clips set likes_count = greatest(likes_count - 1, 0) where id = old.content_id;
	else
		update public.music_videos set likes_count = greatest(likes_count - 1, 0) where id = old.content_id;
	end if;
	return old;
end;
$$;

revoke all on function public.sync_content_like_count() from public, anon, authenticated;
drop trigger if exists content_likes_sync_count on public.content_likes;
create trigger content_likes_sync_count after insert or delete on public.content_likes
	for each row execute function public.sync_content_like_count();

create or replace function public.cleanup_track_engagement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
	delete from public.content_likes where content_type = 'track' and content_id = old.id;
	delete from public.comments where content_type = 'track' and content_id = old.id;
	return old;
end;
$$;

create or replace function public.cleanup_clip_engagement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
	delete from public.content_likes where content_type = 'clip' and content_id = old.id;
	delete from public.comments where content_type = 'clip' and content_id = old.id;
	return old;
end;
$$;

create or replace function public.cleanup_music_video_engagement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
	delete from public.content_likes where content_type = 'music_video' and content_id = old.id;
	delete from public.comments where content_type = 'music_video' and content_id = old.id;
	return old;
end;
$$;

revoke all on function public.cleanup_track_engagement() from public, anon, authenticated;
revoke all on function public.cleanup_clip_engagement() from public, anon, authenticated;
revoke all on function public.cleanup_music_video_engagement() from public, anon, authenticated;
drop trigger if exists tracks_cleanup_engagement on public.tracks;
create trigger tracks_cleanup_engagement before delete on public.tracks
	for each row execute function public.cleanup_track_engagement();
drop trigger if exists clips_cleanup_engagement on public.clips;
create trigger clips_cleanup_engagement before delete on public.clips
	for each row execute function public.cleanup_clip_engagement();
drop trigger if exists music_videos_cleanup_engagement on public.music_videos;
create trigger music_videos_cleanup_engagement before delete on public.music_videos
	for each row execute function public.cleanup_music_video_engagement();

drop policy if exists "Anyone can read comments" on public.comments;
drop policy if exists "Authenticated visitors can comment as themselves" on public.comments;
create policy "Anyone can read comments" on public.comments
	for select to anon, authenticated using (true);

drop policy if exists "Visitors can comment as themselves" on public.comments;
create policy "Visitors can comment as themselves" on public.comments
	for insert to authenticated
	with check (
		visitor_id = (select auth.uid())
		and char_length(btrim(body)) between 1 and 500
		and char_length(btrim(display_name)) between 1 and 40
		and (
			(content_type = 'track' and exists (select 1 from public.tracks where id = content_id))
			or (content_type = 'clip' and exists (select 1 from public.clips where id = content_id))
			or (content_type = 'music_video' and exists (select 1 from public.music_videos where id = content_id))
		)
	);

drop policy if exists "Anyone can read stream counts" on public.track_streams;
drop policy if exists "Anyone can read track streams" on public.track_streams;

create or replace function public.sync_track_view_count()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
	update public.tracks set views_count = views_count + 1 where id = new.track_id;
	return new;
end;
$$;

revoke all on function public.sync_track_view_count() from public, anon, authenticated;
drop trigger if exists track_streams_sync_views on public.track_streams;
create trigger track_streams_sync_views after insert on public.track_streams
	for each row execute function public.sync_track_view_count();

create or replace function public.record_track_stream(p_track_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	inserted_count integer;
begin
	if auth.uid() is null then
		raise exception 'An authenticated visitor is required';
	end if;
	insert into public.track_streams (track_id, visitor_id)
	values (p_track_id, auth.uid())
	on conflict (track_id, visitor_id, played_on) do nothing;
	get diagnostics inserted_count = row_count;
	return inserted_count = 1;
end;
$$;

revoke all on function public.record_track_stream(uuid) from public, anon, authenticated;
grant execute on function public.record_track_stream(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 104857600, array['audio/*', 'video/*', 'image/*'])
on conflict (id) do update set
	public = true,
	file_size_limit = 104857600,
	allowed_mime_types = array['audio/*', 'video/*', 'image/*'];

drop policy if exists "Musicians can upload into their media folder" on storage.objects;
drop policy if exists "Creators can upload to their media folder" on storage.objects;

drop policy if exists "Musicians can update their media" on storage.objects;
create policy "Musicians can update their media" on storage.objects
	for update to authenticated
	using (
		bucket_id = 'media'
		and exists (
			select 1 from public.profiles
			where id::text = (storage.foldername(name))[1]
				and user_id = (select auth.uid()) and role = 'musician'
		)
	)
	with check (
		bucket_id = 'media'
		and exists (
			select 1 from public.profiles
			where id::text = (storage.foldername(name))[1]
				and user_id = (select auth.uid()) and role = 'musician'
		)
	);

drop policy if exists "Musicians can delete their media" on storage.objects;
drop policy if exists "Creators can delete from their media folder" on storage.objects;
create policy "Musicians can delete their media" on storage.objects
	for delete to authenticated
	using (
		bucket_id = 'media'
		and exists (
			select 1 from public.profiles
			where id::text = (storage.foldername(name))[1]
				and user_id = (select auth.uid()) and role = 'musician'
		)
	);

alter table public.profiles
	add column if not exists bio text not null default '',
	add column if not exists contact_email text,
	add column if not exists contact_phone text;
grant update (username, avatar_url, bio, contact_email, contact_phone) on public.profiles to authenticated;

create table if not exists public.posts (
	id uuid primary key default gen_random_uuid(),
	author_id uuid not null references public.profiles(id) on delete cascade,
	title text not null check (char_length(btrim(title)) between 1 and 100),
	description text not null default '',
	image_url text not null,
	storage_path text,
	file_size bigint,
	mime_type text,
	views_count bigint not null default 0 check (views_count >= 0),
	likes_count bigint not null default 0 check (likes_count >= 0),
	created_at timestamptz not null default now()
);

create table if not exists public.freestyles (
	id uuid primary key default gen_random_uuid(),
	author_id uuid not null references public.profiles(id) on delete cascade,
	title text not null check (char_length(btrim(title)) between 1 and 100),
	genre text not null default '',
	description text not null default '',
	audio_url text not null,
	duration_seconds numeric check (duration_seconds is null or duration_seconds between 10 and 60),
	storage_path text,
	file_size bigint,
	mime_type text,
	views_count bigint not null default 0 check (views_count >= 0),
	likes_count bigint not null default 0 check (likes_count >= 0),
	created_at timestamptz not null default now()
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_id_idx on public.posts (author_id);
create index if not exists freestyles_created_at_idx on public.freestyles (created_at desc);
create index if not exists freestyles_author_id_idx on public.freestyles (author_id);
alter table public.tracks add column if not exists duration_seconds numeric;
alter table public.freestyles add column if not exists duration_seconds numeric;
alter table public.tracks drop constraint if exists tracks_duration_seconds_check;
alter table public.tracks add constraint tracks_duration_seconds_check
	check (duration_seconds is null or duration_seconds between 30 and 360);
alter table public.freestyles drop constraint if exists freestyles_duration_seconds_check;
alter table public.freestyles add constraint freestyles_duration_seconds_check
	check (duration_seconds is null or duration_seconds between 10 and 60);

alter table public.posts enable row level security;
alter table public.freestyles enable row level security;
revoke all on public.posts, public.freestyles from public, anon, authenticated;
grant select on public.posts, public.freestyles to anon, authenticated;
grant all on public.posts, public.freestyles to service_role;
grant update (title, description) on public.posts to authenticated;
grant update (title, genre, description) on public.freestyles to authenticated;
grant delete on public.posts, public.freestyles to authenticated;

drop policy if exists "Image posts are publicly readable" on public.posts;
create policy "Image posts are publicly readable" on public.posts
	for select to anon, authenticated using (true);
drop policy if exists "Authors can edit their image posts" on public.posts;
create policy "Authors can edit their image posts" on public.posts
	for update to authenticated
	using (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())))
	with check (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())));
drop policy if exists "Authors can delete their image posts" on public.posts;
create policy "Authors can delete their image posts" on public.posts
	for delete to authenticated
	using (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())));

drop policy if exists "Freestyles are publicly readable" on public.freestyles;
create policy "Freestyles are publicly readable" on public.freestyles
	for select to anon, authenticated using (true);
drop policy if exists "Authors can edit their freestyles" on public.freestyles;
create policy "Authors can edit their freestyles" on public.freestyles
	for update to authenticated
	using (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())))
	with check (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())));
drop policy if exists "Authors can delete their freestyles" on public.freestyles;
create policy "Authors can delete their freestyles" on public.freestyles
	for delete to authenticated
	using (exists (select 1 from public.profiles where id = author_id and user_id = (select auth.uid())));

alter table public.content_likes
	drop constraint if exists content_likes_content_type_check,
	add constraint content_likes_content_type_check
		check (content_type in ('track', 'clip', 'music_video', 'post', 'freestyle'));
alter table public.comments
	drop constraint if exists comments_content_type_check,
	add constraint comments_content_type_check
		check (content_type in ('track', 'clip', 'music_video', 'post', 'freestyle'));

create table if not exists public.content_views (
	id uuid primary key default gen_random_uuid(),
	content_type text not null check (content_type in ('post', 'freestyle')),
	content_id uuid not null,
	visitor_id uuid not null references auth.users(id) on delete cascade,
	created_at timestamptz not null default now(),
	unique (content_type, content_id, visitor_id)
);
alter table public.content_views enable row level security;
revoke all on public.content_views from public, anon, authenticated;
grant all on public.content_views to service_role;

create or replace function public.toggle_content_like(p_content_type text, p_content_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	visitor uuid := auth.uid();
	like_id uuid;
begin
	if visitor is null then
		raise exception 'An authenticated visitor is required';
	end if;
	if p_content_type not in ('track', 'clip', 'music_video', 'post', 'freestyle') then
		raise exception 'Unsupported content type';
	end if;
	if (p_content_type = 'track' and not exists (select 1 from public.tracks where id = p_content_id))
		or (p_content_type = 'clip' and not exists (select 1 from public.clips where id = p_content_id))
		or (p_content_type = 'music_video' and not exists (select 1 from public.music_videos where id = p_content_id))
		or (p_content_type = 'post' and not exists (select 1 from public.posts where id = p_content_id))
		or (p_content_type = 'freestyle' and not exists (select 1 from public.freestyles where id = p_content_id)) then
		raise exception 'Content was not found';
	end if;
	perform pg_advisory_xact_lock(hashtext(visitor::text || ':' || p_content_type || ':' || p_content_id::text));
	select id into like_id from public.content_likes
		where content_type = p_content_type and content_id = p_content_id and visitor_id = visitor;
	if like_id is not null then
		delete from public.content_likes where id = like_id;
		return false;
	end if;
	insert into public.content_likes (content_type, content_id, visitor_id)
	values (p_content_type, p_content_id, visitor)
	on conflict (content_type, content_id, visitor_id) do nothing;
	return exists (
		select 1 from public.content_likes
		where content_type = p_content_type and content_id = p_content_id and visitor_id = visitor
	);
end;
$$;
revoke all on function public.toggle_content_like(text, uuid) from public, anon, authenticated;
grant execute on function public.toggle_content_like(text, uuid) to authenticated;

create or replace function public.sync_content_like_count()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	content_kind text := case when tg_op = 'INSERT' then new.content_type else old.content_type end;
	content_key uuid := case when tg_op = 'INSERT' then new.content_id else old.content_id end;
	delta integer := case when tg_op = 'INSERT' then 1 else -1 end;
begin
	if content_kind = 'track' then
		update public.tracks set likes_count = greatest(likes_count + delta, 0) where id = content_key;
	elsif content_kind = 'clip' then
		update public.clips set likes_count = greatest(likes_count + delta, 0) where id = content_key;
	elsif content_kind = 'music_video' then
		update public.music_videos set likes_count = greatest(likes_count + delta, 0) where id = content_key;
	elsif content_kind = 'post' then
		update public.posts set likes_count = greatest(likes_count + delta, 0) where id = content_key;
	elsif content_kind = 'freestyle' then
		update public.freestyles set likes_count = greatest(likes_count + delta, 0) where id = content_key;
	end if;
	if tg_op = 'INSERT' then return new; end if;
	return old;
end;
$$;

create or replace function public.record_content_view(p_content_type text, p_content_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	visitor uuid := auth.uid();
	inserted_count integer;
begin
	if visitor is null then raise exception 'An authenticated visitor is required'; end if;
	if p_content_type = 'post' then
		if not exists (select 1 from public.posts where id = p_content_id) then raise exception 'Post was not found'; end if;
	elsif p_content_type = 'freestyle' then
		if not exists (select 1 from public.freestyles where id = p_content_id) then raise exception 'Freestyle was not found'; end if;
	else
		raise exception 'Unsupported view content type';
	end if;
	insert into public.content_views (content_type, content_id, visitor_id)
	values (p_content_type, p_content_id, visitor)
	on conflict (content_type, content_id, visitor_id) do nothing;
	get diagnostics inserted_count = row_count;
	if inserted_count = 1 and p_content_type = 'post' then
		update public.posts set views_count = views_count + 1 where id = p_content_id;
	elsif inserted_count = 1 then
		update public.freestyles set views_count = views_count + 1 where id = p_content_id;
	end if;
	return inserted_count = 1;
end;
$$;
revoke all on function public.record_content_view(text, uuid) from public, anon, authenticated;
grant execute on function public.record_content_view(text, uuid) to authenticated;

create or replace function public.get_my_activity()
returns table (content_type text, content_id uuid, title text, artist_name text, image_url text, audio_url text)
language sql
security definer
set search_path = public, pg_temp
as $$
	select 'track'::text, t.id, t.title, p.username, t.cover_url, t.audio_url
	from public.content_likes l
	join public.tracks t on l.content_type = 'track' and t.id = l.content_id
	join public.profiles p on p.id = t.artist_id
	where l.visitor_id = auth.uid()
	union all
	select 'post'::text, t.id, t.title, p.username, t.image_url, null::text
	from public.content_likes l
	join public.posts t on l.content_type = 'post' and t.id = l.content_id
	join public.profiles p on p.id = t.author_id
	where l.visitor_id = auth.uid()
	union all
	select 'freestyle'::text, t.id, t.title, p.username, null::text, t.audio_url
	from public.content_likes l
	join public.freestyles t on l.content_type = 'freestyle' and t.id = l.content_id
	join public.profiles p on p.id = t.author_id
	where l.visitor_id = auth.uid()
	order by title;
$$;
revoke all on function public.get_my_activity() from public, anon, authenticated;
grant execute on function public.get_my_activity() to authenticated;

create or replace function public.get_my_followed_artists()
returns table (artist_id uuid, username text, avatar_url text)
language sql
security definer
set search_path = public, pg_temp
as $$
	select p.id, p.username, p.avatar_url
	from public.artist_follows f
	join public.profiles p on p.id = f.artist_id
	where f.follower_id = auth.uid()
	order by p.username;
$$;
revoke all on function public.get_my_followed_artists() from public, anon, authenticated;
grant execute on function public.get_my_followed_artists() to authenticated;

create or replace function public.cleanup_social_content()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	content_kind text := case when tg_table_name = 'posts' then 'post' else 'freestyle' end;
begin
	delete from public.content_likes where content_type = content_kind and content_id = old.id;
	delete from public.comments where content_type = content_kind and content_id = old.id;
	delete from public.content_views where content_type = content_kind and content_id = old.id;
	return old;
end;
$$;
revoke all on function public.cleanup_social_content() from public, anon, authenticated;
drop trigger if exists posts_cleanup_engagement on public.posts;
create trigger posts_cleanup_engagement before delete on public.posts
	for each row execute function public.cleanup_social_content();
drop trigger if exists freestyles_cleanup_engagement on public.freestyles;
create trigger freestyles_cleanup_engagement before delete on public.freestyles
	for each row execute function public.cleanup_social_content();

drop policy if exists "Visitors can comment as themselves" on public.comments;
create policy "Visitors can comment as themselves" on public.comments
	for insert to authenticated
	with check (
		visitor_id = (select auth.uid())
		and char_length(btrim(body)) between 1 and 500
		and char_length(btrim(display_name)) between 1 and 40
		and (
			(content_type = 'track' and exists (select 1 from public.tracks where id = content_id))
			or (content_type = 'clip' and exists (select 1 from public.clips where id = content_id))
			or (content_type = 'music_video' and exists (select 1 from public.music_videos where id = content_id))
			or (content_type = 'post' and exists (select 1 from public.posts where id = content_id))
			or (content_type = 'freestyle' and exists (select 1 from public.freestyles where id = content_id))
		)
	);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 104857600, array['audio/*', 'image/jpeg', 'image/png', 'image/webp', 'image/avif'])
on conflict (id) do update set
	public = true,
	file_size_limit = 104857600,
	allowed_mime_types = array['audio/*', 'image/jpeg', 'image/png', 'image/webp', 'image/avif'];

create or replace function public.normalize_comment_language(input_text text)
returns text
language sql
immutable
strict
as $$
	select regexp_replace(
		translate(lower(input_text), '013457@$!|', 'oieastasil'),
		'[^a-z]+',
		'',
		'g'
	);
$$;

create or replace function public.reject_abusive_comments()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
	normalized_body text := public.normalize_comment_language(new.body);
	banned_term text;
begin
	foreach banned_term in array array[
		'fuck', 'shit', 'bitch', 'bastard', 'asshole', 'cunt',
		'motherfucker', 'nigger', 'faggot', 'whore', 'slut'
	] loop
		if position(banned_term in normalized_body) > 0 then
			raise exception 'Please remove abusive or profane language before posting.'
				using errcode = '22023';
		end if;
	end loop;
	return new;
end;
$$;
revoke all on function public.normalize_comment_language(text) from public, anon, authenticated;
revoke all on function public.reject_abusive_comments() from public, anon, authenticated;
drop trigger if exists comments_reject_abusive_language on public.comments;
create trigger comments_reject_abusive_language before insert or update of body on public.comments
	for each row execute function public.reject_abusive_comments();

create or replace function public.get_content_comment_counts(p_content_ids uuid[])
returns table (content_type text, content_id uuid, comments_count bigint)
language sql
security definer
set search_path = public, pg_temp
as $$
	select c.content_type, c.content_id, count(*)::bigint
	from public.comments c
	where c.content_id = any(coalesce(p_content_ids, array[]::uuid[]))
		and c.content_type in ('track', 'post', 'freestyle')
	group by c.content_type, c.content_id;
$$;
revoke all on function public.get_content_comment_counts(uuid[]) from public, anon, authenticated;
grant execute on function public.get_content_comment_counts(uuid[]) to anon, authenticated;
