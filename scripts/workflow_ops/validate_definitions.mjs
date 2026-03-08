#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const DEF_DIR = path.join(ROOT, 'workflows', 'definitions');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function exists(p) {
  return fs.existsSync(p);
}

function staticPrefix(filePath) {
  return filePath.replace(/\{\{[^}]+\}\}/g, 'X');
}

function existingStaticParent(filePath) {
  const idx = filePath.indexOf('{{');
  const staticPart = idx === -1 ? filePath : filePath.slice(0, idx);
  const cleaned = staticPart.endsWith('/') ? staticPart.slice(0, -1) : staticPart;
  return cleaned ? path.dirname(cleaned) : null;
}

function validateDefinition(file) {
  const def = readJson(file);
  const issues = [];

  if (!def.id) issues.push('missing id');
  if (!def.execute?.command) issues.push('missing execute.command');
  if (!Array.isArray(def.verify?.requiredFiles)) issues.push('missing verify.requiredFiles');
  if (!def.deliver?.summaryFile) issues.push('missing deliver.summaryFile');

  if (def.execute?.command && !exists(def.execute.command)) {
    issues.push(`execute.command missing on disk: ${def.execute.command}`);
  }

  for (const reqFile of def.verify?.requiredFiles || []) {
    const parent = existingStaticParent(reqFile);
    if (parent && parent.startsWith(`${ROOT}/`) && !exists(parent)) {
      issues.push(`requiredFiles parent missing on disk: ${parent}`);
    }
  }

  if (def.deliver?.summaryFile) {
    const deliverDir = existingStaticParent(def.deliver.summaryFile);
    if (deliverDir && deliverDir.startsWith(`${ROOT}/`) && !exists(deliverDir)) {
      issues.push(`deliver summary parent missing on disk: ${deliverDir}`);
    }
  }

  return {
    file,
    id: def.id || path.basename(file, '.json'),
    ok: issues.length === 0,
    issues
  };
}

const files = fs.readdirSync(DEF_DIR)
  .filter((name) => name.endsWith('.json'))
  .map((name) => path.join(DEF_DIR, name));

const results = files.map(validateDefinition);
const ok = results.every((r) => r.ok);

console.log(JSON.stringify({ ok, count: results.length, results }, null, 2));
process.exit(ok ? 0 : 1);
