import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
export const runtime="nodejs";
export const dynamic="force-dynamic";
function esc(s:string){return s.replace(/[^\x20-\x7E]/g,"?").replace(/\\/g,"\\\\").replace(/\(/g,"\\(").replace(/\)/g,"\\)");}
function pdfReceipt(d:any){
 const p=d.payment||{},b=d.business||{},c=d.customer||{},i=d.invoice||null;
 const lines:string[]=[];
 const wrap=(v:any)=>{const words=String(v??"").replace(/[^\x20-\x7E]/g,"?").split(/\s+/);let line="";for(const w of words){if((line+" "+w).trim().length>24&&line){lines.push(line);line=w}else line=(line+" "+w).trim()}if(line)lines.push(line)};
 wrap(b.name||b.legal_name||"Business");lines.push("PAYMENT RECEIPT","------------------------");
 wrap("Receipt: "+p.payment_number);wrap("Date: "+p.payment_date);wrap("Customer: "+c.name);
 lines.push("------------------------");wrap("Method: "+String(p.payment_method||"").replace(/_/g," "));if(p.external_reference)wrap("Reference: "+p.external_reference);
 wrap("Amount: "+p.currency_code+" "+Number(p.amount||0).toFixed(2));wrap("KES equivalent: "+Number(p.amount_kes||0).toFixed(2));
 if(i){lines.push("------------------------");wrap("Invoice: "+i.invoice_number);wrap("Invoice total: "+Number(i.total_amount||0).toFixed(2));wrap("Paid to date: "+Number(i.amount_paid||0).toFixed(2));wrap("Balance: "+Number(i.balance||0).toFixed(2))}
 lines.push("------------------------");wrap("Status: "+String(p.status||"recorded").toUpperCase());wrap("Thank you for your payment.");if(p.notes)wrap(p.notes);
 const height=Math.max(170,lines.length*9+30),width=144;let stream="BT\n/F1 7 Tf\n9 "+(height-16)+" Td\n9 TL\n";for(const line of lines)stream+="("+esc(line)+") Tj\nT*\n";stream+="ET";
 const objs=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "+width+" "+height+"] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>","<< /Length "+new TextEncoder().encode(stream).length+" >>\nstream\n"+stream+"\nendstream"];
 let out="%PDF-1.4\n",offsets=[0];objs.forEach((o,n)=>{offsets.push(new TextEncoder().encode(out).length);out+=(n+1)+" 0 obj\n"+o+"\nendobj\n"});const x=new TextEncoder().encode(out).length;out+="xref\n0 6\n0000000000 65535 f \n";offsets.slice(1).forEach(n=>out+=String(n).padStart(10,"0")+" 00000 n \n");out+="trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n"+x+"\n%%EOF";return new TextEncoder().encode(out);
}
export async function GET(_r:NextRequest,ctx:{params:Promise<{token:string}>}){
 const {token}=await ctx.params;if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token))return NextResponse.json({error:"Receipt unavailable."},{status:404});
 const sb=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false}});
 const {data,error}=await sb.rpc("get_customer_payment_receipt_by_token",{p_token:token});if(error||!data)return NextResponse.json({error:"Receipt unavailable."},{status:404});
 return new NextResponse(pdfReceipt(data),{headers:{"Content-Type":"application/pdf","Content-Disposition":'inline; filename="payment-receipt.pdf"',"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff"}});
}
