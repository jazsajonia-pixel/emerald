/**
 * Minimal reader for the gzip'd ustar archives GitHub returns from the
 * tarball endpoint. Supports regular files, pax extended headers (`x`, `g`)
 * and GNU long names (`L`). Everything else is skipped.
 */
import { gunzipSync } from 'node:zlib';

export interface TarFile {
  path: string;
  data: Buffer;
}

function str(buf: Buffer, start: number, len: number): string {
  const slice = buf.subarray(start, start + len);
  const nul = slice.indexOf(0);
  return slice.subarray(0, nul < 0 ? slice.length : nul).toString('utf8');
}

function octal(buf: Buffer, start: number, len: number): number {
  const s = str(buf, start, len).trim();
  return s === '' ? 0 : parseInt(s, 8);
}

function parsePax(data: Buffer): Record<string, string> {
  const out: Record<string, string> = {};
  let i = 0;
  while (i < data.length) {
    const sp = data.indexOf(0x20, i);
    if (sp < 0) break;
    const len = parseInt(data.subarray(i, sp).toString('utf8'), 10);
    if (!Number.isFinite(len) || len <= 0) break;
    const record = data.subarray(sp + 1, i + len - 1).toString('utf8');
    const eq = record.indexOf('=');
    if (eq > 0) out[record.slice(0, eq)] = record.slice(eq + 1);
    i += len;
  }
  return out;
}

export function readTarGz(gz: Uint8Array, maxTotalBytes = 200 * 1024 * 1024): TarFile[] {
  const buf = gunzipSync(gz, { maxOutputLength: maxTotalBytes });
  const files: TarFile[] = [];
  let offset = 0;
  let longName: string | null = null;
  let pax: Record<string, string> = {};
  while (offset + 512 <= buf.length) {
    const header = buf.subarray(offset, offset + 512);
    if (header.every((b) => b === 0)) break;
    const size = octal(header, 124, 12);
    const type = String.fromCharCode(header[156] ?? 0);
    const dataStart = offset + 512;
    const data = buf.subarray(dataStart, dataStart + size);
    offset = dataStart + Math.ceil(size / 512) * 512;
    if (type === 'x') {
      pax = parsePax(data);
      continue;
    }
    if (type === 'g') continue;
    if (type === 'L') {
      longName = str(data, 0, data.length);
      continue;
    }
    let name = str(header, 0, 100);
    const magic = str(header, 257, 6);
    if (magic.startsWith('ustar')) {
      const prefix = str(header, 345, 155);
      if (prefix) name = `${prefix}/${name}`;
    }
    if (pax.path) name = pax.path;
    if (longName) name = longName;
    longName = null;
    pax = {};
    if (type === '0' || type === '\0') files.push({ path: name, data: Buffer.from(data) });
  }
  return files;
}
