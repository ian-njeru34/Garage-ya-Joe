"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { ArrowLeft, ArrowRight, Check, Copy, Wrench } from "lucide-react";

export default function EnquirePage() {
  const [name,setName]=useState("");
  const [phone,setPhone]=useState("");
  const [email,setEmail]=useState("");
  const [vehicle,setVehicle]=useState("");
  const [request,setRequest]=useState("");
  const [details,setDetails]=useState("");
  const [prepared,setPrepared]=useState("");
  const [copied,setCopied]=useState(false);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const [success,setSuccess]=useState("");

  async function prepare(event:FormEvent<HTMLFormElement>){
    event.preventDefault();
    setBusy(true);setError("");setSuccess("");setPrepared("");
    const website=String(new FormData(event.currentTarget).get("website")||"");
    try{
      const response=await fetch("/api/public/requests",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({kind:"enquiry",fullName:name,whatsapp:phone,email,vehicleDetails:vehicle,enquiryType:request,details,website})});
      const result=await response.json();
      if(!response.ok)throw new Error(result.error||"Your enquiry could not be saved.");
      setSuccess("Your enquiry has been received by The Garage.");
    }catch(error){setError(error instanceof Error?error.message:"Your enquiry could not be saved. Please try again.");setBusy(false);return;}
    const message=[
      "THE GARAGE — SERVICE ENQUIRY",
      `Name: ${name}`,
      `Phone: ${phone}`,
      email ? `Email: ${email}` : "",
      vehicle ? `Vehicle: ${vehicle}` : "",
      `Request: ${request}`,
      details ? `Details: ${details}` : ""
    ].filter(Boolean).join("\n");
    setPrepared(message);
    setCopied(false);
    setBusy(false);
  }
  async function copyMessage(){
    try{await navigator.clipboard.writeText(prepared);setCopied(true);}
    catch{setCopied(false);}
  }

  return <main className="page">
    <header className="top"><Link href="/" className="back"><ArrowLeft size={16}/> The Garage</Link><span>ENQUIRIES · KENYA</span></header>
    <section className="hero"><div className="eyebrow"><Wrench size={14}/> LET'S GET YOU MOVING</div><h1>Tell us what<br/><em>your vehicle needs.</em></h1><p>Share a few details about your vehicle, service request or spare part. We'll prepare a clear enquiry you can send to the garage.</p></section>
    <section className="form-wrap">
      <form onSubmit={prepare}>
        <div className="form-title"><span>01 / YOUR DETAILS</span><b>How can we reach you?</b></div>
        <div className="fields two">
          <label>Full name<input required value={name} onChange={e=>setName(e.target.value)} placeholder="Your name"/></label>
          <label>WhatsApp number<input required type="tel" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+254…"/></label>
        </div>
        <label>Email address <span className="optional">OPTIONAL</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@example.com"/></label>
        <div className="form-title second"><span>02 / VEHICLE & REQUEST</span><b>What do you need help with?</b></div>
        <label>Vehicle details <span className="optional">OPTIONAL</span><input value={vehicle} onChange={e=>setVehicle(e.target.value)} placeholder="e.g. Toyota Hilux, 2018, KDJ registration"/></label>
        <label>Enquiry type<select required value={request} onChange={e=>setRequest(e.target.value)}><option value="">Select a request</option><option>Vehicle servicing</option><option>Repairs and inspection</option><option>Auto spare parts</option><option>Special import / hard-to-find part</option><option>Other</option></select></label>
        <label>Tell us more <span className="optional">OPTIONAL</span><textarea rows={4} value={details} onChange={e=>setDetails(e.target.value)} placeholder="Describe the service, part, symptoms or part number…"/></label>
        <label className="trap" aria-hidden="true">Leave this field empty<input tabIndex={-1} autoComplete="off" name="website"/></label>
        {error?<p className="form-error" role="alert">{error}</p>:null}{success?<p className="form-success" role="status">{success}</p>:null}
        <button className="submit" type="submit" disabled={busy}>{busy?"Sending enquiry…":"Send my enquiry"} <ArrowRight size={17}/></button>
      </form>
      {prepared&&<aside className="prepared"><div><Check size={17}/><b>Your enquiry has been saved</b></div><p>The owner can now see your request and contact you on WhatsApp. You can also copy the details below for your records.</p><pre>{prepared}</pre><button type="button" onClick={copyMessage}><Copy size={15}/>{copied?"Copied":"Copy enquiry"}</button></aside>}
    </section>
    <footer><span>THE GARAGE</span><Link href="/spares">Looking for a part? Browse spare-parts information <ArrowRight size={14}/></Link></footer>
    <style jsx>{`
      .page{min-height:100vh;background:#090d11;color:#edf2f5;font-family:Arial,sans-serif}.top{height:72px;padding:0 max(22px,calc((100vw - 1080px)/2));display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #ffffff16}.back{display:flex;align-items:center;gap:9px;color:#e7edf1;font-weight:800;letter-spacing:.13em;font-size:12px}.top>span,.eyebrow,.form-title>span{font-size:9px;letter-spacing:.19em;font-weight:800;color:#8eabc0}.hero{max-width:1080px;margin:0 auto;padding:75px 24px 42px}.eyebrow{display:flex;align-items:center;gap:9px;color:#9cc5e2}.hero h1{font-size:clamp(40px,7vw,72px);line-height:1.03;letter-spacing:-.06em;margin:20px 0}.hero h1 em{font-family:Georgia,serif;font-weight:400;color:#9cc5e2}.hero p{max-width:570px;color:#aeb9c1;font-size:14px;line-height:1.85}.form-wrap{max-width:1080px;margin:0 auto;padding:0 24px 70px;display:grid;grid-template-columns:minmax(0,1fr) minmax(280px,.72fr);gap:28px;align-items:start}.form-wrap form,.prepared{background:#101820;border:1px solid #9cc5e233;padding:clamp(22px,4vw,38px)}.form-title{display:grid;gap:9px;margin-bottom:22px}.form-title b{font-size:19px}.second{margin-top:35px}.fields{display:grid;gap:16px}.fields.two{grid-template-columns:1fr 1fr}label{display:grid;gap:8px;margin:17px 0;color:#dce5eb;font-size:11px;font-weight:700}.optional{font-size:8px;color:#7e929f;letter-spacing:.12em;margin-left:5px}input,select,textarea{width:100%;border:1px solid #334653;border-radius:3px;background:#0a1117;color:#f2f5f7;padding:13px;font:13px Arial;outline-color:#9cc5e2}input::placeholder,textarea::placeholder{color:#6f808b}textarea{resize:vertical}.submit:disabled{opacity:.6;cursor:wait}.trap{position:absolute!important;left:-10000px!important;width:1px!important;height:1px!important;overflow:hidden!important}.form-error,.form-success{font-size:12px;line-height:1.6;padding:12px;border-radius:3px}.form-error{background:#4a201c;color:#ffd6cf}.form-success{background:#183a2a;color:#c6f1d2}.submit,.prepared button{display:inline-flex;align-items:center;justify-content:center;gap:10px;background:#dceaf3;color:#10202c;border:0;border-radius:3px;padding:14px 18px;font-weight:800;font-size:11px;cursor:pointer;margin-top:12px}.prepared{position:sticky;top:24px}.prepared>div{display:flex;align-items:center;gap:9px;color:#a8d2b4}.prepared p{color:#aeb9c1;font-size:12px;line-height:1.7}.prepared pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#091016;border:1px solid #293b48;padding:15px;color:#dce5eb;font:11px/1.7 monospace}.prepared button{margin-top:5px}footer{max-width:1080px;margin:auto;padding:22px 24px 35px;border-top:1px solid #ffffff18;display:flex;justify-content:space-between;gap:20px;color:#80929e;font-size:9px;letter-spacing:.15em}footer a{display:flex;align-items:center;gap:8px;color:#b8d2e3;letter-spacing:0;font-size:11px}@media(max-width:760px){.form-wrap{grid-template-columns:1fr}.prepared{position:static}.hero{padding-top:55px}}@media(max-width:500px){.fields.two{grid-template-columns:1fr}.top{padding:0 18px}.top>span{font-size:8px}.hero{padding-left:20px;padding-right:20px}.form-wrap{padding-left:16px;padding-right:16px}footer{padding-left:18px;padding-right:18px;flex-direction:column}}
    `}</style>
  </main>;
}
