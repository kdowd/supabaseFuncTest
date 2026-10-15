-- ============================================================================
--  Storage policies for the 'assets' bucket
--
--  Run this in the Supabase SQL editor (project: pkpbzthkwskkudqogyrl).
--  products.sql created the table; this one decides who may put FILES in the
--  bucket that the cards point at.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  STEP 0 — look before you change anything.
--  Run this on its own first and read the result. It lists every policy that
--  already exists on storage.objects.
-- ---------------------------------------------------------------------------
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename  = 'objects';

-- >>> IMPORTANT — read this before adding the policies below <<<
--
--  Policies are joined with OR. If STEP 0 showed a broad policy such as
--  "authenticated users can do anything", then adding the strict policies
--  below changes NOTHING — the broad one still lets everything through.
--  To actually tighten it you must drop the broad one first, e.g.:
--
--      drop policy "some broad policy name" on storage.objects;
--
--  Strangers are already blocked (an anonymous upload is refused), so there is
--  no "anon" policy to remove.


-- ---------------------------------------------------------------------------
--  STEP 1 — make sure the RLS switch is on. Policies are ignored without it.
-- ---------------------------------------------------------------------------
alter table storage.objects enable row level security;


-- ---------------------------------------------------------------------------
--  STEP 2 — UPLOADING.
--  Logged-in people only, and only into a folder named after their own user id.
--  The page builds paths like  <user-id>/1729000000-shirt.png  so this matches.
-- ---------------------------------------------------------------------------
create policy "assets: upload into your own folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);


-- ---------------------------------------------------------------------------
--  STEP 3 — REPLACING a file you already own.
-- ---------------------------------------------------------------------------
create policy "assets: update your own files"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'assets'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);


-- ---------------------------------------------------------------------------
--  STEP 4 — DELETING your own file.
-- ---------------------------------------------------------------------------
create policy "assets: delete your own files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);

--  No SELECT policy is needed: the bucket is public, so images are served from
--  the /object/public/ address without checking policies at all.


-- ---------------------------------------------------------------------------
--  STEP 5 — limits on the bucket itself.
--
--  The bucket already refuses anything that isn't an image. This pins down
--  exactly which image types and how big a file may be.
--
--  NOTE: I have left image/svg+xml OUT on purpose. It is currently allowed,
--  and this statement will remove it. An SVG is really a web page, so it can
--  carry scripts — worth avoiding for files uploaded by the public. Add it back
--  if you genuinely need vector logos.
-- ---------------------------------------------------------------------------
update storage.buckets
set file_size_limit   = 5242880,   -- 5 MB
    allowed_mime_types = array[
      'image/png',
      'image/jpeg',
      'image/jpg',
      'image/webp',
      'image/gif',
      'image/avif'
    ]
where id = 'assets';


-- ---------------------------------------------------------------------------
--  STEP 6 — check it worked.
-- ---------------------------------------------------------------------------
select id, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'assets';

select policyname, cmd
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
