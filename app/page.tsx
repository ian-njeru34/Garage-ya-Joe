import Link from "next/link";
import { ArrowRight, Wrench, CarFront, PackageSearch, Ship, ShieldCheck, Clock3, Search } from "lucide-react";

const services = [
  { icon: Wrench, title: "Vehicle servicing", text: "Routine maintenance, diagnostics and scheduled servicing." },
  { icon: CarFront, title: "Repairs & inspection", text: "Practical repairs, vehicle checks and clear job updates." },
  { icon: PackageSearch, title: "Auto spares", text: "Find parts by name, brand, SKU or OEM reference." },
  { icon: Ship, title: "Special imports", text: "Request hard-to-find parts and receive an import quotation." }
];

export default function HomePage() {
  return <main>
    <div className="utility"><div className="container utility-inner"><span>Garage ya Joe · Automotive care and parts</span><Link href="/customer">Customer account ↗</Link></div></div>
    <header className="site-header"><div className="container nav">
      <Link className="brand" href="/"><span className="brand-mark">J</span><span>GARAGE <b>YA JOE</b><small>GARAGE · AUTO SPARES · IMPORTS</small></span></Link>
      <nav><a href="#services">Services</a><a href="#spares">Auto spares</a><a href="#how">How it works</a><a href="#contact">Contact</a></nav>
      <Link className="nav-cta" href="#contact">Enquire <ArrowRight size={16}/></Link>
    </div></header>
    <section className="hero"><div className="container hero-grid">
      <div className="hero-copy"><span className="eyebrow"><i/> YOUR VEHICLE, OUR PRIORITY</span><h1>Reliable garage care.<br/><em>The right parts.</em></h1>
        <p>From everyday servicing to hard-to-find imported spares, get practical automotive support in one place.</p>
        <div className="hero-actions"><Link className="button primary" href="/enquire">Book a garage service <ArrowRight size={17}/></Link><Link className="button outline" href="/spares">Find a spare part</Link></div>
        <div className="trust"><span><ShieldCheck size={16}/> Clear quotations</span><span><Clock3 size={16}/> Service updates</span></div>
      </div>
      <div className="hero-panel"><div className="panel-top"><b>GARAGE YA JOE</b><span>● READY TO HELP</span></div><div className="wheel"><div>J</div></div><div className="panel-bottom"><b>One trusted destination</b><span>Garage services · Parts · Sourcing</span></div></div>
    </div></section>
    <section className="search-section" id="spares"><div className="container search-card"><div><span className="eyebrow">LOOKING FOR A PART?</span><h2>Find the part you need.</h2><p>Search by part name, brand, SKU or OEM number.</p></div><form action="/spares" className="search-form"><Search size={19}/><input name="q" placeholder="e.g. Toyota Hilux oil filter" aria-label="Search spare parts"/><button>Search parts <ArrowRight size={16}/></button></form></div></section>
    <section className="section" id="services"><div className="container"><div className="section-heading"><div><span className="eyebrow">WHAT WE DO</span><h2>Automotive support,<br/><em>all under one roof.</em></h2></div><p>Whether your vehicle needs attention or you need a specific component, start with one simple enquiry.</p></div>
      <div className="service-grid">{services.map(({icon:Icon,title,text},i)=><article className="service-card" key={title}><span className="number">0{i+1}</span><div className="service-icon"><Icon size={23}/></div><h3>{title}</h3><p>{text}</p><Link href="/enquire">Explore service <ArrowRight size={15}/></Link></article>)}</div>
    </div></section>
    <section className="process" id="how"><div className="container process-inner"><div><span className="eyebrow">STRAIGHTFORWARD FROM START TO FINISH</span><h2>Know what happens<br/><em>at every step.</em></h2></div><div className="steps"><div><b>01</b><span><strong>Tell us what you need</strong><small>Share your vehicle details, service request or part reference.</small></span></div><div><b>02</b><span><strong>Review your quotation</strong><small>We confirm scope, availability, pricing and timing.</small></span></div><div><b>03</b><span><strong>Approve and track</strong><small>Proceed with the work or sourcing and stay informed.</small></span></div></div></div></section>
    <section className="contact" id="contact"><div className="container contact-box"><div><span className="eyebrow">LET'S GET YOU MOVING</span><h2>What can we help<br/><em>you with today?</em></h2><p>Send an enquiry for a garage service, spare part or import request. Enquire as a guest or create a customer account.</p></div><div className="contact-actions"><Link className="button primary" href="/enquire">Make an enquiry <ArrowRight size={17}/></Link><Link className="button light" href="/customer">Customer login</Link><small>Branch details and business contacts will be configured in Settings.</small></div></div></section>
    <footer><div className="container footer"><b>GARAGE YA JOE</b><span>© {new Date().getFullYear()} Garage ya Joe. All rights reserved.</span><span>Garage · Auto spares · Imports</span></div></footer>
  </main>;
}
