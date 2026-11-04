CREATE TABLE document_layouts (
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES catalog_categories(id) ON DELETE CASCADE,
    field_codes jsonb NOT NULL CHECK (jsonb_typeof(field_codes) = 'array'),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (workflow_id, category_id)
);
