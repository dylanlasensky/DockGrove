// Missing/unknown modes never select production. Existing explicit test deployments remain valid.
export function commerceEnvironment(env) {
 if (env.SALES_MODE === 'test') return {name:'test',live:false,keyPrefixes:['sk_test_','rk_test_'],sessionPrefix:'cs_test_'};
 if (env.SALES_MODE === 'production') return {name:'production',live:true,keyPrefixes:['sk_live_','rk_live_'],sessionPrefix:'cs_live_'};
 throw new Error('Unconfigured commerce environment');
}
export function productionApproved(env) {
 if (env.SALES_MODE !== 'production') return env.SALES_MODE === 'test';
 // These are owner-reviewed evidence references, not credentials. Never populate from fixture tests.
 try {
  const proof=JSON.parse(env.PRODUCTION_READINESS);
  return env.PRODUCTION_SALES_ENABLED === 'true' && proof.environment === 'production'
   && proof.origin === env.PUBLIC_ORIGIN && proof.releaseObject === env.RELEASE_OBJECT
   && proof.keyId === env.ENTITLEMENT_KEY_ID && proof.priceId === env.STRIPE_PRICE_ID
   && ['providerSandbox','nativeActivation','recoveryDelivery','deviceLimitAndRevocation','signedNotarizedArtifact','ownerApproval'].every(k=>typeof proof[k]==='string' && proof[k].trim().length>=8)
   && /^[a-f0-9]{64}$/.test(proof.releaseSHA256 || '');
 } catch { return false; }
}
export function matchesEnvironment(object, env) {
 return object?.livemode === commerceEnvironment(env).live;
}
export function validSessionID(id, env) {
 const prefix=commerceEnvironment(env).sessionPrefix;
 return typeof id === 'string' && id.startsWith(prefix) && /^[A-Za-z0-9_]+$/.test(id) && id.length>prefix.length;
}
