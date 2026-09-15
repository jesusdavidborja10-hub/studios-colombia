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

-- ============================================================
-- CUENTAS DE CLIENTE + SEGURIDAD ADMIN vs CLIENTE
-- ============================================================
-- Hasta ahora, "estar logueado" (auth.role() = 'authenticated') era suficiente
-- para editar el catálogo, porque el único que iniciaba sesión eras tú. Ahora que
-- los CLIENTES también pueden crear cuenta e iniciar sesión, esa regla ya no es
-- segura: cualquier cliente logueado podría editar productos/categorías/ajustes.
-- Por eso creamos una tabla "admins" y una función is_admin(), y cambiamos las
-- reglas de escritura del catálogo para que dependan de estar en esa tabla, no
-- solo de tener sesión iniciada.

create table if not exists admins (
  id uuid primary key references auth.users(id) on delete cascade
);
alter table admins enable row level security;

-- Un usuario puede consultar SOLO si su propia cuenta está en la tabla (para que
-- la tienda sepa si debe mostrarle el panel de admin), pero no puede ver ni
-- modificar la lista de administradores.
drop policy if exists "admins_lectura_propia" on admins;
create policy "admins_lectura_propia" on admins
  for select using (id = auth.uid());

create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from admins where id = auth.uid());
$$;

-- Reemplaza las reglas de escritura del catálogo: de "autenticado" a "admin real".
-- (drop ... if exists por si ya corriste esta parte antes, o si la política
-- original nunca llegó a crearse con ese nombre exacto)
drop policy if exists "categorias_escritura_autenticados" on categories;
drop policy if exists "categorias_actualizacion_autenticados" on categories;
drop policy if exists "categorias_borrado_autenticados" on categories;
drop policy if exists "categorias_escritura_admin" on categories;
drop policy if exists "categorias_actualizacion_admin" on categories;
drop policy if exists "categorias_borrado_admin" on categories;
create policy "categorias_escritura_admin" on categories
  for insert with check (is_admin());
create policy "categorias_actualizacion_admin" on categories
  for update using (is_admin());
create policy "categorias_borrado_admin" on categories
  for delete using (is_admin());

drop policy if exists "productos_escritura_autenticados" on products;
drop policy if exists "productos_actualizacion_autenticados" on products;
drop policy if exists "productos_borrado_autenticados" on products;
drop policy if exists "productos_escritura_admin" on products;
drop policy if exists "productos_actualizacion_admin" on products;
drop policy if exists "productos_borrado_admin" on products;
create policy "productos_escritura_admin" on products
  for insert with check (is_admin());
create policy "productos_actualizacion_admin" on products
  for update using (is_admin());
create policy "productos_borrado_admin" on products
  for delete using (is_admin());

drop policy if exists "ajustes_actualizacion_autenticados" on settings;
drop policy if exists "ajustes_actualizacion_admin" on settings;
create policy "ajustes_actualizacion_admin" on settings
  for update using (is_admin());

drop policy if exists "videos_subida_autenticados" on storage.objects;
drop policy if exists "videos_actualizacion_autenticados" on storage.objects;
drop policy if exists "videos_borrado_autenticados" on storage.objects;
drop policy if exists "videos_subida_admin" on storage.objects;
drop policy if exists "videos_actualizacion_admin" on storage.objects;
drop policy if exists "videos_borrado_admin" on storage.objects;
create policy "videos_subida_admin" on storage.objects
  for insert with check (bucket_id = 'product-videos' and is_admin());
create policy "videos_actualizacion_admin" on storage.objects
  for update using (bucket_id = 'product-videos' and is_admin());
create policy "videos_borrado_admin" on storage.objects
  for delete using (bucket_id = 'product-videos' and is_admin());

-- ---------- Perfil del cliente (nombre y WhatsApp guardados) ----------
create table if not exists customer_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  whatsapp text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table customer_profiles enable row level security;

drop policy if exists "perfil_lectura_propia" on customer_profiles;
drop policy if exists "perfil_escritura_propia" on customer_profiles;
drop policy if exists "perfil_actualizacion_propia" on customer_profiles;
create policy "perfil_lectura_propia" on customer_profiles
  for select using (id = auth.uid());
create policy "perfil_escritura_propia" on customer_profiles
  for insert with check (id = auth.uid());
create policy "perfil_actualizacion_propia" on customer_profiles
  for update using (id = auth.uid());

-- ---------- Pedidos (historial de compras + carrito pendiente) ----------
-- status = 'cart'          -> carrito guardado, todavía no enviado/pagado
-- status = 'whatsapp_sent' -> el cliente presionó "Enviar pedido por WhatsApp"
-- status = 'paypal_paid'   -> pago confirmado con PayPal
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  items jsonb not null default '[]'::jsonb,
  total numeric not null default 0,
  status text not null default 'cart' check (status in ('cart','whatsapp_sent','paypal_paid')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Como mucho un carrito "activo" (status='cart') por cliente a la vez.
create unique index if not exists orders_carrito_unico_por_cliente on orders(customer_id) where status = 'cart';

alter table orders enable row level security;
drop policy if exists "pedidos_lectura_propia" on orders;
drop policy if exists "pedidos_escritura_propia" on orders;
drop policy if exists "pedidos_actualizacion_propia" on orders;
create policy "pedidos_lectura_propia" on orders
  for select using (customer_id = auth.uid());
create policy "pedidos_escritura_propia" on orders
  for insert with check (customer_id = auth.uid());
create policy "pedidos_actualizacion_propia" on orders
  for update using (customer_id = auth.uid());

-- ============================================================
-- PERSONALIZADOS Y PRECIOS (animaciones a la medida)
-- ============================================================
-- Mismo patrón de seguridad que "products": lectura pública para
-- cualquier visitante, escritura (insert/update/delete) solo para
-- administradores reales (tabla "admins" + función is_admin(), ya
-- creada más arriba en este archivo).

create table if not exists custom_options (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  price numeric not null,
  video_url text,
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table custom_options enable row level security;

drop policy if exists "personalizados_lectura_publica" on custom_options;
drop policy if exists "personalizados_escritura_admin" on custom_options;
drop policy if exists "personalizados_actualizacion_admin" on custom_options;
drop policy if exists "personalizados_borrado_admin" on custom_options;

create policy "personalizados_lectura_publica" on custom_options
  for select using (true);
create policy "personalizados_escritura_admin" on custom_options
  for insert with check (is_admin());
create policy "personalizados_actualizacion_admin" on custom_options
  for update using (is_admin());
create policy "personalizados_borrado_admin" on custom_options
  for delete using (is_admin());

-- ---------- Márcate a ti mismo como administrador ----------
-- ⚠️ MUY IMPORTANTE: reemplaza el correo de abajo por el correo EXACTO con el
-- que inicias sesión en "Modo administrador" en la tienda, y corre este bloque
-- UNA SOLA VEZ. Si no corres esto, perderás la capacidad de editar el catálogo
-- (nadie va a cumplir is_admin() todavía).
insert into admins (id)
select id from auth.users where email = 'TU-CORREO-DE-ADMIN-AQUI@ejemplo.com'
on conflict (id) do nothing;
