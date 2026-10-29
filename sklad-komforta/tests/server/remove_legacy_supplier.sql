-- Run with the migration expanded at the marker below, against an isolated
-- transaction. No application tables are modified; all fixtures roll back.
BEGIN;
CREATE SCHEMA supplier_removal_regression;
SET search_path TO supplier_removal_regression, public;
CREATE TABLE onboarding_draft (singleton boolean PRIMARY KEY, payload jsonb);
CREATE TABLE workflow_categories (supplier_filter_field_code text);
CREATE TABLE workflow_category_fields (field_code text);
CREATE TABLE catalog_category_dependencies (target_field_code text);
CREATE TABLE catalog_category_fields (field_code text);
CREATE TABLE entity_field_definitions (field_code text);
CREATE TABLE catalog_items (values jsonb);
CREATE TABLE kanban_cards (values jsonb);
CREATE TABLE quote_positions (values jsonb);
CREATE TABLE order_positions (values jsonb);

INSERT INTO onboarding_draft VALUES (true, '{
 "company":{"organizationName":"supplier"},
 "categories":[{"clientId":"one","fields":[{"fieldCode":"name"},{"fieldCode":"supplier"},{"fieldCode":"custom_vendor"}]}],
 "fields":[{"fieldCode":"supplier"},{"fieldCode":"name"}],
 "workflows":[{"categories":[{"fieldCodes":["name","supplier","custom_vendor"],"supplierFilterFieldCode":"supplier"},{"fieldCodes":["custom_vendor"],"supplierFilterFieldCode":"custom_vendor"}]}],
 "dependencies":[{"clientId":"old","targetFieldCode":"supplier"},{"clientId":"keep","targetFieldCode":"custom_relation"}],
 "rules":[
  {"clientId":"remove-condition","conditions":[{"fieldCode":"supplier"}],"actions":[{"targetFieldCode":"custom_vendor"}]},
  {"clientId":"remove-dependency","actions":[{"dependencyClientId":"old"}]},
  {"clientId":"remove-formula","actions":[{"formula":{"tokens":[{"fieldCode":"supplier"}]}}]},
  {"clientId":"keep","conditions":[{"fieldCode":"custom_vendor","comparisonValue":"supplier"}]}],
 "moneyPipelines":[{"basePriceFieldCode":"supplier"},{"basePriceFieldCode":"base_price","resultFieldCode":"custom_total"}],
 "dictionaries":[{"code":"suppliers","items":[{"value":"supplier"}]}]
}');
INSERT INTO workflow_categories VALUES ('supplier'), ('custom_vendor');
INSERT INTO workflow_category_fields VALUES ('supplier'), ('name'), ('custom_vendor');
INSERT INTO catalog_category_dependencies VALUES ('supplier'), ('custom_relation');
INSERT INTO catalog_category_fields VALUES ('supplier'), ('name'), ('custom_vendor');
INSERT INTO entity_field_definitions VALUES ('supplier'), ('name');
INSERT INTO catalog_items VALUES ('{"supplier":"old","custom_vendor":"keep","note":"supplier"}');
INSERT INTO kanban_cards SELECT * FROM catalog_items;
INSERT INTO quote_positions SELECT * FROM catalog_items;
INSERT INTO order_positions SELECT * FROM catalog_items;

-- APPLY_MIGRATION_TWICE

DO $test$
DECLARE p jsonb; table_name text; remaining boolean;
BEGIN
    SELECT payload INTO p FROM onboarding_draft;
    IF p #> '{categories,0,fields}' <> '[{"fieldCode":"name"},{"fieldCode":"custom_vendor"}]'::jsonb
        THEN RAISE EXCEPTION 'category fields'; END IF;
    IF p #> '{workflows,0,categories,0,fieldCodes}' <> '["name","custom_vendor"]'::jsonb
        OR p #> '{workflows,0,categories,0}' ? 'supplierFilterFieldCode'
        OR p #>> '{workflows,0,categories,1,supplierFilterFieldCode}' <> 'custom_vendor'
        THEN RAISE EXCEPTION 'workflow fields/filter'; END IF;
    IF jsonb_array_length(p -> 'rules') <> 1 OR p #>> '{rules,0,clientId}' <> 'keep'
        OR jsonb_array_length(p -> 'dependencies') <> 1
        OR jsonb_array_length(p -> 'moneyPipelines') <> 1
        THEN RAISE EXCEPTION 'rules and dependencies'; END IF;
    IF p #>> '{company,organizationName}' <> 'supplier'
        OR p #>> '{dictionaries,0,items,0,value}' <> 'supplier'
        THEN RAISE EXCEPTION 'unrelated data changed'; END IF;
    FOREACH table_name IN ARRAY ARRAY['catalog_items','kanban_cards','quote_positions','order_positions'] LOOP
        EXECUTE format('SELECT bool_or(values ? ''supplier'' OR values ->> ''custom_vendor'' <> ''keep'' OR values ->> ''note'' <> ''supplier'') FROM %I', table_name)
        INTO remaining;
        IF remaining THEN RAISE EXCEPTION 'values in %', table_name; END IF;
    END LOOP;
    FOREACH table_name IN ARRAY ARRAY['workflow_category_fields','catalog_category_fields','entity_field_definitions'] LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %I WHERE field_code = ''supplier'')', table_name) INTO remaining;
        IF remaining THEN RAISE EXCEPTION 'fields in %', table_name; END IF;
    END LOOP;
    IF EXISTS(SELECT 1 FROM workflow_categories WHERE supplier_filter_field_code = 'supplier')
        OR EXISTS(SELECT 1 FROM catalog_category_dependencies WHERE target_field_code = 'supplier')
        THEN RAISE EXCEPTION 'remaining references'; END IF;
END $test$;
ROLLBACK;
