'use strict';
// Guard tests must fail before loading pg or contacting any database.
const assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const base={...process.env,TROVAT1O_ISOLATED_PG_TEST:'true',TROVAT1O_PG_CONTAINER_ID:'a'.repeat(64)};
const cases=[
 ['explicit opt-in',{TROVAT1O_ISOLATED_PG_TEST:'false'},'Explicit isolated PostgreSQL test opt-in required'],
 ['remote host',{TROVAT1O_PG_TEST_URL:'postgresql://postgres:fixture-not-a-secret@example.invalid/trovat1o_ci_control'},'Only a fresh loopback CI control database is accepted'],
 ['wrong local database',{TROVAT1O_PG_TEST_URL:'postgresql://postgres:fixture-not-a-secret@127.0.0.1/postgres'},'Only a fresh loopback CI control database is accepted'],
 ['query-string host override',{TROVAT1O_PG_TEST_URL:'postgresql://postgres:fixture-not-a-secret@127.0.0.1/trovat1o_ci_control?host=example.invalid'},'Only a fresh loopback CI control database is accepted'],
 ['unsupported protocol',{TROVAT1O_PG_TEST_URL:'https://127.0.0.1/trovat1o_ci_control'},'Only a fresh loopback CI control database is accepted'],
 ['missing isolated container',{TROVAT1O_PG_TEST_URL:'postgresql://postgres:fixture-not-a-secret@127.0.0.1/trovat1o_ci_control',TROVAT1O_PG_CONTAINER_ID:''},'The isolated CI container ID is required']
];
for(const[name,env,expected]of cases){const result=spawnSync(process.execPath,['tests/integration/native-postgres.cjs'],{env:{...base,...env},encoding:'utf8',timeout:5000});assert.equal(result.status,1,name);assert.ok(result.stderr.includes(expected),name+': '+result.stderr);assert.ok(!result.stderr.includes('fixture-not-a-secret'),name+' disclosed a connection credential');console.log('PASS guard: '+name)}
console.log('PASS: '+cases.length+' isolated database configuration guards; no database contacted.');
