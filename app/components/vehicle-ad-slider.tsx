"use client";
import {BusinessName} from "./business-branding";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,ArrowRight,CarFront} from "lucide-react";
type Ad={id:string;title:string;description:string|null;price_kes:number|null;image_url:string|null;vehicle_year:number|null};
export default function VehicleAdSlider(){
 const [ads,setAds]=useState<Ad[]>([]);const [index,setIndex]=useState(0);
 useEffect(()=>{const u=process.env.NEXT_PUBLIC_SUPABASE_URL,k=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;if(!u||!k)return;let active=true;createClient(u,k).from("vehicle_sale_ads").select("id,title,description,price_kes,image_url,vehicle_year").eq("is_active",true).order("display_order").order("created_at",{ascending:false}).then(({data})=>{if(active)setAds((data||[]) as Ad[])});return()=>{active=false}},[]);
 useEffect(()=>{if(ads.length<2)return;const id=window.setInterval(()=>setIndex(v=>(v+1)%ads.length),5000);return()=>window.clearInterval(id)},[ads.length]);
 const ad=ads[index];
 return <section className="vehicle-ad-card" aria-label="Vehicles available for sale">
  <div className="vehicle-ad-top"><span>AVAILABLE VEHICLES</span><span>{ads.length?String(index+1).padStart(2,"0")+" / "+String(ads.length).padStart(2,"0") : null}</span></div>
  {ad?<><div className="vehicle-ad-image" style={ad.image_url?{backgroundImage:"linear-gradient(0deg,#05080bd9,transparent 65%),url("+JSON.stringify(ad.image_url)+")"}:undefined}>{!ad.image_url&&<CarFront size={64}/>}</div><div className="vehicle-ad-copy"><small>{ad.vehicle_year||"FEATURED VEHICLE"}</small><h3>{ad.title}</h3><p>{ad.description||<>Contact <BusinessName/> for details and viewing.</>}</p><div className="vehicle-ad-bottom"><b>{ad.price_kes? "KSh "+Number(ad.price_kes).toLocaleString("en-KE"):"Price on enquiry"}</b><a href="/enquire">Enquire <ArrowRight size={15}/></a></div></div>{ads.length>1&&<div className="vehicle-ad-controls"><button onClick={()=>setIndex(v=>(v-1+ads.length)%ads.length)} aria-label="Previous advert"><ArrowLeft size={15}/></button><button onClick={()=>setIndex(v=>(v+1)%ads.length)} aria-label="Next advert"><ArrowRight size={15}/></button></div>}</>:<div className="vehicle-ad-empty"><CarFront size={42}/><h3>Vehicles for sale</h3><p>Featured vehicles will appear here. Visit us again to see what's available.</p></div>}
 </section>
}
