/**
 * Supabase wiring with a localStorage fallback so the app works
 * out of the box. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
 * in a .env to enable the real backend.
 *
 * Tables expected on the backend:
 *
 *   create table public.decks (
 *     id uuid primary key default gen_random_uuid(),
 *     name text not null,
 *     author text not null,
 *     author_address text,
 *     description text default '',
 *     cards integer[] not null,
 *     foils text[] default '{}',
 *     likes int default 0,
 *     ratings_sum int default 0,
 *     ratings_count int default 0,
 *     created_at timestamptz default now()
 *   );
 *
 *   create table public.deck_comments (
 *     id uuid primary key default gen_random_uuid(),
 *     deck_id uuid references public.decks(id) on delete cascade,
 *     author text not null,
 *     text text not null,
 *     created_at timestamptz default now()
 *   );
 *
 *   create table public.deck_ratings (
 *     deck_id uuid references public.decks(id) on delete cascade,
 *     voter text not null,
 *     rating int check (rating between 1 and 5),
 *     primary key (deck_id, voter)
 *   );
 *
 *   create table public.chat_messages (
 *     id uuid primary key default gen_random_uuid(),
 *     room text not null default 'lobby',
 *     author text not null,
 *     author_address text,
 *     text text not null,
 *     created_at timestamptz default now()
 *   );
 *
 *   create table public.forum_threads (
 *     id uuid primary key default gen_random_uuid(),
 *     title text not null,
 *     author text not null,
 *     author_address text,
 *     body text not null,
 *     tag text default 'general',
 *     created_at timestamptz default now()
 *   );
 *
 *   create table public.forum_posts (
 *     id uuid primary key default gen_random_uuid(),
 *     thread_id uuid references public.forum_threads(id) on delete cascade,
 *     author text not null,
 *     author_address text,
 *     body text not null,
 *     created_at timestamptz default now()
 *   );
 *
 * Realtime should be enabled on chat_messages.
 * Anon RLS policies should allow insert/select with optional address-based gating.
 */

import { Comment, SavedDeck } from '../types';

import { getSessionToken } from '../game/pvpAuth';
import { getWalletAddress } from './wallet';

const URL = (import.meta as any).env?.VITE_SUPABASE_URL as string | undefined;
const KEY = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY as string | undefined;
export const SUPABASE_ENABLED = !!(URL && KEY);

/** Social WRITES (chat / forum / avatar) go through the authenticated `social`
 *  Edge Function, which stamps the author from a verified session token — so
 *  nobody can post under another player's name. One signature per ~6 h session
 *  (shared with ranked/tournaments), cached. */
async function socialFn(op: string, payload: Record<string, unknown>): Promise<any> {
  const wallet = getWalletAddress();
  if (!wallet) throw new Error('Connect your wallet first.');
  const token = await getSessionToken(wallet);
  if (!token) throw new Error('Sign in with your wallet to post.');
  const r = await fetch(`${URL}/functions/v1/social`, {
    method: 'POST',
    headers: { apikey: KEY!, Authorization: `Bearer ${KEY!}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ op, token, ...payload }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data?.error || 'Post failed');
  return data;
}

async function rest(path: string, init: RequestInit = {}): Promise<any> {
  if (!SUPABASE_ENABLED) throw new Error('supabase not configured');
  const headers: Record<string, string> = {
    apikey: KEY!,
    Authorization: `Bearer ${KEY!}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
    ...((init.headers as Record<string, string>) ?? {}),
  };
  const r = await fetch(`${URL}/rest/v1/${path}`, { ...init, headers });
  if (!r.ok) throw new Error(`supabase ${r.status} ${await r.text()}`);
  return r.json();
}

// ─── Decks ────────────────────────────────────────────────────────────────────

const LS_DECKS = 'wutcardboshi.decks.v2';

function loadLocalDecks(): SavedDeck[] {
  try {
    return JSON.parse(localStorage.getItem(LS_DECKS) ?? '[]');
  } catch {
    return [];
  }
}
function saveLocalDecks(d: SavedDeck[]) {
  localStorage.setItem(LS_DECKS, JSON.stringify(d));
}

export async function listDecks(): Promise<SavedDeck[]> {
  if (!SUPABASE_ENABLED) return loadLocalDecks();
  const rows = await rest('decks?select=*,deck_comments(*)&order=created_at.desc');
  return rows.map(rowToDeck);
}

export async function createDeck(d: Omit<SavedDeck, 'id' | 'likes' | 'ratingsSum' | 'ratingsCount' | 'comments' | 'timestamp'>): Promise<SavedDeck> {
  if (!SUPABASE_ENABLED) {
    const next: SavedDeck = {
      id: crypto.randomUUID(),
      ...d,
      likes: 0,
      ratingsSum: 0,
      ratingsCount: 0,
      comments: [],
      timestamp: Date.now(),
    };
    const all = [...loadLocalDecks(), next];
    saveLocalDecks(all);
    return next;
  }
  // author stamped server-side from the token
  const { row } = await socialFn('deck_publish', {
    deck: { name: d.name, description: d.description, cards: d.cards, foils: d.foils ?? [] },
  });
  return rowToDeck(row);
}

export async function likeDeck(id: string): Promise<{ liked: boolean; likes: number } | null> {
  if (!SUPABASE_ENABLED) {
    // local mode: toggle a single like per deck so the count can't be stacked
    const key = 'wutcardboshi.liked:' + id;
    const wasLiked = !!localStorage.getItem(key);
    if (wasLiked) localStorage.removeItem(key); else localStorage.setItem(key, '1');
    let likes = 0;
    saveLocalDecks(loadLocalDecks().map((d) => {
      if (d.id !== id) return d;
      likes = Math.max(0, d.likes + (wasLiked ? -1 : 1));
      return { ...d, likes };
    }));
    return { liked: !wasLiked, likes };
  }
  // authenticated so likes come from a real wallet; the RPC toggles one like
  // per wallet and returns the authoritative { liked, likes }
  const res = await socialFn('deck_like', { deckId: id });
  return res ? { liked: !!res.liked, likes: Number(res.likes ?? 0) } : null;
}

export async function rateDeck(id: string, voter: string, rating: number): Promise<void> {
  if (!SUPABASE_ENABLED) {
    const all = loadLocalDecks().map((d) => {
      if (d.id !== id) return d;
      const key = 'wutcardboshi.rated:' + id + ':' + voter;
      const prev = Number(localStorage.getItem(key)) || 0;
      const next: SavedDeck = { ...d };
      if (prev) {
        next.ratingsSum = next.ratingsSum - prev + rating;
      } else {
        next.ratingsSum = next.ratingsSum + rating;
        next.ratingsCount = next.ratingsCount + 1;
      }
      localStorage.setItem(key, String(rating));
      return next;
    });
    saveLocalDecks(all);
    return;
  }
  // voter is stamped from the token server-side — can't rate as someone else
  await socialFn('deck_rate', { deckId: id, rating });
}

export async function commentOnDeck(
  id: string,
  author: string,
  text: string,
  authorAddress?: string | null,
): Promise<Comment> {
  if (!SUPABASE_ENABLED) {
    const c: Comment = {
      id: crypto.randomUUID(),
      author,
      authorAddress: authorAddress ?? null,
      text,
      timestamp: Date.now(),
    };
    const all = loadLocalDecks().map((d) => (d.id === id ? { ...d, comments: [...d.comments, c] } : d));
    saveLocalDecks(all);
    return c;
  }
  // author stamped server-side from the token
  const { row } = await socialFn('deck_comment', { deckId: id, text });
  return rowToComment(row);
}

// ─── Chat ─────────────────────────────────────────────────────────────────────

const LS_CHAT = 'wutcardboshi.chat.lobby';

export interface ChatMessage {
  id: string;
  room: string;
  author: string;
  authorAddress?: string | null;
  text: string;
  timestamp: number;
}

export async function listChat(room = 'lobby'): Promise<ChatMessage[]> {
  if (!SUPABASE_ENABLED) {
    try {
      return JSON.parse(localStorage.getItem(LS_CHAT) ?? '[]');
    } catch {
      return [];
    }
  }
  const rows = await rest(`chat_messages?room=eq.${room}&order=created_at.asc&limit=200`);
  return rows.map(rowToChat);
}
export async function sendChat(room: string, author: string, text: string, authorAddress?: string | null): Promise<ChatMessage> {
  if (!SUPABASE_ENABLED) {
    const m: ChatMessage = {
      id: crypto.randomUUID(),
      room,
      author,
      authorAddress: authorAddress ?? null,
      text,
      timestamp: Date.now(),
    };
    const all = [...(await listChat(room)), m].slice(-200);
    localStorage.setItem(LS_CHAT, JSON.stringify(all));
    return m;
  }
  // author is stamped server-side from the session token (params ignored)
  const { row } = await socialFn('chat', { room, text });
  return rowToChat(row);
}

/** Realtime not implemented for the localStorage fallback; caller polls. */
export function subscribeChat(_room: string, _onMsg: (m: ChatMessage) => void): () => void {
  if (!SUPABASE_ENABLED) return () => {};
  // Realtime over Postgres changes. Skipped here to keep the bundle deps zero;
  // the chat panel polls every 4s when SUPABASE_ENABLED. A future PR can swap
  // this for the @supabase/supabase-js realtime client.
  return () => {};
}

// ─── Presence ────────────────────────────────────────────────────────────────

export interface PresenceUser {
  id: string;
  name: string;
  isAnon: boolean;
  lastSeen: number;
}

/** Upsert the user's presence row. Spoof-resistant by relying on the client
 *  picking a stable id (wallet address or a localStorage uuid) — there's no
 *  authority gating it, but the data is non-financial. */
export async function heartbeat(id: string, name: string, isAnon: boolean): Promise<void> {
  if (!SUPABASE_ENABLED) return;
  if (!id || !name) return;
  await rest('chat_presence?on_conflict=id', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify({ id, name, is_anon: isAnon, last_seen: new Date().toISOString() }),
  }).catch(() => {});
}

// ─── Profile avatars (boshi as pfp) ──────────────────────────────────────────
//
// Owner-claimed (no JWT) — same trust model as chat_messages. Used by every
// place a wallet's identity appears: chat row avatars, online sidebar, forum
// authors, deck authors, trade-offer makers.
//
// Reads are cached in localStorage for PROFILE_TTL_MS so we don't hammer
// Supabase on every chat row render (otherwise a 200-message backlog would
// fire 200 GETs every time the chat tab mounts).

export interface ProfileAvatar {
  address: string;
  boshiTokenId: string;
  imageUrl: string | null;
}

const PROFILE_TTL_MS = 24 * 60 * 60 * 1000;
const PROFILE_NEG_TTL_MS = 30 * 60 * 1000;
const PROFILE_CACHE_KEY = 'wutcardboshi.profiles.v1';

interface ProfileCacheEntry {
  data: ProfileAvatar | null;
  ts: number;
}

function loadProfileCache(): Record<string, ProfileCacheEntry> {
  if (typeof localStorage === 'undefined') return {};
  try {
    return JSON.parse(localStorage.getItem(PROFILE_CACHE_KEY) ?? '{}');
  } catch {
    return {};
  }
}

function saveProfileCache(c: Record<string, ProfileCacheEntry>) {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(c));
  } catch {
    /* quota / private mode — ignore */
  }
}

/**
 * Fetch a wallet's selected Boshi pfp. Cached for 24 h on positive hits and
 * 30 m on negative hits so the same address doesn't get re-fetched while a
 * chat backlog renders.
 */
export async function fetchProfile(address: string): Promise<ProfileAvatar | null> {
  if (!address) return null;
  const key = address.toLowerCase();
  const cache = loadProfileCache();
  const hit = cache[key];
  if (hit) {
    const ttl = hit.data ? PROFILE_TTL_MS : PROFILE_NEG_TTL_MS;
    if (Date.now() - hit.ts < ttl) return hit.data;
  }
  if (!SUPABASE_ENABLED) {
    cache[key] = { data: null, ts: Date.now() };
    saveProfileCache(cache);
    return null;
  }
  const rows = await rest(`profile_avatars?address=eq.${encodeURIComponent(key)}&select=*`).catch(
    () => [] as unknown[],
  );
  const row = (rows as Array<{
    address: string;
    boshi_token_id: string;
    image_url: string | null;
  }>)[0];
  const data: ProfileAvatar | null = row
    ? { address: row.address, boshiTokenId: row.boshi_token_id, imageUrl: row.image_url }
    : null;
  cache[key] = { data, ts: Date.now() };
  saveProfileCache(cache);
  return data;
}

/** Upsert the caller's selected avatar; also updates the local cache. */
export async function setProfile(
  address: string,
  boshi: { tokenId: string; imageUrl?: string | null },
): Promise<void> {
  if (!address) return;
  const key = address.toLowerCase();
  const data: ProfileAvatar = {
    address: key,
    boshiTokenId: boshi.tokenId,
    imageUrl: boshi.imageUrl ?? null,
  };
  const cache = loadProfileCache();
  cache[key] = { data, ts: Date.now() };
  saveProfileCache(cache);
  if (!SUPABASE_ENABLED) return;
  // address stamped server-side from the token — can't set another wallet's PFP
  await socialFn('avatar_set', { tokenId: boshi.tokenId, imageUrl: boshi.imageUrl ?? null }).catch(() => {});
}

/** Drop the caller's avatar (revert to initials). */
export async function clearProfile(address: string): Promise<void> {
  if (!address) return;
  const key = address.toLowerCase();
  const cache = loadProfileCache();
  cache[key] = { data: null, ts: Date.now() };
  saveProfileCache(cache);
  if (!SUPABASE_ENABLED) return;
  await socialFn('avatar_clear', {}).catch(() => {});
}

export async function listOnline(thresholdSeconds = 60): Promise<PresenceUser[]> {
  if (!SUPABASE_ENABLED) return [];
  const cutoff = new Date(Date.now() - thresholdSeconds * 1000).toISOString();
  const rows = await rest(`chat_presence?last_seen=gt.${cutoff}&order=last_seen.desc&limit=100`).catch(
    () => [] as unknown[],
  );
  return (rows as Array<{ id: string; name: string; is_anon: boolean; last_seen: string }>).map((r) => ({
    id: r.id,
    name: r.name,
    isAnon: r.is_anon,
    lastSeen: new Date(r.last_seen).getTime(),
  }));
}

// ─── Forum ────────────────────────────────────────────────────────────────────

export interface ForumThread {
  id: string;
  title: string;
  author: string;
  authorAddress?: string | null;
  body: string;
  tag: string;
  timestamp: number;
  postCount?: number;
}

export interface ForumPost {
  id: string;
  threadId: string;
  author: string;
  authorAddress?: string | null;
  body: string;
  timestamp: number;
}

const LS_THREADS = 'wutcardboshi.forum.threads';
const LS_POSTS = 'wutcardboshi.forum.posts';

export async function listThreads(): Promise<ForumThread[]> {
  if (!SUPABASE_ENABLED) {
    const threads: ForumThread[] = JSON.parse(localStorage.getItem(LS_THREADS) ?? '[]');
    const posts: ForumPost[] = JSON.parse(localStorage.getItem(LS_POSTS) ?? '[]');
    return threads.map((t) => ({
      ...t,
      postCount: posts.filter((p) => p.threadId === t.id).length,
    }));
  }
  const rows = await rest('forum_threads?select=*,forum_posts(count)&order=created_at.desc');
  return rows.map((r: any) => ({
    id: r.id,
    title: r.title,
    author: r.author,
    authorAddress: r.author_address,
    body: r.body,
    tag: r.tag,
    timestamp: new Date(r.created_at).getTime(),
    postCount: r.forum_posts?.[0]?.count ?? 0,
  }));
}

export async function createThread(t: Omit<ForumThread, 'id' | 'timestamp' | 'postCount'>): Promise<ForumThread> {
  if (!SUPABASE_ENABLED) {
    const next: ForumThread = { ...t, id: crypto.randomUUID(), timestamp: Date.now(), postCount: 0 };
    const all: ForumThread[] = JSON.parse(localStorage.getItem(LS_THREADS) ?? '[]');
    localStorage.setItem(LS_THREADS, JSON.stringify([next, ...all]));
    return next;
  }
  // author stamped server-side from the token
  const { row } = await socialFn('thread', { title: t.title, body: t.body, tag: t.tag });
  return {
    id: row.id,
    title: row.title,
    author: row.author,
    authorAddress: row.author_address,
    body: row.body,
    tag: row.tag,
    timestamp: new Date(row.created_at).getTime(),
    postCount: 0,
  };
}

export async function listPosts(threadId: string): Promise<ForumPost[]> {
  if (!SUPABASE_ENABLED) {
    const posts: ForumPost[] = JSON.parse(localStorage.getItem(LS_POSTS) ?? '[]');
    return posts.filter((p) => p.threadId === threadId).sort((a, b) => a.timestamp - b.timestamp);
  }
  const rows = await rest(`forum_posts?thread_id=eq.${threadId}&order=created_at.asc`);
  return rows.map((r: any) => ({
    id: r.id,
    threadId: r.thread_id,
    author: r.author,
    authorAddress: r.author_address,
    body: r.body,
    timestamp: new Date(r.created_at).getTime(),
  }));
}

export async function createPost(p: Omit<ForumPost, 'id' | 'timestamp'>): Promise<ForumPost> {
  if (!SUPABASE_ENABLED) {
    const next: ForumPost = { ...p, id: crypto.randomUUID(), timestamp: Date.now() };
    const all: ForumPost[] = JSON.parse(localStorage.getItem(LS_POSTS) ?? '[]');
    localStorage.setItem(LS_POSTS, JSON.stringify([...all, next]));
    return next;
  }
  // author stamped server-side from the token
  const { row } = await socialFn('post', { threadId: p.threadId, body: p.body });
  return {
    id: row.id,
    threadId: row.thread_id,
    author: row.author,
    authorAddress: row.author_address,
    body: row.body,
    timestamp: new Date(row.created_at).getTime(),
  };
}

// ── helpers ──
function rowToDeck(r: any): SavedDeck {
  return {
    id: r.id,
    name: r.name,
    author: r.author,
    authorAddress: r.author_address ?? null,
    description: r.description ?? '',
    cards: r.cards ?? [],
    foils: r.foils ?? [],
    likes: r.likes ?? 0,
    ratingsSum: r.ratings_sum ?? 0,
    ratingsCount: r.ratings_count ?? 0,
    comments: (r.deck_comments ?? []).map(rowToComment).sort((a: Comment, b: Comment) => a.timestamp - b.timestamp),
    timestamp: new Date(r.created_at).getTime(),
  };
}
function rowToComment(r: any): Comment {
  return {
    id: r.id,
    author: r.author,
    authorAddress: r.author_address ?? null,
    text: r.text,
    timestamp: new Date(r.created_at ?? Date.now()).getTime(),
  };
}
function rowToChat(r: any): ChatMessage {
  return {
    id: r.id,
    room: r.room,
    author: r.author,
    authorAddress: r.author_address ?? null,
    text: r.text,
    timestamp: new Date(r.created_at).getTime(),
  };
}
