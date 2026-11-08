import SiteFooter from "./components/site-footer";
import Link from "next/link";
import { ArrowRight, Wrench, CarFront, PackageSearch, Ship, ShieldCheck, Clock3, Search, Gauge, Settings2, MapPin, Phone, Droplet, Filter, Cog, CheckCircle2 } from "lucide-react";
import ScrollExperience from "./components/scroll-experience";
import BackToTop from "./components/back-to-top";
import ServiceStory from "./components/service-story";
import GarageLogo from "./components/garage-logo";
import {BusinessName} from "./components/business-branding";
import VehicleAdSlider from "./components/vehicle-ad-slider";
import CallButton from "./components/call-button";

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
      <div className="utility"><div className="container utility-inner"><span><MapPin size={13}/> AUTOMOTIVE CARE · KENYA</span><div className="utility-actions"><CallButton compact/><Link href="/customer">Customer account <ArrowRight size={13}/></Link></div></div></div>
      <header className="site-header"><div className="container nav">
        <Link className="brand" href="/" aria-label="Business home"><GarageLogo /><span className="brand-wordmark"><BusinessName uppercase/><small>CARE · PERFORMANCE · PARTS</small></span></Link>
        <nav><a href="#services">Services</a><a href="#spares">Auto spares</a><a href="#how">Our process</a><a href="#contact">Contact</a></nav>
        <Link className="nav-cta" href="/enquire">Let's talk <ArrowRight size={16}/></Link>
      </div></header>

      <section className="hero">
        <div className="hero-image" role="img" aria-label="Premium dark sports car in a dramatic automotive studio" />
        <div className="hero-shade" />
        <div className="container hero-content">
          <div className="hero-copy hero-copy-minimal" data-reveal>
            <div className="hero-actions"><Link className="button primary" href="/enquire">Book a garage service <ArrowRight size={17}/></Link><Link className="button ghost" href="/spares">Find a spare part</Link></div>
            <div className="trust"><span><ShieldCheck size={16}/> Clear quotations</span><span><Clock3 size={16}/> Updates you can trust</span></div>
          </div>
          <a className="scroll-cue" href="#spares"><span/> SCROLL TO EXPLORE</a>
        </div>
      </section>

      <section className="search-section" id="spares"><div className="container search-card" data-reveal><div><span className="eyebrow">THE PART YOU'RE LOOKING FOR</span><h2>Find it. Fit it. Get moving.</h2><p>Search by part name, brand, SKU or OEM number.</p></div><form action="/spares" className="search-form"><Search size={19}/><input name="q" placeholder="e.g. Toyota Hilux oil filter" aria-label="Search spare parts"/><button>Search parts <ArrowRight size={16}/></button></form></div></section>

      <section className="section" id="services"><div className="container"><div className="section-heading" data-reveal><div><span className="eyebrow"><BusinessName uppercase/> DIFFERENCE</span><h2>Everything your car needs.<br/><em>Nothing it doesn't.</em></h2></div><p>From preventative maintenance to sourcing a rare component, get straightforward support from one trusted destination.</p></div>
        <div className="service-grid">{services.map(({icon:Icon,title,text},i)=><article className="service-card" data-reveal key={title}><span className="number">0{i+1}</span><div className="service-icon"><Icon size={23}/></div><h3>{title}</h3><p>{text}</p><Link href="/enquire">Explore service <ArrowRight size={15}/></Link></article>)}</div>
      </div></section>

      <ServiceStory />

      <section className="process" id="how"><div className="container process-inner"><div data-reveal><span className="eyebrow">A BETTER WAY TO GET IT DONE</span><h2>Simple from the<br/><em>first hello.</em></h2><p>One clear process, with you in control at every step.</p></div><div className="steps">{[["01","Tell us what you need","Share your vehicle details, service request or part reference."],["02","Review your quotation","We confirm the scope, availability, pricing and timing."],["03","Approve and track","Proceed with the work or sourcing and stay informed."]].map(([n,t,d])=><div data-reveal key={n}><b>{n}</b><span><strong>{t}</strong><small>{d}</small></span></div>)}</div></div></section>

      <section className="contact" id="contact"><div className="container contact-split"><div className="vehicle-ad-column"><VehicleAdSlider/></div><div className="contact-box" data-reveal><span className="eyebrow">LET'S GET YOU MOVING</span><h2>Ready when<br/><em>you are.</em></h2><p>Tell us what your vehicle needs, find a spare part or request a special import quotation. Start an enquiry in just a few steps.</p><div className="contact-actions"><Link className="button primary" href="/enquire">Make an enquiry <ArrowRight size={17}/></Link><Link className="button light" href="/customer">Customer login</Link><small><Phone size={13}/> Call or message our team.</small></div></div></div></section>

      <div className="home-call-bar"><CallButton/></div><SiteFooter />
      <BackToTop />
    </main>
  </ScrollExperience>;
}
