import { requireSupabase } from "./supabase";

export type SlotStatus =
  | "AVAILABLE"
  | "RESERVED"
  | "OCCUPIED"
  | "MAINTENANCE"
  | "OFFLINE";

export type Facility = {
  id: string;
  name: string;
  address: string;
  timezone: string;
  hourly_rate: number;
  additional_hour_rate: number;
  daily_cap: number;
  created_at: string;
};

export type ParkingSlot = {
  id: string;
  lot_id: string;
  slot_number: string;
  slot_type: "STANDARD" | "EV" | "ACCESSIBLE";
  status: SlotStatus;
  sensor_status: "ONLINE" | "OFFLINE";
  updated_at: string;
};

export type Vehicle = {
  id: string;
  user_id: string;
  license_plate: string;
  vehicle_type: "CAR" | "MOTORCYCLE" | "SUV" | "VAN";
  model: string;
  is_ev: boolean;
  accessibility_required: boolean;
  created_at: string;
};

export type Reservation = {
  id: string;
  booking_code: string;
  user_id: string;
  vehicle_id: string;
  lot_id: string;
  slot_id: string;
  starts_at: string;
  ends_at: string;
  status: "CONFIRMED" | "CANCELLED" | "EXPIRED" | "COMPLETED";
  created_at: string;
  parking_lots?: Pick<Facility, "name" | "address">;
  parking_slots?: Pick<ParkingSlot, "slot_number">;
};

export type ParkingSession = {
  id: string;
  reservation_id: string | null;
  user_id: string;
  vehicle_id: string;
  lot_id: string;
  slot_id: string;
  entry_at: string;
  exit_at: string | null;
  status: "ACTIVE" | "COMPLETED";
  amount_due: number | null;
  created_at: string;
};

export type ParkingNotification = {
  id: string;
  user_id: string;
  title: string;
  message: string;
  type: string;
  read_at: string | null;
  created_at: string;
};

export async function signIn(email: string, password: string) {
  const { data, error } = await requireSupabase().auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await requireSupabase().auth.signOut();
  if (error) throw error;
}

export async function updatePassword(password: string) {
  const { data, error } = await requireSupabase().auth.updateUser({ password });
  if (error) throw error;
  return data;
}

export async function registerUser(input: {
  fullName: string;
  email: string;
  phone: string;
  password: string;
}) {
  const client = requireSupabase();
  const { data, error } = await client.auth.signUp({
    email: input.email,
    password: input.password,
    options: {
      data: { full_name: input.fullName, phone: input.phone },
    },
  });
  if (error) throw error;
  if (data.user && data.session) {
    const { error: profileError } = await client
      .from("profiles")
      .update({ full_name: input.fullName, phone: input.phone })
      .eq("id", data.user.id);
    if (profileError) throw profileError;
  }
  return data;
}

export async function requestPasswordReset(email: string) {
  const { error } = await requireSupabase().auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}${import.meta.env.BASE_URL}reset-password`,
  });
  if (error) throw error;
}

export async function getFacilities(): Promise<Facility[]> {
  const { data, error } = await requireSupabase()
    .from("parking_lots")
    .select("*")
    .order("name");
  if (error) throw error;
  return (data ?? []) as unknown as Facility[];
}

export async function deleteFacility(facilityId: string) {
  const { error } = await requireSupabase()
    .from("parking_lots")
    .delete()
    .eq("id", facilityId);
  if (error) throw error;
}

export async function getParkingSlots(lotId?: string): Promise<ParkingSlot[]> {
  let query = requireSupabase()
    .from("parking_slots")
    .select("*")
    .order("slot_number");
  if (lotId) query = query.eq("lot_id", lotId);
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as unknown as ParkingSlot[];
}

export async function getReservations(): Promise<Reservation[]> {
  const { data, error } = await requireSupabase()
    .from("reservations")
    .select(
      "*, parking_lots(name,address), parking_slots(slot_number)",
    )
    .order("starts_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as Reservation[];
}

export async function createReservation(input: {
  lotId: string;
  vehicleId: string;
  startsAt: string;
  endsAt: string;
  preferredSlotId?: string;
}): Promise<Reservation> {
  const { data, error } = await requireSupabase().rpc("create_reservation", {
    p_lot_id: input.lotId,
    p_vehicle_id: input.vehicleId,
    p_starts_at: input.startsAt,
    p_ends_at: input.endsAt,
    p_preferred_slot_id: input.preferredSlotId ?? null,
  });
  if (error) throw error;
  return data as unknown as Reservation;
}

export async function cancelReservation(reservationId: string) {
  const { data, error } = await requireSupabase().rpc("cancel_reservation", {
    p_reservation_id: reservationId,
  });
  if (error) throw error;
  return data;
}

export async function getVehicles(): Promise<Vehicle[]> {
  const { data, error } = await requireSupabase()
    .from("vehicles")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as Vehicle[];
}

export async function saveVehicle(input: {
  id?: string;
  licensePlate: string;
  vehicleType: Vehicle["vehicle_type"];
  model: string;
  isEv: boolean;
  accessibilityRequired: boolean;
}) {
  const client = requireSupabase();
  const user = (await client.auth.getUser()).data.user;
  if (!user) throw new Error("Your session has expired. Please sign in again.");
  const payload = {
    user_id: user.id,
    license_plate: input.licensePlate.toUpperCase().replace(/\s+/g, ""),
    vehicle_type: input.vehicleType,
    model: input.model,
    is_ev: input.isEv,
    accessibility_required: input.accessibilityRequired,
  };
  const result = input.id
    ? await client.from("vehicles").update(payload).eq("id", input.id).select().single()
    : await client.from("vehicles").insert(payload).select().single();
  if (result.error) throw result.error;
  return result.data as unknown as Vehicle;
}

export async function deleteVehicle(vehicleId: string) {
  const { error } = await requireSupabase()
    .from("vehicles")
    .delete()
    .eq("id", vehicleId);
  if (error) throw error;
}

export async function getParkingSessions(): Promise<ParkingSession[]> {
  const { data, error } = await requireSupabase()
    .from("parking_sessions")
    .select("*")
    .order("entry_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as ParkingSession[];
}

export async function getNotifications(): Promise<ParkingNotification[]> {
  const { data, error } = await requireSupabase()
    .from("notifications")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as ParkingNotification[];
}

export type Payment = {
  id: string;
  session_id: string;
  user_id: string;
  amount: number;
  status: "PENDING" | "PAID" | "FAILED" | "REFUNDED";
  method: string;
  receipt_number: string;
  paid_at: string | null;
  created_at: string;
};

export type GateEvent = {
  id: string;
  reservation_id: string | null;
  session_id: string | null;
  user_id: string | null;
  vehicle_id: string | null;
  lot_id: string | null;
  slot_id: string | null;
  event_type: "ENTRY" | "EXIT";
  event_at: string;
  booking_code: string | null;
  source: string;
};

export type SensorDevice = {
  id: string;
  lot_id: string;
  slot_id: string | null;
  device_name: string;
  device_code: string;
  status: "ONLINE" | "OFFLINE";
  last_seen_at: string | null;
  created_at: string;
};

export type PricingRule = {
  id: string;
  lot_id: string;
  first_hour_rate: number;
  additional_hour_rate: number;
  daily_maximum: number;
  currency: string;
  updated_at: string;
};

export async function getPayments(): Promise<Payment[]> {
  const { data, error } = await requireSupabase()
    .from("payments")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as Payment[];
}

export async function getGateEvents(): Promise<GateEvent[]> {
  const { data, error } = await requireSupabase()
    .from("gate_events")
    .select("*")
    .order("event_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as GateEvent[];
}

export async function getSensorDevices(): Promise<SensorDevice[]> {
  const { data, error } = await requireSupabase()
    .from("sensor_devices")
    .select("*")
    .order("device_name");
  if (error) throw error;
  return (data ?? []) as unknown as SensorDevice[];
}

export async function getPricingRules(): Promise<PricingRule[]> {
  const { data, error } = await requireSupabase()
    .from("pricing_rules")
    .select("*")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as PricingRule[];
}

export async function saveFacility(input: {
  id?: string;
  name: string;
  address: string;
  timezone: string;
  hourlyRate: number;
  additionalHourRate: number;
  dailyCap: number;
}) {
  const client = requireSupabase();
  const payload = {
    name: input.name,
    address: input.address,
    timezone: input.timezone,
    hourly_rate: input.hourlyRate,
    additional_hour_rate: input.additionalHourRate,
    daily_cap: input.dailyCap,
  };
  const result = input.id
    ? await client.from("parking_lots").update(payload).eq("id", input.id).select().single()
    : await client.from("parking_lots").insert(payload).select().single();
  if (result.error) throw result.error;
  return result.data as unknown as Facility;
}

export async function saveParkingSlot(input: {
  id?: string;
  lotId: string;
  slotNumber: string;
  slotType: ParkingSlot["slot_type"];
}) {
  const client = requireSupabase();
  const payload = {
    lot_id: input.lotId,
    slot_number: input.slotNumber,
    slot_type: input.slotType,
  };
  const result = input.id
    ? await client.from("parking_slots").update(payload).eq("id", input.id).select().single()
    : await client.from("parking_slots").insert(payload).select().single();
  if (result.error) throw result.error;
  return result.data as unknown as ParkingSlot;
}

export async function deleteParkingSlot(slotId: string) {
  const { error } = await requireSupabase()
    .from("parking_slots")
    .delete()
    .eq("id", slotId);
  if (error) throw error;
}

export async function savePricingRule(input: {
  lotId: string;
  firstHourRate: number;
  additionalHourRate: number;
  dailyMaximum: number;
}) {
  const { data, error } = await requireSupabase()
    .from("pricing_rules")
    .upsert({
      lot_id: input.lotId,
      first_hour_rate: input.firstHourRate,
      additional_hour_rate: input.additionalHourRate,
      daily_maximum: input.dailyMaximum,
      currency: "INR",
      updated_at: new Date().toISOString(),
    }, { onConflict: "lot_id" })
    .select()
    .single();
  if (error) throw error;
  return data as unknown as PricingRule;
}

export async function checkInReservation(bookingCode: string) {
  const { data, error } = await requireSupabase().rpc("check_in_reservation", {
    p_booking_code: bookingCode,
  });
  if (error) throw error;
  return data as unknown as ParkingSession;
}

export async function checkOutSession(sessionId: string) {
  const { data, error } = await requireSupabase().rpc("check_out_session", {
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data;
}

export async function simulatePayment(paymentId: string) {
  const { data, error } = await requireSupabase().rpc("simulate_payment", {
    p_payment_id: paymentId,
  });
  if (error) throw error;
  return data as unknown as Payment;
}

export async function expireReservations() {
  const { data, error } = await requireSupabase().rpc("expire_reservations");
  if (error) throw error;
  return Number(data ?? 0);
}

export async function updateProfile(input: { fullName: string; phone: string }) {
  const client = requireSupabase();
  const user = (await client.auth.getUser()).data.user;
  if (!user) throw new Error("Your session has expired. Please sign in again.");
  const { data, error } = await client
    .from("profiles")
    .update({ full_name: input.fullName, phone: input.phone })
    .eq("id", user.id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function markNotificationRead(notificationId: string) {
  const { error } = await requireSupabase()
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", notificationId);
  if (error) throw error;
}

export async function getProfile() {
  const client = requireSupabase();
  const user = (await client.auth.getUser()).data.user;
  if (!user) throw new Error("Your session has expired. Please sign in again.");
  const { data, error } = await client
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();
  if (error) throw error;
  return { ...data, email: user.email ?? "" };
}

export async function updateSlotStatus(slotId: string, status: SlotStatus) {
  const { data, error } = await requireSupabase().rpc("admin_set_slot_status", {
    p_slot_id: slotId,
    p_status: status,
  });
  if (error) throw error;
  return data;
}

export async function updateSensorStatus(slotId: string, status: "ONLINE" | "OFFLINE") {
  const { data, error } = await requireSupabase().rpc("admin_set_sensor_status", {
    p_slot_id: slotId,
    p_status: status,
  });
  if (error) throw error;
  return data;
}

export async function subscribeToParkingChanges(onChange: () => void) {
  const client = requireSupabase();
  const channel = client
    .channel("parking-live-updates")
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "parking_slots" },
      onChange,
    )
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "reservations" },
      onChange,
    )
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "parking_sessions" },
      onChange,
    )
    .subscribe();
  return () => {
    void client.removeChannel(channel);
  };
}
