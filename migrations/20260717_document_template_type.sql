ALTER TABLE `documents_templates`
  ADD COLUMN `document_type` varchar(20) NOT NULL DEFAULT 'kp' AFTER `source_quote_id`,
  ADD KEY `idx_documents_templates_type_updated` (`document_type`,`updated_at`,`id`);

ALTER TABLE `documents_template_versions`
  ADD COLUMN `document_type` varchar(20) NOT NULL DEFAULT 'kp' AFTER `source_quote_id`,
  ADD KEY `idx_documents_template_versions_type` (`template_id`,`document_type`,`version_no`);

UPDATE `documents_templates`
   SET `document_type` = CASE
     WHEN JSON_VALID(`payload_json`) THEN COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(`payload_json`, '$.document_type')), ''), 'kp')
     ELSE 'kp'
   END;

UPDATE `documents_template_versions`
   SET `document_type` = CASE
     WHEN JSON_VALID(`payload_json`) THEN COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(`payload_json`, '$.document_type')), ''), 'kp')
     ELSE 'kp'
   END;
