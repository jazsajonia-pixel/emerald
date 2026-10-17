/** In-memory fake of the GitHub REST endpoints the server uses. */
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';

export const TOKEN = 'ghp_fake_token_value_for_tests_only_123456';

export function blobSha(content: string): string {
  const buf = Buffer.from(content, 'utf8');
  return createHash('sha1').update(`blob ${buf.length}\0`).update(buf).digest('hex');
}

function tarHeader(name: string, size: number, type: string): Buffer {
  const h = Buffer.alloc(512, 0);
  h.write(name.slice(0, 100), 0, 'utf8');
  h.write('0000644\0', 100);
  h.write('0000000\0', 108);
  h.write('0000000\0', 116);
  h.write(size.toString(8).padStart(11, '0') + '\0', 124);
  h.write('00000000000\0', 136);
  h.write('        ', 148);
  h.write(type, 156);
  h.write('ustar\0', 257);
  h.write('00', 263);
  let sum = 0;
  for (const b of h) sum += b;
  h.write(sum.toString(8).padStart(6, '0') + '\0 ', 148);
  return h;
}

function pad(data: Buffer): Buffer {
  const rem = data.length % 512;
  return rem === 0 ? data : Buffer.concat([data, Buffer.alloc(512 - rem, 0)]);
}

/** Builds a gzip'd tar like GitHub's, using pax headers for long paths. */
export function makeTarGz(files: Record<string, string>, prefix = 'owner-repo-abc123/'): Buffer {
  const parts: Buffer[] = [tarHeader('pax_global_header', 0, 'g')];
  parts.push(tarHeader(prefix, 0, '5'));
  for (const [path, content] of Object.entries(files)) {
    const full = prefix + path;
    const data = Buffer.from(content, 'utf8');
    if (Buffer.byteLength(full) > 100) {
      const rec = ` path=${full}\n`;
      let len = rec.length + 1;
      while (`${len}${rec}`.length !== len) len = `${len}${rec}`.length;
      const pax = Buffer.from(`${len}${rec}`, 'utf8');
      parts.push(tarHeader('PaxHeader', pax.length, 'x'), pad(pax));
    }
    parts.push(tarHeader(full, data.length, '0'), pad(data));
  }
  parts.push(Buffer.alloc(1024, 0));
  return gzipSync(Buffer.concat(parts));
}

export interface RecordedRequest {
  method: string;
  url: string;
  auth: string | null;
}

export class FakeGitHub {
  files = new Map<string, string>();
  requests: RecordedRequest[] = [];
  commits: { path: string; message: string }[] = [];
  failStatus: number | null = null;

  constructor(
    readonly owner = 'me',
    readonly repo = 'vault',
    readonly branch = 'main',
  ) {}

  fetch = async (input: string, init: RequestInit = {}): Promise<Response> => {
    const method = (init.method ?? 'GET').toUpperCase();
    const headers = new Headers(init.headers);
    this.requests.push({ method, url: input, auth: headers.get('authorization') });
    if (headers.get('authorization') !== `Bearer ${TOKEN}`) return new Response('{}', { status: 401 });
    if (this.failStatus) return new Response('{"message":"nope"}', { status: this.failStatus });
    const url = new URL(input);
    const base = `/repos/${this.owner}/${this.repo}`;
    if (!url.pathname.startsWith(base)) return new Response('{}', { status: 404 });
    const rest = url.pathname.slice(base.length);

    if (rest === `/git/trees/${this.branch}` && method === 'GET') {
      const tree = [...this.files].map(([path, c]) => ({
        path,
        type: 'blob',
        sha: blobSha(c),
        size: Buffer.byteLength(c),
      }));
      return Response.json({ sha: 'tree', tree, truncated: false });
    }
    if (rest === `/tarball/${this.branch}` && method === 'GET') {
      return new Response(new Uint8Array(makeTarGz(Object.fromEntries(this.files))), { status: 200 });
    }
    if (rest.startsWith('/contents/')) {
      const path = rest.slice('/contents/'.length).split('/').map(decodeURIComponent).join('/');
      if (method === 'GET') {
        if (url.searchParams.get('ref') !== this.branch) return new Response('{}', { status: 404 });
        const c = this.files.get(path);
        if (c !== undefined) {
          return Response.json({
            type: 'file',
            name: path.split('/').pop(),
            path,
            sha: blobSha(c),
            size: Buffer.byteLength(c),
            encoding: 'base64',
            content: Buffer.from(c).toString('base64'),
          });
        }
        const children = [...this.files.keys()].filter((p) => p.startsWith(`${path}/`) && !p.slice(path.length + 1).includes('/'));
        if (children.length === 0) return new Response('{}', { status: 404 });
        return Response.json(
          children.map((p) => ({ type: 'file', name: p.split('/').pop(), path: p, sha: blobSha(this.files.get(p)!) })),
        );
      }
      if (method === 'PUT') {
        const body = JSON.parse(String(init.body)) as { message: string; content: string; branch: string; sha?: string };
        if (body.branch !== this.branch) return new Response('{}', { status: 404 });
        if (this.files.has(path) && !body.sha) return new Response('{}', { status: 422 });
        this.files.set(path, Buffer.from(body.content, 'base64').toString('utf8'));
        this.commits.push({ path, message: body.message });
        return Response.json({ content: { path, sha: blobSha(this.files.get(path)!) } }, { status: 201 });
      }
    }
    return new Response('{}', { status: 404 });
  };
}
