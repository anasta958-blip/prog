SET search_path TO __TENANT_SCHEMA__, public;

WITH normalized_categories AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_set(
                category.value,
                '{fields}',
                COALESCE((
                    SELECT jsonb_agg(field.value ORDER BY field.ordinality)
                    FROM jsonb_array_elements(COALESCE(category.value -> 'fields', '[]'::jsonb))
                        WITH ORDINALITY AS field(value, ordinality)
                    WHERE field.value ->> 'fieldCode' NOT IN
                        ('retail_price', 'markup_value', 'discount_value')
                ), '[]'::jsonb),
                true
            )
            ORDER BY category.ordinality
        ),
        '[]'::jsonb
    ) AS value
    FROM onboarding_draft AS draft
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(draft.payload -> 'categories', '[]'::jsonb))
        WITH ORDINALITY AS category(value, ordinality)
    WHERE draft.singleton
), normalized_workflows AS (
    SELECT COALESCE(
        jsonb_agg(
            jsonb_set(
                workflow.value,
                '{categories}',
                COALESCE((
                    SELECT jsonb_agg(
                        jsonb_set(
                            workflow_category.value,
                            '{fieldCodes}',
                            COALESCE((
                                SELECT jsonb_agg(field_code.value ORDER BY field_code.ordinality)
                                FROM jsonb_array_elements(
                                    COALESCE(workflow_category.value -> 'fieldCodes', '[]'::jsonb)
                                ) WITH ORDINALITY AS field_code(value, ordinality)
                                WHERE field_code.value #>> '{}' NOT IN
                                    ('retail_price', 'markup_value', 'discount_value')
                            ), '[]'::jsonb),
                            true
                        )
                        ORDER BY workflow_category.ordinality
                    )
                    FROM jsonb_array_elements(COALESCE(workflow.value -> 'categories', '[]'::jsonb))
                        WITH ORDINALITY AS workflow_category(value, ordinality)
                ), '[]'::jsonb),
                true
            )
            ORDER BY workflow.ordinality
        ),
        '[]'::jsonb
    ) AS value
    FROM onboarding_draft AS draft
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(draft.payload -> 'workflows', '[]'::jsonb))
        WITH ORDINALITY AS workflow(value, ordinality)
    WHERE draft.singleton
), normalized_fields AS (
    SELECT COALESCE(
        jsonb_agg(field.value ORDER BY field.ordinality),
        '[]'::jsonb
    ) AS value
    FROM onboarding_draft AS draft
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(draft.payload -> 'fields', '[]'::jsonb))
        WITH ORDINALITY AS field(value, ordinality)
    WHERE draft.singleton
      AND field.value ->> 'fieldCode' NOT IN
          ('retail_price', 'markup_value', 'discount_value')
)
UPDATE onboarding_draft
SET payload = jsonb_set(
    jsonb_set(
        jsonb_set(payload, '{categories}', normalized_categories.value, true),
        '{workflows}', normalized_workflows.value, true
    ),
    '{fields}', normalized_fields.value, true
)
FROM normalized_categories, normalized_workflows, normalized_fields
WHERE singleton;
