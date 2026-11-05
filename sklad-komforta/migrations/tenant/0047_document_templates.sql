CREATE TABLE document_templates (
    workflow_id uuid PRIMARY KEY REFERENCES workflows(id) ON DELETE CASCADE,
    template jsonb NOT NULL CHECK (jsonb_typeof(template) = 'object'),
    updated_at timestamptz NOT NULL DEFAULT now()
);
