"use client";
import {createContext,useContext,useEffect,useState,ReactNode} from "react";
import {createClient} from "@supabase/supabase-js";

const FALLBACK_NAME="Garage ya Joe";
const BrandingContext=createContext(FALLBACK_NAME);

export function BusinessBrandingProvider({children}:{children:ReactNode}){
 const [name,setName]=useState(FALLBACK_NAME);
 useEffect(()=>{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(!url||!key)return;
  let active=true;
  const client=createClient(url,key);
  const refresh=()=>client.rpc("get_public_business_branding").then(({data,error})=>{
   if(!active||error||typeof data!=="string"||!data.trim())return;
   const next=data.trim();setName(next);document.title=next+" | Automotive Care & Auto Spares";
  });
  void refresh();
  window.addEventListener("business-branding-updated",refresh);
  return()=>{active=false;window.removeEventListener("business-branding-updated",refresh)};
 },[]);
 return <BrandingContext.Provider value={name}>{children}</BrandingContext.Provider>;
}

export function BusinessName({fallback=FALLBACK_NAME,uppercase=false,className}:{fallback?:string;uppercase?:boolean;className?:string}){
 const name=useContext(BrandingContext)||fallback;
 return <span className={className}>{uppercase?name.toLocaleUpperCase():name}</span>;
}
