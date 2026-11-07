import {NextRequest,NextResponse} from "next/server";
import {createClient} from "@supabase/supabase-js";
export const runtime="nodejs";
const roles=["mechanic","service_advisor","branch_manager","administrator","inventory_manager","procurement_officer","cashier","accountant"];
export async function POST(req:NextRequest){
 try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,service=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!anon||!service)return NextResponse.json({error:"Account administration is not configured on the server."},{status:503});
  const token=req.headers.get("authorization")?.replace(/^Bearer\s+/i,"");
  if(!token)return NextResponse.json({error:"Sign in as the owner first."},{status:401});
  const auth=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user:owner},error:authError}=await auth.auth.getUser(token);
  if(authError||!owner)return NextResponse.json({error:"Your session is invalid. Please sign in again."},{status:401});
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:assignments,error:roleError}=await admin.from("user_roles").select("business_id,role_code").eq("user_id",owner.id).eq("role_code","owner");
  if(roleError||!assignments?.length)return NextResponse.json({error:"Owner permission required."},{status:403});
  const body=await req.json();const fullName=String(body.fullName||"").trim();const email=String(body.email||"").trim().toLowerCase();const phone=String(body.whatsapp||"").trim();const password=String(body.password||"");const role=String(body.role||"");
  if(!fullName||!email||!/^\S+@\S+\.\S+$/.test(email)||password.length<8||!phone)return NextResponse.json({error:"Enter name, valid email, WhatsApp number and a password of at least 8 characters."},{status:400});
  if(role!=="dealer"&&!roles.includes(role))return NextResponse.json({error:"Select a supported staff role."},{status:400});
  const businessId=assignments[0].business_id;
  const {data:locations}=await admin.from("locations").select("id").eq("business_id",businessId).eq("is_active",true).order("created_at").limit(1);
  const locationId=locations?.[0]?.id||null;
  const {data:created,error:createError}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:fullName,phone,account_type:role==="dealer"?"dealer":"staff"}});
  if(createError||!created.user)return NextResponse.json({error:createError?.message||"Could not create the account."},{status:400});
  const uid=created.user.id;
  const {error:profileError}=await admin.from("profiles").upsert({id:uid,full_name:fullName,phone});
  if(profileError){await admin.auth.admin.deleteUser(uid);return NextResponse.json({error:profileError.message},{status:500});}
  const {error:assignmentError}=await admin.from("user_roles").insert({user_id:uid,business_id:businessId,location_id:role==="dealer"?null:locationId,role_code:role,granted_by:owner.id});
  if(assignmentError){await admin.auth.admin.deleteUser(uid);return NextResponse.json({error:assignmentError.message},{status:500});}
  if(role==="dealer"){
   const supplierId=crypto.randomUUID();const code="DLR-"+supplierId.slice(0,8).toUpperCase();
   const {error:supplierError}=await admin.from("suppliers").insert({id:supplierId,business_id:businessId,supplier_code:code,supplier_name:fullName,supplier_type:"distributor",contact_person:fullName,email,phone});
   if(supplierError){await admin.auth.admin.deleteUser(uid);return NextResponse.json({error:supplierError.message},{status:500});}
   const {error:dealerError}=await admin.from("dealer_accounts").insert({business_id:businessId,supplier_id:supplierId,profile_id:uid});
   if(dealerError){await admin.from("suppliers").delete().eq("id",supplierId).eq("business_id",businessId);await admin.auth.admin.deleteUser(uid);return NextResponse.json({error:dealerError.message},{status:500});}
  }
  return NextResponse.json({ok:true,user:{id:uid,email,fullName,role}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Unexpected account creation error."},{status:500});}
}
