import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const maxDuration = 60;

const REPOSITORY = "ian-njeru34/Garage-ya-Joe";
const DIRECTORY = "public/images/care";
const ALLOWED = new Set([
  "hero-main.jpg",
  "01-engine-oil-drain.jpg",
  "02-oil-filter-change.jpg",
  "03-engine-oil-refill.jpg",
  "04-transmission-fluid-service.jpg",
  "05-air-filter-replacement.jpg",
  "06-final-vehicle-checks.jpg",
]);
const GITHUB_API = "https://api.github.com";

async function authorize(request: NextRequest) {
  const authorization = request.headers.get("authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) return { response: NextResponse.json({ error: "Please sign in as the business owner." }, { status: 401 }) };
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } }
  );
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) return { response: NextResponse.json({ error: "Your session has expired. Please sign in again." }, { status: 401 }) };
  const { data: ownerRoles, error: roleError } = await supabase.from("user_roles")
    .select("business_id").eq("user_id", authData.user.id).eq("role_code", "owner").limit(1);
  if (roleError || !ownerRoles?.length) return { response: NextResponse.json({ error: "Owner permission required." }, { status: 403 }) };
  return { user: authData.user };
}

async function github(path: string, init?: RequestInit) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("Image uploads are not configured yet. Add the GITHUB_TOKEN environment variable in Vercel.");
  return fetch(`${GITHUB_API}/repos/${REPOSITORY}/contents/${path}`, {
    ...init,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      ...(init?.headers || {}),
    },
    cache: "no-store",
  });
}

export async function GET(request: NextRequest) {
  const access = await authorize(request);
  if ("response" in access) return access.response;
  try {
    const response = await github(DIRECTORY);
    if (response.status === 404) return NextResponse.json({ files: [] });
    if (!response.ok) return NextResponse.json({ error: "Could not check the image repository." }, { status: 502 });
    const items = await response.json();
    const files = Array.isArray(items) ? items.filter((item: any) => ALLOWED.has(item.name)).map((item: any) => item.name) : [];
    return NextResponse.json({ files });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Image repository unavailable." }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const access = await authorize(request);
  if ("response" in access) return access.response;
  try {
    const form = await request.formData();
    const file = form.get("file");
    const filename = String(form.get("filename") || "");
    if (!ALLOWED.has(filename)) return NextResponse.json({ error: "This image filename is not permitted." }, { status: 400 });
    if (!(file instanceof File)) return NextResponse.json({ error: "Choose an image file to upload." }, { status: 400 });
    if (file.size < 1 || file.size > 15 * 1024 * 1024) return NextResponse.json({ error: "Images must be smaller than 15 MB." }, { status: 413 });
    if (file.type !== "image/jpeg" || !filename.endsWith(".jpg")) return NextResponse.json({ error: "Please upload a JPEG image (.jpg)." }, { status: 415 });
    const bytes = Buffer.from(await file.arrayBuffer());
    if (bytes.length < 3 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
      return NextResponse.json({ error: "The selected file is not a valid JPEG image." }, { status: 415 });
    }
    const path = `${DIRECTORY}/${filename}`;
    const existing = await github(path);
    let sha: string | undefined;
    if (existing.ok) {
      const previous = await existing.json();
      sha = previous.sha;
    } else if (existing.status !== 404) {
      return NextResponse.json({ error: "Could not check the existing image before replacing it." }, { status: 502 });
    }
    const response = await github(path, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        message: `Upload care process image: ${filename}`,
        content: bytes.toString("base64"),
        branch: "main",
        ...(sha ? { sha } : {}),
      }),
    });
    const result = await response.json();
    if (!response.ok) {
      const message = response.status === 401 || response.status === 403
        ? "GitHub rejected the repository write. Check that GITHUB_TOKEN has Contents: Read and write permission."
        : result?.message || "GitHub could not save this image.";
      return NextResponse.json({ error: message }, { status: response.status === 409 ? 409 : 502 });
    }
    return NextResponse.json({
      ok: true,
      filename,
      path: `/images/care/${filename}`,
      commit: result.commit?.sha || null,
      replaced: Boolean(sha),
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Image upload failed." }, { status: 500 });
  }
}
