# The Garage

Integrated garage services, auto-spares sales and special-order importation platform.

## Technology
- Next.js App Router and TypeScript
- Vercel deployment
- Supabase PostgreSQL, Auth and Storage
- Multi-location design, launching with one location
- Multi-currency transactions with KES as base reporting currency
- Central inventory model supporting multiple warehouses

## Current scaffold
The initial scaffold provides the public landing page and a first database migration for businesses, locations, customer profiles, products, warehouses and stock ledger records. Enquiry submission, customer accounts, staff dashboard, garage jobs, supplier/import workflows, quotations, sales and accounting are planned modules and are not yet operational.

## Local development
1. Install Node.js 20.9 or later.
2. Copy .env.example to .env.local and add the Supabase project URL and publishable/anon key.
3. Run npm install, then npm run dev.

## Supabase
Review supabase/migrations/001_business_foundation.sql before applying it in the Supabase SQL editor. It is intentionally not applied automatically. RLS is enabled with no permissive policies yet, so client access remains closed until business-role and location policies are implemented and reviewed.

## Vercel
Connect this repository to the existing Vercel project garage-ya-joe-blvd. Configure environment variables before enabling database-backed features. Never commit .env.local, service-role keys, database passwords or payment credentials.

## Core rules
- Available stock = on-hand stock minus reserved stock.
- Record stock changes through transactional ledger operations, not arbitrary balance overwrites.
- Preserve transaction currency, exchange rate and KES reporting equivalent on financial records.
- Preserve approved quotation and invoice price snapshots.
- Use server-side privileged operations and business/location-scoped RLS policies.
