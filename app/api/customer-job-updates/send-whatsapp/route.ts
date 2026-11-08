import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const maxDuration = 30;

function normalizeKenyanPhone(raw: string) {
  let n = raw.replace(/\D/g, "");
  if (n.startsWith("0")) n = "254" + n.slice(1);
  if (n.startsWith("7") || n.startsWith("1")) n = "254" + n;
  if (!/^254[17]\d{8}$/.test(n)) throw new Error("Customer WhatsApp number is not a valid Kenyan mobile number.");
  return n;
}

export async function POST(request: NextRequest) {
  const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "Sign in first." }, { status: 401 });
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anon || !service) return NextResponse.json({ error: "Server notification service is not configured." }, { status: 503 });

  const userClient = createClient(url, anon, { global: { headers: { Authorization: "Bearer " + token } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return NextResponse.json({ error: "Your session has expired." }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const updateId = String(body.updateId || "");
  if (!/^[0-9a-f-]{36}$/i.test(updateId)) return NextResponse.json({ error: "Invalid customer update." }, { status: 400 });

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: update, error: updateError } = await admin.from("customer_job_updates")
    .select("id,business_id,location_id,job_card_id,customer_id,message,whatsapp_status")
    .eq("id", updateId).maybeSingle();
  if (updateError || !update) return NextResponse.json({ error: "Published update not found." }, { status: 404 });

  const { data: role } = await admin.from("user_roles").select("role_code")
    .eq("user_id", authData.user.id).eq("business_id", update.business_id)
    .in("role_code", ["owner", "administrator", "branch_manager", "service_advisor", "mechanic"])
    .or("location_id.is.null,location_id.eq." + update.location_id).limit(1).maybeSingle();
  if (!role) return NextResponse.json({ error: "You are not authorized to send updates for this workshop." }, { status: 403 });

  if (update.whatsapp_status === "sent") return NextResponse.json({ ok: true, status: "sent", alreadySent: true });

  const { data: customer, error: customerError } = await admin.from("customers")
    .select("display_name,phone").eq("id", update.customer_id).eq("business_id", update.business_id).maybeSingle();
  if (customerError || !customer?.phone) {
    await admin.from("customer_job_updates").update({ whatsapp_status: "failed", whatsapp_error: "Customer WhatsApp number is missing." }).eq("id", updateId);
    return NextResponse.json({ ok: true, status: "failed", warning: "The update is visible in the customer portal, but no WhatsApp number is saved." });
  }

  const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!accessToken || !phoneNumberId) {
    await admin.from("customer_job_updates").update({ whatsapp_status: "not_configured", whatsapp_error: "WhatsApp Business Cloud API credentials are not configured." }).eq("id", updateId);
    return NextResponse.json({ ok: true, status: "not_configured", warning: "The update is published in the customer portal. WhatsApp delivery is not configured yet." });
  }

  try {
    const to = normalizeKenyanPhone(customer.phone);
    const sent = await fetch("https://graph.facebook.com/v23.0/" + phoneNumberId + "/messages", {
      method: "POST",
      headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to,
        type: "text",
        text: { preview_url: false, body: "Hello " + (customer.display_name || "there") + ", an update from Garage Ya Joe about your vehicle service:\n\n" + update.message + "\n\nYou can also view this update in your customer portal." }
      })
    });
    const result = await sent.json();
    if (!sent.ok || !result.messages?.[0]?.id) throw new Error(result.error?.message || "WhatsApp did not confirm delivery.");
    await admin.from("customer_job_updates").update({ whatsapp_status: "sent", whatsapp_message_id: result.messages[0].id, whatsapp_error: null }).eq("id", updateId);
    return NextResponse.json({ ok: true, status: "sent" });
  } catch (error) {
    const reason = error instanceof Error ? error.message.slice(0, 500) : "WhatsApp delivery failed.";
    await admin.from("customer_job_updates").update({ whatsapp_status: "failed", whatsapp_error: reason }).eq("id", updateId);
    return NextResponse.json({ ok: true, status: "failed", warning: "The update is visible in the customer portal, but WhatsApp could not send it: " + reason });
  }
}
