SET search_path TO __TENANT_SCHEMA__, public;

-- Восьмой шаг onboarding добавляет настройку межкатегорийных связей.
ALTER TABLE onboarding_draft
    DROP CONSTRAINT onboarding_draft_current_step_check;

ALTER TABLE onboarding_draft
    ADD CONSTRAINT onboarding_draft_current_step_check
    CHECK (current_step BETWEEN 1 AND 8);

CREATE TABLE catalog_category_dependencies (
    id uuid PRIMARY KEY,
    source_category_id uuid NOT NULL REFERENCES catalog_categories(id) ON DELETE CASCADE,
    target_category_id uuid NOT NULL,
    target_field_code varchar(80) NOT NULL,
    sort_order integer NOT NULL,
    CHECK (source_category_id <> target_category_id),
    FOREIGN KEY (target_category_id, target_field_code)
        REFERENCES catalog_category_fields(category_id, field_code)
        ON DELETE CASCADE,
    UNIQUE (source_category_id, target_category_id, target_field_code),
    UNIQUE (sort_order)
);
