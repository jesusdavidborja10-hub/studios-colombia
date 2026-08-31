-- STUDIOS COLOMBIA — estructura de base de datos en Supabase
-- Pega TODO este archivo en Supabase → SQL Editor → New query → Run

create extension if not exists pgcrypto;

-- ---------- Tablas ----------

create table categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric not null,
  image text,
  video_url text,
  category_id uuid references categories(id) on delete set null,
  created_at timestamptz not null default now()
);

create table settings (
  id smallint primary key default 1,
  store_name text not null,
  promo_text text not null,
  whatsapp text not null,
  updated_at timestamptz not null default now(),
  constraint settings_singleton check (id = 1)
);

-- Fila inicial de ajustes (la tienda la actualizará desde el panel de admin)
insert into settings (id, store_name, promo_text, whatsapp)
values (
  1,
  'STUDIOS COLOMBIA',
  '🔥 Elige tus animaciones y arma tu pedido — te contesto por WhatsApp al momento.',
  '573015751907'
);

-- ---------- Seguridad (Row Level Security) ----------
-- Lectura: pública (cualquier visitante puede ver el catálogo sin iniciar sesión).
-- Escritura: solo alguien con sesión iniciada (usuario administrador creado en Authentication).

alter table categories enable row level security;
alter table products enable row level security;
alter table settings enable row level security;

create policy "categorias_lectura_publica" on categories
  for select using (true);
create policy "categorias_escritura_autenticados" on categories
  for insert with check (auth.role() = 'authenticated');
create policy "categorias_actualizacion_autenticados" on categories
  for update using (auth.role() = 'authenticated');
create policy "categorias_borrado_autenticados" on categories
  for delete using (auth.role() = 'authenticated');

create policy "productos_lectura_publica" on products
  for select using (true);
create policy "productos_escritura_autenticados" on products
  for insert with check (auth.role() = 'authenticated');
create policy "productos_actualizacion_autenticados" on products
  for update using (auth.role() = 'authenticated');
create policy "productos_borrado_autenticados" on products
  for delete using (auth.role() = 'authenticated');

create policy "ajustes_lectura_publica" on settings
  for select using (true);
create policy "ajustes_actualizacion_autenticados" on settings
  for update using (auth.role() = 'authenticated');

-- ---------- Storage: bucket para videos de productos ----------
-- Bucket público (cualquiera puede ver/reproducir el video), pero solo un
-- usuario autenticado (el admin) puede subir, reemplazar o borrar archivos.
-- Límite de 20 MB por archivo, solo formatos de video comunes.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-videos',
  'product-videos',
  true,
  20971520,
  array['video/mp4','video/quicktime','video/webm','video/x-matroska']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "videos_lectura_publica" on storage.objects
  for select using (bucket_id = 'product-videos');

create policy "videos_subida_autenticados" on storage.objects
  for insert with check (bucket_id = 'product-videos' and auth.role() = 'authenticated');

create policy "videos_actualizacion_autenticados" on storage.objects
  for update using (bucket_id = 'product-videos' and auth.role() = 'authenticated');

create policy "videos_borrado_autenticados" on storage.objects
  for delete using (bucket_id = 'product-videos' and auth.role() = 'authenticated');
