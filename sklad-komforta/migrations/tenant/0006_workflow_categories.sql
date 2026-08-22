SET search_path TO __TENANT_SCHEMA__, public;

CREATE TABLE workflow_categories (
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES catalog_categories(id) ON DELETE CASCADE,
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (workflow_id, category_id),
    UNIQUE (workflow_id, sort_order)
);

CREATE TABLE workflow_category_fields (
    workflow_id uuid NOT NULL,
    category_id uuid NOT NULL,
    field_code varchar(80) NOT NULL,
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (workflow_id, category_id, field_code),
    UNIQUE (workflow_id, category_id, sort_order),
    FOREIGN KEY (workflow_id, category_id)
        REFERENCES workflow_categories(workflow_id, category_id)
        ON DELETE CASCADE
);
