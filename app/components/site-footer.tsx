"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {Facebook,MessageCircle,Youtube,Instagram,Twitter,Phone} from "lucide-react";
type Contacts={whatsapp_number:string|null;telephone_number:string|null;facebook_url:string|null;youtube_url:string|null;instagram_url:string|null;x_url:string|null};
export default function SiteFooter(){
 const [contacts,setContacts]=useState<Contacts|null>(null);
 useEffect(()=>{const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;if(!url||!key)return;let active=true;
  createClient(url,key).from("business_social_links").select("whatsapp_number,telephone_number,facebook_url,youtube_url,instagram_url,x_url").limit(1).maybeSingle().then(({data})=>{if(active&&data)setContacts(data as Contacts)});
  return()=>{active=false};
 },[]);
 const digits=(contacts?.whatsapp_number||"").replace(/\D/g,"");const whatsapp=digits?"https://wa.me/"+digits:null;const tel=(contacts?.telephone_number||"").replace(/[^+0-9]/g,"");
 const socials=[{url:contacts?.facebook_url,label:"Facebook",Icon:Facebook,kind:"facebook"},{url:contacts?.youtube_url,label:"YouTube",Icon:Youtube,kind:"youtube"},{url:contacts?.instagram_url,label:"Instagram",Icon:Instagram,kind:"instagram"},{url:contacts?.x_url,label:"X",Icon:Twitter,kind:"x"}];
 return <footer className="garage-social-footer"><div className="garage-social-inner">
  <div><strong>THE GARAGE</strong><span>Automotive care · Auto spares · Imports</span></div>
  <div className="garage-social-actions">{tel&&<a className="garage-social telephone" href={"tel:"+tel}><Phone size={17}/> Call us</a>}{whatsapp&&<a className="garage-social whatsapp" href={whatsapp} target="_blank" rel="noopener noreferrer"><MessageCircle size={17}/> WhatsApp</a>}{socials.filter(item=>item.url).map(({url,label,Icon,kind})=><a key={kind} className={"garage-social "+kind} href={url!} target="_blank" rel="noopener noreferrer"><Icon size={17}/> {label}</a>)}</div>
  <small className="copyright">© {new Date().getFullYear()} The Garage. All rights reserved.</small>
  <a className="site-credit" href="https://digitalink.co.ke/" target="_blank" rel="noopener noreferrer" aria-label="Website by Digital Ink">Site by <strong>Digital Ink</strong></a>
 </div><style jsx>{`
 .garage-social-footer{border-top:1px solid #ffffff20;background:#080a0c;padding:25px 24px;color:#aab6bd}.garage-social-inner{max-width:1180px;margin:auto;display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap}.garage-social-inner>div:first-child{display:grid;gap:5px}.garage-social-inner strong{font-size:12px;letter-spacing:.16em;color:#f2f3f3}.garage-social-inner span,.garage-social-inner small{font-size:10px;color:#87949c}.garage-social-inner .copyright{display:block;white-space:normal}.garage-social-inner .site-credit{display:inline-flex;align-items:center;gap:4px;min-height:32px;padding:7px 10px;border:1px solid #ffffff26;border-radius:4px;color:#aebbc3;font-size:10px;letter-spacing:.04em;text-decoration:none;white-space:nowrap;visibility:visible;opacity:1;flex:0 0 auto}.garage-social-inner .site-credit strong{color:#f2f5f7;font-size:10px;letter-spacing:.08em}.garage-social-inner .site-credit:hover{border-color:#9cc5e2;color:#fff}.garage-social-actions{display:flex;gap:9px;flex-wrap:wrap}.garage-social{display:inline-flex;align-items:center;gap:8px;padding:10px 14px;border:1px solid #ffffff2a;border-radius:4px;font-size:11px;font-weight:700;color:#f4f6f7;text-decoration:none;transition:background .18s,border-color .18s}.garage-social.whatsapp:hover{background:#174d36;border-color:#2b8a5b}.garage-social.facebook:hover,.garage-social.youtube:hover,.garage-social.instagram:hover,.garage-social.x:hover{background:#173e68;border-color:#3978b7}@media(max-width:600px){.garage-social-inner{align-items:flex-start;flex-direction:column}.garage-social-actions{width:100%}.garage-social{flex:1;justify-content:center}}
 `}</style></footer>;
}
