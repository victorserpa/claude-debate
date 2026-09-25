ALTER TABLE users ADD COLUMN tenant_id bigint NOT NULL REFERENCES tenants(id);
