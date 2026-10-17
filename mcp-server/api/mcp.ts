/**
 * Vercel Function: https://<project>.vercel.app/api/mcp
 * Streamable HTTP MCP endpoint for the Emerald vault. See ../README.md.
 */
import { buildHandler } from '../src/handler.js';

const handle = buildHandler();

export default {
  fetch(request: Request): Promise<Response> {
    return handle(request);
  },
};
