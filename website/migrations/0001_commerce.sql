PRAGMA foreign_keys = ON;
CREATE TABLE purchases (
 id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, session_id TEXT UNIQUE,
 payment_intent TEXT, email TEXT, status TEXT NOT NULL DEFAULT 'pending',
 price_id TEXT NOT NULL, product_id TEXT NOT NULL, amount INTEGER NOT NULL, currency TEXT NOT NULL, major_version INTEGER NOT NULL, device_limit INTEGER NOT NULL,
 created_at INTEGER NOT NULL
);
CREATE TABLE licenses (
 id TEXT PRIMARY KEY, purchase_id TEXT NOT NULL UNIQUE REFERENCES purchases(id), key_hash TEXT NOT NULL UNIQUE,
 status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL
);
CREATE TABLE activations (
 license_id TEXT NOT NULL REFERENCES licenses(id), device_hash TEXT NOT NULL,
 active INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL,
 PRIMARY KEY (license_id, device_hash)
);
CREATE TABLE stripe_events (id TEXT PRIMARY KEY, type TEXT NOT NULL, processed_at INTEGER NOT NULL);
-- A refund/dispute can arrive before the payment event. These markers are monotonic.
CREATE TABLE payment_blocks (payment_intent TEXT PRIMARY KEY, reason TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE recovery_tokens (token_hash TEXT PRIMARY KEY, email TEXT NOT NULL, expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0);
CREATE TABLE request_limits (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);
CREATE INDEX purchase_email ON purchases(email);
CREATE INDEX purchase_payment_intent ON purchases(payment_intent);
CREATE INDEX recovery_expiration ON recovery_tokens(expires_at);
-- Encrypted delivery payloads retain retryability without storing recovery tokens in plaintext.
CREATE TABLE email_outbox (id TEXT PRIMARY KEY, ciphertext TEXT NOT NULL, iv TEXT NOT NULL, expires_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, sent INTEGER NOT NULL DEFAULT 0);
