"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {Phone} from "lucide-react";
import {BusinessName} from "./business-branding";
export default function CallButton({compact=false}:{compact?:boolean}){
 const [phone,setPhone]=useState("");
 useEffect(()=>{const u=process.env.NEXT_PUBLIC_SUPABASE_URL,k=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;if(!u||!k)return;let active=true;createClient(u,k).from("business_social_links").select("telephone_number").limit(1).maybeSingle().then(({data})=>{if(active)setPhone(String(data?.telephone_number||"").replace(/[^+0-9]/g,""))});return()=>{active=false}},[]);
 if(!phone)return null;
 return <a className={compact?"garage-call-link":"garage-call-button"} href={"tel:"+phone} aria-label="Call business"><Phone size={17}/>{!compact&&<span>Call <BusinessName/></span>}</a>
}
