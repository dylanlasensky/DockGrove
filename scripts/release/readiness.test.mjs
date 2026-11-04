import test from 'node:test';
import assert from 'node:assert/strict';
import { audit } from './readiness.mjs';
test('missing source and configuration fail closed',()=>{
 const report=audit({}); assert.equal(report.ready,false); assert.ok(report.code.length); assert.equal(report.configuration.length,2);
});
test('test-only implementations are distinguished from owner configuration',()=>{
 const report=audit({backend:"env.SALES_MODE==='test' && env.STRIPE_SECRET_KEY; cs_test_; s.livemode!==false; environment:'test'",native:'static let environment = "test"',checkout:'product.mode === "test"',home:'product.mode === "test"'}, {environment:'production',origin:'https://licenses.example.com'});
 assert.equal(report.code.length,7); assert.deepEqual(report.configuration,[]); assert.equal(report.ready,false);
});
test('deleting hard-coded strings cannot manufacture launch approval',()=>{
 const report=audit({backend:'',native:'',checkout:'',home:''},{environment:'production',origin:'https://licenses.example.com'});
 assert.deepEqual(report.code,[]); assert.equal(report.ready,false); assert.equal(report.verification.length,5);
});
test('rejects credential-bearing, placeholder and non-origin URLs',()=>{
 for(const origin of ['http://example.com','https://user:secret@example.com','https://example.invalid','https://example.com/api','https://example.com?key=secret']) {
  assert.ok(audit({}, {environment:'production',origin}).configuration.length);
 }
});
