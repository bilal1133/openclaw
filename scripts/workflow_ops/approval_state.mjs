#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const APPROVAL_ROOT = path.join(ROOT, 'workflows', 'approvals');
const STATES = ['pending', 'approved', 'rejected', 'held'];
const REVISION_QUEUE_DIR = path.join(ROOT, 'delivery-queue', 'revisions');
const PATTERN_SANITIZER = path.join(ROOT, 'scripts', 'workflow_ops', 'pattern_sanitizer.mjs');

function nowIso() {
  return new Date().toISOString();
}

function parseArgs(argv) {
  const out = { cmd: argv[2] || '', flags: {} };
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

function ensureDirs() {
  for (const s of STATES) fs.mkdirSync(path.join(APPROVAL_ROOT, s), { recursive: true });
  fs.mkdirSync(REVISION_QUEUE_DIR, { recursive: true });
}

function approvalPath(state, approvalId) {
  return path.join(APPROVAL_ROOT, state, `${approvalId}.json`);
}

function readJson(file, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(obj, null, 2));
}

function locateRecord(approvalId) {
  for (const state of STATES) {
    const p = approvalPath(state, approvalId);
    if (fs.existsSync(p)) return { state, path: p, record: readJson(p) };
  }
  return null;
}

function moveRecord(loc, nextState) {
  const nextPath = approvalPath(nextState, loc.record.approval_id);
  fs.mkdirSync(path.dirname(nextPath), { recursive: true });
  fs.renameSync(loc.path, nextPath);
  return { state: nextState, path: nextPath, record: loc.record };
}

function requireFlag(flags, key) {
  const v = flags[key];
  if (typeof v !== 'string' || !v.trim()) throw new Error(`missing --${key}`);
  return v.trim();
}

function openclawCronAddNotice(to, approvalId, message) {
  if (!to) return { ok: false, skipped: true, reason: 'missing destination' };
  const NODE22 = process.env.OPENCLAW_NODE22 || '/Users/bilal/.nvm/versions/node/v22.22.0/bin/node';
  const OPENCLAW_JS = process.env.OPENCLAW_JS || '/Users/bilal/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/dist/index.js';

  const prompt = [
    'Send this approval notice exactly as plain text.',
    'Do not add commentary, and do not execute tools.',
    '',
    message
  ].join('\n');

  const args = [
    OPENCLAW_JS,
    'cron',
    'add',
    '--name',
    `approval-notice-${approvalId.slice(0, 8)}-${Date.now().toString(36)}`,
    '--description',
    'approval state notice',
    '--delete-after-run',
    '--agent',
    'personal-assistant',
    '--session',
    'isolated',
    '--wake',
    'now',
    '--at',
    '10s',
    '--message',
    prompt,
    '--announce',
    '--channel',
    'whatsapp',
    '--to',
    to,
    '--best-effort-deliver'
  ];

  const res = spawnSync(NODE22, args, { encoding: 'utf8' });
  if (res.status !== 0) {
    return {
      ok: false,
      error: (res.stderr || '').trim() || `exit ${res.status}`
    };
  }

  const parsed = (() => {
    try {
      return JSON.parse((res.stdout || '').trim() || '{}');
    } catch {
      return { raw: (res.stdout || '').trim() };
    }
  })();

  return { ok: true, result: parsed };
}

function resolveCadenceFromManifest(artifactPath) {
  const manifestPath = path.join(artifactPath, 'run-manifest.json');
  const manifest = readJson(manifestPath, {});
  return typeof manifest.cadence === 'string' ? manifest.cadence : 'daily';
}

function releasePublishBundle(record) {
  if (!record?.artifact_path) return { ok: false, skipped: true, reason: 'missing artifact_path' };
  const bundle = path.join(record.artifact_path, 'publish-bundle.md');
  const finalBundle = path.join(record.artifact_path, 'publish-bundle.final.md');
  if (!fs.existsSync(bundle)) return { ok: false, skipped: true, reason: 'publish-bundle missing' };
  fs.copyFileSync(bundle, finalBundle);
  return { ok: true, finalBundle };
}

function runPatternSanitizer(record, cadence) {
  if (!fs.existsSync(PATTERN_SANITIZER)) return { ok: false, skipped: true, reason: 'pattern_sanitizer missing' };
  const args = [
    PATTERN_SANITIZER,
    'sanitize',
    '--brand-id',
    record.brand_id,
    '--artifact-dir',
    record.artifact_path,
    '--run-id',
    record.run_id,
    '--cadence',
    cadence || resolveCadenceFromManifest(record.artifact_path)
  ];
  const res = spawnSync('node', args, { encoding: 'utf8' });
  if (res.status !== 0) {
    return { ok: false, error: (res.stderr || '').trim() || `exit ${res.status}` };
  }
  return { ok: true, output: (res.stdout || '').trim() };
}

function createRecord(flags) {
  const brandId = requireFlag(flags, 'brand-id');
  const runId = requireFlag(flags, 'run-id');
  const artifactPath = requireFlag(flags, 'artifact-path');
  const ownerName = (flags['owner-name'] || 'Brand Owner').toString().trim();
  const ownerWhatsapp = (flags['owner-whatsapp'] || '').toString().trim();
  const summary = (flags.summary || '').toString().trim() || `Approval required for brand ${brandId} run ${runId}.`;
  const deadlineHoursRaw = Number.parseInt(String(flags['deadline-hours'] || '24'), 10);
  const deadlineHours = Number.isFinite(deadlineHoursRaw) && deadlineHoursRaw > 0 ? deadlineHoursRaw : 24;
  const createdAt = nowIso();
  const approvalId = (flags['approval-id'] || `apr-${crypto.randomUUID().slice(0, 8)}-${Date.now().toString(36)}`).toString();
  const deadlineAt = new Date(Date.now() + deadlineHours * 3600 * 1000).toISOString();

  const record = {
    approval_id: approvalId,
    brand_id: brandId,
    run_id: runId,
    created_at: createdAt,
    deadline_at: deadlineAt,
    status: 'pending',
    owner: {
      name: ownerName,
      whatsapp: ownerWhatsapp
    },
    artifact_path: artifactPath,
    summary,
    decision_note: '',
    decided_at: null,
    events: [
      {
        ts: createdAt,
        type: 'created',
        note: summary
      }
    ]
  };

  writeJson(approvalPath('pending', approvalId), record);

  const msg = [
    `Approval Request: ${approvalId}`,
    `Brand: ${brandId}`,
    `Run: ${runId}`,
    `Deadline: ${deadlineAt}`,
    `Artifacts: ${artifactPath}`,
    '',
    summary,
    '',
    `Reply with: APPROVE ${approvalId}`,
    `Or: REJECT ${approvalId} <reason>`
  ].join('\n');

  const notice = ownerWhatsapp ? openclawCronAddNotice(ownerWhatsapp, approvalId, msg) : { ok: false, skipped: true, reason: 'owner_whatsapp missing' };

  return { ok: true, action: 'create', record, notice };
}

function updateState(flags, nextState) {
  const approvalId = requireFlag(flags, 'approval-id');
  const decisionNote = (flags['decision-note'] || '').toString().trim();
  const loc = locateRecord(approvalId);
  if (!loc) throw new Error(`approval record not found: ${approvalId}`);

  const record = loc.record;
  const now = nowIso();
  record.status = nextState;
  record.decision_note = decisionNote;
  record.decided_at = now;
  record.events = Array.isArray(record.events) ? record.events : [];
  record.events.push({ ts: now, type: nextState, note: decisionNote || null });

  writeJson(loc.path, record);
  const moved = moveRecord({ ...loc, record }, nextState);

  const out = { ok: true, action: nextState, record: moved.record };

  if (nextState === 'approved') {
    out.release = releasePublishBundle(record);
    out.pattern = runPatternSanitizer(record, (flags.cadence || '').toString().trim());
    const to = record.owner?.whatsapp || '';
    const msg = [
      `Approval Confirmed: ${record.approval_id}`,
      `Brand: ${record.brand_id}`,
      `Run: ${record.run_id}`,
      `Final bundle released at: ${record.artifact_path}`,
      decisionNote ? `Note: ${decisionNote}` : ''
    ].filter(Boolean).join('\n');
    out.notice = to ? openclawCronAddNotice(to, record.approval_id, msg) : { ok: false, skipped: true, reason: 'owner_whatsapp missing' };
  }

  if (nextState === 'rejected') {
    const revisionPath = path.join(REVISION_QUEUE_DIR, `${record.approval_id}.json`);
    writeJson(revisionPath, {
      approval_id: record.approval_id,
      brand_id: record.brand_id,
      run_id: record.run_id,
      artifact_path: record.artifact_path,
      rejection_note: decisionNote || 'No reason provided',
      created_at: now
    });
    out.revision = { queued: true, path: revisionPath };

    const to = record.owner?.whatsapp || '';
    const msg = [
      `Approval Rejected: ${record.approval_id}`,
      `Brand: ${record.brand_id}`,
      `Run: ${record.run_id}`,
      `Reason: ${decisionNote || 'No reason provided'}`,
      'A revision request has been queued.'
    ].join('\n');
    out.notice = to ? openclawCronAddNotice(to, record.approval_id, msg) : { ok: false, skipped: true, reason: 'owner_whatsapp missing' };
  }

  if (nextState === 'held') {
    const to = record.owner?.whatsapp || '';
    const msg = [
      `Approval Held: ${record.approval_id}`,
      `Brand: ${record.brand_id}`,
      `Run: ${record.run_id}`,
      `Reason: ${decisionNote || 'SLA exceeded'}`,
      'Publishing remains blocked until explicit approval.'
    ].join('\n');
    out.notice = to ? openclawCronAddNotice(to, record.approval_id, msg) : { ok: false, skipped: true, reason: 'owner_whatsapp missing' };
  }

  return out;
}

function parseIsoMs(iso) {
  const t = Date.parse(iso || '');
  return Number.isFinite(t) ? t : 0;
}

function remindRecord(record, reason) {
  const to = record.owner?.whatsapp || '';
  if (!to) return { ok: false, skipped: true, reason: 'owner_whatsapp missing' };
  const msg = [
    `Approval Reminder: ${record.approval_id}`,
    `Brand: ${record.brand_id}`,
    `Run: ${record.run_id}`,
    `Deadline: ${record.deadline_at}`,
    `Reason: ${reason}`,
    '',
    `Reply with: APPROVE ${record.approval_id}`,
    `Or: REJECT ${record.approval_id} <reason>`
  ].join('\n');
  return openclawCronAddNotice(to, record.approval_id, msg);
}

function listStateRecords(state) {
  const dir = path.join(APPROVAL_ROOT, state);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => readJson(path.join(dir, f), null))
    .filter(Boolean);
}

function remind(flags) {
  const specificId = (flags['approval-id'] || '').toString().trim();
  const dueOnly = Boolean(flags['all-due']);
  const now = Date.now();

  const records = specificId
    ? (() => {
      const loc = locateRecord(specificId);
      if (!loc) throw new Error(`approval record not found: ${specificId}`);
      return [loc.record];
    })()
    : listStateRecords('pending');

  const results = [];

  for (const record of records) {
    if (record.status !== 'pending') continue;
    const due = parseIsoMs(record.deadline_at) > 0 && now >= parseIsoMs(record.deadline_at);

    if (dueOnly && !due) continue;

    if (due) {
      const loc = locateRecord(record.approval_id);
      if (!loc) continue;
      record.status = 'held';
      record.decision_note = 'SLA exceeded (auto-hold + reminder)';
      record.decided_at = nowIso();
      record.events = Array.isArray(record.events) ? record.events : [];
      record.events.push({ ts: nowIso(), type: 'held', note: record.decision_note });
      writeJson(loc.path, record);
      moveRecord({ ...loc, record }, 'held');
      const notice = remindRecord(record, 'SLA exceeded. Run moved to HOLD state.');
      results.push({ approval_id: record.approval_id, action: 'held+reminded', notice });
    } else {
      const notice = remindRecord(record, 'Pending owner decision.');
      results.push({ approval_id: record.approval_id, action: 'reminded', notice });
    }
  }

  return { ok: true, action: 'remind', count: results.length, results };
}

function status(flags) {
  const approvalId = (flags['approval-id'] || '').toString().trim();
  if (approvalId) {
    const loc = locateRecord(approvalId);
    if (!loc) throw new Error(`approval record not found: ${approvalId}`);
    return { ok: true, action: 'status', state: loc.state, record: loc.record };
  }

  const summary = {};
  for (const state of STATES) {
    const list = listStateRecords(state);
    summary[state] = {
      count: list.length,
      records: list
    };
  }
  return { ok: true, action: 'status', summary };
}

function usage() {
  console.log('Usage: approval_state.mjs <create|approve|reject|hold|remind|status> [flags]');
  console.log('Examples:');
  console.log('  node approval_state.mjs create --brand-id acme --run-id r1 --artifact-path /path --owner-name "Owner" --owner-whatsapp +10000000000');
  console.log('  node approval_state.mjs approve --approval-id apr-123 --decision-note "Looks good"');
  console.log('  node approval_state.mjs remind --all-due');
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.cmd || args.flags.help) {
    usage();
    process.exit(args.flags.help ? 0 : 1);
  }

  ensureDirs();

  let result;
  if (args.cmd === 'create') result = createRecord(args.flags);
  else if (args.cmd === 'approve') result = updateState(args.flags, 'approved');
  else if (args.cmd === 'reject') result = updateState(args.flags, 'rejected');
  else if (args.cmd === 'hold') result = updateState(args.flags, 'held');
  else if (args.cmd === 'remind') result = remind(args.flags);
  else if (args.cmd === 'status') result = status(args.flags);
  else throw new Error(`unknown command: ${args.cmd}`);

  console.log(JSON.stringify(result, null, 2));
}

try {
  main();
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : String(err) }, null, 2));
  process.exit(1);
}
