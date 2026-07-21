ALTER TABLE `product_names`
  ADD COLUMN IF NOT EXISTS `komplektaciya` varchar(500) DEFAULT NULL AFTER `marking_size`;

INSERT INTO `categories` (`code`, `name`, `sort_order`)
VALUES ('consumables', 'Расходный материал', 25)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `sort_order` = VALUES(`sort_order`);

SET @consumables_category_id = (
  SELECT `id` FROM `categories` WHERE `code` = 'consumables' LIMIT 1
);

INSERT INTO `sections` (`category_id`, `code`, `name`, `sort_order`)
SELECT @consumables_category_id, 'consumables_main', 'Расходный материал', 10
WHERE @consumables_category_id IS NOT NULL
ON DUPLICATE KEY UPDATE
  `category_id` = VALUES(`category_id`),
  `name` = VALUES(`name`),
  `sort_order` = VALUES(`sort_order`);
