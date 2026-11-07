import Link from "next/link";
import { ArrowRight, Wrench, CarFront, PackageSearch, Ship, ShieldCheck, Clock3, Search, Heart, Gauge, Settings2, ChevronUp, MapPin, Phone } from "lucide-react";
import ScrollExperience from "./components/scroll-experience";

const services = [
  { icon: Wrench, title: "Vehicle servicing", text: "Routine maintenance, diagnostics and scheduled servicing." },
  { icon: CarFront, title: "Repairs & inspection", text: "Careful repairs, vehicle checks and clear job updates." },
  { icon: PackageSearch, title: "Auto spares", text: "Find parts by name, brand, SKU or OEM reference." },
  { icon: Ship, title: "Special imports", text: "Source hard-to-find parts and get an import quotation." }
];

export default function HomePage() {
  return <ScrollExperience>
    <main>
      <div id="top" />
      <div className="utility"><div className="container utility-inner"><span><MapPin size={13}/> AUTOMOTIVE CARE · KENYA</span><Link href="/customer">Customer account <ArrowRight size={13}/></Link></div></div>
      <header className="site-header"><div className="container nav">
        <Link className="brand" href="/"><span className="brand-mark">J<span>.</span></span><span>GARAGE <b>YA JOE</b><small>GARAGE · AUTO SPARES · IMPORTS</small></span></Link>
        <nav><a href="#services">Services</a><a href="#spares">Auto spares</a><a href="#how">Our process</a><a href="#contact">Contact</a></nav>
        <Link className="nav-cta" href="/enquire">Let's talk <ArrowRight size={16}/></Link>
      </div></header>

      <section className="hero">
        <div className="hero-image" role="img" aria-label="Premium dark sports car in a dramatic automotive studio" />
        <div className="hero-shade" />
        <div className="container hero-content">
          <div className="hero-copy" data-reveal>
            <span className="eyebrow"><i/> THIS VALENTINE'S, SHOW YOUR CAR SOME LOVE</span>
            <h1>Love your drive.<br/><em>Trust the care.</em></h1>
            <p>Expert garage care, quality auto spares and hard-to-find imports — all in one place. Your journey deserves the right attention.</p>
            <div className="hero-actions"><Link className="button primary" href="/enquire">Book a garage service <ArrowRight size={17}/></Link><Link className="button ghost" href="/spares">Find a spare part</Link></div>
            <div className="trust"><span><ShieldCheck size={16}/> Clear quotations</span><span><Clock3 size={16}/> Updates you can trust</span></div>
          </div>
          <div className="hero-note" data-reveal><Heart size={17}/><span>For every mile<br/><b>that matters.</b></span></div>
          <a className="scroll-cue" href="#spares"><span/> SCROLL TO EXPLORE</a>
        </div>
      </section>

      <section className="search-section" id="spares"><div className="container search-card" data-reveal><div><span className="eyebrow">THE PART YOU'RE LOOKING FOR</span><h2>Find it. Fit it. Get moving.</h2><p>Search by part name, brand, SKU or OEM number.</p></div><form action="/spares" className="search-form"><Search size={19}/><input name="q" placeholder="e.g. Toyota Hilux oil filter" aria-label="Search spare parts"/><button>Search parts <ArrowRight size={16}/></button></form></div></section>

      <section className="section" id="services"><div className="container"><div className="section-heading" data-reveal><div><span className="eyebrow">THE GARAGE YA JOE DIFFERENCE</span><h2>Everything your car needs.<br/><em>Nothing it doesn't.</em></h2></div><p>From preventative maintenance to sourcing a rare component, get straightforward support from one trusted destination.</p></div>
        <div className="service-grid">{services.map(({icon:Icon,title,text},i)=><article className="service-card" data-reveal key={title}><span className="number">0{i+1}</span><div className="service-icon"><Icon size={23}/></div><h3>{title}</h3><p>{text}</p><Link href="/enquire">Explore service <ArrowRight size={15}/></Link></article>)}</div>
      </div></section>

      <section className="feature-band"><div className="container feature-inner"><div className="feature-image" data-reveal><div className="feature-stamp"><Gauge size={23}/><span>CARE IN<br/>EVERY DETAIL</span></div></div><div className="feature-copy" data-reveal><span className="eyebrow">MORE THAN A GARAGE</span><h2>Good service is<br/><em>built on trust.</em></h2><p>We believe looking after your vehicle should feel simple. Understand the work, review the quotation and stay informed as your service or parts request moves forward.</p><div className="feature-points"><span><ShieldCheck/> Transparent quotations</span><span><Settings2/> Practical automotive solutions</span><span><Heart/> Care that goes the extra mile</span></div><Link className="text-link" href="/enquire">Talk to our team <ArrowRight size={16}/></Link></div></div></section>

      <section className="process" id="how"><div className="container process-inner"><div data-reveal><span className="eyebrow">A BETTER WAY TO GET IT DONE</span><h2>Simple from the<br/><em>first hello.</em></h2><p>One clear process, with you in control at every step.</p></div><div className="steps">{[["01","Tell us what you need","Share your vehicle details, service request or part reference."],["02","Review your quotation","We confirm the scope, availability, pricing and timing."],["03","Approve and track","Proceed with the work or sourcing and stay informed."]].map(([n,t,d])=><div data-reveal key={n}><b>{n}</b><span><strong>{t}</strong><small>{d}</small></span></div>)}</div></div></section>

      <section className="contact" id="contact"><div className="container contact-box" data-reveal><div><span className="eyebrow">LET'S GET YOU MOVING</span><h2>Ready when<br/><em>you are.</em></h2><p>Tell us what your vehicle needs, find a spare part or request a special import quotation. Start an enquiry in just a few steps.</p></div><div className="contact-actions"><Link className="button primary" href="/enquire">Make an enquiry <ArrowRight size={17}/></Link><Link className="button light" href="/customer">Customer login</Link><small><Phone size={13}/> Contact details can be managed from business settings.</small></div></div></section>

      <footer><div className="container footer"><div className="footer-brand"><span className="brand-mark">J<span>.</span></span><b>GARAGE YA JOE</b></div><span>© {new Date().getFullYear()} Garage ya Joe. All rights reserved.</span><span>Garage · Auto spares · Imports</span><a href="#top">Back to top ↑</a></div></footer>
      <button className="back-top" aria-label="Back to top" onClick={() => window.scrollTo({top:0,behavior:"smooth"})}><ChevronUp size={20}/></button>
    </main>
  </ScrollExperience>;
}
