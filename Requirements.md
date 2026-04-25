# PrepMind AI — Phase 1 Build Guide

> **For AI Agent Use** | Flutter + FastAPI + Supabase | Production-Level Architecture

---

## Project Overview

**PrepMind AI** is an AI-powered exam preparation mobile app. Students upload academic documents (PDF, DOCX, PPT), and the app generates structured study content (summaries, flashcards, MCQs, revision sheets) using AI with persistent subject-level context.

**Phase 1 Scope:** Project setup, folder architecture, Supabase schema, authentication (email/password + Google), and navigation shell. No AI features yet.

**Tech Stack:**

- **Mobile:** Flutter (latest stable)
- **Backend:** FastAPI (Python 3.12+)
- **Database & Auth & Storage:** Supabase
- **State Management:** Riverpod (flutter_riverpod)
- **API Client:** Dio + Retrofit (optional codegen)

---

## Repository Structure

Two separate repositories (or monorepo with two root folders):

```
prepmind/
├── prepmind_app/          # Flutter mobile app
└── prepmind_api/          # FastAPI backend
```

---

## Part 1: Supabase Setup

> The agent has access to the Supabase MCP. Use it to execute all schema SQL below.

### 1.1 Create Supabase Project

- Project name: `prepmind`
- Region: closest to your users
- Note down: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`

### 1.2 Enable Auth Providers

In Supabase Dashboard → Authentication → Providers:

- Enable **Email** (confirm email: true)
- Enable **Google** (add OAuth credentials from Google Cloud Console)

### 1.3 Database Schema

Execute the following SQL in Supabase SQL Editor in order:

```sql
-- =============================================
-- EXTENSIONS
-- =============================================
create extension if not exists "uuid-ossp";

-- =============================================
-- PROFILES TABLE
-- Extends Supabase auth.users
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

-- Profiles: users can only read/update their own
alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- Subjects: full CRUD for owner
alter table public.subjects enable row level security;

create policy "subjects_select_own" on public.subjects
  for select using (auth.uid() = user_id);

create policy "subjects_insert_own" on public.subjects
  for insert with check (auth.uid() = user_id);

create policy "subjects_update_own" on public.subjects
  for update using (auth.uid() = user_id);

create policy "subjects_delete_own" on public.subjects
  for delete using (auth.uid() = user_id);

-- Documents: full CRUD for owner
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
-- STORAGE BUCKETS
-- =============================================
-- Run via Supabase dashboard or MCP:
-- Bucket name: "documents"
-- Public: false (private bucket)
-- File size limit: 20MB
-- Allowed mime types: application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document, application/vnd.openxmlformats-officedocument.presentationml.presentation

-- Storage RLS policies
-- (after creating bucket in dashboard, add these policies)

-- Updated_at trigger function
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
```

### 1.4 Storage Setup

In Supabase Dashboard → Storage:

1. Create bucket: `documents` (Private)
2. Add storage policy for authenticated users:

```sql
-- Allow users to upload to their own folder
create policy "users upload own documents"
on storage.objects for insert
to authenticated
with check (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);

-- Allow users to read their own documents
create policy "users read own documents"
on storage.objects for select
to authenticated
using (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);

-- Allow users to delete their own documents
create policy "users delete own documents"
on storage.objects for delete
to authenticated
using (bucket_id = 'documents' and auth.uid()::text = (storage.foldername(name))[1]);
```

---

## Part 2: FastAPI Backend

### 2.1 Project Structure

```
prepmind_api/
├── app/
│   ├── __init__.py
│   ├── main.py                  # FastAPI app entry point
│   ├── config.py                # Settings via pydantic-settings
│   ├── dependencies.py          # Shared DI (get_current_user, etc.)
│   │
│   ├── core/
│   │   ├── __init__.py
│   │   ├── supabase.py          # Supabase client singleton
│   │   └── exceptions.py        # Custom exceptions + handlers
│   │
│   ├── models/                  # Pydantic schemas (request/response)
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── subject.py
│   │   ├── document.py
│   │   └── common.py            # Pagination, error response, etc.
│   │
│   └── routers/
│       ├── __init__.py
│       ├── auth.py              # /auth/* endpoints
│       ├── subjects.py          # /subjects/* endpoints
│       └── documents.py         # /documents/* endpoints (upload only in Phase 1)
│
├── tests/
│   ├── conftest.py
│   ├── test_auth.py
│   └── test_subjects.py
│
├── .env                         # Never commit
├── .env.example
├── pyproject.toml               # uv / pip-tools config
├── requirements.txt
└── Dockerfile
```

### 2.2 Dependencies

`requirements.txt`:

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
supabase==2.9.1
python-jose[cryptography]==3.3.0
python-multipart==0.0.9
pydantic==2.9.2
pydantic-settings==2.5.2
httpx==0.27.2
python-dotenv==1.0.1
pytest==8.3.3
pytest-asyncio==0.24.0
```

### 2.3 Environment Variables

`.env.example`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
SUPABASE_JWT_SECRET=your_jwt_secret
APP_ENV=development
ALLOWED_ORIGINS=http://localhost:3000
```

### 2.4 Core Files

**`app/config.py`**

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str
    supabase_jwt_secret: str
    app_env: str = "development"
    allowed_origins: list[str] = ["http://localhost:3000"]

settings = Settings()
```

**`app/core/supabase.py`**

```python
from functools import lru_cache
from supabase import create_client, Client
from app.config import settings

@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    """Admin client with service role key — use only server-side."""
    return create_client(settings.supabase_url, settings.supabase_service_role_key)

@lru_cache(maxsize=1)
def get_supabase_anon_client() -> Client:
    """Anon client — respects RLS."""
    return create_client(settings.supabase_url, settings.supabase_anon_key)
```

**`app/dependencies.py`**

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from app.config import settings
from app.core.supabase import get_supabase_client

bearer_scheme = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> dict:
    """
    Validates the Supabase JWT from the Authorization header.
    Returns the decoded user payload.
    """
    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            options={"verify_aud": False},
        )
        user_id: str = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        return {"id": user_id, "email": payload.get("email")}
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
```

**`app/main.py`**

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import auth, subjects, documents

app = FastAPI(
    title="PrepMind AI API",
    version="0.1.0",
    docs_url="/docs" if settings.app_env != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(subjects.router, prefix="/subjects", tags=["subjects"])
app.include_router(documents.router, prefix="/documents", tags=["documents"])

@app.get("/health")
async def health_check():
    return {"status": "ok"}
```

**`app/models/common.py`**

```python
from pydantic import BaseModel
from typing import Any

class APIResponse(BaseModel):
    success: bool = True
    message: str = "OK"
    data: Any = None

class ErrorResponse(BaseModel):
    success: bool = False
    message: str
    detail: Any = None
```

**`app/models/subject.py`**

```python
from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime
from typing import Optional

class SubjectCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    exam_type: Optional[str] = None
    semester: Optional[str] = None
    color: str = "#6366F1"

class SubjectResponse(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    exam_type: Optional[str]
    semester: Optional[str]
    color: str
    document_count: int
    ai_note_count: int
    created_at: datetime
    updated_at: datetime
```

**`app/routers/subjects.py`**

```python
from fastapi import APIRouter, Depends, HTTPException, status
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.models.subject import SubjectCreate, SubjectResponse
from app.models.common import APIResponse

router = APIRouter()

@router.get("/", response_model=APIResponse)
async def list_subjects(current_user: dict = Depends(get_current_user)):
    supabase = get_supabase_client()
    result = (
        supabase.table("subjects")
        .select("*")
        .eq("user_id", current_user["id"])
        .order("updated_at", desc=True)
        .execute()
    )
    return APIResponse(data=result.data)

@router.post("/", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def create_subject(
    payload: SubjectCreate,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("subjects")
        .insert({**payload.model_dump(), "user_id": current_user["id"]})
        .execute()
    )
    return APIResponse(data=result.data[0], message="Subject created")

@router.delete("/{subject_id}", response_model=APIResponse)
async def delete_subject(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    supabase.table("subjects").delete().eq("id", subject_id).eq("user_id", current_user["id"]).execute()
    return APIResponse(message="Subject deleted")
```

**`app/routers/auth.py`**

```python
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr
from app.core.supabase import get_supabase_anon_client
from app.models.common import APIResponse

router = APIRouter()

class SignUpRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str

class SignInRequest(BaseModel):
    email: EmailStr
    password: str

@router.post("/signup", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def sign_up(payload: SignUpRequest):
    """
    Registers a new user. Supabase sends a confirmation email.
    Profile is auto-created via DB trigger.
    """
    supabase = get_supabase_anon_client()
    try:
        result = supabase.auth.sign_up({
            "email": payload.email,
            "password": payload.password,
            "options": {"data": {"full_name": payload.full_name}},
        })
        return APIResponse(
            data={"user_id": result.user.id if result.user else None},
            message="Confirmation email sent. Please verify your email.",
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.post("/signin", response_model=APIResponse)
async def sign_in(payload: SignInRequest):
    supabase = get_supabase_anon_client()
    try:
        result = supabase.auth.sign_in_with_password({"email": payload.email, "password": payload.password})
        return APIResponse(data={
            "access_token": result.session.access_token,
            "refresh_token": result.session.refresh_token,
            "user": {"id": result.user.id, "email": result.user.email},
        })
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))

@router.post("/signout", response_model=APIResponse)
async def sign_out():
    """Client should discard tokens. Supabase JWT is stateless."""
    return APIResponse(message="Signed out successfully")
```

> **Note:** Google OAuth is handled entirely on the Flutter side using `supabase_flutter`. The backend does not need a Google OAuth endpoint.

### 2.5 Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Part 3: Flutter App

### 3.1 Project Creation

```bash
flutter create prepmind_app --org com.prepmind --platforms android,ios
cd prepmind_app
```

### 3.2 Project Structure

```
prepmind_app/
├── lib/
│   ├── main.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_text_styles.dart
│   │   │   └── app_constants.dart
│   │   ├── router/
│   │   │   └── app_router.dart         # GoRouter config
│   │   ├── providers/
│   │   │   └── supabase_provider.dart  # Supabase client provider
│   │   └── utils/
│   │       └── validators.dart
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart
│   │   │   └── screens/
│   │   │       ├── login_screen.dart
│   │   │       ├── signup_screen.dart
│   │   │       └── forgot_password_screen.dart
│   │   │
│   │   ├── home/
│   │   │   └── screens/
│   │   │       └── home_screen.dart
│   │   │
│   │   ├── subjects/
│   │   │   ├── data/
│   │   │   │   ├── subject_model.dart
│   │   │   │   └── subject_repository.dart
│   │   │   ├── providers/
│   │   │   │   └── subjects_provider.dart
│   │   │   └── screens/
│   │   │       ├── subjects_screen.dart
│   │   │       ├── create_subject_screen.dart
│   │   │       └── subject_detail_screen.dart
│   │   │
│   │   ├── practice/
│   │   │   └── screens/
│   │   │       └── practice_screen.dart    # Placeholder
│   │   │
│   │   └── profile/
│   │       ├── data/
│   │       │   └── profile_repository.dart
│   │       ├── providers/
│   │       │   └── profile_provider.dart
│   │       └── screens/
│   │           └── profile_screen.dart
│   │
│   └── shared/
│       └── widgets/
│           ├── app_button.dart
│           ├── app_text_field.dart
│           ├── loading_overlay.dart
│           └── subject_card.dart
│
├── assets/
│   └── images/
│       └── logo.png
│
├── pubspec.yaml
└── .env                        # gitignored
```

### 3.3 pubspec.yaml Dependencies

```yaml
name: prepmind_app
description: AI-powered exam preparation app

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.5.6

  # State management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Navigation
  go_router: ^14.2.7

  # Network
  dio: ^5.7.0

  # UI
  google_fonts: ^6.2.1
  flutter_svg: ^2.0.10+1
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0

  # File handling
  file_picker: ^8.1.2

  # Utils
  intl: ^0.19.0
  equatable: ^2.0.5
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0
  flutter_dotenv: ^5.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.12
  riverpod_generator: ^2.4.3
  freezed: ^2.5.7
  json_serializable: ^6.8.0

flutter:
  assets:
    - .env
    - assets/images/
```

### 3.4 Core Files

**`lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: PrepMindApp()));
}

class PrepMindApp extends ConsumerWidget {
  const PrepMindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'PrepMind AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
        fontFamily: 'Inter',
      ),
      routerConfig: router,
    );
  }
}
```

**`lib/core/constants/app_colors.dart`**

```dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const primary = Color(0xFF5B4FE8);      // Indigo/Purple from designs
  static const primaryLight = Color(0xFFEDE9FF);
  static const secondary = Color(0xFF10B981);    // Green
  static const surface = Color(0xFFF5F5F7);
  static const background = Colors.white;
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6B7280);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  // Subject card colors (matches designs)
  static const subjectColors = [
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // purple
    Color(0xFF10B981), // green
    Color(0xFFF97316), // orange
    Color(0xFFEF4444), // red
    Color(0xFF6366F1), // indigo
  ];
}
```

**`lib/core/router/app_router.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/subjects/screens/subjects_screen.dart';
import '../../features/subjects/screens/create_subject_screen.dart';
import '../../features/subjects/screens/subject_detail_screen.dart';
import '../../features/practice/screens/practice_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../shell/app_shell.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final supabase = Supabase.instance.client;

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final isAuth = session != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/signup') ||
          state.matchedLocation.startsWith('/forgot-password');

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
          GoRoute(
            path: '/subjects',
            builder: (c, s) => const SubjectsScreen(),
            routes: [
              GoRoute(path: 'create', builder: (c, s) => const CreateSubjectScreen()),
              GoRoute(
                path: ':id',
                builder: (c, s) => SubjectDetailScreen(subjectId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/practice', builder: (c, s) => const PracticeScreen()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
        ],
      ),
    ],
  );
}
```

**`lib/core/shell/app_shell.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/subjects')) return 1;
    if (location.startsWith('/practice')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/home');
            case 1: context.go('/subjects');
            case 2: context.go('/practice');
            case 3: context.go('/profile');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Subjects'),
          NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
```

**`lib/features/auth/data/auth_repository.dart`**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _supabase;
  AuthRepository(this._supabase);

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.prepmind://login-callback',
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
```

**`lib/features/auth/providers/auth_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});
```

**`lib/features/subjects/data/subject_model.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'subject_model.freezed.dart';
part 'subject_model.g.dart';

@freezed
class Subject with _$Subject {
  const factory Subject({
    required String id,
    required String userId,
    required String name,
    String? examType,
    String? semester,
    @Default('#6366F1') String color,
    @Default(0) int documentCount,
    @Default(0) int aiNoteCount,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Subject;

  factory Subject.fromJson(Map<String, dynamic> json) => _$SubjectFromJson(json);
}
```

**`lib/features/subjects/data/subject_repository.dart`**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subject_model.dart';

class SubjectRepository {
  final SupabaseClient _supabase;
  SubjectRepository(this._supabase);

  Future<List<Subject>> getSubjects() async {
    final data = await _supabase
        .from('subjects')
        .select()
        .order('updated_at', ascending: false);
    return (data as List).map((e) => Subject.fromJson(e)).toList();
  }

  Future<Subject> createSubject({
    required String name,
    String? examType,
    String? semester,
    String color = '#6366F1',
  }) async {
    final data = await _supabase.from('subjects').insert({
      'name': name,
      'exam_type': examType,
      'semester': semester,
      'color': color,
    }).select().single();
    return Subject.fromJson(data);
  }

  Future<void> deleteSubject(String id) async {
    await _supabase.from('subjects').delete().eq('id', id);
  }
}
```

**`lib/features/subjects/providers/subjects_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/subject_model.dart';
import '../data/subject_repository.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return SubjectRepository(Supabase.instance.client);
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  return ref.watch(subjectRepositoryProvider).getSubjects();
});
```

**`lib/shared/widgets/app_button.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: isOutlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: child,
            ),
    );
  }
}
```

**`lib/shared/widgets/app_text_field.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
```

**`lib/features/auth/screens/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../core/constants/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                const Text('Welcome back 👋', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Sign in to continue studying', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 40),
                AppTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.contains('@') ? null : 'Enter valid email',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Password',
                  hint: '••••••••',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) => v!.length >= 6 ? null : 'Min 6 characters',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: const Text('Forgot Password?', style: TextStyle(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 8),
                AppButton(label: 'Sign In', onPressed: _signIn, isLoading: _isLoading),
                const SizedBox(height: 16),
                AppButton(label: 'Continue with Google', onPressed: _signInWithGoogle, isOutlined: true),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    TextButton(
                      onPressed: () => context.go('/signup'),
                      child: const Text('Sign Up', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

**`lib/features/home/screens/home_screen.dart`** (skeleton matching the design)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/subjects/providers/subjects_provider.dart';
import '../../../shared/widgets/subject_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final subjectsAsync = ref.watch(subjectsProvider);
    final firstName = user?.userMetadata?['full_name']?.toString().split(' ').first ?? 'Student';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Hi, $firstName 👋', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
                      ],
                    ),
                    const Text('Ready to revise?', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    // Quick action cards
                    Row(
                      children: [
                        Expanded(
                          child: _QuickActionCard(
                            title: 'Revision Planner',
                            subtitle: 'Plan your study schedule',
                            color: AppColors.primary,
                            icon: Icons.calendar_today,
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            title: 'Quick Practice',
                            subtitle: 'Test your knowledge',
                            color: AppColors.secondary,
                            icon: Icons.trending_up,
                            onTap: () => context.go('/practice'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('My Subjects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        TextButton(onPressed: () => context.go('/subjects'), child: const Text('View All')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            subjectsAsync.when(
              data: (subjects) => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => SubjectCard(subject: subjects[i], onTap: () => context.go('/subjects/${subjects[i].id}')),
                    childCount: subjects.take(4).length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                ),
              ),
              loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/subjects/create'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title, subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionCard({required this.title, required this.subtitle, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

**`lib/shared/widgets/subject_card.dart`**

```dart
import 'package:flutter/material.dart';
import '../../features/subjects/data/subject_model.dart';

class SubjectCard extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;

  const SubjectCard({super.key, required this.subject, required this.onTap});

  Color get _color {
    try {
      return Color(int.parse(subject.color.replaceAll('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF6366F1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.menu_book, color: Colors.white, size: 22),
            ),
            const Spacer(),
            Text(subject.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${subject.documentCount} documents', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

### 3.5 Android Deep Link Setup (for Google OAuth)

In `android/app/src/main/AndroidManifest.xml`, inside `<activity>`:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="io.supabase.prepmind" android:host="login-callback" />
</intent-filter>
```

In Supabase Dashboard → Authentication → URL Configuration:

- Add redirect URL: `io.supabase.prepmind://login-callback`

### 3.6 Environment File

`prepmind_app/.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key
API_BASE_URL=http://10.0.2.2:8000   # Android emulator localhost
```

Add `.env` to `pubspec.yaml` assets (already done above) and add to `.gitignore`.

---

## Part 4: Phase 1 Checklist

### Supabase

- [ ] Project created, URL and keys noted
- [ ] Email + Google auth providers enabled
- [ ] Schema SQL executed (profiles, subjects, documents tables)
- [ ] RLS policies applied
- [ ] Storage bucket `documents` created with policies
- [ ] Redirect URL added for Google OAuth

### FastAPI Backend

- [ ] Project structure created
- [ ] `.env` configured
- [ ] `/health` endpoint returns 200
- [ ] `/auth/signup` and `/auth/signin` working
- [ ] `/subjects` CRUD working (list, create, delete)
- [ ] JWT validation middleware working
- [ ] Dockerfile builds successfully

### Flutter App

- [ ] Project created with correct package name
- [ ] All dependencies added to `pubspec.yaml`
- [ ] Supabase initialized in `main.dart`
- [ ] GoRouter configured with auth redirect guard
- [ ] Bottom navigation shell working (4 tabs)
- [ ] Login screen functional (email + Google)
- [ ] Signup screen functional
- [ ] Forgot password screen functional
- [ ] Home screen renders subjects grid
- [ ] Subjects list screen working
- [ ] Create subject screen working (saves to Supabase)
- [ ] Profile screen shows user info + usage stats
- [ ] Auth state persisted across app restarts

---

## Part 5: Key Architecture Decisions

### Why FastAPI over Django?

FastAPI is chosen because: async-first (perfect for AI I/O in Phase 2), automatic OpenAPI docs, Pydantic validation, and lightweight footprint. Django is better for complex admin/ORM needs — not this use case.

### Why Supabase directly from Flutter?

Auth and simple CRUD go directly to Supabase from the Flutter app (via `supabase_flutter`). This is faster to develop and Supabase RLS keeps it secure. The FastAPI backend will be the critical layer in Phase 2 for AI orchestration, document processing, and business logic that cannot be in the client.

### State Management Pattern

- **Riverpod `FutureProvider`** for async data fetching (subjects, profile)
- **Riverpod `StreamProvider`** for auth state
- **Riverpod `StateNotifierProvider`** (Phase 2) for complex state like AI generation progress
- No `setState` except for local UI state (loading buttons, toggle visibility)

### Token Flow

1. Flutter authenticates with Supabase → receives JWT access token
2. JWT stored securely in Supabase session (auto-managed by `supabase_flutter`)
3. For FastAPI calls: attach JWT in `Authorization: Bearer <token>` header
4. FastAPI validates JWT using `SUPABASE_JWT_SECRET`
5. Supabase RLS automatically scopes DB queries to the authenticated user

---

## Part 6: What's NOT in Phase 1 (Deferred to Phase 2)

- Document upload and text extraction
- AI content generation (summaries, MCQs, flashcards)
- AI chat per subject
- Revision planner generation
- Practice module (MCQ/flashcard UI will be placeholder screens)
- Subscription/payments
- Push notifications
- Search functionality
