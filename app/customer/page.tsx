"use client";

import { FormEvent, useState } from "react";
import { createClient } from "@supabase/supabase-js";

export default function CustomerSignInPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    setError("");
    try {
      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      if (!url || !key) throw new Error("Sign-in is temporarily unavailable. Please contact the administrator.");
      const supabase = createClient(url, key);
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (signInError) throw signInError;
      setMessage("You are signed in. Your customer dashboard is not yet available; please contact the garage for assistance.");
      setPassword("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "We could not sign you in. Check your details and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="signin-shell">
      <section className="signin-card">
        <a className="brand" href="/">GARAGE <b>YA JOE</b></a>
        <span className="eyebrow">CUSTOMER ACCOUNT</span>
        <h1>Sign in</h1>
        <p className="intro">Sign in to your Garage ya Joe account.</p>
        <form onSubmit={handleSubmit}>
          <label htmlFor="email">Email address</label>
          <input id="email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          <label htmlFor="password">Password</label>
          <input id="password" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
          {error ? <div className="alert" role="alert">{error}</div> : null}
          {message ? <div className="success" role="status">{message}</div> : null}
          <button type="submit" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
        </form>
        <a className="forgot" href="/auth/forgot-password">Forgot your password?</a>
        <a className="back" href="/">Back to Garage ya Joe</a>
      </section>
      <style jsx>{`
        .signin-shell{min-height:100vh;background:#f5f6f1;display:grid;place-items:center;padding:32px 16px;color:#17231f;font-family:Arial,sans-serif}
        .signin-card{width:min(100%,460px);background:#fff;border:1px solid #e3e8df;border-radius:10px;padding:40px;box-shadow:0 18px 55px #142d2110}
        .brand{display:inline-block;color:#1e493b;font-weight:800;letter-spacing:.08em;font-size:17px;margin-bottom:42px}
        .eyebrow{display:block;color:#71816f;font-size:10px;font-weight:700;letter-spacing:.16em}
        h1{font-size:30px;letter-spacing:-.04em;margin:12px 0}
        .intro{color:#66736d;font-size:14px;line-height:1.7}
        form{display:grid;gap:11px;margin-top:25px}
        label{font-size:12px;font-weight:700;margin-top:7px}
        input{width:100%;padding:13px;border:1px solid #d9e0d8;border-radius:5px;font-size:15px;outline-color:#638044}
        button{margin-top:12px;border:0;border-radius:5px;background:#1e493b;color:#fff;padding:14px;font-weight:700;font-size:13px;cursor:pointer}
        button:disabled{opacity:.6;cursor:wait}
        .alert,.success{padding:13px;border-radius:5px;font-size:13px;line-height:1.6;margin-top:10px}
        .alert{background:#fff0ee;color:#9b3026}.success{background:#eef6e8;color:#31552b}
        .forgot,.back{display:block;margin-top:22px;color:#526d40;font-size:12px;font-weight:700}
        .back{margin-top:14px;color:#66736d}
        @media(max-width:480px){.signin-card{padding:28px 22px}}
      `}</style>
    </main>
  );
}
