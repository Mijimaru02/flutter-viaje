-- Initial schema and authorization model for Viaje en Común.
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 80),
  updated_at timestamptz not null default now()
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 1 and 120),
  destination text not null check (length(trim(destination)) between 1 and 120),
  start_date date not null,
  end_date date not null,
  description text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table public.trip_members (
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'editor', 'reader')),
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);
create unique index trip_members_one_owner
  on public.trip_members(trip_id) where role = 'owner';

create or replace function public.prevent_membership_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.trip_id <> old.trip_id or new.user_id <> old.user_id then
    raise exception 'La identidad de una membresía no se puede cambiar';
  end if;
  if old.role = 'owner' then
    raise exception 'No se puede cambiar el rol del propietario';
  end if;
  if new.role not in ('editor', 'reader') then
    raise exception 'Rol de miembro no válido';
  end if;
  return new;
end;
$$;
create trigger trip_members_prevent_identity_change
  before update on public.trip_members
  for each row execute function public.prevent_membership_identity_change();

create table public.trip_invitations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  email text not null,
  role text not null check (role in ('editor', 'reader')),
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_by uuid references public.profiles(id),
  revoked_at timestamptz,
  check ((used_at is null) = (used_by is null))
);

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  created_by uuid not null references public.profiles(id),
  title text not null check (length(trim(title)) between 1 and 160),
  activity_date date not null,
  start_time time not null,
  end_time time,
  category text not null check (
    category in ('transporte', 'alojamiento', 'comida', 'visita', 'tiempo_libre')
  ),
  address text,
  notes text,
  created_at timestamptz not null default now(),
  check (end_time is null or end_time > start_time),
  unique (id, trip_id),
  foreign key (trip_id, created_by)
    references public.trip_members(trip_id, user_id)
);
create index activities_trip_date_time on public.activities(trip_id, activity_date, start_time);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  created_by uuid not null references public.profiles(id),
  paid_by uuid not null,
  title text not null check (length(trim(title)) between 1 and 160),
  amount_cents integer not null check (amount_cents > 0),
  expense_date date not null,
  category text not null check (
    category in ('transporte', 'alojamiento', 'comida', 'visita', 'otros')
  ),
  created_at timestamptz not null default now(),
  unique (id, trip_id),
  foreign key (trip_id, created_by)
    references public.trip_members(trip_id, user_id),
  foreign key (trip_id, paid_by)
    references public.trip_members(trip_id, user_id)
);
create index expenses_trip_date on public.expenses(trip_id, expense_date desc);

create table public.expense_splits (
  expense_id uuid not null,
  trip_id uuid not null,
  user_id uuid not null,
  split_order integer not null check (split_order >= 0),
  amount_cents integer not null check (amount_cents >= 0),
  primary key (expense_id, user_id),
  unique (expense_id, split_order),
  foreign key (expense_id, trip_id)
    references public.expenses(id, trip_id) on delete cascade,
  foreign key (trip_id, user_id)
    references public.trip_members(trip_id, user_id)
);

create table public.trip_documents (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  created_by uuid not null references public.profiles(id),
  title text not null check (length(trim(title)) between 1 and 160),
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  created_at timestamptz not null default now(),
  foreign key (trip_id, created_by)
    references public.trip_members(trip_id, user_id)
);
create index trip_documents_trip_created on public.trip_documents(trip_id, created_at desc);

create or replace function private.is_trip_member(p_trip_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip_id and m.user_id = (select auth.uid())
  );
$$;

create or replace function private.is_trip_owner(p_trip_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip_id
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
  );
$$;

create or replace function private.can_write_trip(p_trip_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trip_members m
    join public.trips t on t.id = m.trip_id
    where m.trip_id = p_trip_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'editor')
      and t.archived_at is null
  );
$$;

create or replace function private.can_edit_trip_content(
  p_trip_id uuid,
  p_created_by uuid
)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.can_write_trip(p_trip_id)
    and (
      private.is_trip_owner(p_trip_id)
      or p_created_by = (select auth.uid())
    );
$$;

create or replace function private.create_profile_for_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'viajero'), '@', 1)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function private.create_profile_for_new_user();

insert into public.profiles(id, display_name)
select
  u.id,
  coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(u.email, 'viajero'), '@', 1)
  )
from auth.users u
on conflict (id) do nothing;

create or replace function public.validate_trip_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.end_date < new.start_date then
    raise exception 'La fecha de fin debe ser igual o posterior a la de inicio';
  end if;
  if old.archived_at is not null
    and new.archived_at is not null
    and (
      new.title, new.destination, new.start_date, new.end_date, new.description
    ) is distinct from (
      old.title, old.destination, old.start_date, old.end_date, old.description
    ) then
    raise exception 'Reactiva el viaje antes de modificar sus datos';
  end if;
  if exists (
    select 1 from public.activities a
    where a.trip_id = old.id
      and (a.activity_date < new.start_date or a.activity_date > new.end_date)
  ) then
    raise exception 'Las nuevas fechas dejarían actividades fuera del viaje';
  end if;
  return new;
end;
$$;

create trigger trips_validate_dates_before_update
  before update on public.trips
  for each row execute function public.validate_trip_update();

create or replace function public.validate_activity_date()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  trip_start date;
  trip_end date;
  trip_archived_at timestamptz;
begin
  select start_date, end_date, archived_at
  into trip_start, trip_end, trip_archived_at
  from public.trips where id = new.trip_id
  for share;
  if trip_archived_at is not null then
    raise exception 'No se pueden modificar actividades de un viaje archivado';
  end if;
  if new.activity_date < trip_start or new.activity_date > trip_end then
    raise exception 'La actividad debe estar dentro de las fechas del viaje';
  end if;
  if new.end_time is not null and new.end_time <= new.start_time then
    raise exception 'La hora de fin debe ser posterior a la de inicio';
  end if;
  return new;
end;
$$;

create trigger activities_validate_date_before_write
  before insert or update on public.activities
  for each row execute function public.validate_activity_date();

create or replace function public.guard_unarchived_trip_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_trip_id uuid;
  trip_archived_at timestamptz;
begin
  if tg_op = 'DELETE' then
    target_trip_id := old.trip_id;
  else
    target_trip_id := new.trip_id;
  end if;

  select archived_at into trip_archived_at
  from public.trips
  where id = target_trip_id
  for share;

  if found and trip_archived_at is not null then
    raise exception 'No se pueden modificar datos de un viaje archivado';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger trip_members_guard_unarchived
  before update or delete on public.trip_members
  for each row execute function public.guard_unarchived_trip_mutation();
create trigger invitations_guard_unarchived
  before insert or update or delete on public.trip_invitations
  for each row execute function public.guard_unarchived_trip_mutation();
create trigger activities_guard_unarchived
  before insert or update or delete on public.activities
  for each row execute function public.guard_unarchived_trip_mutation();
create trigger expenses_guard_unarchived
  before insert or update or delete on public.expenses
  for each row execute function public.guard_unarchived_trip_mutation();
create trigger expense_splits_guard_unarchived
  before insert or update or delete on public.expense_splits
  for each row execute function public.guard_unarchived_trip_mutation();
create trigger documents_guard_unarchived
  before insert or update or delete on public.trip_documents
  for each row execute function public.guard_unarchived_trip_mutation();

create or replace function private.create_trip_core(
  p_title text,
  p_destination text,
  p_start_date date,
  p_end_date date,
  p_description text default null
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  new_trip_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión válida';
  end if;
  if p_end_date < p_start_date then
    raise exception 'La fecha de fin debe ser igual o posterior a la de inicio';
  end if;
  insert into public.trips(title, destination, start_date, end_date, description)
  values (trim(p_title), trim(p_destination), p_start_date, p_end_date, nullif(trim(p_description), ''))
  returning id into new_trip_id;
  insert into public.trip_members(trip_id, user_id, role)
  values (new_trip_id, (select auth.uid()), 'owner');
  return new_trip_id;
end;
$$;

create or replace function private.create_trip_invitation_core(
  p_trip_id uuid,
  p_email text,
  p_role text
)
returns table(token text, expires_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
declare
  raw_token text;
  invite_expiry timestamptz := now() + interval '7 days';
begin
  if not private.is_trip_owner(p_trip_id) then
    raise exception 'Solo el propietario puede invitar miembros';
  end if;
  if not private.can_write_trip(p_trip_id) then
    raise exception 'No se pueden crear invitaciones en un viaje archivado';
  end if;
  if p_role not in ('editor', 'reader') or position('@' in trim(p_email)) < 2 then
    raise exception 'Correo o rol de invitación no válido';
  end if;
  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.trip_invitations(
    trip_id, email, role, token_hash, expires_at, created_by
  )
  values (
    p_trip_id, lower(trim(p_email)), p_role,
    extensions.digest(convert_to(raw_token, 'UTF8'), 'sha256'),
    invite_expiry, (select auth.uid())
  );
  return query select raw_token, invite_expiry;
end;
$$;

create or replace function private.accept_trip_invitation_core(p_token text)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  invite public.trip_invitations%rowtype;
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  trip_archived_at timestamptz;
begin
  if current_user_id is null or p_token is null or length(p_token) < 32 then
    raise exception 'Invitación o sesión no válida';
  end if;
  select * into invite
  from public.trip_invitations i
  where i.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
  for update;
  if not found then
    raise exception 'Invitación no encontrada';
  end if;
  if invite.used_by = current_user_id then
    return 'already_member';
  end if;
  if invite.revoked_at is not null then
    raise exception 'La invitación ha sido revocada';
  end if;
  if invite.expires_at <= now() then
    raise exception 'La invitación ha caducado';
  end if;
  if invite.used_at is not null then
    raise exception 'La invitación ya ha sido utilizada por otra cuenta';
  end if;
  if current_email <> lower(invite.email) then
    raise exception 'La invitación pertenece a otra cuenta';
  end if;
  select t.archived_at into trip_archived_at
  from public.trips t
  where t.id = invite.trip_id
  for share;
  if trip_archived_at is not null then
    raise exception 'No se puede aceptar una invitación a un viaje archivado';
  end if;
  insert into public.trip_members(trip_id, user_id, role)
  values (invite.trip_id, current_user_id, invite.role)
  on conflict (trip_id, user_id) do nothing;
  update public.trip_invitations
  set used_at = now(), used_by = current_user_id
  where id = invite.id;
  return 'joined';
end;
$$;

create or replace function private.revoke_trip_invitation_core(p_invitation_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.trip_invitations i
  set revoked_at = now()
  where i.id = p_invitation_id
    and i.used_at is null
    and i.revoked_at is null
    and private.is_trip_owner(i.trip_id)
    and private.can_write_trip(i.trip_id);
  if not found then
    raise exception 'No se puede revocar la invitación';
  end if;
end;
$$;

create or replace function private.save_expense_core(
  p_expense_id uuid,
  p_trip_id uuid,
  p_title text,
  p_amount_cents integer,
  p_expense_date date,
  p_category text,
  p_paid_by uuid,
  p_splits jsonb
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  expense_id uuid := p_expense_id;
  split_total bigint;
  split_count bigint;
  distinct_count bigint;
  distinct_order_count bigint;
  invalid_order_count bigint;
  existing_creator uuid;
  trip_archived_at timestamptz;
begin
  select t.archived_at into trip_archived_at
  from public.trips t
  where t.id = p_trip_id
  for share;
  if trip_archived_at is not null then
    raise exception 'No se pueden modificar gastos de un viaje archivado';
  end if;
  if (select auth.uid()) is null or not private.can_write_trip(p_trip_id) then
    raise exception 'No tienes permiso para registrar gastos en este viaje';
  end if;
  if p_amount_cents <= 0 or jsonb_typeof(p_splits) <> 'array' then
    raise exception 'Importe o reparto no válido';
  end if;
  select count(*), count(distinct item.user_id),
    count(distinct item.split_order),
    count(*) filter (where item.split_order < 0 or item.amount_cents is null),
    coalesce(sum(item.amount_cents), 0)
  into split_count, distinct_count, distinct_order_count, invalid_order_count, split_total
  from jsonb_to_recordset(p_splits)
    as item(user_id uuid, amount_cents integer, split_order integer);
  if split_count = 0
    or split_count <> distinct_count
    or split_count <> distinct_order_count
    or invalid_order_count > 0
    or split_total <> p_amount_cents then
    raise exception 'El reparto debe contener participantes únicos y sumar el total exacto';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_splits)
      as item(user_id uuid, amount_cents integer, split_order integer)
    where item.amount_cents < 0
      or item.user_id is null
      or not exists (
        select 1 from public.trip_members m
        where m.trip_id = p_trip_id and m.user_id = item.user_id
      )
  ) then
    raise exception 'El reparto contiene importes o miembros no válidos';
  end if;
  if not exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip_id and m.user_id = p_paid_by
  ) then
    raise exception 'La persona pagadora no pertenece al viaje';
  end if;

  if expense_id is null then
    insert into public.expenses(
      trip_id, created_by, paid_by, title, amount_cents, expense_date, category
    )
    values (
      p_trip_id, (select auth.uid()), p_paid_by, trim(p_title),
      p_amount_cents, p_expense_date, p_category
    )
    returning id into expense_id;
  else
    select e.created_by into existing_creator
    from public.expenses e
    where e.id = expense_id and e.trip_id = p_trip_id
    for update;
    if not found or not private.can_edit_trip_content(p_trip_id, existing_creator) then
      raise exception 'No tienes permiso para editar este gasto';
    end if;
    update public.expenses
    set paid_by = p_paid_by,
        title = trim(p_title),
        amount_cents = p_amount_cents,
        expense_date = p_expense_date,
        category = p_category
    where id = expense_id and trip_id = p_trip_id;
    delete from public.expense_splits where expense_id = p_expense_id;
  end if;

  insert into public.expense_splits(
    expense_id, trip_id, user_id, split_order, amount_cents
  )
  select expense_id, p_trip_id, item.user_id, item.split_order, item.amount_cents
  from jsonb_to_recordset(p_splits)
    as item(user_id uuid, amount_cents integer, split_order integer);
  return expense_id;
end;
$$;

create or replace function public.create_trip(
  p_title text,
  p_destination text,
  p_start_date date,
  p_end_date date,
  p_description text default null
)
returns uuid
language sql security invoker
set search_path = ''
as $$
  select private.create_trip_core(
    p_title, p_destination, p_start_date, p_end_date, p_description
  );
$$;

create or replace function public.create_trip_invitation(
  p_trip_id uuid,
  p_email text,
  p_role text
)
returns table(token text, expires_at timestamptz)
language sql security invoker
set search_path = ''
as $$
  select * from private.create_trip_invitation_core(p_trip_id, p_email, p_role);
$$;

create or replace function public.accept_trip_invitation(p_token text)
returns text
language sql security invoker
set search_path = ''
as $$
  select private.accept_trip_invitation_core(p_token);
$$;

create or replace function public.revoke_trip_invitation(p_invitation_id uuid)
returns void
language sql security invoker
set search_path = ''
as $$
  select private.revoke_trip_invitation_core(p_invitation_id);
$$;

create or replace function public.save_expense(
  p_expense_id uuid,
  p_trip_id uuid,
  p_title text,
  p_amount_cents integer,
  p_expense_date date,
  p_category text,
  p_paid_by uuid,
  p_splits jsonb
)
returns uuid
language sql security invoker
set search_path = ''
as $$
  select private.save_expense_core(
    p_expense_id, p_trip_id, p_title, p_amount_cents,
    p_expense_date, p_category, p_paid_by, p_splits
  );
$$;

create or replace function private.delete_expense_core(
  p_expense_id uuid,
  p_trip_id uuid
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  existing_creator uuid;
  trip_archived_at timestamptz;
begin
  select t.archived_at into trip_archived_at
  from public.trips t
  where t.id = p_trip_id
  for share;
  if not found or trip_archived_at is not null then
    raise exception 'No se pueden modificar gastos de un viaje archivado';
  end if;
  if not private.can_write_trip(p_trip_id) then
    raise exception 'No tienes permiso para eliminar gastos de este viaje';
  end if;
  select e.created_by into existing_creator
  from public.expenses e
  where e.id = p_expense_id and e.trip_id = p_trip_id
  for update;
  if not found or not private.can_edit_trip_content(p_trip_id, existing_creator) then
    raise exception 'No tienes permiso para eliminar este gasto';
  end if;
  delete from public.expenses
  where id = p_expense_id and trip_id = p_trip_id;
end;
$$;

create or replace function public.delete_expense(
  p_expense_id uuid,
  p_trip_id uuid
)
returns void
language sql security invoker
set search_path = ''
as $$
  select private.delete_expense_core(p_expense_id, p_trip_id);
$$;

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_invitations enable row level security;
alter table public.activities enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_splits enable row level security;
alter table public.trip_documents enable row level security;

create policy "Profiles visible to self or fellow trip members"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.trip_members mine
      join public.trip_members theirs on theirs.trip_id = mine.trip_id
      where mine.user_id = (select auth.uid()) and theirs.user_id = profiles.id
    )
  );
create policy "Users update own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "Members read trips"
  on public.trips for select to authenticated
  using (private.is_trip_member(id));
create policy "Owners update trips"
  on public.trips for update to authenticated
  using (private.is_trip_owner(id))
  with check (private.is_trip_owner(id));

create policy "Members read memberships"
  on public.trip_members for select to authenticated
  using (private.is_trip_member(trip_id));
create policy "Owners change member roles"
  on public.trip_members for update to authenticated
  using (private.is_trip_owner(trip_id) and private.can_write_trip(trip_id))
  with check (
    private.is_trip_owner(trip_id)
    and private.can_write_trip(trip_id)
    and role in ('editor', 'reader')
  );

create policy "Owners read invitations"
  on public.trip_invitations for select to authenticated
  using (private.is_trip_owner(trip_id));

create policy "Members read activities"
  on public.activities for select to authenticated
  using (private.is_trip_member(trip_id));
create policy "Editors create activities"
  on public.activities for insert to authenticated
  with check (
    private.can_write_trip(trip_id)
    and created_by = (select auth.uid())
  );
create policy "Owners or authors edit activities"
  on public.activities for update to authenticated
  using (private.can_edit_trip_content(trip_id, created_by))
  with check (
    private.can_edit_trip_content(trip_id, created_by)
    and (
      created_by = (select auth.uid())
      or private.is_trip_owner(trip_id)
    )
  );
create policy "Owners or authors delete activities"
  on public.activities for delete to authenticated
  using (private.can_edit_trip_content(trip_id, created_by));

create policy "Members read expenses"
  on public.expenses for select to authenticated
  using (private.is_trip_member(trip_id));
create policy "Members read splits"
  on public.expense_splits for select to authenticated
  using (private.is_trip_member(trip_id));
create policy "Members read trip documents"
  on public.trip_documents for select to authenticated
  using (private.is_trip_member(trip_id));
create policy "Editors create document metadata"
  on public.trip_documents for insert to authenticated
  with check (
    private.can_write_trip(trip_id)
    and created_by = (select auth.uid())
  );
create policy "Owners or authors delete document metadata"
  on public.trip_documents for delete to authenticated
  using (private.can_edit_trip_content(trip_id, created_by));
create policy "Owners or authors edit document titles"
  on public.trip_documents for update to authenticated
  using (private.can_edit_trip_content(trip_id, created_by))
  with check (
    private.can_edit_trip_content(trip_id, created_by)
    and (
      created_by = (select auth.uid())
      or private.is_trip_owner(trip_id)
    )
  );

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'trip-documents',
  'trip-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png'];

create policy "Trip members read stored documents"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'trip-documents'
    and private.is_trip_member(
      case
        when split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end
    )
  );
create policy "Trip editors upload documents"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'trip-documents'
    and private.can_write_trip(
      case
        when split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end
    )
    and case
      when split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(name, '/', 2)::uuid = (select auth.uid())
      else false
    end
  );
create policy "Trip owners or document authors delete stored files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'trip-documents'
    and private.can_edit_trip_content(
      case
        when split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 1)::uuid
        else null
      end,
      case
        when split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(name, '/', 2)::uuid
        else null
      end
    )
  );

revoke all on function public.create_trip(text, text, date, date, text) from public;
revoke all on function public.create_trip_invitation(uuid, text, text) from public;
revoke all on function public.accept_trip_invitation(text) from public;
revoke all on function public.revoke_trip_invitation(uuid) from public;
revoke all on function public.save_expense(uuid, uuid, text, integer, date, text, uuid, jsonb) from public;
revoke all on function public.delete_expense(uuid, uuid) from public;
grant execute on function public.create_trip(text, text, date, date, text) to authenticated;
grant execute on function public.create_trip_invitation(uuid, text, text) to authenticated;
grant execute on function public.accept_trip_invitation(text) to authenticated;
grant execute on function public.revoke_trip_invitation(uuid) to authenticated;
grant execute on function public.save_expense(uuid, uuid, text, integer, date, text, uuid, jsonb) to authenticated;
grant execute on function public.delete_expense(uuid, uuid) to authenticated;

grant usage on schema private to authenticated;
grant execute on function private.is_trip_member(uuid) to authenticated;
grant execute on function private.is_trip_owner(uuid) to authenticated;
grant execute on function private.can_write_trip(uuid) to authenticated;
grant execute on function private.can_edit_trip_content(uuid, uuid) to authenticated;
grant execute on function private.create_trip_core(text, text, date, date, text) to authenticated;
grant execute on function private.create_trip_invitation_core(uuid, text, text) to authenticated;
grant execute on function private.accept_trip_invitation_core(text) to authenticated;
grant execute on function private.revoke_trip_invitation_core(uuid) to authenticated;
grant execute on function private.save_expense_core(uuid, uuid, text, integer, date, text, uuid, jsonb) to authenticated;
grant execute on function private.delete_expense_core(uuid, uuid) to authenticated;
grant usage on schema private to supabase_auth_admin;
grant execute on function private.create_profile_for_new_user() to supabase_auth_admin;

grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant select on public.trips to authenticated;
grant update (title, destination, start_date, end_date, description, archived_at)
  on public.trips to authenticated;
grant select on public.trip_members to authenticated;
grant update (role) on public.trip_members to authenticated;
grant select on public.trip_invitations to authenticated;
grant select, insert, update, delete on public.activities to authenticated;
grant select on public.expenses, public.expense_splits to authenticated;
grant select, insert, delete on public.trip_documents to authenticated;
grant update (title) on public.trip_documents to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.activities;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;
