-- A database is permanently assigned on first configured use. Do not share it between environments.
CREATE TABLE IF NOT EXISTS commerce_environment (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1),
 mode TEXT NOT NULL CHECK(mode IN ('test','production'))
);
