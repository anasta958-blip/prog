SET search_path TO __TENANT_SCHEMA__, public;

-- Existing roles keep the visibility they had before this setting existed.
ALTER TABLE roles
    ADD COLUMN card_visibility_mode varchar(20) NOT NULL DEFAULT 'all';

ALTER TABLE roles
    ALTER COLUMN card_visibility_mode SET DEFAULT 'own';

ALTER TABLE roles
    ADD CONSTRAINT ck_roles_card_visibility_mode
    CHECK (card_visibility_mode IN ('own', 'all', 'subordinates', 'specific'));

CREATE TABLE role_card_visibility_members (
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    membership_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, membership_id)
);

CREATE INDEX ix_role_card_visibility_members_membership
    ON role_card_visibility_members (membership_id);
