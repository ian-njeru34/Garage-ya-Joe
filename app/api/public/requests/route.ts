import {NextRequest,NextResponse} from "next/server";
import {createClient} from "@supabase/supabase-js";
export const runtime="nodejs";
const clean=(v:unknown,max:number)=>String(v??"").trim().slice(0,max);
export async function POST(req:NextRequest){
 try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key)return NextResponse.json({error:"The request service is not configured. Please contact the garage directly."},{status:503});
  const body=await req.json();
  // A hidden honeypot field catches basic automated form submissions.
  if(clean(body.website,200))return NextResponse.json({ok:true});
  const kind=clean(body.kind,20);
  const fullName=clean(body.fullName,120),whatsapp=clean(body.whatsapp,40),email=clean(body.email,180);
  if(!fullName||!whatsapp)return NextResponse.json({error:"Your name and WhatsApp number are required."},{status:400});
  if(email&&!/^\S+@\S+\.\S+$/.test(email))return NextResponse.json({error:"Enter a valid email address."},{status:400});
  const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:business,error:businessError}=await admin.from("businesses").select("id").order("created_at",{ascending:true}).limit(1).single();
  if(businessError||!business)return NextResponse.json({error:"The garage is not ready to receive requests yet."},{status:503});
  if(kind==="enquiry"){
   const enquiryType=clean(body.enquiryType,100),details=clean(body.details,3000),vehicleDetails=clean(body.vehicleDetails,240);
   if(!enquiryType)return NextResponse.json({error:"Choose an enquiry type."},{status:400});
   const {error}=await admin.from("customer_enquiries").insert({business_id:business.id,full_name:fullName,email:email||null,whatsapp,vehicle_details:vehicleDetails||null,enquiry_type:enquiryType,details:details||null});
   if(error)throw error;
   return NextResponse.json({ok:true,message:"Your enquiry has been received by The Garage."});
  }
  if(kind==="spare"){
   const partName=clean(body.partName,180),partNumber=clean(body.partNumber,120),vehicleMake=clean(body.vehicleMake,80),vehicleModel=clean(body.vehicleModel,100),notes=clean(body.notes,2000);
   const quantity=Math.max(1,Math.min(1000,Number(body.quantity)||1));
   if(!partName)return NextResponse.json({error:"Enter the spare part you need."},{status:400});
   const {error}=await admin.from("spare_requests").insert({business_id:business.id,customer_id:null,created_by:null,customer_name:fullName,customer_email:email||null,customer_whatsapp:whatsapp,part_name:partName,part_number:partNumber||null,vehicle_make:vehicleMake||null,vehicle_model:vehicleModel||null,quantity,customer_notes:notes||null});
   if(error)throw error;
   return NextResponse.json({ok:true,message:"Your spare-parts request has been received."});
  }
  return NextResponse.json({error:"Unsupported request type."},{status:400});
 }catch(error){return NextResponse.json({error:error instanceof Error?error.message:"Could not save your request. Please try again."},{status:500});}
}
