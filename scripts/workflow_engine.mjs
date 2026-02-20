#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const WF_ROOT = path.join(ROOT, 'workflows');
const DEF_DIR = path.join(WF_ROOT, 'definitions');
const STATE_DIR = path.join(WF_ROOT, 'state');
const RUNS_DIR = path.join(STATE_DIR, 'runs');
const TOOLS_DIR = path.join(STATE_DIR, 'tools');
const OUTBOX_DIR = path.join(WF_ROOT, 'outbox');
const LOGS_DIR = path.join(WF_ROOT, 'logs');
const INDEX_PATH = path.join(STATE_DIR, 'index.json');
const FEEDBACK_LOOP_SCRIPT = path.join(ROOT, 'scripts', 'workflow_feedback_loop.mjs');

const STAGES = ['intake', 'classify', 'plan', 'configure_tools', 'execute', 'verify', 'deliver', 'log'];

function ensureDirs() {
  [WF_ROOT, DEF_DIR, STATE_DIR, RUNS_DIR, TOOLS_DIR, OUTBOX_DIR, LOGS_DIR].forEach((d) => fs.mkdirSync(d, { recursive: true }));
}

function nowIso() {
  return new Date().toISOString();
}

function hash(input) {
  return crypto.createHash('sha256').update(input).digest('hex');
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

function usage() {
  console.log('Usage: workflow_engine.mjs run <workflow-id> --input "..." [--idempotency-key KEY] [--force] [--resume RUN_ID]');
}

function parseArgs(argv) {
  const args = { cmd: argv[2], workflowId: argv[3], input: '', idempotencyKey: '', force: false, resume: '' };
  for (let i = 4; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--input') args.input = argv[++i] || '';
    else if (token === '--idempotency-key') args.idempotencyKey = argv[++i] || '';
    else if (token === '--force') args.force = true;
    else if (token === '--resume') args.resume = argv[++i] || '';
  }
  return args;
}

function loadWorkflow(workflowId) {
  const file = path.join(DEF_DIR, `${workflowId}.json`);
  const wf = readJson(file);
  if (!wf) throw new Error(`Workflow not found: ${file}`);
  return { wf, file };
}

function runCommand(command, args, env = {}) {
  const res = spawnSync(command, args, {
    encoding: 'utf8',
    env: { ...process.env, ...env }
  });
  return {
    ok: res.status === 0,
    status: res.status,
    stdout: (res.stdout || '').trim(),
    stderr: (res.stderr || '').trim()
  };
}

function runFeedbackImprove(workflowId, wf) {
  const cfg = wf.selfImprove || {};
  if (!cfg.enabled) return { skipped: true, reason: 'selfImprove disabled' };
  if (!fs.existsSync(FEEDBACK_LOOP_SCRIPT)) return { skipped: true, reason: 'feedback loop script missing' };
  const args = [FEEDBACK_LOOP_SCRIPT, 'improve', '--workflow-id', workflowId, '--max-changes', String(cfg.maxChangesPerRun || 2)];
  if (cfg.autoApplyLowRisk) args.push('--auto-apply');
  const res = runCommand('node', args);
  if (!res.ok) return { skipped: true, reason: 'improve command failed', stderr: res.stderr };
  try {
    return { result: JSON.parse(res.stdout || '{}') };
  } catch {
    return { result: { raw: res.stdout } };
  }
}

function loadIndex() {
  return readJson(INDEX_PATH, { idempotency: {} });
}

function saveIndex(index) {
  writeJson(INDEX_PATH, index);
}

function runPath(runId) {
  return path.join(RUNS_DIR, `${runId}.json`);
}

function saveRun(run) {
  run.updatedAt = nowIso();
  writeJson(runPath(run.runId), run);
}

function stageRecord(name) {
  return {
    name,
    status: 'pending',
    attempts: 0,
    startedAt: null,
    finishedAt: null,
    output: null,
    error: null
  };
}

function getStage(run, name) {
  return run.stages.find((s) => s.name === name);
}

function setStage(run, name, patch) {
  const s = getStage(run, name);
  Object.assign(s, patch);
}

function appendLog(line) {
  fs.appendFileSync(path.join(LOGS_DIR, 'events.jsonl'), `${JSON.stringify(line)}\n`);
}

function renderTemplate(text, ctx) {
  return text.replace(/\{\{(\w+)\}\}/g, (_, key) => String(ctx[key] ?? ''));
}

function todayDate() {
  return new Date().toISOString().slice(0, 10);
}

function parseInputPayload(inputText) {
  const raw = (inputText || '').trim();
  if (!raw) return null;

  const asJson = () => {
    try {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
      return null;
    }
  };

  const direct = asJson();
  if (direct) return direct;

  const prefixed = raw.match(/^RUN_BRAND_WORKFLOW\s+(\{[\s\S]+\})$/);
  if (!prefixed) return null;
  try {
    const parsed = JSON.parse(prefixed[1]);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function runStage(run, wf, name) {
  const s = getStage(run, name);
  if (s.status === 'completed') return;

  setStage(run, name, { status: 'running', startedAt: nowIso(), attempts: s.attempts + 1, error: null });
  saveRun(run);

  try {
    let output = null;

    if (name === 'intake') {
      const parsedPayload = parseInputPayload(run.input);
      const inferredTask = parsedPayload
        ? String(parsedPayload.task || parsedPayload.prompt || parsedPayload.message || '').trim()
        : '';

      const normalizedTask = inferredTask || run.input.trim();
      if (parsedPayload && typeof parsedPayload.brand_id === 'string') run.context.brand_id = parsedPayload.brand_id.trim();
      if (parsedPayload && typeof parsedPayload.cadence === 'string') run.context.cadence = parsedPayload.cadence.trim();
      if (parsedPayload && typeof parsedPayload.run_date === 'string') run.context.run_date = parsedPayload.run_date.trim();
      if (parsedPayload && typeof parsedPayload.trigger_source === 'string') run.context.trigger_source = parsedPayload.trigger_source.trim();
      if (parsedPayload && typeof parsedPayload.approval_id === 'string') run.context.approval_id = parsedPayload.approval_id.trim();
      if (parsedPayload && typeof parsedPayload.role === 'string') run.context.role = parsedPayload.role.trim();

      output = {
        inputText: run.input,
        normalizedTask,
        parsedPayload,
        receivedAt: nowIso()
      };
      run.context.task = output.normalizedTask;
    } else if (name === 'classify') {
      const t = (run.context.task || '').toLowerCase();
      let route = 'general';
      if (run.context.brand_id || run.context.cadence || (t.includes('run_brand_workflow'))) route = 'brand';
      else if (/(blog|article|newsletter|linkedin|post|thread|content)/.test(t)) route = 'content';
      else if (/(restart|fix|debug|config|setup|gateway|cron|error)/.test(t)) route = 'ops';
      if (route === 'brand') {
        if (!run.context.cadence) run.context.cadence = 'daily';
        if (!run.context.run_date) run.context.run_date = todayDate();
        if (!run.context.trigger_source) run.context.trigger_source = 'manual';
      }
      output = { route };
      run.context.route = route;
    } else if (name === 'plan') {
      const route = run.context.route || 'general';
      const steps = route === 'content'
        ? ['delegate_to_personal_assistant', 'generate_publish_pack', 'deliver_summary']
        : route === 'brand'
          ? ['delegate_to_brand_orchestrator', 'assemble_role_artifacts', 'run_guardrails', 'create_approval_package', 'deliver_summary']
        : route === 'ops'
          ? ['delegate_with_ops_prefix', 'verify_changes', 'deliver_summary']
          : ['handle_directly_or_delegate', 'verify', 'deliver'];
      output = { route, steps, assumptions: wf.defaults?.assumptions || [] };
      run.context.plan = output;
    } else if (name === 'configure_tools') {
      const cfg = wf.autoConfigure || { enabled: false, allowlist: [], toolCommands: {} };
      const configured = [];
      const skipped = [];
      if (!cfg.enabled) {
        output = { configured, skipped, reason: 'autoConfigure disabled' };
      } else {
        for (const tool of cfg.allowlist || []) {
          const marker = path.join(TOOLS_DIR, `${tool}.ok`);
          if (fs.existsSync(marker)) {
            skipped.push({ tool, reason: 'already_configured' });
            continue;
          }
          const cmd = cfg.toolCommands?.[tool];
          if (!cmd || !cmd.command) {
            skipped.push({ tool, reason: 'no_command' });
            continue;
          }
          const res = runCommand(cmd.command, cmd.args || []);
          if (res.ok) {
            fs.writeFileSync(marker, `${nowIso()}\n`);
            configured.push({ tool, stdout: res.stdout });
          } else {
            skipped.push({ tool, reason: 'command_failed', stderr: res.stderr });
          }
        }
        output = { configured, skipped };
      }
      run.context.tools = output;
    } else if (name === 'execute') {
      const execCfg = wf.execute || {};
      if (!execCfg.command) throw new Error('Missing workflow execute.command');
      const templateContext = {
        task: run.context.task || '',
        route: run.context.route || 'general',
        brand_id: run.context.brand_id || '',
        cadence: run.context.cadence || '',
        run_date: run.context.run_date || '',
        trigger_source: run.context.trigger_source || '',
        approval_id: run.context.approval_id || '',
        runId: run.runId,
        idempotencyKey: run.idempotencyKey
      };
      const args = (execCfg.args || []).map((a) => renderTemplate(a, templateContext));
      const res = runCommand(execCfg.command, args, {
        WF_RUN_ID: run.runId,
        WF_ROUTE: templateContext.route,
        WF_TASK: templateContext.task,
        WF_BRAND_ID: templateContext.brand_id,
        WF_CADENCE: templateContext.cadence,
        WF_RUN_DATE: templateContext.run_date,
        WF_TRIGGER_SOURCE: templateContext.trigger_source,
        WF_APPROVAL_ID: templateContext.approval_id,
        WF_IDEMPOTENCY_KEY: run.idempotencyKey
      });
      if (!res.ok) throw new Error(res.stderr || `execute failed with status ${res.status}`);
      output = { stdout: res.stdout };
      run.context.execution = output;
    } else if (name === 'verify') {
      const checks = [];
      const verify = wf.verify || {};
      const verifyTemplateContext = {
        runId: run.runId,
        workflowId: run.workflowId,
        task: run.context.task || '',
        route: run.context.route || 'general',
        brand_id: run.context.brand_id || '',
        cadence: run.context.cadence || '',
        run_date: run.context.run_date || '',
        trigger_source: run.context.trigger_source || '',
        approval_id: run.context.approval_id || ''
      };
      for (const file of verify.requiredFiles || []) {
        const p = renderTemplate(file, verifyTemplateContext);
        checks.push({ file: p, exists: fs.existsSync(p) });
      }
      const failed = checks.filter((c) => !c.exists);
      output = { checks, ok: failed.length === 0 };
      if (!output.ok) throw new Error(`verify failed: missing ${failed.map((f) => f.file).join(', ')}`);
    } else if (name === 'deliver') {
      const outPath = renderTemplate(wf.deliver?.summaryFile || path.join(OUTBOX_DIR, '{{runId}}.md'), {
        runId: run.runId,
        workflowId: run.workflowId,
        task: run.context.task || '',
        route: run.context.route || '',
        brand_id: run.context.brand_id || '',
        cadence: run.context.cadence || '',
        run_date: run.context.run_date || '',
        trigger_source: run.context.trigger_source || '',
        approval_id: run.context.approval_id || ''
      });
      const lines = [
        `# Workflow Run ${run.runId}`,
        `- Workflow: ${run.workflowId}`,
        `- Route: ${run.context.route}`,
        `- Brand: ${run.context.brand_id || 'n/a'}`,
        `- Cadence: ${run.context.cadence || 'n/a'}`,
        `- Run Date: ${run.context.run_date || 'n/a'}`,
        `- Trigger Source: ${run.context.trigger_source || 'n/a'}`,
        `- Approval ID: ${run.context.approval_id || 'n/a'}`,
        `- Task: ${run.context.task}`,
        `- Status: ${run.status}`,
        `- Updated: ${nowIso()}`,
        '',
        '## Execution',
        '```',
        String(run.context.execution?.stdout || 'n/a'),
        '```'
      ];
      fs.mkdirSync(path.dirname(outPath), { recursive: true });
      fs.writeFileSync(outPath, lines.join('\n'));
      output = { summaryFile: outPath };
      run.context.delivery = output;
    } else if (name === 'log') {
      appendLog({
        ts: nowIso(),
        runId: run.runId,
        workflowId: run.workflowId,
        status: run.status,
        route: run.context.route,
        brand_id: run.context.brand_id || null,
        cadence: run.context.cadence || null,
        approval_id: run.context.approval_id || null,
        role: run.context.role || null
      });
      const improve = runFeedbackImprove(run.workflowId, wf);
      output = { logged: true, selfImprove: improve };
    } else {
      throw new Error(`Unknown stage: ${name}`);
    }

    setStage(run, name, { status: 'completed', finishedAt: nowIso(), output, error: null });
    saveRun(run);
  } catch (err) {
    setStage(run, name, {
      status: 'failed',
      finishedAt: nowIso(),
      error: err instanceof Error ? err.message : String(err)
    });
    saveRun(run);
    throw err;
  }
}

function runWorkflow(args) {
  ensureDirs();
  const { wf } = loadWorkflow(args.workflowId);
  const input = args.input?.trim();
  if (!input) throw new Error('Missing --input');

  const idKey = args.idempotencyKey || hash(`${args.workflowId}:${input}`);
  const index = loadIndex();

  if (!args.force && !args.resume) {
    const existing = index.idempotency?.[idKey];
    if (existing) {
      const existingRun = readJson(runPath(existing));
      if (existingRun?.status === 'completed') {
        console.log(JSON.stringify({ reused: true, runId: existing, workflowId: args.workflowId, status: existingRun.status }, null, 2));
        return;
      }
    }
  }

  let run;
  if (args.resume) {
    run = readJson(runPath(args.resume));
    if (!run) throw new Error(`Run not found: ${args.resume}`);
  } else {
    const runId = crypto.randomUUID();
    run = {
      runId,
      workflowId: args.workflowId,
      idempotencyKey: idKey,
      input,
      status: 'running',
      createdAt: nowIso(),
      updatedAt: nowIso(),
      context: {},
      stages: STAGES.map(stageRecord)
    };
    saveRun(run);
  }

  try {
    for (const stage of STAGES) {
      runStage(run, wf, stage);
    }
    run.status = 'completed';
    saveRun(run);
    const latest = loadIndex();
    latest.idempotency = latest.idempotency || {};
    latest.idempotency[run.idempotencyKey] = run.runId;
    saveIndex(latest);
    console.log(JSON.stringify({ runId: run.runId, workflowId: run.workflowId, status: run.status, output: run.context.delivery }, null, 2));
  } catch (err) {
    run.status = 'failed';
    saveRun(run);
    console.error(JSON.stringify({ runId: run.runId, workflowId: run.workflowId, status: run.status, error: err instanceof Error ? err.message : String(err) }, null, 2));
    process.exit(1);
  }
}

const args = parseArgs(process.argv);
if (args.cmd !== 'run' || !args.workflowId) {
  usage();
  process.exit(1);
}

runWorkflow(args);
