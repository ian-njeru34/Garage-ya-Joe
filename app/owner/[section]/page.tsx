"use client";

import { useEffect, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { useParams, useRouter } from "next/navigation";
import {
  LayoutDashboard, Wrench, Users, Package, Warehouse, Ship,
  FileText, ShoppingCart, Wallet, UserCog, Settings, ArrowLeft,
  ShieldCheck, Construction
} from "lucide-react";

const modules = {
  garage: { title: "Garage", description: "Appointments, vehicle inspections, job cards and workshop progress.", icon: Wrench, tasks: ["Appointments and booking calendar", "Vehicle arrival and inspection", "Job cards and work progress", "Mechanic assignments and final inspection"] },
  customers: { title: "Customers", description: "Customer records, contact details and vehicle service history.", icon: Users, tasks: ["Customer directory and profiles", "Customer contact and account details", "Vehicles linked to customers", "Service and transaction history"] },
  spares: { title: "Auto Spares", description: "Manage the parts catalogue, pricing and customer enquiries.", icon: Package, tasks: ["Parts catalogue and product details", "Retail prices and availability", "Customer spare-part enquiries", "Link parts to garage jobs"] },
  inventory: { title: "Inventory", description: "Manage stock across warehouses with traceable stock movements.", icon: Warehouse, tasks: ["Stock on hand and reserved quantities", "Goods receipts and stock adjustments", "Warehouse transfers", "Stock movement history"] },
  importation: { title: "Importation", description: "Track customer special orders and imported spare parts.", icon: Ship, tasks: ["Import and sourcing requests", "Supplier quotations and orders", "Shipment and customs documents", "Landed cost allocation and receipt"] },
  quotations: { title: "Quotations", description: "Prepare, review and manage customer quotations.", icon: FileText, tasks: ["Create quotations for parts and labour", "Set validity and payment terms", "Record customer approval", "Convert accepted quotations into orders"] },
  sales: { title: "Sales", description: "Manage orders, invoices and customer payments.", icon: ShoppingCart, tasks: ["Sales orders and order fulfilment", "Invoices and credit notes", "Record customer payments", "Sales history and receipts"] },
  finance: { title: "Finance", description: "Review business cash flow and financial records.", icon: Wallet, tasks: ["Income and expense records", "Cash and bank accounts", "Accounts receivable and payable", "Financial reports and reconciliations"] },
  staff: { title: "Staff", description: "Manage team members, roles and access to business locations.", icon: UserCog, tasks: ["Staff directory and invitations", "Role assignments and permissions", "Branch and warehouse access", "Staff activity and account status"] },
  settings: { title: "Settings", description: "Configure business information, branches and system preferences.", icon: Settings, tasks: ["Business profile and contact details", "Branches and warehouses", "Currency and tax preferences", "System and security settings"] },
} as const;

type ModuleKey = keyof typeof modules;

export default function OwnerModulePage() {
  const params = useParams<{ section: string }>();
  const router = useRouter();
  const section = params.section as ModuleKey;
  const item = modules[section];
  const [checking, setChecking] = useState(true);
  const [allowed, setAllowed] = useState(false);
  const [email, setEmail] = useState("");

  useEffect(() => {
    let alive = true;
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !key) {
      router.replace("/customer");
      return;
    }
    const supabase = createClient(url, key);
    async function verify() {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) {
        router.replace("/customer");
        return;
      }
      const { data: roles, error: roleError } = await supabase
        .from("user_roles")
        .select("role_code")
        .eq("user_id", data.user.id);
      if (roleError || !roles?.some((role) => role.role_code === "owner")) {
        router.replace("/customer");
        return;
      }
      if (alive) {
        setEmail(data.user.email ?? "");
        setAllowed(true);
        setChecking(false);
      }
    }
    void verify().catch(() => router.replace("/customer"));
    return () => { alive = false; };
  }, [router]);

  if (checking) return <main className="state">Verifying owner access…<style jsx>{`.state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;color:#52645a;font:14px Arial}`}</style></main>;
  if (!allowed) return null;
  if (!item) return <main className="state"><section><h1>Section not found</h1><p>This owner workspace section does not exist.</p><a href="/owner">Return to overview</a></section><style jsx>{`.state{min-height:100vh;display:grid;place-items:center;background:#f5f6f1;color:#263b30;font:14px Arial}.state section{background:white;padding:32px;border:1px solid #e3e8df;border-radius:8px}.state a{color:#42643a;font-weight:bold}`}</style></main>;

  const Icon = item.icon;
  return (
    <main className="shell">
      <header className="top"><a href="/owner" className="back"><ArrowLeft size={16}/> Owner overview</a><span className="identity"><ShieldCheck size={15}/> {email}</span></header>
      <section className="content">
        <div className="eyebrow">GARAGE YA JOE · OWNER WORKSPACE</div>
        <div className="heading"><div className="icon"><Icon size={25}/></div><div><h1>{item.title}</h1><p>{item.description}</p></div></div>
        <div className="status"><Construction size={18}/><div><b>Module setup in progress</b><p>This section is now connected to the owner workspace. Its operational screens and actions are being implemented; no transactions can be created here yet.</p></div></div>
        <h2>Planned capabilities</h2>
        <div className="tasks">{item.tasks.map((task,index)=><div className="task" key={task}><span>{String(index+1).padStart(2,"0")}</span><b>{task}</b></div>)}</div>
        <a className="return" href="/owner"><LayoutDashboard size={16}/> Return to owner overview</a>
      </section>
      <style jsx>{`
        .shell{min-height:100vh;background:#f5f6f1;color:#17231f;font-family:Arial,sans-serif}.top{height:64px;background:white;border-bottom:1px solid #e3e8df;padding:0 max(24px,calc((100vw - 1100px)/2));display:flex;align-items:center;justify-content:space-between}.back{display:flex;align-items:center;gap:8px;color:#476345;font-size:12px;font-weight:700}.identity{display:flex;align-items:center;gap:7px;color:#718075;font-size:11px}.content{max-width:1100px;margin:auto;padding:48px 24px}.eyebrow{font-size:9px;font-weight:800;letter-spacing:.16em;color:#829083}.heading{display:flex;align-items:center;gap:16px;margin:18px 0 30px}.icon{width:54px;height:54px;background:#eaf1e1;color:#52733d;border-radius:8px;display:grid;place-items:center}.heading h1{font-size:30px;letter-spacing:-.04em;margin:0 0 7px}.heading p{font-size:13px;color:#6b786f;margin:0;line-height:1.6}.status{background:#fff;border:1px solid #e2e9dc;border-left:3px solid #91b64d;border-radius:6px;padding:20px;display:flex;gap:14px;color:#52733d;align-items:flex-start}.status b{font-size:13px;color:#263b30}.status p{font-size:12px;line-height:1.7;color:#6b786f;margin:6px 0 0;max-width:750px}.content h2{font-size:16px;margin:35px 0 14px}.tasks{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.task{background:#fff;border:1px solid #e4e9e2;border-radius:5px;padding:17px;display:flex;align-items:center;gap:13px}.task span{font-size:10px;color:#7d9367;font-weight:800}.task b{font-size:12px;font-weight:600;color:#45544a}.return{display:inline-flex;align-items:center;gap:8px;margin-top:30px;background:#1e493b;color:white;padding:12px 16px;border-radius:5px;font-size:11px;font-weight:700}
        @media(max-width:600px){.top{padding:0 16px}.identity{font-size:0}.content{padding:32px 16px}.tasks{grid-template-columns:1fr}.heading h1{font-size:25px}}
      `}</style>
    </main>
  );
}
