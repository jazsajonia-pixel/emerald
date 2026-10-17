/**
 * End to end: the official MCP client talks to the real handler (mcp-handler
 * + MCP SDK v2) over Streamable HTTP; GitHub is faked in memory.
 */
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { buildHandler } from '../src/handler.js';
import { FakeGitHub, TOKEN, blobSha } from './fake_github.js';

const SECRET = 's'.repeat(48);
const ENV = {
  EMERALD_GITHUB_OWNER: 'me',
  EMERALD_GITHUB_REPO: 'vault',
  EMERALD_GITHUB_BRANCH: 'main',
  EMERALD_GITHUB_TOKEN: TOKEN,
  EMERALD_MCP_SECRET: SECRET,
};

let gh: FakeGitHub;
let handler: (req: Request) => Promise<Response>;

beforeEach(() => {
  gh = new FakeGitHub();
  gh.files.set('Garden.md', '# Garden\n\nStart here. Tomatoes grow fast.\n');
  gh.files.set('Projects/Plan.md', '# Plan\n\nSee [[Garden]] for tomatoes.\n');
  gh.files.set('Daily/2026-10-18.md', 'Worked on [the plan](../Projects/Plan.md).\n');
  gh.files.set('.obsidian/workspace.md', 'hidden config with tomatoes');
  gh.files.set('image.png', 'binary');
  let n = 0;
  handler = buildHandler({
    env: ENV,
    githubFetch: gh.fetch,
    toolDeps: {
      now: () => new Date('2026-10-18T09:15:00.000Z'),
      newId: () => `20261018T091500Z-${(n++).toString(16).padStart(8, '0')}`,
    },
  });
});

const handlerFetch = (req: string | URL | Request, init?: RequestInit) =>
  handler(req instanceof Request ? req : new Request(req, init));

async function connect(headers: Record<string, string> = { Authorization: `Bearer ${SECRET}` }, query = '') {
  const client = new Client({ name: 'test-client', version: '1.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(`https://emerald.example/api/mcp${query}`), {
    fetch: handlerFetch as typeof fetch,
    requestInit: { headers },
  });
  await client.connect(transport);
  return client;
}

async function call(client: Client, name: string, args: Record<string, unknown> = {}) {
  const r = (await client.callTool({ name, arguments: args })) as {
    content: { type: string; text: string }[];
    isError?: boolean;
  };
  return { text: r.content.map((c) => c.text).join('\n'), isError: r.isError === true };
}

test('rejects requests without the access secret', async () => {
  const res = await handler(
    new Request('https://emerald.example/api/mcp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
    }),
  );
  assert.equal(res.status, 401);
  await assert.rejects(connect({ Authorization: 'Bearer wrong' }));
  assert.equal(gh.requests.length, 0, 'no GitHub call before authentication');
});

test('reports missing configuration with 503 and no secrets', async () => {
  const h = buildHandler({ env: { EMERALD_GITHUB_TOKEN: TOKEN } });
  const res = await h(new Request('https://emerald.example/api/mcp', { method: 'POST' }));
  assert.equal(res.status, 503);
  const body = await res.text();
  assert.ok(body.includes('EMERALD_MCP_SECRET'));
  assert.ok(!body.includes(TOKEN));
});

test('lists exactly the safe tools (no delete/rename)', async () => {
  const client = await connect();
  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name).sort();
  assert.deepEqual(names, [
    'find_backlinks',
    'list_notes',
    'list_pending_proposals',
    'propose_note_change',
    'read_note',
    'search_notes',
  ]);
  for (const t of tools) {
    if (t.name !== 'propose_note_change') assert.equal(t.annotations?.readOnlyHint, true, t.name);
    assert.notEqual(t.annotations?.destructiveHint, true, t.name);
  }
  await client.close();
});

test('also accepts the secret as ?key= and X-API-Key', async () => {
  const a = await connect({}, `?key=${SECRET}`);
  assert.ok((await call(a, 'list_notes')).text.includes('Garden.md'));
  const b = await connect({ 'X-API-Key': SECRET });
  assert.ok((await call(b, 'list_notes')).text.includes('Garden.md'));
});

test('read tools see notes only, never hidden folders or other files', async () => {
  const client = await connect();
  const list = await call(client, 'list_notes');
  assert.ok(list.text.startsWith('3 note(s)'));
  assert.ok(!list.text.includes('.obsidian') && !list.text.includes('image.png'));
  const folder = await call(client, 'list_notes', { folder: 'Projects' });
  assert.ok(folder.text.includes('Projects/Plan.md') && !folder.text.includes('Garden.md'));

  const read = await call(client, 'read_note', { path: 'Projects/Plan.md' });
  assert.ok(read.text.includes(`Version: ${blobSha(gh.files.get('Projects/Plan.md')!)}`));
  assert.ok(read.text.includes('See [[Garden]]'));

  const search = await call(client, 'search_notes', { query: 'tomatoes' });
  assert.ok(search.text.startsWith('2 match(es)'), search.text);
  assert.ok(search.text.indexOf('Garden.md') < search.text.indexOf('Projects/Plan.md'));
  assert.ok(!search.text.includes('.obsidian'));

  const back = await call(client, 'find_backlinks', { path: 'Projects/Plan.md' });
  assert.ok(back.text.includes('Daily/2026-10-18.md'));
  const back2 = await call(client, 'find_backlinks', { path: 'Garden.md' });
  assert.ok(back2.text.includes('Projects/Plan.md'));

  for (const bad of ['../secrets.md', '.obsidian/workspace.md', '/etc/passwd.md', 'image.png']) {
    const r = await call(client, 'read_note', { path: bad });
    assert.ok(r.isError, bad);
  }
  assert.ok((await call(client, 'read_note', { path: 'Missing.md' })).isError);
});

test('propose_note_change records a proposal and never edits the note', async () => {
  const client = await connect();
  const before = gh.files.get('Projects/Plan.md')!;
  const version = blobSha(before);
  const r = await call(client, 'propose_note_change', {
    path: 'Projects/Plan.md',
    new_content: '# Plan\n\nSee [[Garden]].\n\n## Next\n- water\n',
    summary: 'Add a Next section',
    expected_version: version,
  });
  assert.ok(!r.isError, r.text);
  assert.ok(r.text.includes('Nothing has changed in the note yet'));
  assert.equal(gh.files.get('Projects/Plan.md'), before, 'note untouched');

  const file = '.emerald/proposals/20261018T091500Z-00000000.json';
  const saved = JSON.parse(gh.files.get(file)!);
  assert.deepEqual(saved, {
    format: 'emerald-proposal',
    version: 1,
    id: '20261018T091500Z-00000000',
    createdAt: '2026-10-18T09:15:00.000Z',
    kind: 'update',
    path: 'Projects/Plan.md',
    baseSha: version,
    content: '# Plan\n\nSee [[Garden]].\n\n## Next\n- water\n',
    summary: 'Add a Next section',
    client: null,
  });
  assert.deepEqual(gh.commits, [{ path: file, message: 'Propose update of Projects/Plan.md (Emerald MCP)' }]);

  const created = await call(client, 'propose_note_change', {
    path: 'Ideas/New idea.md',
    new_content: '# New idea\n',
    summary: 'Capture idea',
  });
  assert.ok(!created.isError, created.text);
  assert.equal(gh.files.has('Ideas/New idea.md'), false, 'new note not created directly');
  assert.equal(JSON.parse(gh.files.get('.emerald/proposals/20261018T091500Z-00000001.json')!).kind, 'create');

  const pending = await call(client, 'list_pending_proposals');
  assert.ok(pending.text.startsWith('2 proposal(s)'), pending.text);
  assert.ok(pending.text.includes('update Projects/Plan.md — Add a Next section'));
});

test('propose_note_change refuses stale, identical, unsafe and oversized changes', async () => {
  const client = await connect();
  const stale = await call(client, 'propose_note_change', {
    path: 'Garden.md',
    new_content: 'x',
    summary: 's',
    expected_version: '0'.repeat(40),
  });
  assert.ok(stale.isError && stale.text.includes('changed since you read it'));
  const same = await call(client, 'propose_note_change', {
    path: 'Garden.md',
    new_content: gh.files.get('Garden.md')!,
    summary: 's',
  });
  assert.ok(same.isError && same.text.includes('identical'));
  for (const bad of ['../x.md', '.emerald/proposals/x.md', '.obsidian/a.md', 'notes.txt']) {
    const r = await call(client, 'propose_note_change', { path: bad, new_content: 'x', summary: 's' });
    assert.ok(r.isError, bad);
  }
  const big = await call(client, 'propose_note_change', {
    path: 'Big.md',
    new_content: 'a'.repeat(512 * 1024 + 1),
    summary: 's',
  });
  assert.ok(big.isError && big.text.includes('too large'));
  assert.equal(gh.commits.length, 0);
});

test('caps the number of pending proposals', async () => {
  for (let i = 0; i < 50; i++) gh.files.set(`.emerald/proposals/p${i}.json`, '{}');
  const client = await connect();
  const r = await call(client, 'propose_note_change', { path: 'A.md', new_content: 'x', summary: 's' });
  assert.ok(r.isError && r.text.includes('already 50 proposals'));
});

test('GitHub failures become clear errors without the token', async () => {
  const client = await connect();
  gh.failStatus = 401;
  const r = await call(client, 'list_notes');
  assert.ok(r.isError && r.text.includes('401'));
  assert.ok(!r.text.includes(TOKEN));
  gh.failStatus = 403;
  assert.ok((await call(client, 'read_note', { path: 'Garden.md' })).text.includes('403'));
});
