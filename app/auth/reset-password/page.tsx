"use client";

import { FormEvent, useEffect, useState } from "react";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

let browserClient: SupabaseClient | null = null;

function getSupabase() {
  if (browserClient) return browserClient;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error("Password reset is not configured. Please contact the administrator.");
  browserClient = createClient(url, key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return browserClient;
}

export default function ResetPasswordPage() {
  const [ready, setReady] = useState(false);
  const [checking, setChecking] = useState(true);
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    let client: SupabaseClient;
    try {
      client = getSupabase();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Supabase is not configured.");
      setChecking(false);
      return;
    }

    const params = new URLSearchParams(window.location.search);
    const tokenHash = params.get("token_hash");
    const recoveryType = params.get("type");
    const { data: listener } = client.auth.onAuthStateChange((event, session) => {
      if (!active) return;
      if (event === "PASSWORD_RECOVERY" && session) {
        setReady(true);
        setChecking(false);
        setError("");
      }
    });

    async function completeRecovery() {
      try {
        if (tokenHash && recoveryType === "recovery") {
          const { data, error: verifyError } = await client.auth.verifyOtp({
            token_hash: tokenHash,
            type: "recovery",
          });
          if (verifyError) throw verifyError;
          if (active) setReady(Boolean(data.session));
        } else {
          const code = params.get("code");
          if (code) {
            const { error: exchangeError } = await client.auth.exchangeCodeForSession(code);
            if (exchangeError) throw exchangeError;
          }
          const { data, error: sessionError } = await client.auth.getSession();
          if (sessionError) throw sessionError;
          if (active && data.session) setReady(true);
          else if (active) setError("This password-reset link is missing or has expired. Request a new password-reset email.");
        }
      } catch (recoveryError) {
        if (active) setError(recoveryError instanceof Error ? recoveryError.message : "This password-reset link is invalid or has expired. Request a new one.");
      } finally {
        if (active) setChecking(false);
      }
    }
    void completeRecovery();

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setMessage("");
    if (password.length < 8) {
      setError("Use a password with at least 8 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setError("The passwords do not match.");
      return;
    }
    setBusy(true);
    try {
      const client = getSupabase();
      const { error: updateError } = await client.auth.updateUser({ password });
      if (updateError) throw updateError;
      setMessage("Your password has been updated. You can now sign in with your new password.");
      setPassword("");
      setConfirmPassword("");
      await client.auth.signOut();
    } catch (e) {
      setError(e instanceof Error ? e.message : "We could not update your password. Request a new reset link and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="reset-shell">
      <section className="reset-card">
        <a className="reset-brand" href="/">THE GARAGE</a>
        <span className="reset-eyebrow">ACCOUNT SECURITY</span>
        <h1>Set a new password</h1>
        <p className="reset-intro">Choose a new password for your The Garage account.</p>

        {checking ? <p className="reset-note">Checking your secure reset link…</p> : null}
        {!checking && error && !ready ? <div className="reset-alert" role="alert">{error}</div> : null}
        {message ? <div className="reset-success" role="status">{message} <a href="/customer">Go to customer sign in</a>.</div> : null}

        {ready && !message ? (
          <form className="reset-form" onSubmit={handleSubmit}>
            <label htmlFor="new-password">New password</label>
            <input id="new-password" type="password" autoComplete="new-password" minLength={8} required value={password} onChange={(e) => setPassword(e.target.value)} />
            <label htmlFor="confirm-password">Confirm new password</label>
            <input id="confirm-password" type="password" autoComplete="new-password" minLength={8} required value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} />
            {error ? <div className="reset-alert" role="alert">{error}</div> : null}
            <button type="submit" disabled={busy}>{busy ? "Updating password…" : "Update password"}</button>
          </form>
        ) : null}

        {!checking && !ready && !message ? <p className="reset-help">Return to the sign-in page and request another password-reset email. Make sure you open the newest email.</p> : null}
        <a className="reset-back" href="/customer">Back to customer sign in</a>
      </section>
      <style jsx>{`
        .reset-shell{min-height:100vh;background:#f5f6f1;display:grid;place-items:center;padding:32px 16px;color:#17231f;font-family:Arial,sans-serif}
        .reset-card{width:min(100%,460px);background:#fff;border:1px solid #e3e8df;border-radius:10px;padding:40px;box-shadow:0 18px 55px #142d2110}
        .reset-brand{display:inline-block;color:#1e493b;font-weight:800;letter-spacing:.08em;font-size:17px;margin-bottom:42px}
        .reset-eyebrow{display:block;color:#71816f;font-size:10px;font-weight:700;letter-spacing:.16em}
        h1{font-size:30px;letter-spacing:-.04em;margin:12px 0}
        .reset-intro,.reset-help{color:#66736d;font-size:14px;line-height:1.7}
        .reset-form{display:grid;gap:10px;margin-top:25px}
        label{font-size:12px;font-weight:700;margin-top:7px}
        input{width:100%;padding:13px;border:1px solid #d9e0d8;border-radius:5px;font-size:15px;outline-color:#638044}
        button{margin-top:12px;border:0;border-radius:5px;background:#1e493b;color:#fff;padding:14px;font-weight:700;font-size:13px;cursor:pointer}
        button:disabled{opacity:.6;cursor:wait}
        .reset-alert,.reset-success,.reset-note{padding:12px;border-radius:5px;font-size:13px;line-height:1.6;margin-top:18px}
        .reset-alert{background:#fff0ee;color:#9b3026}.reset-success{background:#eef6e8;color:#31552b}.reset-success a{font-weight:700;text-decoration:underline}
        .reset-note{background:#f1f4ed;color:#53634f}
        .reset-back{display:inline-block;margin-top:26px;color:#526d40;font-size:12px;font-weight:700}
        @media(max-width:480px){.reset-card{padding:28px 22px}}
      `}</style>
    </main>
  );
}
