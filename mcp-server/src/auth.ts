/**
 * Shared-secret access check. AI apps send the secret as
 * `Authorization: Bearer <secret>`, `X-API-Key: <secret>`, or (for clients
 * that only accept a URL, e.g. "No authentication" connectors) as the `key`
 * query parameter. Comparison is constant-time on SHA-256 digests.
 */
import { createHash, timingSafeEqual } from 'node:crypto';

export const MIN_SECRET_LENGTH = 32;

export function presentedSecret(req: Request): string | null {
  const auth = req.headers.get('authorization');
  if (auth) {
    const m = /^Bearer\s+(.+)$/i.exec(auth.trim());
    if (m) return m[1]!.trim();
  }
  const apiKey = req.headers.get('x-api-key');
  if (apiKey) return apiKey.trim();
  const key = new URL(req.url).searchParams.get('key');
  return key ? key.trim() : null;
}

function digest(s: string): Buffer {
  return createHash('sha256').update(s, 'utf8').digest();
}

export function secretMatches(presented: string | null, expected: string): boolean {
  if (!presented) return false;
  return timingSafeEqual(digest(presented), digest(expected));
}
