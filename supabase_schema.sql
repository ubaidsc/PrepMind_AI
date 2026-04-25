-- =============================================
-- PrepMind AI — Supabase Schema (Phase 1)
-- Run in Supabase SQL Editor in this exact order
-- =============================================

-- EXTENSIONS
create extension if not exists "uuid-ossp";

-- =============================================
-- PROFILES TABLE
-- =============================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  plan text not null default 'free' check (plan in ('free', 'pro')),
  ai_requests_used integer not null default 0,
  ai_requests_limit integer not null default 20,
  documents_uploaded integer not null default 0,
  documents_limit integer not null default 5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================
-- SUBJECTS TABLE
-- =============================================
create table public.subjects (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  exam_type text,
  semester text,
  color text not null default '#6366F1',
  icon text not null default 'book',
  document_count integer not null default 0,
  ai_note_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =============================================
-- DOCUMENTS TABLE
-- =============================================
create table public.documents (
  id uuid primary key default uuid_generate_v4(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  file_type text not null check (file_type in ('pdf', 'docx', 'pptx')),
  file_size_bytes bigint not null,
  storage_path text not null,
  status text not null default 'uploaded' check (status in ('uploaded', 'processing', 'ready', 'failed')),
  page_count integer,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =============================================
-- ROW LEVEL SECURITY
-- =============================================

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

alter table public.subjects enable row level security;

create policy "subjects_select_own" on public.subjects
  for select using (auth.uid() = user_id);

create policy "subjects_insert_own" on public.subjects
  for insert with check (auth.uid() = user_id);

create policy "subjects_update_own" on public.subjects
  for update using (auth.uid() = user_id);

create policy "subjects_delete_own" on public.subjects
  for delete using (auth.uid() = user_id);

alter table public.documents enable row level security;

create policy "documents_select_own" on public.documents
  for select using (auth.uid() = user_id);

create policy "documents_insert_own" on public.documents
  for insert with check (auth.uid() = user_id);

create policy "documents_update_own" on public.documents
  for update using (auth.uid() = user_id);

create policy "documents_delete_own" on public.documents
  for delete using (auth.uid() = user_id);

-- =============================================
-- UPDATED_AT TRIGGERS
-- =============================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger set_subjects_updated_at before update on public.subjects
  for each row execute function public.set_updated_at();

create trigger set_documents_updated_at before update on public.documents
  for each row execute function public.set_updated_at();

-- =============================================
-- STORAGE POLICIES (run after creating bucket)
-- =============================================
-- 1. In Supabase Dashboard → Storage, create bucket: "documents" (Private)
-- 2. Then run below:

create policy "users upload own documents"
on storage.objects for insert
to authenticated
with check (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "users read own documents"
on storage.objects for select
to authenticated
using (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "users delete own documents"
on storage.objects for delete
to authenticated
using (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);
