import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const maxDuration = 30;

function normalizeKenyanPhone(raw: string) {
  let n=raw.replace(/\D/g,"");
  if(n.startsWith("0"))n="254"+n.slice(1);
  if(n.startsWith("7")||n.startsWith("1"))n="254"+n;
  if(!/^254[17]\d{8}$/.test(n))throw new Error("Customer phone must be a valid Kenyan mobile number in 07…, 01… or 254… format.");
  return n;
}

export async function POST(request:NextRequest){
  const auth=(request.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
  if(!auth)return NextResponse.json({error:"Sign in as the owner first."},{status:401});
  const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{global:{headers:{Authorization:"Bearer "+auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:authData,error:authError}=await supabase.auth.getUser(auth);
  if(authError||!authData.user)return NextResponse.json({error:"Your session has expired."},{status:401});
  const {data:roles,error:roleError}=await supabase.from("user_roles").select("business_id").eq("user_id",authData.user.id).eq("role_code","owner").limit(1);
  if(roleError||!roles?.length)return NextResponse.json({error:"Owner permission required."},{status:403});
  const body=await request.json().catch(()=>({}));
  const invoiceId=String(body.invoiceId||"");
  if(!/^[0-9a-f-]{36}$/i.test(invoiceId))return NextResponse.json({error:"Invalid invoice."},{status:400});
  const {data:invoice,error:invoiceError}=await supabase.from("invoices").select("id,business_id,invoice_number,status,receipt_share_token,customer_id").eq("id",invoiceId).eq("business_id",roles[0].business_id).maybeSingle();
  if(invoiceError||!invoice||!invoice.receipt_share_token||!["issued","partially_paid","paid","overdue"].includes(invoice.status))return NextResponse.json({error:"Issue the invoice first; its PDF receipt is not available."},{status:400});
  const {data:customer,error:customerError}=await supabase.from("customers").select("display_name,phone").eq("id",invoice.customer_id).eq("business_id",invoice.business_id).maybeSingle();
  if(customerError||!customer?.phone)return NextResponse.json({error:"The customer has no WhatsApp phone number saved."},{status:400});
  const accessToken=process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId=process.env.WHATSAPP_PHONE_NUMBER_ID;
  if(!accessToken||!phoneNumberId)return NextResponse.json({error:"WhatsApp Business Cloud API is not configured. Use the WhatsApp share link to send the PDF link manually."},{status:503});
  try{
    const to=normalizeKenyanPhone(customer.phone);
    const base=new URL(request.url).origin;
    const receiptUrl=base+"/api/invoices/receipt/"+invoice.receipt_share_token;
    const pdfResponse=await fetch(receiptUrl,{cache:"no-store"});
    if(!pdfResponse.ok)throw new Error("Could not generate the invoice PDF.");
    const pdf=await pdfResponse.arrayBuffer();
    const form=new FormData();
    form.append("messaging_product","whatsapp");
    form.append("type","application/pdf");
    form.append("file",new Blob([pdf],{type:"application/pdf"}),"invoice-"+invoice.invoice_number+".pdf");
    const upload=await fetch("https://graph.facebook.com/v23.0/"+phoneNumberId+"/media",{method:"POST",headers:{Authorization:"Bearer "+accessToken},body:form});
    const media=await upload.json();
    if(!upload.ok||!media.id)throw new Error(media.error?.message||"WhatsApp could not accept the PDF attachment.");
    const sent=await fetch("https://graph.facebook.com/v23.0/"+phoneNumberId+"/messages",{method:"POST",headers:{Authorization:"Bearer "+accessToken,"Content-Type":"application/json"},body:JSON.stringify({messaging_product:"whatsapp",to,type:"document",document:{id:media.id,filename:"Invoice-"+invoice.invoice_number+".pdf",caption:"Hello "+(customer.display_name||"")+", please find your invoice "+invoice.invoice_number+". Thank you."}})});
    const result=await sent.json();
    if(!sent.ok)throw new Error(result.error?.message||"WhatsApp did not send the invoice.");
    return NextResponse.json({ok:true,invoiceNumber:invoice.invoice_number,messageId:result.messages?.[0]?.id||null});
  }catch(error){return NextResponse.json({error:error instanceof Error?error.message:"WhatsApp delivery failed."},{status:502});}
}
