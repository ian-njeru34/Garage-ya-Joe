"use client";

import { useEffect, useState } from "react";
import { createClient, User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import GarageLogo from "../components/garage-logo";
import {
  LayoutDashboard, Wrench, Users, Package, Warehouse, Ship, CarFront,
  FileText, ShoppingCart, Wallet, UserCog, Settings, LogOut,
  Menu, ShieldCheck, ArrowUpRight, MessageCircle
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
  { label: "Sales", href: "/owner/sales", icon: ShoppingCart, description: "Orders, invoices and payments" },
  { label: "Finance", href: "/owner/finance", icon: Wallet, description: "Cash flow and financial records" },
  { label: "Staff", href: "/owner/staff", icon: UserCog, description: "Team members, roles and access" },
  { label: "Settings", href: "/owner/settings", icon: Settings, description: "Business, branch and system settings" },
];

export default function OwnerDashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [checking, setChecking] = useState(true);
  const [error, setError] = useState("");
  const [signingOut, setSigningOut] = useState(false);

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
      if (roleError || !roles?.some((role) => role.role_code === "owner")) {
        await supabase.auth.signOut();
        router.replace("/customer");
        return;
      }
      if (alive) {
        setUser(authData.user);
        setChecking(false);
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

  async function signOut() {
    setSigningOut(true);
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (url && key) await createClient(url, key).auth.signOut();
    router.replace("/customer");
    router.refresh();
  }

  if (checking) return <main className="state"><div className="state-card">Verifying owner access…</div><style jsx>{`.state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;font:14px Arial;color:#52645a}.state-card{padding:28px;background:white;border:1px solid #e3e8df;border-radius:8px}`}</style></main>;
  if (error) return <main className="state"><div className="state-card"><p>{error}</p><a href="/customer">Return to sign in</a></div><style jsx>{`.state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;font:14px Arial;color:#52645a}.state-card{padding:28px;background:white;border:1px solid #e3e8df;border-radius:8px}.state-card a{color:#42643a;font-weight:bold}`}</style></main>;

  return (
    <main className="owner-shell">
      <aside className="sidebar">
        <a className="brand" href="/"><GarageLogo/><span>THE GARAGE<small>OWNER WORKSPACE</small></span></a>
        <div className="side-label">WORKSPACE</div>
        <nav>{sections.map(({label,href,icon:Icon},index)=><a key={href} href={href} className={index===0?"active":""}><Icon size={17}/><span>{label}</span>{index===0?<i/>:null}</a>)}</nav>
        <div className="side-bottom"><ShieldCheck size={16}/><span>Owner access verified</span></div>
      </aside>
      <section className="main">
        <header className="topbar"><div><span className="crumb">The Garage</span><span className="slash">/</span><b>Overview</b></div><div className="account"><span className="avatar">{(user?.email?.[0]||"O").toUpperCase()}</span><span className="account-email">{user?.email}</span><button onClick={signOut} disabled={signingOut}><LogOut size={15}/><span>{signingOut?"Signing out…":"Sign out"}</span></button></div></header>
        <div className="content">
          <div className="welcome"><div><span className="eyebrow">BUSINESS MANAGEMENT</span><h1>Owner overview</h1><p>Welcome to your The Garage workspace. Manage your operations from one place.</p></div><span className="verified"><ShieldCheck size={15}/> Owner account</span></div>
          <section className="notice"><div className="notice-icon"><LayoutDashboard size={19}/></div><div><b>Your owner workspace is ready to configure</b><p>This is the secure starting point for your business dashboard. Operational summaries will appear here as garage, inventory, sales and finance workflows are connected.</p></div></section>
          <div className="section-head"><div><h2>Business modules</h2><p>Choose an area to manage.</p></div><span>MAIN BRANCH</span></div>
          <div className="module-grid">{sections.slice(1).map(({label,href,icon:Icon,description})=><a href={href} key={href} className="module"><div className="module-icon"><Icon size={20}/></div><div className="module-copy"><b>{label}</b><p>{description}</p></div><ArrowUpRight size={16} className="arrow"/></a>)}</div>
          <footer>THE GARAGE <span>·</span> Owner workspace</footer>
        </div>
      </section>
      <style jsx>{`
        .owner-shell{min-height:100vh;background:#f5f6f1;color:#17231f;font-family:Arial,sans-serif;display:grid;grid-template-columns:250px 1fr}
        .sidebar{background:#17382e;color:#e7eee8;padding:25px 16px;display:flex;flex-direction:column;min-height:100vh}
        .brand{display:flex;align-items:center;gap:10px;padding:0 8px 30px;color:#fff;font-size:14px;font-weight:800;letter-spacing:.06em}
        .brand :global(.brand-mark){width:45px;height:38px;display:block;flex:none}
        .brand small{display:block;color:#a9bcb0;font-size:8px;letter-spacing:.16em;margin-top:4px}
        .side-label{font-size:9px;font-weight:700;letter-spacing:.17em;color:#91a79a;padding:8px 12px 12px}
        nav{display:grid;gap:4px}nav a{height:42px;padding:0 12px;display:flex;align-items:center;gap:12px;border-radius:5px;color:#c4d1c8;font-size:12px;font-weight:600}nav a.active{background:#2a5141;color:#fff}nav a i{width:6px;height:6px;border-radius:50%;background:#c5e46a;margin-left:auto}
        .side-bottom{margin-top:auto;border-top:1px solid #ffffff20;padding:17px 9px 4px;display:flex;align-items:center;gap:9px;color:#bfd0c2;font-size:10px}
        .main{min-width:0}.topbar{height:68px;background:white;border-bottom:1px solid #e3e8df;display:flex;align-items:center;justify-content:space-between;padding:0 34px;font-size:11px}.crumb{color:#849087}.slash{padding:0 10px;color:#bdc6be}.topbar b{color:#34443b}
        .account{display:flex;align-items:center;gap:10px}.avatar{width:29px;height:29px;border-radius:50%;background:#eaf1df;color:#416237;display:grid;place-items:center;font-weight:800}.account-email{color:#536158}.account button{border:0;background:transparent;color:#58685d;display:flex;align-items:center;gap:6px;font-size:11px;cursor:pointer;margin-left:12px}.content{max-width:1250px;margin:auto;padding:38px 34px}.welcome{display:flex;align-items:flex-end;justify-content:space-between;gap:20px}.eyebrow{font-size:9px;font-weight:800;letter-spacing:.17em;color:#748477}.welcome h1{font-size:32px;letter-spacing:-.05em;margin:9px 0}.welcome p{font-size:13px;color:#6b786f;margin:0}.verified{display:flex;align-items:center;gap:7px;color:#456c37;background:#edf4e7;border-radius:30px;padding:9px 13px;font-size:10px;font-weight:700;white-space:nowrap}
        .notice{margin-top:30px;background:#fff;border:1px solid #e2e9dc;border-left:3px solid #91b64d;border-radius:6px;padding:20px;display:flex;gap:14px;align-items:flex-start}.notice-icon{width:38px;height:38px;border-radius:6px;background:#eff4e8;color:#52733d;display:grid;place-items:center;flex:none}.notice b{font-size:13px}.notice p{margin:6px 0 0;color:#6b786f;font-size:12px;line-height:1.7;max-width:760px}
        .section-head{display:flex;align-items:end;justify-content:space-between;margin:34px 0 16px}.section-head h2{font-size:17px;margin:0 0 5px}.section-head p{font-size:11px;color:#7a877e;margin:0}.section-head>span{font-size:9px;letter-spacing:.12em;font-weight:800;color:#78877c;background:#e9eee6;padding:8px 10px;border-radius:4px}
        .module-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}.module{min-height:105px;background:#fff;border:1px solid #e4e9e2;border-radius:6px;padding:17px;display:flex;align-items:flex-start;gap:12px;transition:border-color .15s,transform .15s}.module:hover{border-color:#aabf91;transform:translateY(-1px)}.module-icon{width:36px;height:36px;border-radius:5px;background:#eff4e8;color:#52733d;display:grid;place-items:center;flex:none}.module-copy{min-width:0;flex:1}.module-copy b{font-size:12px}.module-copy p{font-size:10px;line-height:1.55;color:#758178;margin:6px 0 0}.arrow{color:#9aa69c;flex:none}
        footer{margin-top:40px;border-top:1px solid #e1e7df;padding-top:17px;font-size:9px;letter-spacing:.12em;color:#839087;font-weight:700}footer span{padding:0 5px}
        @media(max-width:1050px){.owner-shell{grid-template-columns:215px 1fr}.module-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.content{padding:30px 24px}.topbar{padding:0 24px}}
        @media(max-width:700px){.owner-shell{display:block}.sidebar{min-height:auto;padding:15px 14px}.brand{padding:0 4px 14px}.side-label{display:none}nav{display:flex;overflow:auto;padding-bottom:4px}nav a{flex:none;padding:0 11px}nav a span{white-space:nowrap}.side-bottom{display:none}.topbar{padding:0 16px}.account-email{display:none}.content{padding:27px 16px}.welcome{align-items:flex-start;flex-direction:column}.module-grid{grid-template-columns:1fr}.section-head{margin-top:27px}}
      `}</style>
    </main>
  );
}
