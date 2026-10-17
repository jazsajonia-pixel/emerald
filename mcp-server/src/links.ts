/**
 * Minimal link extraction for backlinks, following the app's LinkParser
 * (lib/features/links/link_parser.dart): wiki links `[[Note]]`,
 * `[[Folder/Note|alias]]`, `[[Note#Heading]]`, embeds, and Markdown links to
 * `.md` files. Code spans and fenced blocks are ignored.
 */
import { isMarkdown, noteTitle } from './paths.js';

export function maskCode(text: string): string {
  const lines = text.split('\n');
  let fence: string | null = null;
  return lines
    .map((line) => {
      const t = line.trimStart();
      const isFence =
        (fence === null && (t.startsWith('```') || t.startsWith('~~~'))) ||
        (fence !== null && t.startsWith(fence));
      if (isFence) {
        fence = fence === null ? t.slice(0, 3) : null;
        return ' '.repeat(line.length);
      }
      if (fence !== null) return ' '.repeat(line.length);
      return line.replace(/(`+)[^`]*?\1/g, (m) => ' '.repeat(m.length));
    })
    .join('\n');
}

const WIKI = /!?\[\[([^[\]\n]+?)\]\]/g;
const MD = /!?\[(?:[^[\]\n]|\[[^[\]\n]*\])*\]\(\s*(<[^>\n]*>|[^)\s]+)(?:\s+"[^"\n]*")?\s*\)/g;
const SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

function resolveRelative(fromPath: string, target: string): string | null {
  const dir = fromPath.includes('/') ? fromPath.slice(0, fromPath.lastIndexOf('/')).split('/') : [];
  const parts = target.startsWith('/') ? [] : [...dir];
  for (const seg of target.replace(/^\//, '').split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') {
      if (parts.length === 0) return null;
      parts.pop();
    } else parts.push(seg);
  }
  return parts.join('/');
}

/**
 * Returns true if [sourcePath]'s [text] links to [targetPath]. Wiki links
 * match by path (with or without `.md`) or, case-insensitively, by title.
 */
export function linksTo(sourcePath: string, text: string, targetPath: string): boolean {
  const masked = maskCode(text);
  const targetLower = targetPath.toLowerCase();
  const targetNoExt = targetLower.slice(0, -3);
  const titleLower = noteTitle(targetPath).toLowerCase();
  for (const m of masked.matchAll(WIKI)) {
    const inner = m[1]!;
    const name = inner.split('|')[0]!.split('#')[0]!.trim().toLowerCase();
    if (name === '') continue;
    if (name === targetLower || name === targetNoExt) return true;
    if (!name.includes('/') && (name === titleLower || name === `${titleLower}.md`)) return true;
    if (name.includes('/') && (targetNoExt.endsWith(`/${name}`) || targetLower.endsWith(`/${name}`))) {
      return true;
    }
  }
  for (const m of masked.matchAll(MD)) {
    if (m[0].startsWith('!')) continue;
    let raw = m[1]!;
    if (raw.startsWith('<')) raw = raw.slice(1, -1);
    if (SCHEME.test(raw) || raw.startsWith('#')) continue;
    let decoded: string;
    try {
      decoded = decodeURIComponent(raw.split('#')[0]!);
    } catch {
      continue;
    }
    if (!isMarkdown(decoded)) continue;
    const resolved = resolveRelative(sourcePath, decoded);
    if (resolved !== null && resolved.toLowerCase() === targetLower) return true;
  }
  return false;
}
