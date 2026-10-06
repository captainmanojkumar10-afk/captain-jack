-- Smart Parking Automation schema
-- Run this file in the Supabase SQL Editor for the project configured in Replit.
-- Never put a Supabase service-role key in the browser application.

create extension if not exists pgcrypto;

do $$ begin
  create type public.profile_role as enum ('USER', 'ADMIN');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.slot_status as enum ('AVAILABLE', 'RESERVED', 'OCCUPIED', 'MAINTENANCE', 'OFFLINE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.slot_type as enum ('STANDARD', 'EV', 'ACCESSIBLE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.sensor_status as enum ('ONLINE', 'OFFLINE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vehicle_type as enum ('CAR', 'MOTORCYCLE', 'SUV', 'VAN');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.reservation_status as enum ('CONFIRMED', 'CANCELLED', 'EXPIRED', 'COMPLETED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.session_status as enum ('ACTIVE', 'COMPLETED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_status as enum ('PENDING', 'PAID', 'FAILED', 'REFUNDED');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text not null default '',
  role public.profile_role not null default 'USER',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parking_lots (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  timezone text not null default 'Asia/Kolkata',
  hourly_rate numeric(10,2) not null default 30 check (hourly_rate >= 0),
  additional_hour_rate numeric(10,2) not null default 20 check (additional_hour_rate >= 0),
  daily_cap numeric(10,2) not null default 200 check (daily_cap >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parking_slots (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.parking_lots(id) on delete cascade,
  slot_number text not null,
  slot_type public.slot_type not null default 'STANDARD',
  status public.slot_status not null default 'AVAILABLE',
  sensor_status public.sensor_status not null default 'ONLINE',
  sensor_id text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (lot_id, slot_number)
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  license_plate text not null,
  vehicle_type public.vehicle_type not null default 'CAR',
  model text not null default '',
  is_ev boolean not null default false,
  accessibility_required boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, license_plate)
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  booking_code text not null unique,
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  lot_id uuid not null references public.parking_lots(id) on delete restrict,
  slot_id uuid not null references public.parking_slots(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.reservation_status not null default 'CONFIRMED',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.parking_sessions (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid references public.reservations(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  lot_id uuid not null references public.parking_lots(id) on delete restrict,
  slot_id uuid not null references public.parking_slots(id) on delete restrict,
  entry_at timestamptz not null default now(),
  exit_at timestamptz,
  status public.session_status not null default 'ACTIVE',
  amount_due numeric(10,2),
  created_at timestamptz not null default now(),
  check ((status = 'ACTIVE' and exit_at is null) or (status = 'COMPLETED' and exit_at is not null))
);

create table if not exists public.gate_events (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid references public.reservations(id) on delete set null,
  session_id uuid references public.parking_sessions(id) on delete set null,
  user_id uuid references public.profiles(id) on delete set null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  lot_id uuid references public.parking_lots(id) on delete set null,
  slot_id uuid references public.parking_slots(id) on delete set null,
  event_type text not null check (event_type in ('ENTRY', 'EXIT')),
  event_at timestamptz not null default now(),
  booking_code text,
  source text not null default 'MANUAL'
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.parking_sessions(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(10,2) not null check (amount >= 0),
  status public.payment_status not null default 'PENDING',
  method text not null default 'MOCK',
  receipt_number text not null unique default ('SP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  type text not null default 'INFO',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.pricing_rules (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.parking_lots(id) on delete cascade,
  first_hour_rate numeric(10,2) not null default 30 check (first_hour_rate >= 0),
  additional_hour_rate numeric(10,2) not null default 20 check (additional_hour_rate >= 0),
  daily_maximum numeric(10,2) not null default 200 check (daily_maximum >= 0),
  currency text not null default 'INR',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  unique (lot_id)
);

create or replace function public.sync_pricing_rule_to_lot()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.parking_lots
  set hourly_rate = new.first_hour_rate,
      additional_hour_rate = new.additional_hour_rate,
      daily_cap = new.daily_maximum
  where id = new.lot_id;
  return new;
end;
$$;

drop trigger if exists pricing_rules_sync_lot on public.pricing_rules;
create trigger pricing_rules_sync_lot
after insert or update on public.pricing_rules
for each row execute function public.sync_pricing_rule_to_lot();

create table if not exists public.sensor_devices (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.parking_lots(id) on delete cascade,
  slot_id uuid references public.parking_slots(id) on delete set null,
  device_name text not null,
  device_code text not null unique,
  status public.sensor_status not null default 'ONLINE',
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists parking_slots_lot_status_idx on public.parking_slots(lot_id, status);
create index if not exists reservations_user_starts_idx on public.reservations(user_id, starts_at desc);
create index if not exists reservations_slot_status_idx on public.reservations(slot_id, status);
create index if not exists parking_sessions_user_entry_idx on public.parking_sessions(user_id, entry_at desc);
create index if not exists parking_sessions_slot_active_idx on public.parking_sessions(slot_id) where status = 'ACTIVE';
create unique index if not exists one_active_session_per_slot_idx on public.parking_sessions(slot_id) where status = 'ACTIVE';
create index if not exists gate_events_event_at_idx on public.gate_events(event_at desc);
create index if not exists payments_user_created_idx on public.payments(user_id, created_at desc);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists lots_set_updated_at on public.parking_lots;
create trigger lots_set_updated_at before update on public.parking_lots
for each row execute function public.set_updated_at();
drop trigger if exists slots_set_updated_at on public.parking_slots;
create trigger slots_set_updated_at before update on public.parking_slots
for each row execute function public.set_updated_at();
drop trigger if exists vehicles_set_updated_at on public.vehicles;
create trigger vehicles_set_updated_at before update on public.vehicles
for each row execute function public.set_updated_at();
drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at before update on public.reservations
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'ADMIN'
  );
$$;

create or replace function public.create_reservation(
  p_lot_id uuid,
  p_vehicle_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_preferred_slot_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_vehicle public.vehicles%rowtype;
  v_slot public.parking_slots%rowtype;
  v_reservation public.reservations%rowtype;
  v_booking_code text;
begin
  if v_user_id is null then raise exception 'Sign in to reserve a parking slot'; end if;
  if p_starts_at < now() or p_ends_at <= p_starts_at then
    raise exception 'Choose a valid future parking time';
  end if;
  if p_ends_at - p_starts_at > interval '24 hours' then
    raise exception 'A reservation cannot exceed 24 hours';
  end if;

  select * into v_vehicle from public.vehicles
  where id = p_vehicle_id and user_id = v_user_id;
  if not found then raise exception 'Choose one of your registered vehicles'; end if;

  select s.* into v_slot
  from public.parking_slots s
  join public.parking_lots l on l.id = s.lot_id
  where s.lot_id = p_lot_id
    and l.is_active
    and s.status = 'AVAILABLE'
    and (p_preferred_slot_id is null or s.id = p_preferred_slot_id)
    and (not v_vehicle.is_ev or s.slot_type = 'EV')
    and (not v_vehicle.accessibility_required or s.slot_type = 'ACCESSIBLE')
  order by case when p_preferred_slot_id is not null and s.id = p_preferred_slot_id then 0 else 1 end,
           s.slot_number
  limit 1
  for update of s skip locked;
  if not found then raise exception 'No suitable available slot was found. Refresh availability and try again.'; end if;

  v_booking_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.reservations (
    booking_code, user_id, vehicle_id, lot_id, slot_id, starts_at, ends_at, status
  ) values (
    v_booking_code, v_user_id, p_vehicle_id, p_lot_id, v_slot.id, p_starts_at, p_ends_at, 'CONFIRMED'
  ) returning * into v_reservation;

  update public.parking_slots set status = 'RESERVED' where id = v_slot.id;
  insert into public.notifications (user_id, title, message, type)
  values (v_user_id, 'Reservation confirmed', 'Your booking ' || v_booking_code || ' is confirmed for slot ' || v_slot.slot_number || '.', 'RESERVATION');
  return to_jsonb(v_reservation);
end;
$$;

create or replace function public.cancel_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.reservations%rowtype;
begin
  select * into v_reservation
  from public.reservations
  where id = p_reservation_id
    and (user_id = auth.uid() or public.is_admin())
  for update;
  if not found then raise exception 'Reservation not found'; end if;
  if v_reservation.status <> 'CONFIRMED' then raise exception 'This reservation can no longer be cancelled'; end if;
  if v_reservation.starts_at <= now() then raise exception 'Reservations can only be cancelled before their start time'; end if;

  update public.reservations set status = 'CANCELLED' where id = p_reservation_id returning * into v_reservation;
  update public.parking_slots set status = 'AVAILABLE'
  where id = v_reservation.slot_id and status = 'RESERVED';
  insert into public.notifications (user_id, title, message, type)
  values (v_reservation.user_id, 'Reservation cancelled', 'Booking ' || v_reservation.booking_code || ' has been cancelled.', 'RESERVATION');
  return to_jsonb(v_reservation);
end;
$$;

create or replace function public.admin_set_slot_status(p_slot_id uuid, p_status public.slot_status)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot public.parking_slots%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  update public.parking_slots set status = p_status
  where id = p_slot_id returning * into v_slot;
  if not found then raise exception 'Parking slot not found'; end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'SLOT_STATUS_CHANGED', 'parking_slot', v_slot.id, jsonb_build_object('status', p_status));
  return to_jsonb(v_slot);
end;
$$;

create or replace function public.admin_set_sensor_status(p_slot_id uuid, p_status public.sensor_status)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot public.parking_slots%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  update public.parking_slots
  set sensor_status = p_status,
      status = case
        when p_status = 'OFFLINE' and status = 'AVAILABLE' then 'OFFLINE'::public.slot_status
        when p_status = 'ONLINE' and status = 'OFFLINE' then 'AVAILABLE'::public.slot_status
        else status
      end
  where id = p_slot_id returning * into v_slot;
  if not found then raise exception 'Parking slot not found'; end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'SENSOR_STATUS_CHANGED', 'parking_slot', v_slot.id, jsonb_build_object('sensor_status', p_status));
  return to_jsonb(v_slot);
end;
$$;

create or replace function public.check_in_reservation(p_booking_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.reservations%rowtype;
  v_session public.parking_sessions%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select * into v_reservation
  from public.reservations
  where booking_code = upper(trim(p_booking_code)) and status = 'CONFIRMED'
  for update;
  if not found then raise exception 'No active reservation matches this booking ID'; end if;
  if v_reservation.ends_at <= now() then raise exception 'This reservation has expired'; end if;

  insert into public.parking_sessions (reservation_id, user_id, vehicle_id, lot_id, slot_id)
  values (v_reservation.id, v_reservation.user_id, v_reservation.vehicle_id, v_reservation.lot_id, v_reservation.slot_id)
  returning * into v_session;
  update public.parking_slots set status = 'OCCUPIED' where id = v_reservation.slot_id;
  insert into public.gate_events (reservation_id, session_id, user_id, vehicle_id, lot_id, slot_id, event_type, booking_code)
  values (v_reservation.id, v_session.id, v_reservation.user_id, v_reservation.vehicle_id, v_reservation.lot_id, v_reservation.slot_id, 'ENTRY', v_reservation.booking_code);
  insert into public.notifications (user_id, title, message, type)
  values (v_reservation.user_id, 'Vehicle checked in', 'Your vehicle is parked in slot ' || (select slot_number from public.parking_slots where id = v_reservation.slot_id) || '.', 'ENTRY');
  return to_jsonb(v_session);
end;
$$;

create or replace function public.check_out_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.parking_sessions%rowtype;
  v_lot public.parking_lots%rowtype;
  v_elapsed_minutes integer;
  v_hours integer;
  v_days integer;
  v_amount numeric(10,2);
  v_payment public.payments%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select * into v_session from public.parking_sessions
  where id = p_session_id and status = 'ACTIVE'
  for update;
  if not found then raise exception 'Active parking session not found'; end if;

  select * into v_lot from public.parking_lots where id = v_session.lot_id;
  v_elapsed_minutes := greatest(1, ceil(extract(epoch from (now() - v_session.entry_at)) / 60.0)::integer);
  v_hours := greatest(1, ceil(v_elapsed_minutes / 60.0)::integer);
  v_days := greatest(1, ceil(v_hours / 24.0)::integer);
  v_amount := least(
    v_days * v_lot.daily_cap,
    v_lot.hourly_rate + greatest(0, v_hours - 1) * v_lot.additional_hour_rate
  );

  update public.parking_sessions
  set status = 'COMPLETED', exit_at = now(), amount_due = v_amount
  where id = v_session.id returning * into v_session;
  if v_session.reservation_id is not null then
    update public.reservations set status = 'COMPLETED' where id = v_session.reservation_id;
  end if;
  update public.parking_slots set status = 'AVAILABLE' where id = v_session.slot_id;
  insert into public.gate_events (reservation_id, session_id, user_id, vehicle_id, lot_id, slot_id, event_type)
  values (v_session.reservation_id, v_session.id, v_session.user_id, v_session.vehicle_id, v_session.lot_id, v_session.slot_id, 'EXIT');
  insert into public.payments (session_id, user_id, amount, status, method)
  values (v_session.id, v_session.user_id, v_amount, 'PENDING', 'MOCK')
  returning * into v_payment;
  insert into public.notifications (user_id, title, message, type)
  values (v_session.user_id, 'Parking session complete', 'Your parking fee is ₹' || v_amount::text || '. Complete the mock payment to receive your receipt.', 'EXIT');
  return jsonb_build_object('session', to_jsonb(v_session), 'payment', to_jsonb(v_payment));
end;
$$;

create or replace function public.simulate_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  update public.payments set status = 'PAID', paid_at = now()
  where id = p_payment_id and user_id = auth.uid() and status = 'PENDING'
  returning * into v_payment;
  if not found then raise exception 'Payment not found or already completed'; end if;
  insert into public.notifications (user_id, title, message, type)
  values (v_payment.user_id, 'Payment confirmed', 'Receipt ' || v_payment.receipt_number || ' is ready.', 'PAYMENT');
  return to_jsonb(v_payment);
end;
$$;

create or replace function public.expire_reservations_internal()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_reservation public.reservations%rowtype;
begin
  v_count := 0;
  for v_reservation in
    update public.reservations
    set status = 'EXPIRED'
    where status = 'CONFIRMED' and ends_at <= now()
    returning *
  loop
    update public.parking_slots
    set status = 'AVAILABLE'
    where id = v_reservation.slot_id and status = 'RESERVED';
    insert into public.notifications (user_id, title, message, type)
    values (
      v_reservation.user_id,
      'Reservation expired',
      'Booking ' || v_reservation.booking_code || ' has expired.',
      'RESERVATION'
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.expire_reservations_internal() from public, anon, authenticated;

create or replace function public.expire_reservations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return public.expire_reservations_internal();
end;
$$;

alter table public.profiles enable row level security;
alter table public.parking_lots enable row level security;
alter table public.parking_slots enable row level security;
alter table public.vehicles enable row level security;
alter table public.reservations enable row level security;
alter table public.parking_sessions enable row level security;
alter table public.gate_events enable row level security;
alter table public.payments enable row level security;
alter table public.notifications enable row level security;
alter table public.pricing_rules enable row level security;
alter table public.sensor_devices enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "profiles read self or admin" on public.profiles;
create policy "profiles read self or admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.is_admin());
drop policy if exists "profiles update self" on public.profiles;
create policy "profiles update self" on public.profiles for update to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke update on public.profiles from authenticated;
grant update (full_name, phone, updated_at) on public.profiles to authenticated;

drop policy if exists "active facilities visible" on public.parking_lots;
create policy "active facilities visible" on public.parking_lots for select to anon, authenticated
using (is_active or public.is_admin());
drop policy if exists "admin manages facilities" on public.parking_lots;
create policy "admin manages facilities" on public.parking_lots for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "parking availability visible" on public.parking_slots;
create policy "parking availability visible" on public.parking_slots for select to anon, authenticated
using (true);
drop policy if exists "admin manages parking slots" on public.parking_slots;
create policy "admin manages parking slots" on public.parking_slots for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users manage own vehicles" on public.vehicles;
create policy "users manage own vehicles" on public.vehicles for all to authenticated
using (user_id = (select auth.uid()) or public.is_admin())
with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "users read own reservations" on public.reservations;
create policy "users read own reservations" on public.reservations for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "admins manage reservations" on public.reservations;
create policy "admins manage reservations" on public.reservations for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users read own sessions" on public.parking_sessions;
create policy "users read own sessions" on public.parking_sessions for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "admins read all sessions" on public.parking_sessions;
create policy "admins read all sessions" on public.parking_sessions for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users read own gate events" on public.gate_events;
create policy "users read own gate events" on public.gate_events for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "admins manage gate events" on public.gate_events;
create policy "admins manage gate events" on public.gate_events for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users read own payments" on public.payments;
create policy "users read own payments" on public.payments for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "admins read all payments" on public.payments;
create policy "admins read all payments" on public.payments for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users manage own notifications" on public.notifications;
create policy "users manage own notifications" on public.notifications for all to authenticated
using (user_id = (select auth.uid()) or public.is_admin())
with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "active pricing visible" on public.pricing_rules;
create policy "active pricing visible" on public.pricing_rules for select to anon, authenticated
using (true);
drop policy if exists "admins manage pricing" on public.pricing_rules;
create policy "admins manage pricing" on public.pricing_rules for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins manage sensors" on public.sensor_devices;
create policy "admins manage sensors" on public.sensor_devices for all to authenticated
using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admins read audit logs" on public.audit_logs;
create policy "admins read audit logs" on public.audit_logs for select to authenticated
using (public.is_admin());

grant usage on schema public to anon, authenticated;
grant select on public.parking_lots, public.parking_slots, public.pricing_rules to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.vehicles, public.reservations,
  public.parking_sessions, public.gate_events, public.payments, public.notifications,
  public.parking_lots, public.parking_slots, public.pricing_rules, public.sensor_devices,
  public.audit_logs to authenticated;

grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.create_reservation(uuid, uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;
grant execute on function public.admin_set_slot_status(uuid, public.slot_status) to authenticated;
grant execute on function public.admin_set_sensor_status(uuid, public.sensor_status) to authenticated;
grant execute on function public.check_in_reservation(text) to authenticated;
grant execute on function public.check_out_session(uuid) to authenticated;
grant execute on function public.simulate_payment(uuid) to authenticated;
grant execute on function public.expire_reservations() to authenticated;

-- Enable Realtime publication updates for occupancy, bookings and sessions.
do $$ begin
  alter publication supabase_realtime add table public.parking_slots;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.reservations;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.parking_sessions;
exception when duplicate_object then null;
end $$;

-- Create a sample facility only when the project has no facilities.
insert into public.parking_lots (name, address, timezone, hourly_rate, additional_hour_rate, daily_cap)
select 'Central Station Parking', '12 Connaught Place, New Delhi', 'Asia/Kolkata', 30, 20, 200
where not exists (select 1 from public.parking_lots);

insert into public.parking_slots (lot_id, slot_number, slot_type, status, sensor_status)
select l.id, slots.slot_number, slots.slot_type, slots.status, 'ONLINE'
from public.parking_lots l
cross join (values
  ('A-01', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-02', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-03', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-04', 'EV'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-05', 'EV'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-06', 'ACCESSIBLE'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-07', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-08', 'STANDARD'::public.slot_type, 'MAINTENANCE'::public.slot_status),
  ('A-09', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('A-10', 'STANDARD'::public.slot_type, 'OFFLINE'::public.slot_status),
  ('B-01', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status),
  ('B-02', 'STANDARD'::public.slot_type, 'AVAILABLE'::public.slot_status)
) as slots(slot_number, slot_type, status)
where l.name = 'Central Station Parking'
  and not exists (select 1 from public.parking_slots existing where existing.lot_id = l.id and existing.slot_number = slots.slot_number);

insert into public.pricing_rules (lot_id, first_hour_rate, additional_hour_rate, daily_maximum, currency)
select l.id, l.hourly_rate, l.additional_hour_rate, l.daily_cap, 'INR'
from public.parking_lots l
where not exists (select 1 from public.pricing_rules p where p.lot_id = l.id);

-- Supabase projects support pg_cron; if enabled this expires stale bookings every five minutes.
do $$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'smart-parking-expire-reservations') then
    update cron.job
    set schedule = '*/5 * * * *',
        command = 'select public.expire_reservations_internal();'
    where jobname = 'smart-parking-expire-reservations';
  else
    perform cron.schedule(
      'smart-parking-expire-reservations',
      '*/5 * * * *',
      'select public.expire_reservations_internal();'
    );
  end if;
exception when undefined_table or undefined_function or insufficient_privilege then
  raise notice 'pg_cron unavailable; reservation expiry can be run from the admin dashboard.';
end $$;

-- Promote a user to administrator from the Supabase SQL Editor after signup:
-- update public.profiles set role = 'ADMIN' where id = 'AUTH_USER_UUID';
