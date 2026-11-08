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

      const requestedLocationId = clean(body.locationId, 80);
      let locationId: string | null = null;
      if (role !== "dealer") {
        let locationQuery = admin
          .from("locations")
          .select("id")
          .eq("business_id", ownerRole.business_id)
          .eq("is_active", true);
        if (requestedLocationId) locationQuery = locationQuery.eq("id", requestedLocationId);
        const { data: location, error: locationError } = await locationQuery.limit(1).maybeSingle();
        if (locationError || !location?.id) {
          return json({ error: requestedLocationId ? "Select an active location belonging to this business." : "The garage needs an active location before staff accounts can be created." }, 400);
        }
        locationId = location.id;
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

    if (action === "owner_update_staff" || action === "owner_deactivate_user") {
      const token = request.headers.get("Authorization")?.replace(/^Bearer\\s+/i, "");
      if (!token) return json({ error: "Sign in as the owner first." }, 401);
      const { data: authData, error: authError } = await admin.auth.getUser(token);
      if (authError || !authData.user) return json({ error: "Your session is invalid." }, 401);
      const owner = authData.user;
      const { data: ownerRole } = await admin.from("user_roles").select("business_id")
        .eq("user_id", owner.id).eq("role_code", "owner").limit(1).maybeSingle();
      if (!ownerRole) return json({ error: "Owner permission required." }, 403);
      const userId = clean(body.userId, 80);
      if (!userId || userId === owner.id) return json({ error: "You cannot change your own owner account here." }, 400);
      const { data: target } = await admin.from("user_roles").select("id,user_id,role_code,location_id")
        .eq("business_id", ownerRole.business_id).eq("user_id", userId).neq("role_code", "owner").limit(1).maybeSingle();
      if (!target) return json({ error: "Staff account not found in this business." }, 404);
      if (action === "owner_deactivate_user") {
        const { error: profileError } = await admin.from("profiles").update({ is_active: false, updated_at: new Date().toISOString() }).eq("id", userId);
        if (profileError) throw profileError;
        const { error: banError } = await admin.auth.admin.updateUserById(userId, { ban_duration: "876000h" });
        if (banError) throw banError;
        return json({ ok: true, message: "Account sign-in disabled. Historical records retained." });
      }
      const nextRole = clean(body.role, 40);
      const locationId = clean(body.locationId, 80);
      if (!staffRoles.includes(nextRole)) return json({ error: "Choose a valid staff role." }, 400);
      if (!locationId) return json({ error: "Select an active branch for this staff member." }, 400);
      const { data: location, error: locationError } = await admin.from("locations").select("id")
        .eq("id", locationId).eq("business_id", ownerRole.business_id).eq("is_active", true).maybeSingle();
      if (locationError || !location) return json({ error: "The selected branch is not active in this business." }, 400);
      const { error: updateError } = await admin.from("user_roles").update({ role_code: nextRole, location_id: locationId })
        .eq("id", target.id).eq("business_id", ownerRole.business_id);
      if (updateError) throw updateError;
      return json({ ok: true, message: "Staff role and branch updated." });
    }

    if (action === "dealer_list" || action === "dealer_respond") {
      const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
      if (!token) return json({ error: "Sign in as a dealer first." }, 401);
      const { data: authData, error: authError } = await admin.auth.getUser(token);
      if (authError || !authData.user) return json({ error: "Your dealer session is invalid." }, 401);
      const dealerUser = authData.user;
      const { data: dealer, error: dealerError } = await admin
        .from("dealer_accounts").select("business_id,supplier_id")
        .eq("profile_id", dealerUser.id).maybeSingle();
      if (dealerError || !dealer) return json({ error: "Dealer account not found." }, 403);

      if (action === "dealer_list") {
        const { data: requests, error } = await admin.from("spare_requests")
          .select("id,part_name,part_number,vehicle_make,vehicle_model,vehicle_year,quantity,customer_notes,status,created_at")
          .eq("business_id", dealer.business_id)
          .order("created_at", { ascending: false });
        if (error) throw error;
        return json({ ok: true, requests: requests ?? [] });
      }

      const requestId = clean(body.requestId, 80);
      const availability = clean(body.availability, 20);
      const price = body.price === "" || body.price == null ? null : Number(body.price);
      const shipping = body.shipping === "" || body.shipping == null ? 0 : Number(body.shipping);
      const days = body.estimatedDays === "" || body.estimatedDays == null ? null : Number(body.estimatedDays);
      if (!requestId || !["available", "to_order", "unavailable"].includes(availability)) {
        return json({ error: "Provide a valid request and availability." }, 400);
      }
      if ((price !== null && (!Number.isFinite(price) || price < 0)) ||
          !Number.isFinite(shipping) || shipping < 0 ||
          (days !== null && (!Number.isInteger(days) || days < 0))) {
        return json({ error: "Enter valid prices, shipping and delivery days." }, 400);
      }
      const { data: assignedRequest, error: requestError } = await admin.from("spare_requests")
        .select("id,business_id").eq("id", requestId)
        .eq("business_id", dealer.business_id).maybeSingle();
      if (requestError || !assignedRequest) return json({ error: "This spare request is not available." }, 404);

      const { error: responseError } = await admin.from("spare_request_responses").upsert({
        business_id: dealer.business_id, spare_request_id: requestId,
        dealer_profile_id: dealerUser.id, availability,
        quoted_unit_price: price, currency_code: "KES",
        estimated_days: days, estimated_shipping_kes: shipping,
        response_notes: clean(body.notes, 1000) || null,
        updated_at: new Date().toISOString(),
      }, { onConflict: "spare_request_id,dealer_profile_id" });
      if (responseError) throw responseError;
      const { error: updateError } = await admin.from("spare_requests")
        .update({ status: "dealer_responded", updated_at: new Date().toISOString() })
        .eq("id", requestId).eq("business_id", dealer.business_id);
      if (updateError) throw updateError;
      return json({ ok: true, message: "Your quote has been sent to The Garage owner." });
    }

    if (action === "owner_publish_spare_quote") {
      const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
      if (!token) return json({ error: "Sign in as the owner first." }, 401);
      const { data: authData, error: authError } = await admin.auth.getUser(token);
      if (authError || !authData.user) return json({ error: "Your session is invalid." }, 401);
      const owner = authData.user;
      const requestId = clean(body.requestId, 80);
      const responseId = clean(body.responseId, 80);
      const markupPercent = Number(body.markupPercent);
      const markupFixed = Number(body.markupFixed);
      if (!requestId || !responseId || !Number.isFinite(markupPercent) || markupPercent < 0 ||
          !Number.isFinite(markupFixed) || markupFixed < 0) {
        return json({ error: "Enter a valid dealer quote and non-negative markup." }, 400);
      }
      const { data: ownerRole } = await admin.from("user_roles")
        .select("business_id").eq("user_id", owner.id).eq("role_code", "owner").limit(1).maybeSingle();
      if (!ownerRole) return json({ error: "Owner permission required." }, 403);
      const { data: spare, error: spareError } = await admin.from("spare_requests")
        .select("id,business_id,quantity,assigned_dealer_id")
        .eq("id", requestId).eq("business_id", ownerRole.business_id).maybeSingle();
      if (spareError || !spare) return json({ error: "Spare request not found." }, 404);
      const { data: dealerResponse, error: quoteError } = await admin.from("spare_request_responses")
        .select("id,quoted_unit_price,estimated_shipping_kes,availability,spare_request_id")
        .eq("id", responseId).eq("business_id", ownerRole.business_id)
        .eq("spare_request_id", requestId).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (quoteError || !dealerResponse) return json({ error: "Dealer response not found for this request." }, 404);
      if (dealerResponse.availability === "unavailable" || dealerResponse.quoted_unit_price == null) {
        return json({ error: "This dealer response does not contain an available priced offer." }, 400);
      }
      const dealerUnit = Number(dealerResponse.quoted_unit_price);
      const customerUnit = Math.round((dealerUnit * (1 + markupPercent / 100) + markupFixed) * 100) / 100;
      const shipping = Number(dealerResponse.estimated_shipping_kes || 0);
      const total = Math.round((customerUnit * Number(spare.quantity) + shipping) * 100) / 100;
      const publishedAt = new Date().toISOString();
      const { error: savePriceError } = await admin.from("owner_spare_pricing").upsert({
        business_id: ownerRole.business_id,
        spare_request_id: requestId,
        selected_response_id: responseId,
        markup_percent: markupPercent,
        markup_fixed_kes: markupFixed,
        customer_unit_price_kes: customerUnit,
        customer_shipping_kes: shipping,
        customer_total_kes: total,
        published_at: publishedAt,
        updated_by: owner.id,
        updated_at: publishedAt,
      }, { onConflict: "business_id,spare_request_id" });
      if (savePriceError) throw savePriceError;
      const { error: saveRequestError } = await admin.from("spare_requests").update({
        status: "quoted", updated_at: publishedAt,
      }).eq("id", requestId).eq("business_id", ownerRole.business_id);
      if (saveRequestError) throw saveRequestError;
      return json({ ok: true, customerUnit, shipping, total });
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
