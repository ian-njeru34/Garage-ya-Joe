"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {useRouter} from "next/navigation";
import {ArrowLeft,Facebook,MessageCircle,Save,CheckCircle2} from "lucide-react";
const sb=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
export default function OwnerSettingsPage(){
 const router=useRouter();const [businessId,setBusinessId]=useState("");const [whatsapp,setWhatsapp]=useState("");const [facebook,setFacebook]=useState("");const [loading,setLoading]=useState(true);const [saving,setSaving]=useState(false);const [error,setError]=useState("");const [success,setSuccess]=useState("");
 useEffect(()=>{let alive=true;(async()=>{try{const db=sb();const {data:{user},error:authError}=await db.auth.getUser();if(authError||!user){router.replace("/customer");return}
 const {data:roles,error:roleError}=await db.from("user_roles").select("business_id").eq("user_id",user.id).eq("role_code","owner").limit(1);if(roleError||!roles?.length){router.replace("/customer");return}
 const id=roles[0].business_id;const {data,error:readError}=await db.from("business_social_links").select("whatsapp_number,facebook_url").eq("business_id",id).maybeSingle();if(readError)throw readError;
 if(alive){setBusinessId(id);setWhatsapp(data?.whatsapp_number||"");setFacebook(data?.facebook_url||"");setLoading(false)}
 }catch(e){if(alive){setError(e instanceof Error?e.message:"Unable to load business contact settings.");setLoading(false)}}})();return()=>{alive=false}},[router]);
 async function save(e:React.FormEvent){e.preventDefault();setSaving(true);setError("");setSuccess("");const phone=whatsapp.trim(),fb=facebook.trim();
 if(phone&&!/^\+?[0-9][0-9 ()-]{6,19}$/.test(phone)){setError("Enter a valid WhatsApp number with country code, e.g. +2547XXXXXXXX.");setSaving(false);return}
 if(fb&&!/^https:\/\/(www\.)?facebook\.com\//i.test(fb)){setError("Enter a full Facebook page URL beginning with https://www.facebook.com/.");setSaving(false);return}
 const db=sb();const {data:{user}}=await db.auth.getUser();const {error:saveError}=await db.from("business_social_links").upsert({business_id:businessId,whatsapp_number:phone||null,facebook_url:fb||null,updated_by:user?.id,updated_at:new Date().toISOString()},{onConflict:"business_id"});
 if(saveError)setError(saveError.message);else setSuccess("Contact links saved. They will now appear in the public website footer.");setSaving(false);
 }
 if(loading)return <main className="settings-state">Loading business settings…</main>;
 return <main className="settings-page"><header><a href="/owner"><ArrowLeft size={16}/> Owner dashboard</a><span>BUSINESS SETTINGS</span></header><section><div className="intro"><span>PUBLIC CONTACT DETAILS</span><h1>Social & WhatsApp links</h1><p>Set the contact details customers should use. These links will appear in the footer across the public website.</p></div><form onSubmit={save}>
 <label><span><MessageCircle size={17}/> WhatsApp number</span><input value={whatsapp} onChange={e=>setWhatsapp(e.target.value)} placeholder="+2547XXXXXXXX" inputMode="tel"/><small>Include the country code. Use the number that receives customer WhatsApp messages.</small></label>
 <label><span><Facebook size={17}/> Facebook page URL</span><input type="url" value={facebook} onChange={e=>setFacebook(e.target.value)} placeholder="https://www.facebook.com/your-page"/><small>Enter the full public Facebook page link.</small></label>
 {error&&<p className="message error">{error}</p>}{success&&<p className="message success"><CheckCircle2 size={16}/>{success}</p>}
 <button disabled={saving||!businessId}>{saving?"Saving…":<><Save size={16}/> Save contact details</>}</button></form>
 <aside><b>Preview</b><p>The footer will display a WhatsApp button and/or Facebook button when the corresponding field is saved. Leave a field empty to hide that button.</p></aside></section>
 <style jsx>{`
 .settings-page{min-height:100vh;background:#f4f6f1;color:#1c2c24;font-family:Arial,sans-serif;padding:0 24px 60px}.settings-page header{max-width:980px;margin:auto;height:72px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #dfe6dc}.settings-page header a{display:flex;align-items:center;gap:8px;font-size:12px;color:#405b49;text-decoration:none}.settings-page header>span,.intro>span{font-size:9px;letter-spacing:.16em;font-weight:800;color:#7a897d}.settings-page section{max-width:720px;margin:48px auto}.intro h1{font-size:clamp(28px,5vw,42px);letter-spacing:-.04em;margin:12px 0}.intro p{color:#6b786e;font-size:13px;line-height:1.7;max-width:560px}.settings-page form{background:#fff;border:1px solid #e1e7de;border-radius:8px;padding:24px;margin-top:26px;display:grid;gap:22px}.settings-page label{display:grid;gap:9px}.settings-page label>span{display:flex;align-items:center;gap:9px;font-size:12px;font-weight:700}.settings-page input{width:100%;padding:14px;border:1px solid #d9e1d7;border-radius:5px;font:13px Arial;color:#24352a}.settings-page label small{font-size:10px;color:#778379}.settings-page button{display:flex;align-items:center;justify-content:center;gap:9px;padding:13px;border:0;border-radius:4px;background:#1e493b;color:white;font-size:12px;font-weight:700;cursor:pointer}.settings-page button:disabled{opacity:.6;cursor:wait}.settings-page aside{margin-top:16px;padding:16px;background:#e9efe6;border-radius:6px;font-size:11px;color:#526653;line-height:1.6}.settings-page aside p{margin:6px 0 0}.message{display:flex;align-items:center;gap:8px;font-size:12px;margin:0}.error{color:#a33}.success{color:#28623e}@media(max-width:560px){.settings-page{padding-inline:16px}.settings-page section{margin:34px auto}.settings-page form{padding:18px}}
 `}</style></main>;
}