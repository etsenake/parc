import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { root } from 'astro:config/server';

export function renderWhatsNew(): string {
  const renderer = fileURLToPath(new URL('../scripts/whats_new.py', root));
  const folder = mkdtempSync(join(tmpdir(), 'parc-whats-new-'));
  try {
    const page = join(folder, 'index.html');
    execFileSync(process.env.PYTHON || 'python3', [renderer, page], { stdio: ['ignore', 'ignore', 'inherit'] });
    return readFileSync(page, 'utf8');
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

export function splitOnce(page: string, anchor: string): [string, string] {
  const at = page.indexOf(anchor);
  if (at < 0 || page.indexOf(anchor, at + anchor.length) >= 0) {
    throw new Error(`What's New: expected exactly one ${anchor}`);
  }
  return [page.slice(0, at), page.slice(at + anchor.length)];
}
