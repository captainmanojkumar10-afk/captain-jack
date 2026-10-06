# Smart Parking Automation

A responsive parking platform for live slot availability, reservations, vehicle sessions, mock payments, and facility administration.

## Run & Operate

- `pnpm --filter @workspace/smart-parking run dev` — run the parking app
- `pnpm --filter @workspace/api-server run dev` — run the workspace API server (not used for parking data)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required secrets: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- Parking app: React + Vite + TypeScript
- Parking auth/data: Supabase Auth, Postgres, RLS, and Realtime only
- Workspace API/DB scaffold: Express 5 and Drizzle (not used by the parking product)
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `artifacts/smart-parking/src/lib/parking-api.ts` — Supabase client-side data operations
- `artifacts/smart-parking/supabase/migrations/` — Supabase schema, security policies, RPCs, and sample facility data
- `artifacts/smart-parking/src/App.tsx` — route setup and authenticated app shell

## Architecture decisions

- All app persistence and authentication must remain exclusively in Supabase; do not route parking data through the workspace API or Replit PostgreSQL.
- The browser receives only the Supabase URL and anon/public key; RLS and security-definer RPCs enforce user/admin permissions and atomic booking.

## Product

Drivers find available spaces, manage vehicles, reserve slots, and track parking and payment history. Administrators manage facilities, occupancy, reservations, entry/exit, pricing, sensors, and analytics.

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Gotchas

_Populate as you build — sharp edges, "always run X before Y" rules._

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
