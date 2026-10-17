import { test } from 'node:test';
import assert from 'node:assert/strict';
import { InvalidPathError, isVaultNotePath, normalizeNotePath, normalizePath, noteTitle } from '../src/paths.js';
import { linksTo, maskCode } from '../src/links.js';
import { readTarGz } from '../src/tar.js';
import { presentedSecret, secretMatches } from '../src/auth.js';
import { loadConfig } from '../src/config.js';
import { newProposalId, parseProposal, proposalFilePath } from '../src/proposals.js';
import { makeTarGz } from './fake_github.js';

test('note paths: valid ones normalize', () => {
  assert.equal(normalizeNotePath('Projects/Plan.md'), 'Projects/Plan.md');
  assert.equal(normalizeNotePath('  Note.md '), 'Note.md');
  assert.equal(normalizePath('Projects/'), 'Projects');
  assert.equal(noteTitle('A/B/My Note.md'), 'My Note');
});

test('note paths: escapes, hidden entries, and non-notes are rejected', () => {
  for (const bad of [
    '../x.md', 'a/../b.md', '/abs.md', 'a\\b.md', '.obsidian/app.md', 'a/.git/x.md',
    '.emerald/proposals/x.md', 'x.txt', '', 'a//b.md', 'bad:name.md', 'tab\there.md', 'a/ lead.md',
  ]) {
    assert.throws(() => normalizeNotePath(bad), InvalidPathError, bad);
  }
  assert.equal(isVaultNotePath('.emerald/proposals/1.json'), false);
  assert.equal(isVaultNotePath('.obsidian/x.md'), false);
  assert.equal(isVaultNotePath('Notes/A.md'), true);
});

test('links: wiki, alias, heading, folder, markdown, code ignored', () => {
  const t = 'Projects/Plan.md';
  assert.ok(linksTo('A.md', 'see [[Plan]]', t));
  assert.ok(linksTo('A.md', 'see [[plan|the plan]]', t));
  assert.ok(linksTo('A.md', 'see [[Plan#Goals]]', t));
  assert.ok(linksTo('A.md', 'see ![[Projects/Plan]]', t));
  assert.ok(linksTo('A.md', 'see [x](Projects/Plan.md)', t));
  assert.ok(linksTo('Projects/B.md', 'see [x](Plan.md#top)', t));
  assert.ok(linksTo('Other/B.md', 'see [x](../Projects/Plan.md)', t));
  assert.ok(linksTo('Projects/B.md', 'see [x](My%20Plan.md)', 'Projects/My Plan.md'));
  assert.ok(linksTo('A.md', 'see [x](<Projects/My Plan.md>)', 'Projects/My Plan.md'));
  assert.ok(!linksTo('A.md', '`[[Plan]]` and\n```\n[[Plan]]\n```', t));
  assert.ok(!linksTo('A.md', 'see [[Planet]] and [x](https://e.com/Plan.md)', t));
  assert.equal(maskCode('a `b` c').length, 'a `b` c'.length);
});

test('tar: reads files, long pax paths, skips folders', () => {
  const long = `${'d'.repeat(60)}/${'n'.repeat(60)}.md`;
  const files = readTarGz(makeTarGz({ 'A.md': 'hello', [long]: 'long one', 'Ünïcode.md': 'ü' }));
  const map = new Map(files.map((f) => [f.path, f.data.toString('utf8')]));
  assert.equal(map.get('owner-repo-abc123/A.md'), 'hello');
  assert.equal(map.get(`owner-repo-abc123/${long}`), 'long one');
  assert.equal(map.get('owner-repo-abc123/Ünïcode.md'), 'ü');
  assert.equal(files.length, 3);
});

test('auth: bearer, x-api-key and ?key= are accepted; wrong or missing are not', () => {
  const s = 'x'.repeat(40);
  const r = (h: Record<string, string>, q = '') => new Request(`https://h/api/mcp${q}`, { headers: h });
  assert.ok(secretMatches(presentedSecret(r({ authorization: `Bearer ${s}` })), s));
  assert.ok(secretMatches(presentedSecret(r({ 'x-api-key': s })), s));
  assert.ok(secretMatches(presentedSecret(r({}, `?key=${s}`)), s));
  assert.ok(!secretMatches(presentedSecret(r({ authorization: 'Bearer nope' })), s));
  assert.ok(!secretMatches(presentedSecret(r({})), s));
});

test('config: names missing variables without leaking values', () => {
  assert.throws(
    () => loadConfig({ EMERALD_GITHUB_TOKEN: 'secret-token-value', EMERALD_MCP_SECRET: 'short' }),
    (e: Error) =>
      e.message.includes('EMERALD_GITHUB_OWNER') &&
      e.message.includes('EMERALD_MCP_SECRET') &&
      !e.message.includes('secret-token-value') &&
      !e.message.includes('short'),
  );
  const c = loadConfig({
    EMERALD_GITHUB_OWNER: 'me',
    EMERALD_GITHUB_REPO: 'vault',
    EMERALD_GITHUB_TOKEN: 't',
    EMERALD_MCP_SECRET: 'y'.repeat(32),
  });
  assert.equal(c.repo.branch, 'main');
});

test('proposals: ids, file paths and parsing', () => {
  const id = newProposalId(new Date('2026-10-18T09:15:00.123Z'), () => 'ab12cd34');
  assert.equal(id, '20261018T091500Z-ab12cd34');
  assert.equal(proposalFilePath(id), '.emerald/proposals/20261018T091500Z-ab12cd34.json');
  assert.throws(() => proposalFilePath('../../x'));
  assert.equal(parseProposal('{"format":"other"}'), null);
  assert.equal(parseProposal('not json'), null);
});
