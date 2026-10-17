/**
 * MCP tools exposed to AI apps. Read tools work on the GitHub copy of the
 * vault. The only write tool records a proposal; it never edits a note.
 * There is no delete or rename tool.
 */
import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/server';
import { GitHubError, type GitHubRepo } from './github.js';
import { InvalidPathError, normalizeNotePath, normalizePath, noteTitle } from './paths.js';
import { linksTo } from './links.js';
import {
  MAX_CONTENT_BYTES,
  MAX_PENDING,
  PROPOSALS_DIR,
  newProposalId,
  parseProposal,
  proposalFilePath,
  type Proposal,
} from './proposals.js';

type ToolResult = { content: { type: 'text'; text: string }[]; isError?: boolean };

const ok = (text: string): ToolResult => ({ content: [{ type: 'text', text }] });
const fail = (text: string): ToolResult => ({ content: [{ type: 'text', text }], isError: true });

async function guarded(fn: () => Promise<ToolResult>): Promise<ToolResult> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof InvalidPathError || e instanceof GitHubError) return fail(e.message);
    return fail('Unexpected server error.');
  }
}

export function snippet(text: string, index: number, radius = 80): string {
  const start = Math.max(0, index - radius);
  const end = Math.min(text.length, index + radius);
  return `${start > 0 ? '…' : ''}${text.slice(start, end).replace(/\s+/g, ' ').trim()}${end < text.length ? '…' : ''}`;
}

export interface ToolDeps {
  repo: GitHubRepo;
  now?: () => Date;
  newId?: (now: Date) => string;
}

export function registerVaultTools(server: McpServer, deps: ToolDeps): void {
  const { repo } = deps;
  const now = deps.now ?? (() => new Date());
  const newId = deps.newId ?? ((d: Date) => newProposalId(d));
  const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };

  server.registerTool(
    'list_notes',
    {
      title: 'List notes',
      description:
        'List Markdown notes in the Emerald vault (the GitHub copy synced from the phone). Optionally limit to a folder.',
      inputSchema: z.object({
        folder: z.string().max(1000).optional().describe('Vault-relative folder, e.g. "Projects". Omit for all notes.'),
        limit: z.number().int().min(1).max(1000).optional(),
      }),
      annotations: readOnly,
    },
    async ({ folder, limit }) =>
      guarded(async () => {
        const dir = folder ? normalizePath(folder.trim()) : '';
        const notes = (await repo.listNotes()).filter((n) => dir === '' || n.path.startsWith(`${dir}/`));
        const max = limit ?? 200;
        if (notes.length === 0) return ok(dir ? `No notes in "${dir}".` : 'The vault has no notes yet.');
        const lines = notes.slice(0, max).map((n) => `- ${n.path} (${n.size} bytes)`);
        const more = notes.length > max ? `\n…and ${notes.length - max} more.` : '';
        return ok(`${notes.length} note(s):\n${lines.join('\n')}${more}`);
      }),
  );

  server.registerTool(
    'read_note',
    {
      title: 'Read note',
      description:
        'Read the full Markdown text of one note. Returns its version id, which propose_note_change can use to make sure the note did not change in between.',
      inputSchema: z.object({ path: z.string().max(1000).describe('Vault-relative path ending in .md') }),
      annotations: readOnly,
    },
    async ({ path }) =>
      guarded(async () => {
        const p = normalizeNotePath(path);
        const note = await repo.readNote(p);
        if (!note) return fail(`No note at "${p}".`);
        return ok(`Path: ${note.path}\nVersion: ${note.sha}\n\n${note.content}`);
      }),
  );

  server.registerTool(
    'search_notes',
    {
      title: 'Search notes',
      description:
        'Full-text search across note titles and contents (case-insensitive; every word must appear). Returns paths with a short snippet.',
      inputSchema: z.object({
        query: z.string().min(1).max(500),
        limit: z.number().int().min(1).max(100).optional(),
      }),
      annotations: readOnly,
    },
    async ({ query, limit }) =>
      guarded(async () => {
        const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
        if (terms.length === 0) return fail('Empty query.');
        const notes = await repo.readAllNotes();
        const hits: { path: string; score: number; snip: string }[] = [];
        for (const [path, text] of notes) {
          const title = noteTitle(path).toLowerCase();
          const lower = text.toLowerCase();
          if (!terms.every((t) => title.includes(t) || lower.includes(t))) continue;
          const score = terms.reduce((s, t) => s + (title.includes(t) ? 10 : 0) + (lower.split(t).length - 1), 0);
          const first = Math.max(0, lower.indexOf(terms[0]!));
          hits.push({ path, score, snip: snippet(text, first) });
        }
        hits.sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
        if (hits.length === 0) return ok(`No notes match "${query}".`);
        const max = limit ?? 20;
        const lines = hits.slice(0, max).map((h) => `- ${h.path}: ${h.snip}`);
        return ok(`${hits.length} match(es):\n${lines.join('\n')}`);
      }),
  );

  server.registerTool(
    'find_backlinks',
    {
      title: 'Find backlinks',
      description: 'List notes that link to the given note ([[wiki links]] or Markdown links).',
      inputSchema: z.object({ path: z.string().max(1000).describe('Vault-relative path of the target note') }),
      annotations: readOnly,
    },
    async ({ path }) =>
      guarded(async () => {
        const target = normalizeNotePath(path);
        const notes = await repo.readAllNotes();
        const sources = [...notes]
          .filter(([p, text]) => p !== target && linksTo(p, text, target))
          .map(([p]) => p)
          .sort();
        if (sources.length === 0) return ok(`No notes link to "${target}".`);
        return ok(`${sources.length} note(s) link to ${target}:\n${sources.map((s) => `- ${s}`).join('\n')}`);
      }),
  );

  server.registerTool(
    'list_pending_proposals',
    {
      title: 'List pending proposals',
      description: 'List changes proposed earlier that are still waiting for approval in the Emerald app.',
      inputSchema: z.object({}),
      annotations: readOnly,
    },
    async () =>
      guarded(async () => {
        const files = (await repo.listFolder(PROPOSALS_DIR)).filter((f) => f.name.endsWith('.json'));
        if (files.length === 0) return ok('No proposals are waiting for approval.');
        const lines: string[] = [];
        for (const f of files.slice(0, MAX_PENDING)) {
          const raw = await repo.readRaw(f.path);
          const p = raw ? parseProposal(raw) : null;
          if (p) lines.push(`- ${p.id}: ${p.kind} ${p.path} — ${p.summary}`);
        }
        return ok(`${lines.length} proposal(s) waiting for approval in Emerald:\n${lines.join('\n')}`);
      }),
  );

  server.registerTool(
    'propose_note_change',
    {
      title: 'Propose note change',
      description:
        'Propose creating a note or replacing a note\'s full text. This does NOT change the note: the proposal waits until the owner reviews the diff and approves it in the Emerald app. Send the complete new Markdown text, not a fragment. Deleting or renaming notes is not supported.',
      inputSchema: z.object({
        path: z.string().max(1000).describe('Vault-relative path ending in .md'),
        new_content: z.string().describe('Complete new Markdown text of the note'),
        summary: z.string().min(1).max(500).describe('One sentence explaining the change for the owner'),
        expected_version: z
          .string()
          .regex(/^[0-9a-f]{40}$/)
          .optional()
          .describe('Version id from read_note; the proposal is refused if the note changed since'),
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ path, new_content, summary, expected_version }) =>
      guarded(async () => {
        const p = normalizeNotePath(path);
        if (Buffer.byteLength(new_content, 'utf8') > MAX_CONTENT_BYTES) {
          return fail('The proposed note is too large (limit 512 KB).');
        }
        const pending = (await repo.listFolder(PROPOSALS_DIR)).filter((f) => f.name.endsWith('.json'));
        if (pending.length >= MAX_PENDING) {
          return fail(`There are already ${pending.length} proposals waiting. Ask the owner to review them in Emerald first.`);
        }
        const current = await repo.readNote(p);
        if (expected_version && (!current || current.sha !== expected_version)) {
          return fail(`"${p}" changed since you read it (or no longer exists). Read it again and redo the change.`);
        }
        if (current && current.content === new_content) return fail('The proposed text is identical to the current note.');
        const at = now();
        const proposal: Proposal = {
          format: 'emerald-proposal',
          version: 1,
          id: newId(at),
          createdAt: at.toISOString(),
          kind: current ? 'update' : 'create',
          path: p,
          baseSha: current ? current.sha : null,
          content: new_content,
          summary: summary.trim(),
          client: null,
        };
        await repo.createFile(
          proposalFilePath(proposal.id),
          `${JSON.stringify(proposal, null, 2)}\n`,
          `Propose ${proposal.kind} of ${p} (Emerald MCP)`,
        );
        return ok(
          `Proposal ${proposal.id} saved: ${proposal.kind} "${p}". Nothing has changed in the note yet — ` +
            'the owner will review the diff and approve or reject it in the Emerald app.',
        );
      }),
  );
}
