/**
 * Vault-relative note paths, mirroring the Flutter app's `VaultPath` rules
 * (lib/core/vault/vault_path.dart): `/`-separated, no absolute paths, no `..`,
 * no hidden (dot) segments, no control or reserved characters.
 */
export class InvalidPathError extends Error {}

const RESERVED = ['<', '>', ':', '"', '|', '?', '*'];

export function validateName(name: string, original = name): void {
  if (name.length === 0) throw new InvalidPathError(`${original}: empty path segment`);
  if (name === '.' || name === '..') {
    throw new InvalidPathError(`${original}: relative segments are not allowed`);
  }
  if (name.includes('/') || name.includes('\\')) {
    throw new InvalidPathError(`${original}: name contains a path separator`);
  }
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (c < 0x20 || c === 0x7f) throw new InvalidPathError(`${original}: contains control characters`);
  }
  if (name.trim() !== name) throw new InvalidPathError(`${original}: leading or trailing whitespace`);
  if (name.startsWith('.')) {
    throw new InvalidPathError(`${original}: hidden/internal entries are not accessible`);
  }
  for (const r of RESERVED) {
    if (name.includes(r)) throw new InvalidPathError(`${original}: contains reserved character "${r}"`);
  }
  if (name.length > 255) throw new InvalidPathError(`${original}: name too long`);
}

/** Normalizes a folder or file path; '' is the vault root. */
export function normalizePath(path: string): string {
  if (path === '') return '';
  if (path.startsWith('/') || path.includes('\\')) {
    throw new InvalidPathError(`${path}: must be relative and use "/"`);
  }
  const parts = path.split('/');
  const out: string[] = [];
  parts.forEach((seg, i) => {
    if (seg === '' && i === parts.length - 1 && i > 0) return; // trailing slash
    validateName(seg, path);
    out.push(seg);
  });
  return out.join('/');
}

export function isMarkdown(path: string): boolean {
  return path.toLowerCase().endsWith('.md');
}

/** Normalizes a note path and requires the `.md` extension. */
export function normalizeNotePath(path: string): string {
  const p = normalizePath(path.trim());
  if (p === '' || !isMarkdown(p)) throw new InvalidPathError(`${path}: notes must be .md files`);
  return p;
}

/** True for paths the Emerald app syncs (same rule as SyncEngine._syncablePath). */
export function isVaultNotePath(path: string): boolean {
  if (!isMarkdown(path)) return false;
  try {
    return normalizePath(path) === path;
  } catch {
    return false;
  }
}

export function noteTitle(path: string): string {
  const base = path.slice(path.lastIndexOf('/') + 1);
  return isMarkdown(base) ? base.slice(0, -3) : base;
}
