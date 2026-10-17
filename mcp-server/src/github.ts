/**
 * Small GitHub REST client for one repository branch. Uses the same API
 * version as the app's sync client (2022-11-28). The token never appears in
 * error messages.
 */
import { readTarGz } from './tar.js';
import { isVaultNotePath } from './paths.js';

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface RepoConfig {
  owner: string;
  repo: string;
  branch: string;
  token: string;
  apiBase?: string;
}

export class GitHubError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export interface TreeNote {
  path: string;
  sha: string;
  size: number;
}

export interface NoteFile {
  path: string;
  sha: string;
  content: string;
}

const MAX_NOTE_BYTES = 1024 * 1024;

function encodePath(path: string): string {
  return path.split('/').map(encodeURIComponent).join('/');
}

export class GitHubRepo {
  constructor(
    private readonly cfg: RepoConfig,
    private readonly fetchFn: FetchLike = fetch,
  ) {}

  private get base(): string {
    const api = (this.cfg.apiBase ?? 'https://api.github.com').replace(/\/$/, '');
    return `${api}/repos/${encodeURIComponent(this.cfg.owner)}/${encodeURIComponent(this.cfg.repo)}`;
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${this.cfg.token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'emerald-mcp-server',
      ...extra,
    };
  }

  private async request(url: string, init: RequestInit = {}): Promise<Response> {
    let res: Response;
    try {
      res = await this.fetchFn(url, { ...init, headers: this.headers(init.headers as Record<string, string>) });
    } catch {
      throw new GitHubError('Could not reach GitHub.', 0);
    }
    return res;
  }

  private static failure(res: Response, what: string): GitHubError {
    const s = res.status;
    if (s === 401) return new GitHubError(`GitHub rejected the server's token (401) while ${what}.`, s);
    if (s === 403 || s === 429) {
      return new GitHubError(`GitHub refused the request (${s}: permission or rate limit) while ${what}.`, s);
    }
    if (s === 404) return new GitHubError(`Not found on GitHub (404) while ${what}.`, s);
    if (s === 409) return new GitHubError(`GitHub reported a conflict (409) while ${what}.`, s);
    if (s === 422) return new GitHubError(`GitHub rejected the request (422) while ${what}.`, s);
    return new GitHubError(`GitHub error ${s} while ${what}.`, s);
  }

  /** All syncable Markdown notes on the branch (hidden folders excluded). */
  async listNotes(): Promise<TreeNote[]> {
    const url = `${this.base}/git/trees/${encodeURIComponent(this.cfg.branch)}?recursive=1`;
    const res = await this.request(url);
    if (!res.ok) throw GitHubRepo.failure(res, 'listing notes');
    const body = (await res.json()) as {
      tree: { path: string; type: string; sha: string; size?: number }[];
      truncated?: boolean;
    };
    if (body.truncated) {
      throw new GitHubError('The repository is too large to list in one request.', 413);
    }
    return body.tree
      .filter((e) => e.type === 'blob' && isVaultNotePath(e.path))
      .map((e) => ({ path: e.path, sha: e.sha, size: e.size ?? 0 }))
      .sort((a, b) => a.path.localeCompare(b.path));
  }

  /** Reads a note, or returns null if it does not exist. */
  async readNote(path: string): Promise<NoteFile | null> {
    const url = `${this.base}/contents/${encodePath(path)}?ref=${encodeURIComponent(this.cfg.branch)}`;
    const res = await this.request(url);
    if (res.status === 404) return null;
    if (!res.ok) throw GitHubRepo.failure(res, `reading ${path}`);
    const body = (await res.json()) as { type?: string; sha: string; size: number; content?: string; encoding?: string };
    if (Array.isArray(body) || body.type !== 'file') {
      throw new GitHubError(`${path} is not a file.`, 400);
    }
    if (body.size > MAX_NOTE_BYTES || body.encoding !== 'base64' || body.content === undefined) {
      throw new GitHubError(`${path} is too large to read through this server (over 1 MB).`, 413);
    }
    return { path, sha: body.sha, content: Buffer.from(body.content, 'base64').toString('utf8') };
  }

  /** Downloads every syncable note in one request (tarball of the branch). */
  async readAllNotes(): Promise<Map<string, string>> {
    const url = `${this.base}/tarball/${encodeURIComponent(this.cfg.branch)}`;
    const res = await this.request(url, { redirect: 'follow' });
    if (!res.ok) throw GitHubRepo.failure(res, 'downloading the vault');
    const files = readTarGz(new Uint8Array(await res.arrayBuffer()));
    const out = new Map<string, string>();
    for (const f of files) {
      // Entries are prefixed with "<owner>-<repo>-<sha>/".
      const slash = f.path.indexOf('/');
      if (slash < 0) continue;
      const path = f.path.slice(slash + 1);
      if (!isVaultNotePath(path) || f.data.length > MAX_NOTE_BYTES) continue;
      out.set(path, f.data.toString('utf8'));
    }
    return out;
  }

  /** Lists file names in a folder; [] if the folder does not exist. */
  async listFolder(path: string): Promise<{ name: string; path: string; sha: string }[]> {
    const url = `${this.base}/contents/${encodePath(path)}?ref=${encodeURIComponent(this.cfg.branch)}`;
    const res = await this.request(url);
    if (res.status === 404) return [];
    if (!res.ok) throw GitHubRepo.failure(res, `listing ${path}`);
    const body = (await res.json()) as { type: string; name: string; path: string; sha: string }[];
    if (!Array.isArray(body)) return [];
    return body.filter((e) => e.type === 'file').map((e) => ({ name: e.name, path: e.path, sha: e.sha }));
  }

  /** Reads any file (used for proposal files); null if missing. */
  async readRaw(path: string): Promise<string | null> {
    const url = `${this.base}/contents/${encodePath(path)}?ref=${encodeURIComponent(this.cfg.branch)}`;
    const res = await this.request(url);
    if (res.status === 404) return null;
    if (!res.ok) throw GitHubRepo.failure(res, `reading ${path}`);
    const body = (await res.json()) as { content?: string; encoding?: string };
    if (body.encoding !== 'base64' || body.content === undefined) return null;
    return Buffer.from(body.content, 'base64').toString('utf8');
  }

  /**
   * Creates a new file. Never overwrites: without a `sha`, GitHub refuses
   * to replace an existing file.
   */
  async createFile(path: string, content: string, message: string): Promise<void> {
    const url = `${this.base}/contents/${encodePath(path)}`;
    const res = await this.request(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        content: Buffer.from(content, 'utf8').toString('base64'),
        branch: this.cfg.branch,
      }),
    });
    if (!res.ok) throw GitHubRepo.failure(res, `creating ${path}`);
  }
}
