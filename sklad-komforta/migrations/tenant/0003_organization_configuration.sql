SET search_path TO __TENANT_SCHEMA__, public;

CREATE TABLE onboarding_draft (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    current_step smallint NOT NULL DEFAULT 1 CHECK (current_step BETWEEN 1 AND 7),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE organization_profile (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    organization_name text NOT NULL,
    company_type varchar(30) NULL,
    legal_name text NULL,
    inn varchar(12) NULL,
    kpp varchar(9) NULL,
    ogrn varchar(15) NULL,
    address text NULL,
    phone text NULL,
    email text NULL,
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workflows (
    id uuid PRIMARY KEY,
    code varchar(80) NOT NULL UNIQUE,
    name text NOT NULL,
    sort_order integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workflow_columns (
    id uuid PRIMARY KEY,
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    name text NOT NULL,
    color varchar(7) NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
    sort_order integer NOT NULL,
    UNIQUE (workflow_id, sort_order)
);

CREATE TABLE workflow_transitions (
    from_column_id uuid NOT NULL REFERENCES workflow_columns(id) ON DELETE CASCADE,
    to_column_id uuid NOT NULL REFERENCES workflow_columns(id) ON DELETE CASCADE,
    PRIMARY KEY (from_column_id, to_column_id),
    CHECK (from_column_id <> to_column_id)
);

CREATE TABLE catalog_categories (
    id uuid PRIMARY KEY,
    name text NOT NULL UNIQUE,
    sort_order integer NOT NULL
);

CREATE TABLE catalog_sections (
    id uuid PRIMARY KEY,
    category_id uuid NOT NULL REFERENCES catalog_categories(id) ON DELETE CASCADE,
    name text NOT NULL,
    sort_order integer NOT NULL,
    UNIQUE (category_id, name)
);

CREATE TABLE catalog_groups (
    id uuid PRIMARY KEY,
    section_id uuid NOT NULL REFERENCES catalog_sections(id) ON DELETE CASCADE,
    name text NOT NULL,
    sort_order integer NOT NULL,
    UNIQUE (section_id, name)
);

CREATE TABLE entity_field_definitions (
    id uuid PRIMARY KEY,
    context_code varchar(40) NOT NULL,
    field_code varchar(80) NOT NULL,
    label text NOT NULL,
    field_type varchar(30) NOT NULL,
    is_visible boolean NOT NULL,
    is_required boolean NOT NULL,
    sort_order integer NOT NULL,
    UNIQUE (context_code, field_code)
);

CREATE TABLE dictionary_types (
    id uuid PRIMARY KEY,
    code varchar(80) NOT NULL UNIQUE,
    name text NOT NULL,
    sort_order integer NOT NULL
);

CREATE TABLE dictionary_items (
    id uuid PRIMARY KEY,
    dictionary_type_id uuid NOT NULL REFERENCES dictionary_types(id) ON DELETE CASCADE,
    value text NOT NULL,
    sort_order integer NOT NULL,
    UNIQUE (dictionary_type_id, value)
);

INSERT INTO permissions (code, name, group_name)
VALUES
    ('catalog.view', 'Просмотр каталога', 'Каталог'),
    ('catalog.manage', 'Управление каталогом', 'Каталог'),
    ('company.view', 'Просмотр данных компании', 'Компания'),
    ('company.manage', 'Управление данными компании', 'Компания'),
    ('quotes.view', 'Просмотр КП и ПКП', 'Коммерческие предложения'),
    ('quotes.manage', 'Управление КП и ПКП', 'Коммерческие предложения'),
    ('orders.view', 'Просмотр комплектаций', 'Комплектация'),
    ('orders.manage', 'Управление комплектациями', 'Комплектация'),
    ('documents.view', 'Просмотр документов', 'Документы'),
    ('documents.manage', 'Управление документами', 'Документы')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;
