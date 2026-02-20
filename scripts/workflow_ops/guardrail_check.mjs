#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const APPROVAL_ROOT = path.join(ROOT, 'workflows', 'approvals');

function parseArgs(argv) {
  const out = { cmd: argv[2] || 'check', flags: {} };
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

function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

function readJson(file, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function requireFlag(flags, key) {
  const v = flags[key];
  if (typeof v !== 'string' || !v.trim()) throw new Error(`missing --${key}`);
  return v.trim();
}

function extractSection(text, heading) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim().toLowerCase() === heading.toLowerCase());
  if (start === -1) return [];
  const section = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^##\s+/.test(line)) break;
    section.push(line);
  }
  return section;
}

function extractProhibitedPhrases(dossier) {
  const lines = extractSection(dossier, '## Messaging Do/Don\'t');
  const out = new Set();
  for (const raw of lines) {
    const line = raw.trim();
    if (!line.startsWith('-')) continue;
    if (!/(don't|do not|avoid|never|prohibit|forbid)/i.test(line)) continue;

    const quoted = [...line.matchAll(/"([^"]+)"/g)].map((m) => m[1]?.trim()).filter(Boolean);
    for (const q of quoted) out.add(q.toLowerCase());

    const cleaned = line
      .replace(/^[-*]\s*/, '')
      .replace(/^(do not|don't|avoid|never|prohibit|forbid)\s*/i, '')
      .replace(/[:.]$/g, '')
      .trim();
    if (cleaned.length >= 4) out.add(cleaned.toLowerCase());
  }
  return [...out];
}

function countSourcesCsvRows(file) {
  const text = readText(file).trim();
  if (!text) return 0;
  const lines = text.split(/\r?\n/).filter(Boolean);
  if (lines.length <= 1) return 0;
  return lines.length - 1;
}

function countUrls(text) {
  const matches = text.match(/https?:\/\/[^\s)\]]+/g);
  return matches ? matches.length : 0;
}

function findUnsupportedNumericClaims(text, fileLabel) {
  const lines = text.split(/\r?\n/);
  const issues = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!/(\$\s?\d|\d+%|\b\d{4}\b|\b\d{2,}\b)/.test(line)) continue;
    if (/(https?:\/\/|\[source|citation|according to)/i.test(line)) continue;
    if (!/[A-Za-z]/.test(line)) continue;
    issues.push({ file: fileLabel, line: i + 1, text: line.trim() });
    if (issues.length >= 20) break;
  }
  return issues;
}

function findProhibitedUsage(text, phrases, fileLabel) {
  const low = text.toLowerCase();
  const hits = [];
  for (const phrase of phrases) {
    if (!phrase || phrase.length < 4) continue;
    if (low.includes(phrase)) hits.push({ file: fileLabel, phrase });
  }
  return hits;
}

function findApprovalRecord(approvalId) {
  const states = ['pending', 'approved', 'rejected', 'held'];
  for (const state of states) {
    const file = path.join(APPROVAL_ROOT, state, `${approvalId}.json`);
    if (fs.existsSync(file)) return { state, file, record: readJson(file, null) };
  }
  return null;
}

function runCheck(flags) {
  const brandId = requireFlag(flags, 'brand-id');
  const artifactDir = requireFlag(flags, 'artifact-dir');
  const dossierPath = path.join(ROOT, 'brands', brandId, 'profile', 'brand-dossier.md');
  const dossier = readText(dossierPath);
  const manifestPath = path.join(artifactDir, 'run-manifest.json');
  const manifest = readJson(manifestPath, {});
  const cadence = (flags.cadence || manifest.cadence || 'daily').toString();

  const required = [
    'technical-writer.md',
    'marketing-pack.md',
    'brand-design-pack.md',
    'publish-bundle.md',
    'sources.csv',
    'run-manifest.json',
    'approval-summary.md'
  ];

  if (cadence === 'weekly' || cadence === 'monthly') required.push('client-success-report.md');

  const checks = [];

  const missing = required.filter((f) => !fs.existsSync(path.join(artifactDir, f)));
  checks.push({
    name: 'mandatory_artifacts_present',
    severity: 'blocking',
    ok: missing.length === 0,
    details: missing.length ? { missing } : { required_count: required.length }
  });

  const sourcesRows = countSourcesCsvRows(path.join(artifactDir, 'sources.csv'));
  checks.push({
    name: 'source_rows_present',
    severity: 'blocking',
    ok: sourcesRows > 0,
    details: { rows: sourcesRows }
  });

  const marketingPack = readText(path.join(artifactDir, 'marketing-pack.md'));
  const publishBundle = readText(path.join(artifactDir, 'publish-bundle.md'));
  const urlCount = countUrls(marketingPack) + countUrls(publishBundle);
  checks.push({
    name: 'reference_links_present',
    severity: 'blocking',
    ok: urlCount > 0,
    details: { url_count: urlCount }
  });

  const unsupported = [
    ...findUnsupportedNumericClaims(marketingPack, 'marketing-pack.md'),
    ...findUnsupportedNumericClaims(publishBundle, 'publish-bundle.md')
  ];
  checks.push({
    name: 'unsupported_claims_check',
    severity: 'blocking',
    ok: unsupported.length === 0,
    details: unsupported.length ? { count: unsupported.length, sample: unsupported.slice(0, 5) } : { count: 0 }
  });

  const phrases = extractProhibitedPhrases(dossier);
  const prohibitedHits = [
    ...findProhibitedUsage(marketingPack, phrases, 'marketing-pack.md'),
    ...findProhibitedUsage(publishBundle, phrases, 'publish-bundle.md')
  ];
  checks.push({
    name: 'prohibited_language_check',
    severity: 'blocking',
    ok: prohibitedHits.length === 0,
    details: prohibitedHits.length ? { count: prohibitedHits.length, sample: prohibitedHits.slice(0, 5) } : { count: 0 }
  });

  const approvalId = (flags['approval-id'] || manifest.approval_id || '').toString();
  if (approvalId) {
    const approval = findApprovalRecord(approvalId);
    checks.push({
      name: 'approval_state_exists',
      severity: 'blocking',
      ok: Boolean(approval),
      details: approval ? { state: approval.state, file: approval.file } : { missing_approval_id: approvalId }
    });
  } else {
    checks.push({
      name: 'approval_state_exists',
      severity: 'warning',
      ok: false,
      details: { note: 'approval_id not provided' }
    });
  }

  const blockingFailed = checks.filter((c) => c.severity === 'blocking' && !c.ok);
  const warningFailed = checks.filter((c) => c.severity === 'warning' && !c.ok);

  return {
    ok: blockingFailed.length === 0,
    brand_id: brandId,
    artifact_dir: artifactDir,
    cadence,
    blocking_failures: blockingFailed.length,
    warning_failures: warningFailed.length,
    checks
  };
}

function usage() {
  console.log('Usage: guardrail_check.mjs check --brand-id <id> --artifact-dir <path> [--approval-id <id>] [--cadence daily|weekly|monthly]');
}

try {
  const args = parseArgs(process.argv);
  if (args.flags.help || args.cmd !== 'check') {
    usage();
    process.exit(args.flags.help ? 0 : 1);
  }
  const result = runCheck(args.flags);
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 2);
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : String(err) }, null, 2));
  process.exit(1);
}
