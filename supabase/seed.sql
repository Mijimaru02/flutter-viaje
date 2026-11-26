do $$
declare
  lucia_id uuid;
  ana_id uuid;
  marcos_id uuid;
  shared_trip_id uuid := '00000000-0000-4000-8000-000000000001';
  private_trip_id uuid := '00000000-0000-4000-8000-000000000002';
  lodging_id uuid := '00000000-0000-4000-8000-000000000010';
  transport_id uuid := '00000000-0000-4000-8000-000000000011';
begin
  select id into lucia_id from auth.users where lower(email) = 'lucia@viaje.test';
  select id into ana_id from auth.users where lower(email) = 'ana@viaje.test';
  select id into marcos_id from auth.users where lower(email) = 'marcos@viaje.test';

  if lucia_id is null or ana_id is null or marcos_id is null then
    raise exception
      'Crea primero las cuentas lucia@viaje.test, ana@viaje.test y marcos@viaje.test en Supabase Auth';
  end if;

  insert into public.profiles(id, display_name)
  values
    (lucia_id, 'Lucía'),
    (ana_id, 'Ana'),
    (marcos_id, 'Marcos')
  on conflict (id) do nothing;

  insert into public.trips(
    id, title, destination, start_date, end_date, description
  )
  values
    (
      shared_trip_id, 'Escapada a Lisboa', 'Lisboa',
      date '2027-05-01', date '2027-05-03',
      'Viaje de demostración compartido'
    ),
    (
      private_trip_id, 'Fin de semana en Roma', 'Roma',
      date '2027-06-12', date '2027-06-14',
      'Viaje privado de Lucía'
    )
  on conflict (id) do nothing;

  insert into public.trip_members(trip_id, user_id, role)
  values
    (shared_trip_id, lucia_id, 'owner'),
    (shared_trip_id, ana_id, 'editor'),
    (shared_trip_id, marcos_id, 'reader'),
    (private_trip_id, lucia_id, 'owner')
  on conflict (trip_id, user_id) do nothing;

  insert into public.activities(
    id, trip_id, created_by, title, activity_date,
    start_time, end_time, category, address, notes
  )
  values (
    '00000000-0000-4000-8000-000000000020',
    shared_trip_id, ana_id, 'Visita a Belém',
    date '2027-05-02', time '10:00', time '12:00',
    'visita', 'Belém, Lisboa', 'Actividad de ejemplo'
  )
  on conflict (id) do nothing;

  insert into public.expenses(
    id, trip_id, created_by, paid_by, title,
    amount_cents, expense_date, category
  )
  values
    (
      lodging_id, shared_trip_id, ana_id, ana_id, 'Alojamiento',
      12000, date '2027-05-01', 'alojamiento'
    ),
    (
      transport_id, shared_trip_id, ana_id, marcos_id, 'Transporte',
      3000, date '2027-05-02', 'transporte'
    )
  on conflict (id) do nothing;

  insert into public.expense_splits(
    expense_id, trip_id, user_id, split_order, amount_cents
  )
  values
    (lodging_id, shared_trip_id, ana_id, 0, 4000),
    (lodging_id, shared_trip_id, marcos_id, 1, 4000),
    (lodging_id, shared_trip_id, lucia_id, 2, 4000),
    (transport_id, shared_trip_id, marcos_id, 0, 1500),
    (transport_id, shared_trip_id, lucia_id, 1, 1500)
  on conflict (expense_id, user_id) do nothing;
end;
$$;
