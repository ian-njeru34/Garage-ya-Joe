import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function clean(value: unknown) {
  return String(value ?? "").normalize("NFKD").replace(/[^\x20-\x7E]/g, "?");
}
function escapePdf(value: string) { return value.replace(/\\/g,"\\\\").replace(/\(/g,"\\(").replace(/\)/g,"\\)"); }
function makePdf(data: any) {
  const inv=data.invoice||{}, biz=data.business||{}, customer=data.customer||{}, items=Array.isArray(data.items)?data.items:[];
  const lines:string[]=[];
  const wrap=(s:string,width=25)=>{const words=clean(s).split(/\s+/);let line="";for(const w of words){if((line+" "+w).trim().length>width&&line){lines.push(line);line=w}else line=(line+" "+w).trim()}if(line)lines.push(line)};
  wrap(biz.name||biz.legal_name||"Garage",25);lines.push("CUSTOMER INVOICE RECEIPT","--------------------------------");
  wrap("Invoice: "+(inv.invoice_number||""),25);wrap("Customer: "+(customer.name||""),25);
  wrap("Date: "+(inv.issued_at?new Date(inv.issued_at).toLocaleDateString("en-KE"):""),25);
  lines.push("--------------------------------");
  for(const item of items){wrap(item.description||"Item",25);wrap(String(item.quantity)+" "+(item.unit_of_measure||"")+" x "+Number(item.unit_price||0).toFixed(2),25);wrap("Line: "+Number(item.line_total||0).toFixed(2),25)}
  lines.push("--------------------------------");wrap("Subtotal: "+Number(inv.subtotal_amount||0).toFixed(2),25);
  if(Number(inv.discount_amount||0)>0)wrap("Discount: -"+Number(inv.discount_amount).toFixed(2),25);
  if(Number(inv.tax_amount||0)>0)wrap("Tax: "+Number(inv.tax_amount).toFixed(2),25);
  wrap("TOTAL: "+(inv.currency_code||"KES")+" "+Number(inv.total_amount||0).toFixed(2),25);
  wrap("Paid: "+Number(inv.amount_paid||0).toFixed(2),25);
  wrap("Balance: "+Math.max(0,Number(inv.total_amount||0)-Number(inv.amount_paid||0)).toFixed(2),25);
  if(inv.due_date)wrap("Due: "+inv.due_date,25);
  lines.push("--------------------------------");wrap("Status: "+String(inv.status||"issued").toUpperCase(),25);
  wrap("Thank you for choosing us.",25);
  if(inv.customer_notes)wrap(inv.customer_notes,25);
  const fontSize=7, leading=9, height=Math.max(180,lines.length*leading+32), width=144;
  let stream="BT\n/F1 "+fontSize+" Tf\n10 "+(height-18)+" Td\n"+leading+" TL\n";
  for(const line of lines)stream+="("+escapePdf(line)+") Tj\nT*\n";
  stream+="ET";
  const objects:string[]=[];
  objects.push("<< /Type /Catalog /Pages 2 0 R >>");
  objects.push("<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
  objects.push("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "+width+" "+height+"] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>");
  objects.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  objects.push("<< /Length "+new TextEncoder().encode(stream).length+" >>\nstream\n"+stream+"\nendstream");
  let pdf="%PDF-1.4\n", offsets=[0];
  objects.forEach((obj,i)=>{offsets.push(new TextEncoder().encode(pdf).length);pdf+=(i+1)+" 0 obj\n"+obj+"\nendobj\n"});
  const xref=new TextEncoder().encode(pdf).length;pdf+="xref\n0 "+(objects.length+1)+"\n0000000000 65535 f \n";
  offsets.slice(1).forEach(o=>pdf+=String(o).padStart(10,"0")+" 00000 n \n");
  pdf+="trailer\n<< /Size "+(objects.length+1)+" /Root 1 0 R >>\nstartxref\n"+xref+"\n%%EOF";
  return new TextEncoder().encode(pdf);
}

export async function GET(_request: NextRequest, context: {params: Promise<{token:string}>}) {
  const {token}=await context.params;
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token))
    return NextResponse.json({error:"Receipt link is invalid."},{status:404});
  const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false}});
  const {data,error}=await supabase.rpc("get_invoice_receipt_by_token",{p_token:token});
  if(error||!data)return NextResponse.json({error:"This receipt is unavailable."},{status:404});
  const pdf=makePdf(data);
  return new NextResponse(pdf,{headers:{"Content-Type":"application/pdf","Content-Disposition":'inline; filename="garage-invoice-receipt.pdf"',"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff"}});
}
