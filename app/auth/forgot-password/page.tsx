"use client";

import { FormEvent, useState } from "react";
import { createClient } from "@supabase/supabase-js";

const REDIRECT_URL = "https://garage-ya-joe.vercel.app/auth/reset-password";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setBusy(true);
    try {
      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      if (!url || !key) {
        throw new Error("Password recovery is not configured. Please contact the administrator.");
      }
      const supabase = createClient(url, key, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
      });
      const { error: requestError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: REDIRECT_URL,
      });
      if (requestError) throw requestError;
      setSent(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "We could not send the recovery email. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="forgot-shell">
      <section className="forgot-card">
        <a className="brand" href="/">GARAGE <b>YA JOE</b></a>
        <span className="eyebrow">ACCOUNT SECURITY</span>
        <h1>Forgot your password?</h1>
        <p className="intro">Enter the email address associated with your Garage ya Joe account. We’ll send a secure link to choose a new password.</p>
        {sent ? (
          <div className="success" role="status">
            If an account exists for <strong>{email.trim()}</strong>, a password-reset email has been requested. Check your inbox and spam folder, then open the newest email on this device.
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            <label htmlFor="recovery-email">Email address</label>
            <input id="recovery-email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" />
            {error ? <div className="error" role="alert">{error}</div> : null}
            <button type="submit" disabled={busy}>{busy ? "Sending…" : "Send recovery email"}</button>
          </form>
        )}
        <a className="back" href="/customer">Back to sign in</a>
      </section>
      <style jsx>{`
        .forgot-shell{min-height:100vh;background:#f5f6f1;display:grid;place-items:center;padding:32px 16px;color:#17231f;font-family:Arial,sans-serif}
        .forgot-card{width:min(100%,460px);background:#fff;border:1px solid #e3e8df;border-radius:10px;padding:40px;box-shadow:0 18px 55px #142d2110}
        .brand{display:inline-block;color:#1e493b;font-weight:800;letter-spacing:.08em;font-size:17px;margin-bottom:42px}
        .eyebrow{display:block;color:#71816f;font-size:10px;font-weight:700;letter-spacing:.16em}
        h1{font-size:30px;letter-spacing:-.04em;margin:12px 0}
        .intro{color:#66736d;font-size:14px;line-height:1.7}
        form{display:grid;gap:11px;margin-top:25px}
        label{font-size:12px;font-weight:700;margin-top:7px}
        input{width:100%;padding:13px;border:1px solid #d9e0d8;border-radius:5px;font-size:15px;outline-color:#638044}
        button{margin-top:12px;border:0;border-radius:5px;background:#1e493b;color:#fff;padding:14px;font-weight:700;font-size:13px;cursor:pointer}
        button:disabled{opacity:.6;cursor:wait}
        .error,.success{padding:13px;border-radius:5px;font-size:13px;line-height:1.6;margin-top:18px}
        .error{background:#fff0ee;color:#9b3026}.success{background:#eef6e8;color:#31552b}
        .back{display:inline-block;margin-top:26px;color:#526d40;font-size:12px;font-weight:700}
        @media(max-width:480px){.forgot-card{padding:28px 22px}}
      `}</style>
    </main>
  );
}
