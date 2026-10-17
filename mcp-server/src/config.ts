import { MIN_SECRET_LENGTH } from './auth.js';
import type { RepoConfig } from './github.js';

export interface ServerConfig {
  repo: RepoConfig;
  accessSecret: string;
}

const NAME = /^[A-Za-z0-9_.-]{1,100}$/;

/**
 * Reads configuration from environment variables (set in Vercel → Project →
 * Settings → Environment Variables). Throws a message naming the missing or
 * invalid variable, never its value.
 */
export function loadConfig(env: Record<string, string | undefined> = process.env): ServerConfig {
  const owner = env.EMERALD_GITHUB_OWNER?.trim() ?? '';
  const repo = env.EMERALD_GITHUB_REPO?.trim() ?? '';
  const branch = env.EMERALD_GITHUB_BRANCH?.trim() || 'main';
  const token = env.EMERALD_GITHUB_TOKEN?.trim() ?? '';
  const secret = env.EMERALD_MCP_SECRET?.trim() ?? '';
  const problems: string[] = [];
  if (!NAME.test(owner)) problems.push('EMERALD_GITHUB_OWNER');
  if (!NAME.test(repo) || repo === '.' || repo === '..') problems.push('EMERALD_GITHUB_REPO');
  if (branch.length > 255 || /[\s~^:?*[\\]/.test(branch) || branch.includes('..')) {
    problems.push('EMERALD_GITHUB_BRANCH');
  }
  if (token === '') problems.push('EMERALD_GITHUB_TOKEN');
  if (secret.length < MIN_SECRET_LENGTH) problems.push(`EMERALD_MCP_SECRET (at least ${MIN_SECRET_LENGTH} characters)`);
  if (problems.length > 0) {
    throw new Error(`Server is not configured. Missing or invalid: ${problems.join(', ')}.`);
  }
  return { repo: { owner, repo, branch, token }, accessSecret: secret };
}
