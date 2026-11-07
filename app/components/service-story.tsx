"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowRight, CheckCircle2, Cog, Droplet, Filter, Gauge, Wrench } from "lucide-react";

const stages = [
  { number:"01", label:"ENGINE OIL", title:"Drain the used engine oil.", description:"The vehicle is secured on a lift, the sump plug is removed and old engine oil is collected in a drain pan.", action:"RAISE · DRAIN · COLLECT", image:"https://images.pexels.com/photos/4439585/pexels-photo-4439585.jpeg?auto=compress&cs=tinysrgb&w=1600", alt:"Mechanic working underneath a raised vehicle during an oil change", icon:Droplet },
  { number:"02", label:"OIL FILTER", title:"Renew the oil filter.", description:"The old filter is removed, the sealing surface is checked and a new filter is fitted correctly to the vehicle specification.", action:"REMOVE · INSPECT · FIT", image:"https://images.pexels.com/photos/4439588/pexels-photo-4439588.jpeg?auto=compress&cs=tinysrgb&w=1600", alt:"Automotive mechanic inspecting service components in an engine bay", icon:Wrench },
  { number:"03", label:"FRESH ENGINE OIL", title:"Refill to the correct specification.", description:"Fresh oil of the manufacturer-recommended grade is poured in, then the level is checked using the correct procedure.", action:"SELECT GRADE · REFILL · CHECK", image:"https://images.pexels.com/photos/4439585/pexels-photo-4439585.jpeg?auto=compress&cs=tinysrgb&w=1600", alt:"Engine oil being replenished during routine vehicle maintenance", icon:Gauge },
  { number:"04", label:"TRANSMISSION", title:"Service the gearbox fluid.", description:"The transmission is inspected and, where required, old fluid is drained and replaced with the exact fluid specified for that gearbox.", action:"INSPECT · DRAIN · REFILL", image:"https://images.pexels.com/photos/4439585/pexels-photo-4439585.jpeg?auto=compress&cs=tinysrgb&w=1600", alt:"Transmission service work being carried out in an automotive workshop", icon:Cog },
  { number:"05", label:"AIR FILTER", title:"Replace the dirty air filter.", description:"The air-box is opened, the used filter is removed, the housing is checked and a clean correctly seated filter is installed.", action:"OPEN · REPLACE · SECURE", image:"https://lirp.cdn-website.com/ebfbd06d/dms3rep/multi/opt/Why%2BPreventative%2BMaintenance%2BIs%2Bthe%2BBest%2BAuto%2BEngine%2BRepair%2BBountiful%2BUT-1920w.jpg", alt:"Mechanic checking engine air intake and filter during a service", icon:Filter },
  { number:"06", label:"FINAL CHECKS", title:"Check the work before the drive.", description:"Fluid levels, leaks, service points and the engine bay are checked before the vehicle is lowered and handed back.", action:"VERIFY · CLEAN · HAND OVER", image:"https://images.pexels.com/photos/4439588/pexels-photo-4439588.jpeg?auto=compress&cs=tinysrgb&w=1600", alt:"Professional mechanic inspecting a vehicle in a workshop", icon:CheckCircle2 },
];

export default function ServiceStory() {
  const [active, setActive] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  useEffect(() => {
    if (isPaused) return;
    const timer = window.setInterval(() => setActive((current) => (current + 1) % stages.length), 1500);
    return () => window.clearInterval(timer);
  }, [isPaused]);
  const stage = stages[active];
  const Icon = stage.icon;
  return (
    <section className="service-story" id="care" aria-label="The care in every detail">
      <div className="container">
        <div className="service-story-heading" data-reveal>
          <span className="eyebrow">THE CARE IN EVERY DETAIL</span>
          <h2>One service. <em>Every detail.</em></h2>
          <p>Follow a real workshop service from the first inspection to the final checks. A new part of the process comes into focus every 1.5 seconds.</p>
        </div>
        <div
          className={`service-showcase${isPaused ? " is-paused" : ""}`}
          aria-live="polite"
          aria-atomic="true"
          onMouseEnter={() => setIsPaused(true)}
          onMouseLeave={() => setIsPaused(false)}
          onFocusCapture={() => setIsPaused(true)}
          onBlurCapture={(event) => {
            if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setIsPaused(false);
          }}
        >
          <div className="service-showcase-image" key={stage.number} role="img" aria-label={stage.alt} style={{ backgroundImage: `linear-gradient(90deg, #05090dcc 0%, #05090d55 58%, #05090d22 100%), url("${stage.image}")` }}>
            <div className="showcase-image-top"><span>THE GARAGE <i /> WORKSHOP PROCESS</span><span>{stage.number} / 06</span></div>
            <div className="showcase-image-bottom"><span className="live-dot" /> LIVE SERVICE SEQUENCE</div>
          </div>
          <div className="service-showcase-copy" key={stage.number + "-copy"}>
            <div className="showcase-stage"><span>{stage.number}</span><b>{stage.label}</b></div>
            <div className="showcase-icon"><Icon size={25} strokeWidth={1.6} /></div>
            <h3>{stage.title}</h3><p>{stage.description}</p>
            <div className="showcase-action"><CheckCircle2 size={15} /> {stage.action}</div>
            <div className="showcase-progress" aria-label={`Service step ${active + 1} of ${stages.length}`}>
              {stages.map((item, index) => <button key={item.number} type="button" className={index === active ? "active" : ""} onClick={() => setActive(index)} aria-label={`Show step ${item.number}: ${item.label}`} aria-current={index === active ? "step" : undefined} />)}
            </div>
            <div className="showcase-footer"><span>{isPaused ? "PAUSED · MOVE POINTER AWAY TO RESUME" : "HOVER TO PAUSE · AUTO-ADVANCES EVERY 1.5 SECONDS"}</span><Link href="/enquire">Book a service <ArrowRight size={15} /></Link></div>
          </div>
        </div>
      </div>
    </section>
  );
}
