#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const WF_ROOT = path.join(ROOT, 'workflows');
const DEF_DIR = path.join(WF_ROOT, 'definitions');
const RUNS_DIR = path.join(WF_ROOT, 'state', 'runs');
const FEEDBACK_DIR = path.join(WF_ROOT, 'feedback');
const FEEDBACK_FILE = path.join(FEEDBACK_DIR, 'entries.jsonl');
const IMPROVE_LOG = path.join(FEEDBACK_DIR, 'improvements.jsonl');
const BACKUP_DIR = path.join(DEF_DIR, '.backups');

function ensure() {
  [WF_ROOT, DEF_DIR, RUNS_DIR, FEEDBACK_DIR, BACKUP_DIR].forEach((d) => fs.mkdirSync(d, { recursive: true }));
}

function nowIso() {
  return new Date().toISOString();
}

function parseArgs(argv) {
  const out = { cmd: argv[2] || '', workflowId: '', runId: '', feedback: '', score: null, autoApply: false, json: false, maxChanges: 3 };
  for (let i = 3; i < argv.length; i += 1) {
    const t = argv[i];
    if (t === '--workflow-id') out.workflowId = argv[++i] || '';
    else if (t === '--run-id') out.runId = argv[++i] || '';
    else if (t === '--feedback') out.feedback = argv[++i] || '';
    else if (t === '--score') out.score = Number(argv[++i] || '');
    else if (t === '--auto-apply') out.autoApply = true;
    else if (t === '--json') out.json = true;
    else if (t === '--max-changes') out.maxChanges = Math.max(1, Number(argv[++i] || '3'));
  }
  return out;
}

function readJson(file, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

function appendJsonl(file, obj) {
  fs.appendFileSync(file, `${JSON.stringify(obj)}\n`);
}

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  }).filter(Boolean);
}

function listRuns(workflowId) {
  const files = fs.existsSync(RUNS_DIR) ? fs.readdirSync(RUNS_DIR).filter((f) => f.endsWith('.json')) : [];
  return files.map((f) => readJson(path.join(RUNS_DIR, f))).filter((r) => r && r.workflowId === workflowId);
}

function containsAny(text, needles) {
  const t = (text || '').toLowerCase();
  return needles.some((n) => t.includes(n));
}

function deriveSuggestions(workflowId) {
  const feedback = readJsonl(FEEDBACK_FILE).filter((e) => e.workflowId === workflowId);
  const runs = listRuns(workflowId);
  const suggestions = [];

  const combined = feedback.map((f) => String(f.feedback || '')).join('\n').toLowerCase();

  if (containsAny(combined, ['source', 'citation', 'reference', 'proof'])) {
    suggestions.push('Always include source links for key claims and date-tag major facts.');
  }
  if (containsAny(combined, ['too long', 'lengthy', 'verbose'])) {
    suggestions.push('Prefer concise outputs unless user explicitly asks for long-form detail.');
  }
  if (containsAny(combined, ['too short', 'shallow', 'not enough detail'])) {
    suggestions.push('Add deeper detail with concrete examples and clear section structure.');
  }
  if (containsAny(combined, ['wrong', 'incorrect', 'hallucinat', 'inaccurate'])) {
    suggestions.push('Add stricter verification checks before final delivery.');
  }
  if (containsAny(combined, ['slow', 'takes too long', 'latency'])) {
    suggestions.push('Optimize for speed: limit low-value deep dives and prioritize high-signal sources first.');
  }

  const failed = runs.filter((r) => r.status === 'failed').length;
  const total = runs.length;
  if (total >= 3 && failed / total >= 0.25) {
    suggestions.push('Increase resilience: use fallback delegates and continue with best-effort outputs on partial failures.');
  }

  // Autonomous signals (no user feedback required)
  const completed = runs.filter((r) => r.status === 'completed');
  const durations = completed
    .map((r) => {
      const c = Date.parse(r.createdAt || '');
      const u = Date.parse(r.updatedAt || '');
      return Number.isFinite(c) && Number.isFinite(u) ? (u - c) : null;
    })
    .filter((v) => Number.isFinite(v));
  const avgDurationMs = durations.length ? durations.reduce((a, b) => a + b, 0) / durations.length : null;
  if (avgDurationMs && avgDurationMs > 180000) {
    suggestions.push('Reduce latency: trim low-value substeps and prioritize highest-signal sources first.');
  }

  const verifyFailures = runs.filter((r) => {
    const verify = Array.isArray(r.stages) ? r.stages.find((s) => s.name === 'verify') : null;
    return verify && verify.status === 'failed';
  }).length;
  if (total >= 2 && verifyFailures > 0) {
    suggestions.push('Harden verify stage: add pre-delivery checks for expected files/artifacts and fallback generation.');
  }

  const execFailures = runs.filter((r) => {
    const exec = Array.isArray(r.stages) ? r.stages.find((s) => s.name === 'execute') : null;
    return exec && exec.status === 'failed';
  }).length;
  if (total >= 2 && execFailures > 0) {
    suggestions.push('Improve execute reliability: add retry policy and alternate delegate path when primary dispatch fails.');
  }

  const lowScores = feedback.filter((f) => Number.isFinite(f.score) && f.score <= 2).length;
  if (feedback.length >= 3 && lowScores / feedback.length >= 0.34) {
    suggestions.push('Raise quality gate strictness before final delivery.');
  }

  return {
    feedbackCount: feedback.length,
    runCount: runs.length,
    autonomousSignals: {
      avgDurationMs,
      verifyFailures,
      execFailures,
      failedRuns: failed
    },
    suggestions: Array.from(new Set(suggestions))
  };
}

function applySuggestions(workflowId, suggestions, maxChanges) {
  const defPath = path.join(DEF_DIR, `${workflowId}.json`);
  const wf = readJson(defPath);
  if (!wf) throw new Error(`Workflow definition not found: ${defPath}`);

  const backupPath = path.join(BACKUP_DIR, `${workflowId}-${Date.now()}.json`);
  writeJson(backupPath, wf);

  wf.defaults = wf.defaults || {};
  const existing = Array.isArray(wf.defaults.assumptions) ? wf.defaults.assumptions : [];
  const adds = [];
  for (const s of suggestions) {
    if (adds.length >= maxChanges) break;
    if (!existing.includes(s)) adds.push(s);
  }

  wf.defaults.assumptions = [...existing, ...adds];
  writeJson(defPath, wf);

  const record = { ts: nowIso(), workflowId, applied: adds, backupPath, defPath };
  appendJsonl(IMPROVE_LOG, record);
  return record;
}

function cmdSubmit(args) {
  if (!args.workflowId) throw new Error('--workflow-id is required');
  if (!args.feedback.trim()) throw new Error('--feedback is required');
  if (args.score !== null && (!Number.isFinite(args.score) || args.score < 1 || args.score > 5)) {
    throw new Error('--score must be between 1 and 5');
  }
  const entry = {
    ts: nowIso(),
    workflowId: args.workflowId,
    runId: args.runId || null,
    score: args.score,
    feedback: args.feedback.trim()
  };
  appendJsonl(FEEDBACK_FILE, entry);
  return { ok: true, entry };
}

function cmdImprove(args) {
  if (!args.workflowId) throw new Error('--workflow-id is required');
  const analysis = deriveSuggestions(args.workflowId);
  let applied = null;
  if (args.autoApply && analysis.suggestions.length > 0) {
    applied = applySuggestions(args.workflowId, analysis.suggestions, args.maxChanges);
  }
  return { ok: true, workflowId: args.workflowId, analysis, autoApplied: applied };
}

function main() {
  ensure();
  const args = parseArgs(process.argv);
  if (!args.cmd || !['submit', 'improve'].includes(args.cmd)) {
    console.log('Usage: workflow_feedback_loop.mjs <submit|improve> --workflow-id <id> [--feedback "..."] [--score 1-5] [--run-id id] [--auto-apply] [--max-changes N] [--json]');
    process.exit(1);
  }

  let out;
  if (args.cmd === 'submit') out = cmdSubmit(args);
  else out = cmdImprove(args);

  if (args.json || true) console.log(JSON.stringify(out, null, 2));
}

main();
