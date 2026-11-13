'use strict';
// Optional local SQL/RLS execution using real PostgreSQL in WASM, never a URL.
// Install the exact engine outside app/release dependencies:
// mkdir -p tmp/local-postgres
// cp tests/fixtures/local-postgres/package{,-lock}.json tmp/local-postgres/
// npm ci --prefix tmp/local-postgres --ignore-scripts --no-audit --no-fund
// node tests/local-postgres.cjs --require-engine
// Missing engine is an explicit SKIP for the generic source-test loop; the
// --require-engine gate fails instead. --sql tests/sql/foo.sql selects one test.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const requireEngine = args.includes('--require-engine');
const jsonOutput = args.includes('--json');
const dependencyRoot = path.join(root, 'tmp/local-postgres');
let PGlite, pgcrypto, engineVersion;
try {
  const localRequire = createRequire(path.join(dependencyRoot, 'package.json'));
  ({ PGlite } = localRequire('@electric-sql/pglite'));
  ({ pgcrypto } = localRequire('@electric-sql/pglite/contrib/pgcrypto'));
  engineVersion = JSON.parse(fs.readFileSync(path.join(dependencyRoot, 'node_modules/@electric-sql/pglite/package.json'), 'utf8')).version;
} catch {
  const text = 'Local SQL engine unavailable: install @electric-sql/pglite@0.5.16 into tmp/local-postgres; no remote database was contacted.';
  console.log(`${requireEngine ? 'FAIL' : 'SKIP'}: ${text}`);
  process.exit(requireEngine ? 1 : 0);
}
assert.equal(engineVersion, '0.5.16', 'Use the audited exact PGlite engine version');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const digest = content => crypto.createHash('sha256').update(content).digest('hex');
const migrations = ['schema.sql', 'notifications.sql', 'admin-security.sql', 'oauth-profiles.sql', 'free-access.sql', 'billing.sql', 'host-contact.sql', 'retention.sql', 'admin-operations.sql', 'account-export.sql', 'write-quotas.sql', 'push-dispatch.sql', 'account-lifecycle.sql', 'session-security.sql', 'account-erasure-requests.sql', 'support-submit.sql']
  .map(file => `supabase/${file}`);
const required = new Set(migrations);
const selected = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--sql') {
    const file = args[++i];
    if (!file || !/^tests\/sql\/[a-z0-9-]+\.sql$/.test(file) || file.endsWith('/local-fixture.sql')) throw new Error('Select a repository SQL regression under tests/sql');
    selected.push(file);
  }
}
const tests = selected.length ? selected : fs.readdirSync(path.join(root, 'tests/sql')).filter(file => file.endsWith('.sql') && file !== 'local-fixture.sql').sort().map(file => `tests/sql/${file}`);
const result = {
  capturedAt: new Date().toISOString(), engine: { pglite: engineVersion, postgres: null, cryptoStub: false },
  limits: ['PostgreSQL WASM differs from hosted Supabase PostgreSQL and its managed extensions.', 'Auth/JWT/MFA are synthetic schema/settings fixtures, not real provider exchanges.', 'Single connection cannot prove concurrent client races, HTTP gateways, pg_cron scheduling, backups or deployment.'],
  migrations: [], tests: [], omittedOptionalMigrations: []
};
const log = text => { if (!jsonOutput) console.log(text); };
async function tableCounts(db) {
  const { rows } = await db.query("select table_schema,table_name from information_schema.tables where table_schema in ('auth','public','private') and table_type='BASE TABLE' order by 1,2");
  const counts = {};
  for (const row of rows) {
    const name = `${row.table_schema}.${row.table_name}`;
    const quote = value => '"' + value.replaceAll('"', '""') + '"';
    counts[name] = (await db.query(`select count(*)::integer as n from ${quote(row.table_schema)}.${quote(row.table_name)}`)).rows[0].n;
  }
  return counts;
}
(async () => {
  const db = new PGlite({ extensions: { pgcrypto } }); // in-memory, no connection URL accepted
  try {
    await db.waitReady;
    result.engine.postgres = (await db.query('select version() as version')).rows[0].version;
    await db.exec(read('tests/sql/local-fixture.sql'));
    const actualDigest = (await db.query("select encode(extensions.digest(convert_to('probe','UTF8'),'sha256'),'hex') as hash")).rows[0].hash;
    assert.equal(actualDigest, crypto.createHash('sha256').update('probe').digest('hex'), 'Real pgcrypto SHA-256 must match Node');
    for (const file of migrations) {
      if (!fs.existsSync(path.join(root, file))) {
        if (required.has(file)) throw new Error(`Missing required SQL source: ${file}`);
        result.omittedOptionalMigrations.push(file);
        log(`SKIP: optional migration not yet present ${file}`);
        continue;
      }
      const started = Date.now();
      const sql = read(file);
      await db.exec(sql);
      result.migrations.push({ file, sha256: digest(sql), elapsedMs: Date.now() - started, status: 'passed' });
      log(`PASS: local PostgreSQL applied ${file}`);
    }
    const baseline = await tableCounts(db);
    for (const file of tests) {
      const started = Date.now();
      const sql = read(file);
      try {
        await db.exec(sql);
        assert.deepEqual(await tableCounts(db), baseline, `Regression must rollback all fixture rows: ${file}`);
      } catch (error) {
        try { await db.exec('rollback; reset role;'); } catch {}
        error.message = `${file}: ${error.message}`;
        throw error;
      }
      result.tests.push({ file, sha256: digest(sql), status: 'passed', elapsedMs: Date.now() - started, rollbackCountsVerified: true });
      log(`PASS: local PostgreSQL regression ${file}; fixture rows rolled back`);
    }
    result.baselineCounts = baseline;
    result.status = 'passed';
    if (jsonOutput) console.log(JSON.stringify(result, null, 2));
    else log(`PASS: ${result.migrations.length} local SQL sources and ${result.tests.length} rollback regressions on PGlite ${engineVersion}; not a Supabase integration test.`);
  } finally { await db.close(); }
})().catch(error => {
  result.status = 'failed';
  result.error = { message: error.message, code: error.code, context: error.where, position: error.position };
  console.error(jsonOutput ? JSON.stringify(result, null, 2) : JSON.stringify(result.error, null, 2));
  process.exitCode = 1;
});
