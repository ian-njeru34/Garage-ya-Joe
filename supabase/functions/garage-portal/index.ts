import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

const clean = (value: unknown, max: number) => String(value ?? "").trim().slice(0, max);
const staffRoles = [
  "mechanic", "service_advisor", "branch_manager", "administrator",
  "inventory_manager", "procurement_officer", "cashier", "accountant",
];

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const secretKeys = (() => {
  try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); }
  catch { return {}; }
})();
const serviceKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!supabaseUrl || !serviceKey) throw new Error("Supabase server credentials are unavailable.");

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const body = await request.json();
    const action = clean(body.action, 30);

    if (action === "create_user") {
      const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
      if (!token) return json({ error: "Sign in as the owner first." }, 401);

      const { data: authData, error: authError } = await admin.auth.getUser(token);
      if (authError || !authData.user) return json({ error: "Your session is invalid. Sign in again." }, 401);
      const owner = authData.user;

      const { data: ownerRole, error: ownerRoleError } = await admin
        .from("user_roles")
        .select("business_id")
        .eq("user_id", owner.id)
        .eq("role_code", "owner")
        .limit(1)
        .maybeSingle();
      if (ownerRoleError || !ownerRole) return json({ error: "Owner permission required." }, 403);

      const fullName = clean(body.fullName, 120);
      const email = clean(body.email, 180).toLowerCase();
      const phone = clean(body.whatsapp, 40);
      const password = String(body.password ?? "");
      const role = clean(body.role, 40);
      if (!fullName || !phone || !/^\S+@\S+\.\S+$/.test(email) || password.length < 8) {
        return json({ error: "Enter a name, valid email, WhatsApp number and password of at least 8 characters." }, 400);
      }
      if (role !== "dealer" && !staffRoles.includes(role)) {
        return json({ error: "Select a supported staff role." }, 400);
      }

      const { data: locations } = await admin
        .from("locations")
        .select("id")
        .eq("business_id", ownerRole.business_id)
        .eq("is_active", true)
        .order("created_at")
        .limit(1);
      const locationId = locations?.[0]?.id ?? null;
      if (role !== "dealer" && !locationId) {
        return json({ error: "The garage needs an active location before staff accounts can be created." }, 400);
      }

      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, phone, account_type: role === "dealer" ? "dealer" : "staff" },
      });
      if (createError || !created.user) {
        return json({ error: createError?.message ?? "Could not create the account." }, 400);
      }

      const userId = created.user.id;
      const { error: assignmentError } = await admin.from("user_roles").insert({
        user_id: userId,
        business_id: ownerRole.business_id,
        location_id: role === "dealer" ? null : locationId,
        role_code: role,
        granted_by: owner.id,
      });
      if (assignmentError) {
        await admin.auth.admin.deleteUser(userId);
        return json({ error: "The account could not be assigned its role. Check that the role is configured." }, 400);
      }

      if (role === "dealer") {
        const supplierId = crypto.randomUUID();
        const supplierCode = "DLR-" + supplierId.slice(0, 8).toUpperCase();
        const { error: supplierError } = await admin.from("suppliers").insert({
          id: supplierId,
          business_id: ownerRole.business_id,
          supplier_code: supplierCode,
          supplier_name: fullName,
          supplier_type: "distributor",
          contact_person: fullName,
          email,
          phone,
        });
        if (supplierError) {
          await admin.auth.admin.deleteUser(userId);
          return json({ error: "Dealer supplier record could not be created." }, 400);
        }
        const { error: dealerError } = await admin.from("dealer_accounts").insert({
          business_id: ownerRole.business_id,
          supplier_id: supplierId,
          profile_id: userId,
        });
        if (dealerError) {
          await admin.from("suppliers").delete().eq("id", supplierId).eq("business_id", ownerRole.business_id);
          await admin.auth.admin.deleteUser(userId);
          return json({ error: "Dealer account could not be linked to its supplier record." }, 400);
        }
      }

      return json({ ok: true, user: { id: userId, email, fullName, role } });
    }

    if (action === "public_request") {
      // Honeypot field for simple automated form submissions.
      if (clean(body.website, 200)) return json({ ok: true });

      const fullName = clean(body.fullName, 120);
      const whatsapp = clean(body.whatsapp, 40);
      const email = clean(body.email, 180);
      if (!fullName || !whatsapp) return json({ error: "Your name and WhatsApp number are required." }, 400);
      if (email && !/^\S+@\S+\.\S+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);

      const { data: business, error: businessError } = await admin
        .from("businesses")
        .select("id")
        .order("created_at", { ascending: true })
        .limit(1)
        .single();
      if (businessError || !business) return json({ error: "The garage is not ready to receive requests yet." }, 503);

      const kind = clean(body.kind, 20);
      if (kind === "enquiry") {
        const enquiryType = clean(body.enquiryType, 100);
        if (!enquiryType) return json({ error: "Choose an enquiry type." }, 400);
        const { error } = await admin.from("customer_enquiries").insert({
          business_id: business.id,
          full_name: fullName,
          email: email || null,
          whatsapp,
          vehicle_details: clean(body.vehicleDetails, 240) || null,
          enquiry_type: enquiryType,
          details: clean(body.details, 3000) || null,
        });
        if (error) throw error;
        return json({ ok: true, message: "Your enquiry has been received by The Garage." });
      }

      if (kind === "spare") {
        const partName = clean(body.partName, 180);
        if (!partName) return json({ error: "Enter the spare part you need." }, 400);
        const quantity = Math.max(1, Math.min(1000, Number(body.quantity) || 1));
        const { error } = await admin.from("spare_requests").insert({
          business_id: business.id,
          customer_id: null,
          created_by: null,
          customer_name: fullName,
          customer_email: email || null,
          customer_whatsapp: whatsapp,
          part_name: partName,
          part_number: clean(body.partNumber, 120) || null,
          vehicle_make: clean(body.vehicleMake, 80) || null,
          vehicle_model: clean(body.vehicleModel, 100) || null,
          quantity,
          customer_notes: clean(body.notes, 2000) || null,
        });
        if (error) throw error;
        return json({ ok: true, message: "Your spare-parts request has been received." });
      }
      return json({ error: "Unsupported request type." }, 400);
    }

    return json({ error: "Unsupported action." }, 400);
  } catch (error) {
    console.error("garage-portal error", error);
    return json({ error: "The request could not be completed. Please try again." }, 500);
  }
});
