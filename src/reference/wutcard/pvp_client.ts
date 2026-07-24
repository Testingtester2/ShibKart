// Realtime Supabase client for ranked PvP (Edge Functions + Postgres Realtime).
// Reuses WutCardBoshi's existing env vars. Safe no-op if unconfigured (vs-AI still works).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
const url = (import.meta as any).env?.VITE_SUPABASE_URL as string | undefined;
const key = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY as string | undefined;
export const supabase: SupabaseClient | null = url && key ? createClient(url, key) : null;
export const isSupabaseConfigured = () => supabase != null;
