SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE quote_proposal_types
    ADD CONSTRAINT uq_quote_proposal_types_id_quote UNIQUE (id, quote_id);

CREATE TABLE quote_client_type_selections (
    quote_id uuid PRIMARY KEY REFERENCES quotes(id) ON DELETE CASCADE,
    proposal_type_id uuid NOT NULL,
    selected_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_quote_client_type_selection_same_quote
        FOREIGN KEY (proposal_type_id, quote_id)
        REFERENCES quote_proposal_types(id, quote_id)
        ON DELETE CASCADE
);

ALTER TABLE quotes
    ADD COLUMN client_selection_submitted_at timestamptz NULL;

CREATE INDEX ix_quote_client_type_selections_type
    ON quote_client_type_selections (proposal_type_id);
