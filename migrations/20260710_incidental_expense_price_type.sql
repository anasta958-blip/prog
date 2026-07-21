ALTER TABLE `product_names`
  ADD COLUMN `price_type` enum('fixed','percent') NOT NULL DEFAULT 'fixed' AFTER `retail_price`;
