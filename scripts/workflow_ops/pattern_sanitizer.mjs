#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const SHARED_FILE = path.join(ROOT, 'brands', '_shared', 'pattern-library.jsonl');

function parseArgs(argv) {
  const out = { cmd: argv[2] || 'sanitize', flags: {} };
  for (let i = 3; i < argv.length; i += 1) {
    const t = argv[i];
    if (!t.startsWith('--')) continue;
    const k = t.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) out.flags[k] = true;
    else {
      out.flags[k] = next;
      i += 1;
    }
  }
  return out;
}

function requireFlag(flags, key) {
  const v = flags[key];
  if (typeof v !== 'string' || !v.trim()) throw new Error(`missing --${key}`);
  return v.trim();
}

function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

function extractBrandNameFromDossier(dossierPath) {
  const text = readText(dossierPath);
  const m = text.match(/^brand_name:\s*(.+)$/m);
  if (!m) return '';
  return (m[1] || '').replace(/^['"]|['"]$/g, '').trim();
}

function sanitizeLine(raw, ctx) {
  let line = raw || '';
  line = line.replace(/https?:\/\/[^\s)\]]+/g, '[link]');
  line = line.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '<email>');
  line = line.replace(/\+?\d[\d\s().-]{7,}\d/g, '<phone>');
  line = line.replace(/\$\s?\d[\d,.]*/g, '<metric>');
  line = line.replace(/\b\d+(?:\.\d+)?%\b/g, '<metric>');
  line = line.replace(/\b\d{1,4}(?:,\d{3})*(?:\.\d+)?\b/g, '<metric>');
  if (ctx.brandName) {
    const re = new RegExp(ctx.brandName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'ig');
    line = line.replace(re, '<brand>');
  }
  return line.replace(/\s+/g, ' ').trim();
}

function uniqueNonEmpty(lines, minLen = 10, maxLen = 220, limit = 20) {
  const out = [];
  const seen = new Set();
  for (const line of lines) {
    const s = line.trim();
    if (s.length < minLen || s.length > maxLen) continue;
    if (seen.has(s)) continue;
    seen.add(s);
    out.push(s);
    if (out.length >= limit) break;
  }
  return out;
}

function pickByRegex(text, regex) {
  const out = [];
  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    if (regex.test(line)) out.push(line.trim());
  }
  return out;
}

function runSanitize(flags) {
  const brandId = requireFlag(flags, 'brand-id');
  const artifactDir = requireFlag(flags, 'artifact-dir');
  const runId = requireFlag(flags, 'run-id');
  const cadence = (flags.cadence || 'daily').toString();

  const dossierPath = path.join(ROOT, 'brands', brandId, 'profile', 'brand-dossier.md');
  const brandName = extractBrandNameFromDossier(dossierPath);
  const ctx = { brandName };

  const technical = readText(path.join(artifactDir, 'technical-writer.md'));
  const marketing = readText(path.join(artifactDir, 'marketing-pack.md'));
  const design = readText(path.join(artifactDir, 'brand-design-pack.md'));
  const cs = readText(path.join(artifactDir, 'client-success-report.md'));

  const hookCandidates = [
    ...pickByRegex(marketing, /^#+\s+/),
    ...pickByRegex(marketing, /hook|angle|opening/i)
  ];
  const ctaCandidates = pickByRegex(marketing, /cta|call to action|next step|reply|book|apply/i);
  const designCandidates = [
    ...pickByRegex(design, /^#+\s+/),
    ...pickByRegex(design, /layout|composition|palette|style|prompt/i)
  ];
  const csCandidates = [
    ...pickByRegex(cs, /risk|renewal|retention|next action|qbr|nps|churn/i),
    ...pickByRegex(technical, /SOP|checklist|runbook|qa|acceptance/i)
  ];

  const hooks = uniqueNonEmpty(hookCandidates.map((l) => sanitizeLine(l, ctx)), 12, 180, 12);
  const ctas = uniqueNonEmpty(ctaCandidates.map((l) => sanitizeLine(l, ctx)), 12, 180, 12);
  const designDirectives = uniqueNonEmpty(designCandidates.map((l) => sanitizeLine(l, ctx)), 12, 220, 12);
  const csFrameworks = uniqueNonEmpty(csCandidates.map((l) => sanitizeLine(l, ctx)), 12, 220, 12);

  const entry = {
    ts: new Date().toISOString(),
    source_brand_ref: crypto.createHash('sha256').update(brandId).digest('hex').slice(0, 12),
    run_id: runId,
    cadence,
    patterns: {
      hooks,
      ctas,
      design_directives: designDirectives,
      cs_frameworks: csFrameworks
    },
    policy: 'patterns_only',
    source_artifact_dir: path.basename(artifactDir)
  };

  fs.mkdirSync(path.dirname(SHARED_FILE), { recursive: true });
  if (!flags['dry-run']) fs.appendFileSync(SHARED_FILE, `${JSON.stringify(entry)}\n`);

  return {
    ok: true,
    action: 'sanitize',
    appended: !Boolean(flags['dry-run']),
    shared_file: SHARED_FILE,
    summary: {
      hooks: hooks.length,
      ctas: ctas.length,
      design_directives: designDirectives.length,
      cs_frameworks: csFrameworks.length
    }
  };
}

function usage() {
  console.log('Usage: pattern_sanitizer.mjs sanitize --brand-id <id> --artifact-dir <dir> --run-id <id> --cadence <daily|weekly|monthly> [--dry-run]');
}

try {
  const args = parseArgs(process.argv);
  if (args.flags.help || args.cmd !== 'sanitize') {
    usage();
    process.exit(args.flags.help ? 0 : 1);
  }
  const result = runSanitize(args.flags);
  console.log(JSON.stringify(result, null, 2));
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : String(err) }, null, 2));
  process.exit(1);
}
