import { createMcpHandler } from 'mcp-handler';
import { presentedSecret, secretMatches } from './auth.js';
import { loadConfig, type ServerConfig } from './config.js';
import { GitHubRepo, type FetchLike } from './github.js';
import { registerVaultTools, type ToolDeps } from './tools.js';

export const SERVER_INFO = { name: 'emerald-vault', version: '0.1.0' };

function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  });
}

export interface HandlerOptions {
  env?: Record<string, string | undefined>;
  githubFetch?: FetchLike;
  toolDeps?: Omit<ToolDeps, 'repo'>;
}

/** Builds the HTTP handler: secret check first, then the MCP protocol. */
export function buildHandler(opts: HandlerOptions = {}): (req: Request) => Promise<Response> {
  let config: ServerConfig | null = null;
  let configError: string | null = null;
  try {
    config = loadConfig(opts.env);
  } catch (e) {
    configError = (e as Error).message;
  }
  const mcp = config
    ? createMcpHandler(
        (server) => {
          registerVaultTools(server, {
            ...opts.toolDeps,
            repo: new GitHubRepo(config!.repo, opts.githubFetch),
          });
        },
        { serverInfo: SERVER_INFO },
      )
    : null;

  return async (req: Request) => {
    if (!config || !mcp) return json(503, { error: configError ?? 'Server is not configured.' });
    if (!secretMatches(presentedSecret(req), config.accessSecret)) {
      return json(401, { error: 'Missing or wrong access secret.' });
    }
    return mcp(req);
  };
}
