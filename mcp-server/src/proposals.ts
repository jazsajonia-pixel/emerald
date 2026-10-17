/**
 * AI change proposals stored in the sync repository under
 * `.emerald/proposals/`. The Emerald app never syncs hidden folders into the
 * vault; it lists these files separately and shows each one for approval.
 * Nothing in a note changes until the user approves it in the app.
 *
 * Format (version 1), one JSON file per proposal:
 * {
 *   "format": "emerald-proposal", "version": 1,
 *   "id": "20261018T091500Z-ab12cd34",
 *   "createdAt": "2026-10-18T09:15:00.000Z",
 *   "kind": "create" | "update",
 *   "path": "Folder/Note.md",
 *   "baseSha": "<git blob sha of the note when proposed>" | null,
 *   "content": "<full new note text>",
 *   "summary": "<why the AI proposes this>",
 *   "client": "<MCP client name, if reported>" | null
 * }
 */
import { randomBytes } from 'node:crypto';

export const PROPOSALS_DIR = '.emerald/proposals';
export const MAX_PENDING = 50;
export const MAX_CONTENT_BYTES = 512 * 1024;

export interface Proposal {
  format: 'emerald-proposal';
  version: 1;
  id: string;
  createdAt: string;
  kind: 'create' | 'update';
  path: string;
  baseSha: string | null;
  content: string;
  summary: string;
  client: string | null;
}

export function newProposalId(now: Date, rand: () => string = () => randomBytes(4).toString('hex')): string {
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  return `${stamp}-${rand()}`;
}

export function proposalFilePath(id: string): string {
  if (!/^[0-9TZ]+-[0-9a-f]{8}$/.test(id)) throw new Error('invalid proposal id');
  return `${PROPOSALS_DIR}/${id}.json`;
}

export function parseProposal(text: string): Proposal | null {
  try {
    const p = JSON.parse(text) as Partial<Proposal>;
    if (p.format !== 'emerald-proposal' || p.version !== 1) return null;
    if (typeof p.id !== 'string' || typeof p.path !== 'string' || typeof p.content !== 'string') return null;
    if (p.kind !== 'create' && p.kind !== 'update') return null;
    return p as Proposal;
  } catch {
    return null;
  }
}
