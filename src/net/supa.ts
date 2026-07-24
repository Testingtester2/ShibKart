import { createClient, type SupabaseClient } from "@supabase/supabase-js";
const url = (import.meta as any).env?.VITE_SUPABASE_URL as string | undefined;
const key = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY as string | undefined;
/** Same env vars as WutCardBoshi. Null when unconfigured -> game runs vs AI only. */
export const supabase: SupabaseClient | null = url && key ? createClient(url, key) : null;
export const netConfigured = () => supabase != null;
