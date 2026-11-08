"use client";

import { useEffect, useState } from "react";
import { createClient, User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import GarageLogo from "../components/garage-logo";
import {BusinessName} from "../components/business-branding";
import {
  LayoutDashboard, Wrench, Users, Package, Warehouse, Ship, CarFront,
  FileText, ShoppingCart, Wallet, UserCog, Settings, LogOut,
  ShieldCheck, ArrowUpRight, MessageCircle, RefreshCw
} from "lucide-react";

const sections = [
  { label: "Overview", href: "/owner", icon: LayoutDashboard, description: "Business activity and key updates" },
  { label: "Garage", href: "/owner/garage", icon: Wrench, description: "Appointments, inspections and job cards" },
  { label: "Customers", href: "/owner/customers", icon: Users, description: "Customer accounts and service history" },
  { label: "Vehicle adverts", href: "/owner/vehicles-for-sale", icon: CarFront, description: "Create, publish, edit, hide and delete cars advertised on the homepage" },
  { label: "Enquiries", href: "/owner/enquiries", icon: MessageCircle, description: "Customer requests and WhatsApp follow-up" },
  { label: "Auto Spares", href: "/owner/spares", icon: Package, description: "Parts catalogue and sales enquiries" },
  { label: "Inventory", href: "/owner/inventory", icon: Warehouse, description: "Stock levels, receipts and transfers" },
  { label: "Importation", href: "/owner/importation", icon: Ship, description: "Special orders and imported parts" },
  { label: "Quotations", href: "/owner/quotations", icon: FileText, description: "Prepare and manage customer quotations" },
  { label: "Sales", href: "/owner/sales", icon: ShoppingCart, description: "Orders and sales fulfilment" },
  { label: "Invoices & payments", href: "/owner/invoices", icon: Wallet, description: "Issue PDF receipts, share invoices on WhatsApp and record customer payments" },
  { label: "Finance", href: "/owner/finance", icon: Wallet, description: "Cash flow and financial records" },
  { label: "Staff", href: "/owner/staff", icon: UserCog, description: "Team members, roles and access" },
  { label: "Branches & locations", href: "/owner/locations", icon: Warehouse, description: "Manage branches, garages and business locations" },
  { label: "Settings", href: "/owner/settings", icon: Settings, description: "Public contact and social media settings" },
];

const metricDefinitions = [
  { key: "customers", label: "Customers", table: "customers", href: "/owner/customers", icon: Users },
  { key: "appointments", label: "Service bookings", table: "service_appointments", href: "/owner/garage", icon: Wrench },
  { key: "jobs", label: "Open job cards", table: "job_cards", href: "/owner/garage", icon: FileText },
  { key: "products", label: "Parts catalogue", table: "products", href: "/owner/spares", icon: Package },
  { key: "imports", label: "Import requests", table: "import_requests", href: "/owner/importation", icon: Ship },
  { key: "shipments", label: "Shipments", table: "shipments", href: "/owner/importation/shipments", icon: TruckIcon },
  { key: "quotations", label: "Quotations", table: "quotations", href: "/owner/quotations", icon: FileText },
  { key: "invoices", label: "Invoices", table: "invoices", href: "/owner/invoices", icon: Wallet },
];

function TruckIcon({size=18}:{size?:number}) { return <Ship size={size}/>; }

export default function OwnerDashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [checking, setChecking] = useState(true);
  const [error, setError] = useState("");
  const [signingOut, setSigningOut] = useState(false);
  const [metrics, setMetrics] = useState<Record<string, number | null>>({});
  const [refreshing, setRefreshing] = useState(false);
  const [refreshedAt, setRefreshedAt] = useState("");

  async function loadMetrics(businessId: string) {
    const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const entries = await Promise.all(metricDefinitions.map(async item => {
      let query = supabase.from(item.table).select("id", { count: "exact", head: true }).eq("business_id", businessId);
      if (item.key === "jobs") query = query.not("status", "in", "(completed,invoiced,closed)");
      if (item.key === "appointments") query = query.not("status", "in", "(completed,cancelled,converted)");
      if (item.key === "shipments") query = query.not("status", "in", "(received,cancelled)");
      const { count, error } = await query;
      return [item.key, error ? null : (count ?? 0)] as const;
    }));
    setMetrics(Object.fromEntries(entries));
    setRefreshedAt(new Date().toLocaleTimeString("en-KE", { hour: "2-digit", minute: "2-digit" }));
  }

  useEffect(() => {
    let alive = true;
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !key) {
      setError("The account service is not configured. Please contact the administrator.");
      setChecking(false);
      return;
    }
    const supabase = createClient(url, key);
    async function verify() {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        router.replace("/customer");
        return;
      }
      const { data: roles, error: roleError } = await supabase
        .from("user_roles")
        .select("role_code,business_id,location_id")
        .eq("user_id", authData.user.id);
      const owner = roles?.find(role => role.role_code === "owner");
      if (roleError || !owner?.business_id) {
        await supabase.auth.signOut();
        router.replace("/customer");
        return;
      }
      if (alive) {
        setUser(authData.user);
        setChecking(false);
        void loadMetrics(owner.business_id).catch(() => setError("Some dashboard totals could not be loaded. Use Refresh to try again."));
      }
    }
    void verify().catch(() => {
      if (alive) {
        setError("We could not verify your owner access. Please sign in again.");
        setChecking(false);
      }
    });
    return () => { alive = false; };
  }, [router]);

  async function refresh() {
    if (!user) return;
    setRefreshing(true);
    const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data: roles } = await supabase.from("user_roles").select("business_id").eq("user_id", user.id).eq("role_code", "owner").limit(1);
    if (roles?.[0]?.business_id) await loadMetrics(roles[0].business_id);
    setRefreshing(false);
  }

  async function signOut() {
    setSigningOut(true);
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (url && key) await createClient(url, key).auth.signOut();
    router.replace("/customer");
    router.refresh();
  }

  if (checking) return <main className="state"><div className="state-card">Verifying owner access…</div><style jsx>{".state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;font:14px Arial;color:#52645a}.state-card{padding:28px;background:white;border:1px solid #e3e8df;border-radius:8px}"}</style></main>;
  if (error && !user) return <main className="state"><div className="state-card"><p>{error}</p><a href="/customer">Return to sign in</a></div><style jsx>{".state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;font:14px Arial;color:#52645a}.state-card{padding:28px;background:white;border:1px solid #e3e8df;border-radius:8px}.state-card a{color:#42643a;font-weight:bold}"}</style></main>;

  return (
    <main className="owner-shell">
      <aside className="sidebar">
        <a className="brand" href="/"><GarageLogo/><span><BusinessName uppercase/><small>OWNER WORKSPACE</small></span></a>
        <div className="side-label">WORKSPACE</div>
        <nav>{sections.map(({label,href,icon:Icon},index)=><a key={href} href={href} className={index===0?"active":""}><Icon size={17}/><span>{label}</span>{index===0?<i/>:null}</a>)}</nav>
        <div className="side-bottom"><ShieldCheck size={16}/><span>Owner access verified</span></div>
      </aside>
      <section className="main">
        <header className="topbar"><div><span className="crumb"><BusinessName/></span><span className="slash">/</span><b>Overview</b></div><div className="account"><span className="avatar">{(user?.email?.[0]||"O").toUpperCase()}</span><span className="account-email">{user?.email}</span><button onClick={signOut} disabled={signingOut}><LogOut size={15}/><span>{signingOut?"Signing out…":"Sign out"}</span></button></div></header>
        <div className="content">
          <div className="welcome"><div><span className="eyebrow">BUSINESS MANAGEMENT</span><h1>Owner overview</h1><p>Live operational snapshot for your garage, parts, procurement and sales.</p></div><span className="verified"><ShieldCheck size={15}/> Owner account</span></div>
          <section className="overview-panel">
            <div className="panel-head"><div><b>Business activity</b><p>Live totals are read from your business records and refresh on demand.</p></div><button onClick={()=>void refresh()} disabled={refreshing}><RefreshCw size={14}/>{refreshing?"Refreshing…":"Refresh"}</button></div>
            <div className="metric-grid">{metricDefinitions.map(({key,label,href,icon:Icon})=><a className="metric" href={href} key={key}><span className="metric-icon"><Icon size={17}/></span><span className="metric-copy"><small>{label}</small><b>{metrics[key]===undefined?"…":metrics[key]===null?"—":metrics[key]?.toLocaleString("en-KE")}</b></span><ArrowUpRight size={14} className="metric-arrow"/></a>)}</div>
            <div className="updated">{refreshedAt?"Last refreshed at "+refreshedAt:"Loading business totals…"}{error?<span>{error}</span>:null}</div>
          </section>
          <div className="section-head"><div><h2>Business modules</h2><p>Open a module to complete day-to-day work.</p></div><span>MAIN BRANCH</span></div>
          <div className="module-grid">{sections.slice(1).map(({label,href,icon:Icon,description})=><a href={href} key={href} className="module"><div className="module-icon"><Icon size={20}/></div><div className="module-copy"><b>{label}</b><p>{description}</p></div><ArrowUpRight size={16} className="arrow"/></a>)}</div>
          <footer><BusinessName uppercase/> <span>·</span> Owner workspace</footer>
        </div>
      </section>
      <style jsx>{`
        .owner-shell{min-height:100vh;background:#f5f6f1;color:#17231f;font-family:Arial,sans-serif;display:grid;grid-template-columns:250px 1fr}
        .sidebar{background:#17382e;color:#e7eee8;padding:25px 16px;display:flex;flex-direction:column;min-height:100vh}
        .brand{display:flex;align-items:center;gap:10px;padding:0 8px 30px;color:#fff;font-size:14px;font-weight:800;letter-spacing:.06em}.brand :global(.brand-mark){width:45px;height:38px;display:block;flex:none}.brand small{display:block;color:#a9bcb0;font-size:8px;letter-spacing:.16em;margin-top:4px}
        .side-label{font-size:9px;font-weight:700;letter-spacing:.17em;color:#91a79a;padding:8px 12px 12px}nav{display:grid;gap:4px}nav a{height:42px;padding:0 12px;display:flex;align-items:center;gap:12px;border-radius:5px;color:#c4d1c8;font-size:12px;font-weight:600}nav a.active{background:#2a5141;color:#fff}nav a i{width:6px;height:6px;border-radius:50%;background:#c5e46a;margin-left:auto}
        .side-bottom{margin-top:auto;border-top:1px solid #ffffff20;padding:17px 9px 4px;display:flex;align-items:center;gap:9px;color:#bfd0c2;font-size:10px}
        .main{min-width:0}.topbar{height:68px;background:white;border-bottom:1px solid #e3e8df;display:flex;align-items:center;justify-content:space-between;padding:0 34px;font-size:11px}.crumb{color:#849087}.slash{padding:0 10px;color:#bdc6be}.topbar b{color:#34443b}.account{display:flex;align-items:center;gap:10px}.avatar{width:29px;height:29px;border-radius:50%;background:#eaf1df;color:#416237;display:grid;place-items:center;font-weight:800}.account-email{color:#536158}.account button{border:0;background:transparent;color:#58685d;display:flex;align-items:center;gap:6px;font-size:11px;cursor:pointer;margin-left:12px}
        .content{max-width:1250px;margin:auto;padding:38px 34px}.welcome{display:flex;align-items:flex-end;justify-content:space-between;gap:20px}.eyebrow{font-size:9px;font-weight:800;letter-spacing:.17em;color:#748477}.welcome h1{font-size:32px;letter-spacing:-.05em;margin:9px 0}.welcome p{font-size:13px;color:#6b786f;margin:0}.verified{display:flex;align-items:center;gap:7px;color:#456c37;background:#edf4e7;border-radius:30px;padding:9px 13px;font-size:10px;font-weight:700;white-space:nowrap}
        .overview-panel{margin-top:27px;background:#fff;border:1px solid #e2e9dc;border-radius:6px;padding:19px}.panel-head{display:flex;align-items:center;justify-content:space-between;gap:12px}.panel-head b{font-size:13px}.panel-head p{margin:5px 0 0;color:#748077;font-size:11px}.panel-head button{display:flex;align-items:center;gap:7px;border:1px solid #dfe7dc;background:#f7f9f5;color:#45613c;padding:9px 11px;border-radius:4px;font-size:10px;font-weight:bold}.metric-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:9px;margin-top:18px}.metric{border:1px solid #e9eee7;border-radius:5px;padding:12px;display:flex;align-items:center;gap:10px;min-width:0}.metric:hover{border-color:#aabf91}.metric-icon{width:31px;height:31px;border-radius:5px;background:#eff4e8;color:#52733d;display:grid;place-items:center;flex:none}.metric-copy{display:grid;gap:4px;min-width:0}.metric-copy small{font-size:9px;color:#7a877e}.metric-copy b{font-size:18px;color:#263b30}.metric-arrow{margin-left:auto;color:#9aa69c;flex:none}.updated{margin-top:12px;font-size:9px;color:#879188;display:flex;gap:10px;flex-wrap:wrap}.updated span{color:#9b4c42}
        .section-head{display:flex;align-items:end;justify-content:space-between;margin:31px 0 16px}.section-head h2{font-size:17px;margin:0 0 5px}.section-head p{font-size:11px;color:#7a877e;margin:0}.section-head>span{font-size:9px;letter-spacing:.12em;font-weight:800;color:#78877c;background:#e9eee6;padding:8px 10px;border-radius:4px}.module-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}.module{min-height:105px;background:#fff;border:1px solid #e4e9e2;border-radius:6px;padding:17px;display:flex;align-items:flex-start;gap:12px;transition:border-color .15s,transform .15s}.module:hover{border-color:#aabf91;transform:translateY(-1px)}.module-icon{width:36px;height:36px;border-radius:5px;background:#eff4e8;color:#52733d;display:grid;place-items:center;flex:none}.module-copy{min-width:0;flex:1}.module-copy b{font-size:12px}.module-copy p{font-size:10px;line-height:1.55;color:#758178;margin:6px 0 0}.arrow{color:#9aa69c;flex:none}
        footer{margin-top:40px;border-top:1px solid #e1e7df;padding-top:17px;font-size:9px;letter-spacing:.12em;color:#839087;font-weight:700}footer span{padding:0 5px}
        @media(max-width:1050px){.owner-shell{grid-template-columns:215px 1fr}.metric-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.module-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.content{padding:30px 24px}.topbar{padding:0 24px}}
        @media(max-width:700px){.owner-shell{display:block}.sidebar{min-height:auto;padding:15px 14px}.brand{padding:0 4px 14px}.side-label{display:none}nav{display:flex;overflow:auto;padding-bottom:4px}nav a{flex:none;padding:0 11px}nav a span{white-space:nowrap}.side-bottom{display:none}.topbar{padding:0 16px}.account-email{display:none}.content{padding:27px 16px}.welcome{align-items:flex-start;flex-direction:column}.metric-grid{grid-template-columns:1fr 1fr}.module-grid{grid-template-columns:1fr}.section-head{margin-top:27px}}
        @media(max-width:420px){.metric-grid{grid-template-columns:1fr}.panel-head{align-items:flex-start;flex-direction:column}}
      `}</style>
    </main>
  );
}
