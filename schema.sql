

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

;
;
;
;

CREATE TABLE `catalog_groups` (
  `id` int(11) NOT NULL,
  `section_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `sort_order` int(11) DEFAULT 0,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `catalog_services` (
  `id` int(11) NOT NULL,
  `name` varchar(300) NOT NULL,
  `cost` decimal(10,2) NOT NULL DEFAULT 0.00,
  `marking_size` varchar(255) DEFAULT NULL,
  `purchase_price` decimal(10,2) DEFAULT NULL,
  `minimal_price` decimal(10,2) DEFAULT NULL,
  `retail_price` decimal(10,2) DEFAULT NULL,
  `linked_product_name_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `unit` varchar(50) DEFAULT NULL,
  `work_section_code` varchar(50) DEFAULT 'installation',
  `sort_order` int(11) DEFAULT 0,
  `category_scope_code` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `categories` (
  `id` int(11) NOT NULL,
  `code` varchar(50) NOT NULL,
  `name` varchar(200) NOT NULL,
  `sort_order` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `company_director` (
  `singleton_id` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `user_id` int(11) NOT NULL,
  `updated_by` int(11) DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `company_profiles` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `company_type` varchar(20) DEFAULT 'ooo',
  `company_name` varchar(255) DEFAULT NULL,
  `legal_name` varchar(255) DEFAULT NULL,
  `inn` varchar(20) DEFAULT NULL,
  `ogrn` varchar(20) DEFAULT NULL,
  `kpp` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `phone` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `website` varchar(255) DEFAULT NULL,
  `director_name` varchar(255) DEFAULT NULL,
  `signatory_name` varchar(255) DEFAULT NULL,
  `signatory_title` varchar(255) DEFAULT NULL,
  `bank_name` varchar(255) DEFAULT NULL,
  `bank_bik` varchar(20) DEFAULT NULL,
  `bank_account` varchar(50) DEFAULT NULL,
  `corr_account` varchar(50) DEFAULT NULL,
  `intro_default` text DEFAULT NULL,
  `footer_default` text DEFAULT NULL,
  `autofill_fields_json` longtext DEFAULT NULL,
  `is_default` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `documents_templates` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `source_quote_id` int(11) DEFAULT NULL,
  `document_type` varchar(20) NOT NULL DEFAULT 'kp',
  `title` varchar(255) NOT NULL,
  `page_format` varchar(40) DEFAULT 'a4',
  `theme_name` varchar(40) DEFAULT 'clean',
  `payload_json` longtext DEFAULT NULL,
  `current_version_id` int(11) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `documents_template_versions` (
  `id` int(11) NOT NULL,
  `template_id` int(11) NOT NULL,
  `version_no` int(11) NOT NULL,
  `version_name` varchar(255) NOT NULL,
  `source_quote_id` int(11) DEFAULT NULL,
  `document_type` varchar(20) NOT NULL DEFAULT 'kp',
  `page_format` varchar(40) DEFAULT 'a4',
  `theme_name` varchar(40) DEFAULT 'clean',
  `payload_json` longtext DEFAULT NULL,
  `created_by` int(11) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `kp_clients` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `company_type` varchar(20) DEFAULT 'ooo',
  `company_name` varchar(255) NOT NULL,
  `legal_name` varchar(255) DEFAULT NULL,
  `inn` varchar(20) DEFAULT NULL,
  `ogrn` varchar(20) DEFAULT NULL,
  `kpp` varchar(20) DEFAULT NULL,
  `object_type` varchar(100) DEFAULT NULL,
  `object_address` text DEFAULT NULL,
  `recipient_name` varchar(255) DEFAULT NULL,
  `salutation` varchar(255) DEFAULT NULL,
  `proposal_title` varchar(255) DEFAULT NULL,
  `intro_text` text DEFAULT NULL,
  `phone` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `bank_name` varchar(255) DEFAULT NULL,
  `bank_bik` varchar(20) DEFAULT NULL,
  `note` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `kp_contractors` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `company_type` varchar(20) DEFAULT 'ooo',
  `company_name` varchar(255) NOT NULL,
  `legal_name` varchar(255) DEFAULT NULL,
  `inn` varchar(20) DEFAULT NULL,
  `ogrn` varchar(20) DEFAULT NULL,
  `kpp` varchar(20) DEFAULT NULL,
  `object_type` varchar(100) DEFAULT NULL,
  `object_address` text DEFAULT NULL,
  `recipient_name` varchar(255) DEFAULT NULL,
  `salutation` varchar(255) DEFAULT NULL,
  `proposal_title` varchar(255) DEFAULT NULL,
  `intro_text` text DEFAULT NULL,
  `phone` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `bank_name` varchar(255) DEFAULT NULL,
  `bank_bik` varchar(20) DEFAULT NULL,
  `note` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `kp_quotes` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `client_id` int(11) DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  `status` enum('created','sent','viewed','chosen','rejected','completed') NOT NULL DEFAULT 'created',
  `selected_variant_label` varchar(255) DEFAULT NULL,
  `company_snapshot_json` longtext DEFAULT NULL,
  `client_snapshot_json` longtext DEFAULT NULL,
  `payload_json` longtext DEFAULT NULL,
  `created_order_id` int(11) DEFAULT NULL,
  `public_token` varchar(64) NOT NULL,
  `sent_at` datetime DEFAULT NULL,
  `viewed_at` datetime DEFAULT NULL,
  `chosen_at` datetime DEFAULT NULL,
  `rejected_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `last_opened_at` datetime DEFAULT NULL,
  `public_open_count` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `workflow_status` varchar(100) NOT NULL DEFAULT 'Составить КП',
  `is_archived` tinyint(1) NOT NULL DEFAULT 0,
  `archived_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `measurement_units` (
  `id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `sort_order` int(11) DEFAULT 0,
  `is_default` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `orders` (
  `id` int(11) NOT NULL,
  `order_number` varchar(50) NOT NULL,
  `address` text DEFAULT NULL,
  `manager_id` int(11) NOT NULL,
  `status` enum('draft','active','closed') DEFAULT 'active',
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `status_order` enum('Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Вторые этапы','Выполнено') DEFAULT 'Составление комплектации',
  `doc_snapshot` mediumtext DEFAULT NULL COMMENT 'JSON snapshot документа для редактирования',
  `order_type` enum('Квартира','Дом','Ресторан','Кафе','Бассейн','Офис','Производство') DEFAULT NULL,
  `rop_id` int(11) DEFAULT NULL,
  `status_changed_by` int(11) DEFAULT NULL,
  `status_changed_at` datetime DEFAULT NULL,
  `client_type` text DEFAULT NULL,
  `is_archived` tinyint(1) NOT NULL DEFAULT 0,
  `archived_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `order_invoices` (
  `id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `file_path` varchar(500) NOT NULL,
  `original_name` varchar(255) NOT NULL,
  `uploaded_by` int(11) DEFAULT NULL,
  `uploaded_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `pkp_quotes` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `client_id` int(11) DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  `status` varchar(50) DEFAULT 'created',
  `workflow_status` varchar(100) DEFAULT NULL,
  `selected_variant_label` varchar(255) DEFAULT NULL,
  `company_snapshot_json` longtext DEFAULT NULL,
  `client_snapshot_json` longtext DEFAULT NULL,
  `payload_json` longtext DEFAULT NULL,
  `public_token` varchar(64) DEFAULT NULL,
  `public_open_count` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `sent_at` datetime DEFAULT NULL,
  `viewed_at` datetime DEFAULT NULL,
  `chosen_at` datetime DEFAULT NULL,
  `rejected_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `is_archived` tinyint(1) NOT NULL DEFAULT 0,
  `archived_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `quote_payload_variants` (
  `id` int(11) NOT NULL,
  `quote_type` varchar(10) NOT NULL,
  `quote_id` int(11) NOT NULL,
  `proposal_type_index` int(11) NOT NULL DEFAULT 0,
  `proposal_type_id` varchar(80) DEFAULT NULL,
  `proposal_type_label` varchar(255) DEFAULT NULL,
  `variant_index` int(11) NOT NULL DEFAULT 0,
  `variant_id` varchar(80) DEFAULT NULL,
  `variant_label` varchar(255) DEFAULT NULL,
  `selected_variant` tinyint(1) NOT NULL DEFAULT 0,
  `vat_mode` varchar(20) DEFAULT 'none',
  `items_count` int(11) NOT NULL DEFAULT 0,
  `total_sum` decimal(14,2) NOT NULL DEFAULT 0.00,
  `purchase_sum` decimal(14,2) NOT NULL DEFAULT 0.00,
  `margin_sum` decimal(14,2) NOT NULL DEFAULT 0.00,
  `margin_percent` decimal(10,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `quote_payload_items` (
  `id` int(11) NOT NULL,
  `quote_type` varchar(10) NOT NULL,
  `quote_id` int(11) NOT NULL,
  `proposal_type_index` int(11) NOT NULL DEFAULT 0,
  `proposal_type_id` varchar(80) DEFAULT NULL,
  `variant_index` int(11) NOT NULL DEFAULT 0,
  `variant_id` varchar(80) DEFAULT NULL,
  `category_index` int(11) NOT NULL DEFAULT 0,
  `category_code` varchar(80) DEFAULT NULL,
  `category_name` varchar(255) DEFAULT NULL,
  `section_index` int(11) NOT NULL DEFAULT 0,
  `section_id` varchar(80) DEFAULT NULL,
  `section_code` varchar(80) DEFAULT NULL,
  `section_name` varchar(255) DEFAULT NULL,
  `item_index` int(11) NOT NULL DEFAULT 0,
  `uid` varchar(120) DEFAULT NULL,
  `item_type` varchar(40) DEFAULT 'product',
  `product_name_id` int(11) NOT NULL DEFAULT 0,
  `service_id` int(11) NOT NULL DEFAULT 0,
  `name` varchar(500) DEFAULT NULL,
  `marking_size` varchar(500) DEFAULT NULL,
  `group_name` varchar(255) DEFAULT NULL,
  `quantity` decimal(14,4) NOT NULL DEFAULT 0.0000,
  `unit` varchar(80) DEFAULT NULL,
  `supplier` varchar(255) DEFAULT NULL,
  `purchase_price` decimal(14,2) DEFAULT NULL,
  `base_price` decimal(14,2) DEFAULT NULL,
  `final_price` decimal(14,2) DEFAULT NULL,
  `line_sum` decimal(14,2) NOT NULL DEFAULT 0.00,
  `excluded_from_calc` tinyint(1) NOT NULL DEFAULT 0,
  `raw_json` longtext DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `products` (
  `id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL,
  `section_id` int(11) NOT NULL,
  `product_name_id` int(11) DEFAULT NULL,
  `order_id` int(11) DEFAULT NULL,
  `marking` varchar(300) DEFAULT NULL,
  `size_value` varchar(200) DEFAULT NULL,
  `quantity` decimal(10,2) DEFAULT 0.00,
  `dozakaz` tinyint(1) NOT NULL DEFAULT 0,
  `unit` varchar(50) DEFAULT 'шт',
  `note` text DEFAULT NULL,
  `komplektaciya` varchar(500) DEFAULT NULL,
  `supplier` varchar(300) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `status` enum('Не согласовано','Согласовано') DEFAULT 'Не согласовано',
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `custom_name` varchar(300) DEFAULT NULL,
  `group_name` varchar(255) DEFAULT NULL,
  `invoice_check` enum('','Проверено','Ошибка') DEFAULT '',
  `shipment_status` enum('','Купить','На складе','Заказано','На объекте') DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `product_names` (
  `id` int(11) NOT NULL,
  `section_id` int(11) NOT NULL,
  `group_name` varchar(255) DEFAULT NULL,
  `name` varchar(300) NOT NULL,
  `sort_order` int(11) DEFAULT 0,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_custom` tinyint(1) DEFAULT 0,
  `status` enum('Не согласовано','Согласовано') DEFAULT 'Не согласовано',
  `supplier` varchar(300) DEFAULT NULL,
  `marking_size` varchar(300) DEFAULT NULL,
  `komplektaciya` varchar(500) DEFAULT NULL,
  `note` text DEFAULT NULL,
  `unit` varchar(50) DEFAULT NULL,
  `purchase_price` decimal(10,2) DEFAULT NULL,
  `retail_price` decimal(10,2) DEFAULT NULL,
  `price_type` enum('fixed','percent') NOT NULL DEFAULT 'fixed',
  `discount_value` decimal(10,2) DEFAULT NULL,
  `labor_price` decimal(10,2) DEFAULT NULL,
  `minimal_price` decimal(10,2) DEFAULT NULL,
  `linked_service_id` int(11) DEFAULT NULL,
  `technical_note` mediumtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `product_service_links` (
  `product_name_id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL,
  `sort_order` int(11) DEFAULT 0,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `role_access_policies` (
  `role` varchar(50) NOT NULL,
  `config_json` longtext DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `rop_managers` (
  `rop_id` int(11) NOT NULL,
  `manager_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `sections` (
  `id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL,
  `code` varchar(50) NOT NULL,
  `name` varchar(200) NOT NULL,
  `sort_order` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `section_suppliers` (
  `section_id` int(11) NOT NULL,
  `supplier_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `suppliers` (
  `id` int(11) NOT NULL,
  `name` varchar(300) NOT NULL,
  `sort_order` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `role` enum('admin','manager','rop','logist','prorab') NOT NULL DEFAULT 'manager',
  `full_name` varchar(200) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `phone` varchar(50) DEFAULT NULL,
  `telegram` varchar(100) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

ALTER TABLE `catalog_groups`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_catalog_group_section_name` (`section_id`,`name`);

ALTER TABLE `catalog_services`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_catalog_services_product_name` (`linked_product_name_id`),
  ADD KEY `idx_catalog_services_name_marking` (`name`(120),`marking_size`(120)),
  ADD KEY `idx_catalog_services_work_section_order` (`work_section_code`,`sort_order`,`name`(120));

ALTER TABLE `categories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`);

ALTER TABLE `company_director`
  ADD PRIMARY KEY (`singleton_id`),
  ADD UNIQUE KEY `user_id` (`user_id`),
  ADD KEY `fk_company_director_updated_by` (`updated_by`);

ALTER TABLE `company_profiles`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_company_profiles_user_default` (`user_id`,`is_default`);

ALTER TABLE `documents_templates`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_documents_templates_user` (`user_id`),
  ADD KEY `idx_documents_templates_quote` (`source_quote_id`),
  ADD KEY `idx_documents_templates_current_version` (`current_version_id`),
  ADD KEY `idx_documents_templates_type_updated` (`document_type`,`updated_at`,`id`),
  ADD KEY `idx_documents_templates_user_updated` (`user_id`,`updated_at`,`id`),
  ADD KEY `idx_documents_templates_updated` (`updated_at`,`id`);

ALTER TABLE `documents_template_versions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_documents_template_versions_template` (`template_id`),
  ADD KEY `idx_documents_template_versions_type` (`template_id`,`document_type`,`version_no`),
  ADD KEY `idx_documents_template_versions_version` (`template_id`,`version_no`);

ALTER TABLE `kp_clients`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_kp_clients_user` (`user_id`),
  ADD KEY `idx_kp_clients_updated` (`updated_at`,`id`),
  ADD KEY `idx_kp_clients_user_updated` (`user_id`,`updated_at`,`id`);

ALTER TABLE `kp_contractors`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_kp_contractors_user` (`user_id`),
  ADD KEY `idx_kp_contractors_updated` (`updated_at`,`id`),
  ADD KEY `idx_kp_contractors_user_updated` (`user_id`,`updated_at`,`id`);

ALTER TABLE `kp_quotes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_kp_quotes_token` (`public_token`),
  ADD KEY `fk_kp_quotes_user` (`user_id`),
  ADD KEY `fk_kp_quotes_client` (`client_id`),
  ADD KEY `idx_kp_quotes_created_order_id` (`created_order_id`),
  ADD KEY `idx_kp_quotes_user_updated` (`user_id`,`updated_at`,`id`),
  ADD KEY `idx_kp_quotes_workflow_updated` (`workflow_status`,`updated_at`,`id`),
  ADD KEY `idx_kp_quotes_archive_updated` (`is_archived`,`updated_at`,`id`);

ALTER TABLE `measurement_units`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

ALTER TABLE `orders`
  ADD PRIMARY KEY (`id`),
  ADD KEY `manager_id` (`manager_id`),
  ADD KEY `rop_id` (`rop_id`),
  ADD KEY `idx_orders_status_created` (`status_order`,`created_at`,`id`),
  ADD KEY `idx_orders_archive_created` (`is_archived`,`created_at`,`id`),
  ADD KEY `idx_orders_manager_created` (`manager_id`,`created_at`,`id`),
  ADD KEY `idx_orders_rop_created` (`rop_id`,`created_at`,`id`),
  ADD KEY `idx_orders_status_changed_by` (`status_changed_by`);

ALTER TABLE `order_invoices`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_order_invoices_order` (`order_id`,`uploaded_at`),
  ADD KEY `fk_order_invoices_user` (`uploaded_by`);

ALTER TABLE `pkp_quotes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_pkp_quote_token` (`public_token`),
  ADD KEY `idx_pkp_quotes_user` (`user_id`),
  ADD KEY `idx_pkp_quotes_client` (`client_id`),
  ADD KEY `idx_pkp_quotes_user_updated` (`user_id`,`updated_at`,`id`),
  ADD KEY `idx_pkp_quotes_workflow_updated` (`workflow_status`,`updated_at`,`id`),
  ADD KEY `idx_pkp_quotes_archive_updated` (`is_archived`,`updated_at`,`id`);

ALTER TABLE `quote_payload_variants`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_quote_payload_variant` (`quote_type`,`quote_id`,`proposal_type_index`,`variant_index`),
  ADD KEY `idx_quote_payload_variants_quote` (`quote_type`,`quote_id`),
  ADD KEY `idx_quote_payload_variants_selected` (`quote_type`,`quote_id`,`selected_variant`);

ALTER TABLE `quote_payload_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_quote_payload_items_quote` (`quote_type`,`quote_id`),
  ADD KEY `idx_quote_payload_items_variant` (`quote_type`,`quote_id`,`proposal_type_index`,`variant_index`),
  ADD KEY `idx_quote_payload_items_catalog` (`product_name_id`,`service_id`),
  ADD KEY `idx_quote_payload_items_category` (`quote_type`,`quote_id`,`category_code`,`section_id`);

ALTER TABLE `products`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `section_id` (`section_id`),
  ADD KEY `product_name_id` (`product_name_id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_products_order` (`order_id`,`id`),
  ADD KEY `idx_products_order_category_section` (`order_id`,`category_id`,`section_id`),
  ADD KEY `idx_products_order_product_name` (`order_id`,`product_name_id`);

ALTER TABLE `product_names`
  ADD PRIMARY KEY (`id`),
  ADD KEY `section_id` (`section_id`),
  ADD KEY `idx_product_names_created_by` (`created_by`),
  ADD KEY `idx_product_names_section_status_group_order` (`section_id`,`status`,`group_name`(80),`sort_order`,`name`(120),`marking_size`(120)),
  ADD KEY `idx_product_names_section_name_marking` (`section_id`,`name`(120),`marking_size`(120)),
  ADD KEY `idx_product_names_linked_service` (`linked_service_id`),
  ADD KEY `idx_product_names_status_name` (`status`,`name`(120));

ALTER TABLE `product_service_links`
  ADD PRIMARY KEY (`product_name_id`,`service_id`),
  ADD KEY `idx_product_service_links_service` (`service_id`);

ALTER TABLE `role_access_policies`
  ADD PRIMARY KEY (`role`);

ALTER TABLE `rop_managers`
  ADD PRIMARY KEY (`rop_id`,`manager_id`),
  ADD KEY `manager_id` (`manager_id`);

ALTER TABLE `sections`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `category_id` (`category_id`,`code`);

ALTER TABLE `section_suppliers`
  ADD PRIMARY KEY (`section_id`,`supplier_id`),
  ADD KEY `supplier_id` (`supplier_id`);

ALTER TABLE `suppliers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD KEY `idx_users_role_full_name` (`role`,`full_name`);

ALTER TABLE `catalog_groups`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=120;

ALTER TABLE `catalog_services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2731;

ALTER TABLE `categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

ALTER TABLE `company_profiles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

ALTER TABLE `documents_templates`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

ALTER TABLE `documents_template_versions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

ALTER TABLE `kp_clients`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28;

ALTER TABLE `kp_contractors`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

ALTER TABLE `kp_quotes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=82;

ALTER TABLE `measurement_units`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=72;

ALTER TABLE `orders`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=72;

ALTER TABLE `order_invoices`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

ALTER TABLE `pkp_quotes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

ALTER TABLE `quote_payload_variants`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `quote_payload_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28881;

ALTER TABLE `product_names`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6778;

ALTER TABLE `sections`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=66;

ALTER TABLE `suppliers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=71;

ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

ALTER TABLE `catalog_groups`
  ADD CONSTRAINT `fk_catalog_groups_section` FOREIGN KEY (`section_id`) REFERENCES `sections` (`id`) ON DELETE CASCADE;

ALTER TABLE `catalog_services`
  ADD CONSTRAINT `fk_catalog_services_product_name` FOREIGN KEY (`linked_product_name_id`) REFERENCES `product_names` (`id`) ON DELETE SET NULL;

ALTER TABLE `company_director`
  ADD CONSTRAINT `fk_company_director_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_company_director_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `company_profiles`
  ADD CONSTRAINT `fk_company_profiles_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `documents_template_versions`
  ADD CONSTRAINT `fk_documents_template_versions_template` FOREIGN KEY (`template_id`) REFERENCES `documents_templates` (`id`) ON DELETE CASCADE;

ALTER TABLE `kp_clients`
  ADD CONSTRAINT `fk_kp_clients_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `kp_contractors`
  ADD CONSTRAINT `fk_kp_contractors_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `kp_quotes`
  ADD CONSTRAINT `fk_kp_quotes_client` FOREIGN KEY (`client_id`) REFERENCES `kp_clients` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_kp_quotes_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `orders`
  ADD CONSTRAINT `orders_ibfk_1` FOREIGN KEY (`manager_id`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `orders_ibfk_2` FOREIGN KEY (`rop_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

ALTER TABLE `order_invoices`
  ADD CONSTRAINT `fk_order_invoices_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_order_invoices_user` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

ALTER TABLE `products`
  ADD CONSTRAINT `products_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`),
  ADD CONSTRAINT `products_ibfk_2` FOREIGN KEY (`section_id`) REFERENCES `sections` (`id`),
  ADD CONSTRAINT `products_ibfk_3` FOREIGN KEY (`product_name_id`) REFERENCES `product_names` (`id`),
  ADD CONSTRAINT `products_ibfk_4` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`);

ALTER TABLE `product_names`
  ADD CONSTRAINT `fk_product_names_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `product_names_ibfk_1` FOREIGN KEY (`section_id`) REFERENCES `sections` (`id`);

ALTER TABLE `product_service_links`
  ADD CONSTRAINT `fk_product_service_links_product` FOREIGN KEY (`product_name_id`) REFERENCES `product_names` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_product_service_links_service` FOREIGN KEY (`service_id`) REFERENCES `catalog_services` (`id`) ON DELETE CASCADE;

ALTER TABLE `rop_managers`
  ADD CONSTRAINT `rop_managers_ibfk_1` FOREIGN KEY (`rop_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `rop_managers_ibfk_2` FOREIGN KEY (`manager_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

ALTER TABLE `sections`
  ADD CONSTRAINT `sections_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`);

ALTER TABLE `section_suppliers`
  ADD CONSTRAINT `section_suppliers_ibfk_1` FOREIGN KEY (`section_id`) REFERENCES `sections` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `section_suppliers_ibfk_2` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`id`) ON DELETE CASCADE;
COMMIT;

;
;
;
