<?php

function kpJson($data, $code = 200) {
    jsonResponse($data, $code);
}

function kpCompanyProfileOwnerId(PDO $db, int $fallbackUid): int {
    $st = $db->prepare("SELECT id FROM users WHERE username = 'admin' LIMIT 1");
    $st->execute();
    $id = intval($st->fetch()['id'] ?? 0);
    if ($id) return $id;
    $st = $db->prepare("SELECT id FROM users WHERE role = 'admin' ORDER BY id LIMIT 1");
    $st->execute();
    $id = intval($st->fetch()['id'] ?? 0);
    return $id ?: $fallbackUid;
}

function kpLoadSharedCompanyProfile(PDO $db, int $uid): array {
    $ownerId = kpCompanyProfileOwnerId($db, $uid);
    $fields = "id, user_id, company_type, company_name, legal_name, inn, ogrn, kpp, address, phone, email, website, director_name, signatory_name, signatory_title, bank_name, bank_bik, bank_account, corr_account, intro_default, footer_default, autofill_fields_json, is_default, created_at, updated_at";
    $st = $db->prepare("SELECT {$fields} FROM company_profiles WHERE user_id = ? ORDER BY is_default DESC, id LIMIT 1");
    $st->execute([$ownerId]);
    $row = $st->fetch();
    if (!$row && $ownerId !== $uid) {
        $st->execute([$uid]);
        $row = $st->fetch();
    }
    if (!$row) {
        $row = $db->query("SELECT {$fields} FROM company_profiles ORDER BY is_default DESC, id LIMIT 1")->fetch();
    }
    return $row ?: [];
}

function kpLoadSharedCompanyProfiles(PDO $db, int $uid): array {
    $ownerId = kpCompanyProfileOwnerId($db, $uid);
    $fields = "id, user_id, company_type, company_name, legal_name, inn, ogrn, kpp, address, phone, email, website, director_name, signatory_name, signatory_title, bank_name, bank_bik, bank_account, corr_account, intro_default, footer_default, autofill_fields_json, is_default, created_at, updated_at";
    $st = $db->prepare("SELECT {$fields} FROM company_profiles WHERE user_id = ? ORDER BY is_default DESC, id");
    $st->execute([$ownerId]);
    $rows = $st->fetchAll();
    if (!$rows && $ownerId !== $uid) {
        $st->execute([$uid]);
        $rows = $st->fetchAll();
    }
    if (!$rows) {
        $rows = $db->query("SELECT {$fields} FROM company_profiles ORDER BY is_default DESC, id")->fetchAll();
    }
    return $rows ?: [];
}

function kpCanDelete($user) {
    return accessCan($user, 'kp', 'delete');
}

function kpScopeUserIds($user) {
    return accessResolveScopeUserIds($user, 'kp');
}

function kpAssertQuoteAccess($user, $quote) {
    if (($user['role'] ?? '') === 'admin') return;
    $ids = kpScopeUserIds($user);
    if (!$ids) return;
    if (in_array(intval($quote['user_id'] ?? 0), $ids, true)) return;
    kpJson(['error' => 'Forbidden'], 403);
}

function kpNormalizeStatus($status) {
    $allowed = ['created', 'sent', 'viewed', 'chosen', 'rejected', 'completed'];
    return in_array($status, $allowed, true) ? $status : 'created';
}

function kpMakeToken() {
    return bin2hex(random_bytes(16));
}

function kpNullableInt($value) {
    if ($value === null) return null;
    if (is_string($value)) {
        $value = trim($value);
        if ($value === '') return null;
        $value = str_replace(["\xC2\xA0", ' '], '', $value);
        $value = str_replace(',', '.', $value);
    }
    if (!is_numeric($value)) return null;
    return intval(round(floatval($value)));
}

function kpIntValue($value, $default = 0) {
    $normalized = kpNullableInt($value);
    return $normalized === null ? intval($default) : $normalized;
}

function kpNormalizeNumericPayload($value, $key = null) {
    $intKeys = [
        'quantity', 'purchase_price', 'minimal_price', 'retail_price',
        'linked_service_cost', 'linked_service_purchase_price',
        'markup_value', 'discount_value', 'price', 'final_price',
        'sum', 'total', 'total_with_vat', 'vat_sum',
        'purchase_total', 'margin_value', 'margin_percent', 'retail_total'
    ];
    if (is_array($value)) {
        foreach ($value as $k => $item) {
            $value[$k] = kpNormalizeNumericPayload($item, is_string($k) ? $k : null);
        }
        return $value;
    }
    if ($key !== null && in_array($key, $intKeys, true)) {
        $normalized = kpNullableInt($value);
        return $normalized === null ? $value : $normalized;
    }
    return $value;
}

function kpCatalogTextNorm($value) {
    return mb_strtolower(trim((string)$value), 'UTF-8');
}

function kpResolveCatalogGroupName($db, $sectionId, $groupName) {
    $groupName = trim((string)$groupName);
    if ($groupName === '') return '';
    $st = $db->prepare(
        "SELECT name
           FROM catalog_groups
          WHERE section_id = ?
            AND LOWER(TRIM(name)) = LOWER(TRIM(?))
          LIMIT 1"
    );
    $st->execute([intval($sectionId), $groupName]);
    $row = $st->fetch();
    return $row ? trim((string)$row['name']) : '';
}

function kpProductServiceLinksSchemaReady($db) {
    return true;
}

function kpDecodePayloadRow($quote) {
    if (!is_array($quote)) return [];
    $payload = [];
    if (!empty($quote['payload_json'])) {
        $payload = json_decode($quote['payload_json'], true);
        if (!is_array($payload)) $payload = [];
    }
    return $payload;
}

function kpEncodePayloadValue($payload) {
    return json_encode(is_array($payload) ? $payload : [], JSON_UNESCAPED_UNICODE);
}

function kpPayloadNumber($value) {
    if ($value === null || $value === '') return 0.0;
    return floatval($value);
}

function kpPayloadVariantsForNormalize(array $payload) {
    $proposalTypes = $payload['proposal_types'] ?? null;
    if (is_array($proposalTypes) && count($proposalTypes)) return $proposalTypes;
    $variants = $payload['variants'] ?? null;
    if (is_array($variants) && count($variants)) {
        return [[
            'id' => 'ptype-default',
            'label' => '',
            'selected_variant_id' => '',
            'variants' => $variants,
        ]];
    }
    return [];
}

function kpPayloadItemFinalPrice(array $item) {
    if (array_key_exists('base_price', $item) && $item['base_price'] !== '') {
        $base = kpPayloadNumber($item['base_price']);
    } elseif (array_key_exists('retail_price', $item) && $item['retail_price'] !== '') {
        $base = kpPayloadNumber($item['retail_price']);
    } elseif (array_key_exists('final_price', $item) && $item['final_price'] !== '') {
        return max(kpPayloadNumber($item['final_price']), 0);
    } else {
        return 0.0;
    }
    $markup = kpPayloadNumber($item['markup_value'] ?? 0);
    $discount = max(kpPayloadNumber($item['discount_value'] ?? 0), 0);
    $factor = 1 + ($markup / 100) - ($discount / 100);
    if ($factor < 0) $factor = 0;
    return max($base * $factor, 0);
}

function kpPayloadItemIsPercentIncidental(array $item) {
    return (string)($item['category_code'] ?? ($item['_cat_code'] ?? '')) === 'incidental_expenses'
        && (string)($item['price_type'] ?? '') === 'percent';
}

function kpPayloadItemLineSum(array $item, $percentBase = 0.0) {
    if (!empty($item['excluded_from_calc'])) return 0.0;
    $qty = kpPayloadNumber($item['quantity'] ?? 0);
    if ($qty < 0) $qty = 0;
    $price = kpPayloadItemFinalPrice($item);
    if (kpPayloadItemIsPercentIncidental($item)) {
        return max(kpPayloadNumber($percentBase), 0) * ($price / 100) * $qty;
    }
    if ($price > 0 || array_key_exists('base_price', $item) || array_key_exists('retail_price', $item) || array_key_exists('final_price', $item)) {
        return $qty * $price;
    }
    if (array_key_exists('line_sum', $item) && $item['line_sum'] !== '') return max(kpPayloadNumber($item['line_sum']), 0);
    if (array_key_exists('sum', $item) && $item['sum'] !== '') return max(kpPayloadNumber($item['sum']), 0);
    return 0.0;
}

function kpPayloadItemPurchaseSum(array $item) {
    if (!empty($item['excluded_from_calc'])) return 0.0;
    $qty = kpPayloadNumber($item['quantity'] ?? 0);
    if ($qty < 0) $qty = 0;
    $price = array_key_exists('purchase_price', $item) ? kpPayloadNumber($item['purchase_price']) : 0.0;
    return $qty * $price;
}

function kpSyncQuotePayloadRows($db, $quoteType, $quoteId, array $payload) {
    $quoteType = $quoteType === 'pkp' ? 'pkp' : 'kp';
    $quoteId = intval($quoteId);
    if ($quoteId <= 0) return;

    try {
        $db->prepare("DELETE FROM quote_payload_items WHERE quote_type = ? AND quote_id = ?")->execute([$quoteType, $quoteId]);
        $db->prepare("DELETE FROM quote_payload_variants WHERE quote_type = ? AND quote_id = ?")->execute([$quoteType, $quoteId]);

        $variantInsert = $db->prepare(
            "INSERT INTO quote_payload_variants
             (quote_type, quote_id, proposal_type_index, proposal_type_id, proposal_type_label, variant_index, variant_id, variant_label, selected_variant, vat_mode, items_count, total_sum, purchase_sum, margin_sum, margin_percent)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        );
        $itemInsert = $db->prepare(
            "INSERT INTO quote_payload_items
             (quote_type, quote_id, proposal_type_index, proposal_type_id, variant_index, variant_id, category_index, category_code, category_name, section_index, section_id, section_code, section_name, item_index, uid, item_type, product_name_id, service_id, name, marking_size, group_name, quantity, unit, supplier, purchase_price, base_price, final_price, line_sum, excluded_from_calc, raw_json)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        );

        foreach (kpPayloadVariantsForNormalize($payload) as $typeIndex => $type) {
            if (!is_array($type)) continue;
            $variants = $type['variants'] ?? [];
            if (!is_array($variants)) $variants = [];
            $typeId = (string)($type['id'] ?? '');
            $selectedVariantId = (string)($type['selected_variant_id'] ?? '');
            foreach ($variants as $variantIndex => $variant) {
                if (!is_array($variant)) continue;
                $variantId = (string)($variant['id'] ?? '');
                $items = [];
                $cats = $variant['snapshot'] ?? [];
                if (is_array($cats) && count($cats)) {
                    foreach ($cats as $catIndex => $cat) {
                        if (!is_array($cat)) continue;
                        $sections = $cat['sections'] ?? [];
                        if (!is_array($sections)) $sections = [];
                        foreach ($sections as $sectionIndex => $section) {
                            if (!is_array($section)) continue;
                            $sectionItems = $section['items'] ?? [];
                            if (!is_array($sectionItems)) $sectionItems = [];
                            foreach ($sectionItems as $itemIndex => $item) {
                                if (!is_array($item)) continue;
                                $item['_cat_index'] = $catIndex;
                                $item['_cat_code'] = (string)($cat['catCode'] ?? ($item['category_code'] ?? ''));
                                $item['_cat_name'] = (string)($cat['catName'] ?? ($item['category_name'] ?? ''));
                                $item['_section_index'] = $sectionIndex;
                                $item['_section_id'] = (string)($section['secId'] ?? ($item['section_id'] ?? ''));
                                $item['_section_code'] = (string)($section['secCode'] ?? ($item['section_code'] ?? ''));
                                $item['_section_name'] = (string)($section['secName'] ?? ($item['section_name'] ?? ''));
                                $item['_item_index'] = $itemIndex;
                                $items[] = $item;
                            }
                        }
                    }
                } elseif (is_array($variant['items'] ?? null)) {
                    foreach ($variant['items'] as $itemIndex => $item) {
                        if (!is_array($item)) continue;
                        $item['_cat_index'] = 0;
                        $item['_cat_code'] = (string)($item['category_code'] ?? '');
                        $item['_cat_name'] = (string)($item['category_name'] ?? '');
                        $item['_section_index'] = 0;
                        $item['_section_id'] = (string)($item['section_id'] ?? '');
                        $item['_section_code'] = (string)($item['section_code'] ?? '');
                        $item['_section_name'] = (string)($item['section_name'] ?? '');
                        $item['_item_index'] = $itemIndex;
                        $items[] = $item;
                    }
                }

                $percentBase = 0.0;
                foreach ($items as $item) {
                    if (!empty($item['excluded_from_calc']) || kpPayloadItemIsPercentIncidental($item)) continue;
                    $percentBase += kpPayloadItemLineSum($item);
                }

                $total = 0.0;
                $purchase = 0.0;
                $itemsCount = 0;
                foreach ($items as $item) {
                    $excluded = !empty($item['excluded_from_calc']);
                    if (!$excluded) {
                        $itemsCount++;
                        $total += kpPayloadItemLineSum($item, $percentBase);
                        $purchase += kpPayloadItemPurchaseSum($item);
                    }
                }
                $margin = $total - $purchase;
                $marginPercent = $purchase > 0 ? (($total - $purchase) / $purchase) * 100 : null;
                $variantInsert->execute([
                    $quoteType, $quoteId, intval($typeIndex), $typeId, (string)($type['label'] ?? ''),
                    intval($variantIndex), $variantId, (string)($variant['label'] ?? ''),
                    ($selectedVariantId !== '' && $selectedVariantId === $variantId) ? 1 : 0,
                    (string)($variant['vat_mode'] ?? ($payload['vat_mode'] ?? 'none')),
                    $itemsCount, $total, $purchase, $margin, $marginPercent
                ]);

                foreach ($items as $item) {
                    $rawItem = $item;
                    unset(
                        $rawItem['_cat_index'],
                        $rawItem['_cat_code'],
                        $rawItem['_cat_name'],
                        $rawItem['_section_index'],
                        $rawItem['_section_id'],
                        $rawItem['_section_code'],
                        $rawItem['_section_name'],
                        $rawItem['_item_index']
                    );
                    $itemInsert->execute([
                        $quoteType,
                        $quoteId,
                        intval($typeIndex),
                        $typeId,
                        intval($variantIndex),
                        $variantId,
                        intval($item['_cat_index'] ?? 0),
                        (string)($item['_cat_code'] ?? ''),
                        (string)($item['_cat_name'] ?? ''),
                        intval($item['_section_index'] ?? 0),
                        (string)($item['_section_id'] ?? ''),
                        (string)($item['_section_code'] ?? ''),
                        (string)($item['_section_name'] ?? ''),
                        intval($item['_item_index'] ?? 0),
                        (string)($item['uid'] ?? ''),
                        (string)($item['item_type'] ?? 'product'),
                        intval($item['product_name_id'] ?? 0),
                        intval($item['service_id'] ?? 0),
                        (string)($item['name'] ?? ''),
                        (string)($item['marking_size'] ?? ''),
                        (string)($item['group_name'] ?? ''),
                        kpPayloadNumber($item['quantity'] ?? 0),
                        (string)($item['unit'] ?? ''),
                        (string)($item['supplier'] ?? ''),
                        array_key_exists('purchase_price', $item) ? kpPayloadNumber($item['purchase_price']) : null,
                        array_key_exists('base_price', $item) ? kpPayloadNumber($item['base_price']) : null,
                        kpPayloadItemFinalPrice($item),
                        kpPayloadItemLineSum($item, $percentBase),
                        !empty($item['excluded_from_calc']) ? 1 : 0,
                        json_encode($rawItem, JSON_UNESCAPED_UNICODE),
                    ]);
                }
            }
        }
    } catch (PDOException $e) {
        if (in_array($e->getCode(), ['42S02', '42S22'], true)) return;
        throw $e;
    }
}

function kpDeleteQuotePayloadRows($db, $quoteType, $quoteId) {
    $quoteType = $quoteType === 'pkp' ? 'pkp' : 'kp';
    $quoteId = intval($quoteId);
    if ($quoteId <= 0) return;
    try {
        $db->prepare("DELETE FROM quote_payload_items WHERE quote_type = ? AND quote_id = ?")->execute([$quoteType, $quoteId]);
        $db->prepare("DELETE FROM quote_payload_variants WHERE quote_type = ? AND quote_id = ?")->execute([$quoteType, $quoteId]);
    } catch (PDOException $e) {
        if (in_array($e->getCode(), ['42S02', '42S22'], true)) return;
        throw $e;
    }
}

function kpBuildWorkflowChangedMeta($user, $workflowStatus) {
    return [
        'workflow_status' => (string)$workflowStatus,
        'changed_at' => date('Y-m-d H:i:s'),
        'user_id' => intval($user['id'] ?? 0),
        'login' => (string)($user['username'] ?? $user['login'] ?? ''),
        'role' => (string)($user['role'] ?? ''),
        'full_name' => (string)($user['full_name'] ?? '')
    ];
}

function kpDecodeJsonField($value) {
    if (!$value) return [];
    $data = json_decode((string)$value, true);
    return is_array($data) ? $data : [];
}

function kpCompanyTypeLabel($type) {
    $map = [
        'person' => 'Физ лицо',
        'ip' => 'ИП',
        'ooo' => 'ООО',
    ];
    $type = trim((string)$type);
    return $map[$type] ?? ($type !== '' ? $type : '—');
}

function kpGetQuotePayload($quote) {
    $payload = $quote['payload_json'] ? json_decode($quote['payload_json'], true) : [];
    return is_array($payload) ? $payload : [];
}

function kpIsComplectationCategoryAllowed($item, $card = null) {
    $catCode = trim((string)($item['category_code'] ?? ($card['category_code'] ?? '')));
    return in_array($catCode, ['equipment', 'materials'], true);
}

function kpHttpHeaders() {
    return [
        'Accept: application/json, text/javascript, */*; q=0.01',
        'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'Content-Type: application/x-www-form-urlencoded; charset=UTF-8',
        'Referer: https://egrul.nalog.ru/index.html',
        'Origin: https://egrul.nalog.ru',
        'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        'X-Requested-With: XMLHttpRequest',
    ];
}

function kpHttpGet($url) {
    $opts = [
        'http' => [
            'method' => 'GET',
            'header' => implode("\r\n", kpHttpHeaders()),
            'ignore_errors' => true,
            'timeout' => 30,
        ],
        'ssl' => [
            'verify_peer' => true,
            'verify_peer_name' => true,
        ],
    ];
    return appFileGetContents($url, false, stream_context_create($opts), 0, null, 'kpHttpGet');
}

function kpHttpPost($url, $data) {
    $opts = [
        'http' => [
            'method' => 'POST',
            'header' => implode("\r\n", kpHttpHeaders()),
            'content' => http_build_query($data),
            'ignore_errors' => true,
            'timeout' => 30,
        ],
        'ssl' => [
            'verify_peer' => true,
            'verify_peer_name' => true,
        ],
    ];
    return appFileGetContents($url, false, stream_context_create($opts), 0, null, 'kpHttpPost');
}

function kpExtractPdfObjects($pdf) {
    preg_match_all('/(\d+)\s+(\d+)\s+obj(.*?)endobj/s', $pdf, $matches, PREG_SET_ORDER);
    $objects = [];
    foreach ($matches as $m) {
        $objects[$m[1] . ' ' . $m[2]] = $m[3];
    }
    return $objects;
}

function kpPdfDecodeStream($objectBody) {
    if (!preg_match('/stream\s*(.*?)\s*endstream/s', $objectBody, $m)) return '';
    $stream = $m[1];
    $stream = preg_replace("/^\r?\n/", '', $stream);
    if (strpos($objectBody, '/FlateDecode') !== false) {
        $decoded = @zlib_decode($stream);
        if ($decoded !== false) return $decoded;
        $decoded = @gzuncompress($stream);
        if ($decoded !== false) return $decoded;
    }
    return $stream;
}

function kpPdfDecodeUtf16Hex($hex) {
    $bin = @hex2bin(preg_replace('/[^0-9A-Fa-f]/', '', $hex));
    if ($bin === false || $bin === '') return '';
    if (strpos($bin, "\xFE\xFF") === 0 || strpos($bin, "\xFF\xFE") === 0) {
        $txt = @mb_convert_encoding($bin, 'UTF-8', 'UTF-16');
        return $txt !== false ? $txt : '';
    }
    if (strlen($bin) % 2 === 0) {
        $txt = @mb_convert_encoding($bin, 'UTF-8', 'UTF-16BE');
        if ($txt !== false && $txt !== '') return $txt;
    }
    return preg_replace('/[^\P{C}\n\r\t]+/u', '', $bin);
}

function kpPdfDecodeLiteral($text) {
    $text = preg_replace_callback('/\\\\([0-7]{1,3})/', function ($m) {
        return chr(octdec($m[1]));
    }, $text);
    $text = strtr($text, [
        '\\\\' => '\\',
        '\\(' => '(',
        '\\)' => ')',
        '\\n' => "\n",
        '\\r' => "\r",
        '\\t' => "\t",
        '\\b' => "\b",
        '\\f' => "\f",
    ]);
    if (strpos($text, "\xFE\xFF") === 0 || strpos($text, "\xFF\xFE") === 0) {
        $txt = @mb_convert_encoding($text, 'UTF-8', 'UTF-16');
        return $txt !== false ? $txt : '';
    }
    return $text;
}

function kpPdfParseToUnicodeMap($cmapText) {
    $map = [];
    if (preg_match_all('/beginbfchar(.*?)endbfchar/s', $cmapText, $blocks, PREG_SET_ORDER)) {
        foreach ($blocks as $block) {
            if (preg_match_all('/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/', $block[1], $pairs, PREG_SET_ORDER)) {
                foreach ($pairs as $pair) {
                    $map[strtoupper($pair[1])] = kpPdfDecodeUtf16Hex($pair[2]);
                }
            }
        }
    }
    if (preg_match_all('/beginbfrange(.*?)endbfrange/s', $cmapText, $blocks, PREG_SET_ORDER)) {
        foreach ($blocks as $block) {
            $lines = preg_split('/\r?\n/', trim($block[1]));
            foreach ($lines as $line) {
                $line = trim($line);
                if ($line === '') continue;
                if (preg_match('/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/', $line, $m)) {
                    $start = hexdec($m[1]);
                    $end = hexdec($m[2]);
                    $dest = hexdec($m[3]);
                    $width = strlen($m[1]);
                    for ($i = $start; $i <= $end; $i++, $dest++) {
                        $srcHex = strtoupper(str_pad(dechex($i), $width, '0', STR_PAD_LEFT));
                        $dstHex = strtoupper(str_pad(dechex($dest), 4, '0', STR_PAD_LEFT));
                        $map[$srcHex] = kpPdfDecodeUtf16Hex($dstHex);
                    }
                } elseif (preg_match('/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]/', $line, $m)) {
                    $start = hexdec($m[1]);
                    $width = strlen($m[1]);
                    if (preg_match_all('/<([0-9A-Fa-f]+)>/', $m[3], $arr)) {
                        foreach ($arr[1] as $idx => $dstHex) {
                            $srcHex = strtoupper(str_pad(dechex($start + $idx), $width, '0', STR_PAD_LEFT));
                            $map[$srcHex] = kpPdfDecodeUtf16Hex($dstHex);
                        }
                    }
                }
            }
        }
    }
    return $map;
}

function kpPdfFontMaps($pdf) {
    $objects = kpExtractPdfObjects($pdf);
    $maps = [];
    foreach ($objects as $objId => $body) {
        if (!preg_match('/\/ToUnicode\s+(\d+)\s+(\d+)\s+R/', $body, $ref)) continue;
        $toUnicodeId = $ref[1] . ' ' . $ref[2];
        if (empty($objects[$toUnicodeId])) continue;
        $cmap = kpPdfDecodeStream($objects[$toUnicodeId]);
        if ($cmap === '') continue;
        $maps[$objId] = kpPdfParseToUnicodeMap($cmap);
    }
    return $maps;
}

function kpPdfDecodeHexWithMap($hex, $map) {
    $hex = strtoupper(preg_replace('/[^0-9A-F]/', '', $hex));
    if ($hex === '') return '';
    $out = '';
    if ($map) {
        $step = 4;
        for ($i = 0; $i < strlen($hex); $i += $step) {
            $chunk = substr($hex, $i, $step);
            if ($chunk === '') continue;
            $out .= $map[$chunk] ?? kpPdfDecodeUtf16Hex($chunk);
        }
        return $out;
    }
    return kpPdfDecodeUtf16Hex($hex);
}

function kpPdfExtractText($pdf) {
    $objects = kpExtractPdfObjects($pdf);
    $fontMapsByObject = kpPdfFontMaps($pdf);
    $resourceFontMap = [];
    foreach ($objects as $objId => $body) {
        if (preg_match_all('/\/(F[\w\d]+)\s+(\d+)\s+(\d+)\s+R/', $body, $fontRefs, PREG_SET_ORDER)) {
            foreach ($fontRefs as $fontRef) {
                $resourceFontMap[$fontRef[1]] = $fontMapsByObject[$fontRef[2] . ' ' . $fontRef[3]] ?? [];
            }
        }
    }

    $text = '';
    foreach ($objects as $body) {
        if (strpos($body, 'stream') === false) continue;
        $decoded = kpPdfDecodeStream($body);
        if ($decoded === '' || (strpos($decoded, 'BT') === false && strpos($decoded, 'Tf') === false)) continue;
        $currentFont = '';
        $currentMap = [];
        $lines = preg_split('/\r?\n/', $decoded);
        foreach ($lines as $line) {
            if (preg_match('/\/(F[\w\d]+)\s+\d+(?:\.\d+)?\s+Tf/', $line, $fm)) {
                $currentFont = $fm[1];
                $currentMap = $resourceFontMap[$currentFont] ?? [];
            }
            if (preg_match_all('/<([0-9A-Fa-f]+)>\s*Tj/', $line, $hexes)) {
                foreach ($hexes[1] as $hex) {
                    $text .= kpPdfDecodeHexWithMap($hex, $currentMap);
                }
                $text .= "\n";
            }
            if (preg_match_all('/\((.*?)\)\s*Tj/', $line, $lits)) {
                foreach ($lits[1] as $lit) {
                    $text .= kpPdfDecodeLiteral($lit);
                }
                $text .= "\n";
            }
            if (preg_match('/\[(.*?)\]\s*TJ/', $line, $arr)) {
                if (preg_match_all('/<([0-9A-Fa-f]+)>|\((.*?)\)/', $arr[1], $parts, PREG_SET_ORDER)) {
                    foreach ($parts as $part) {
                        if (!empty($part[1])) $text .= kpPdfDecodeHexWithMap($part[1], $currentMap);
                        elseif (isset($part[2])) $text .= kpPdfDecodeLiteral($part[2]);
                    }
                    $text .= "\n";
                }
            }
        }
    }
    $text = preg_replace("/[ \t]+\n/u", "\n", $text);
    $text = preg_replace("/\n{2,}/u", "\n", $text);
    return trim($text);
}

function kpNormalizeExtractText($text) {
    $text = str_replace(["\r\n", "\r"], "\n", $text);
    $text = preg_replace('/[ \t]+/u', ' ', $text);
    $text = preg_replace('/ *\n */u', "\n", $text);
    return trim($text);
}

function kpPickRegexValue($text, $patterns) {
    foreach ($patterns as $pattern) {
        if (preg_match($pattern, $text, $m)) {
            return trim((string)($m[1] ?? ''));
        }
    }
    return '';
}

function kpPickRegexDigits($text, $patterns, $expectedLength = 0) {
    foreach ($patterns as $pattern) {
        if (!preg_match($pattern, $text, $m)) continue;
        $digits = preg_replace('/\D+/', '', (string)($m[1] ?? ''));
        if ($digits === '') continue;
        if ($expectedLength > 0 && strlen($digits) !== $expectedLength) continue;
        return $digits;
    }
    return '';
}

function kpPickLineAfterLabel($text, $labels) {
    foreach ($labels as $label) {
        $pattern = '/(?:' . $label . ')\s*[:\-]?\s*([^\n]+)/ui';
        if (preg_match($pattern, $text, $m)) {
            return trim((string)($m[1] ?? ''));
        }
    }
    return '';
}

function kpCleanFnString($value) {
    $value = html_entity_decode(strip_tags((string)$value), ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $value = preg_replace('/\s+/u', ' ', $value);
    return trim((string)$value);
}

function kpSearchRowValue(array $row, array $keys) {
    foreach ($keys as $key) {
        if (!array_key_exists($key, $row)) continue;
        $value = kpCleanFnString($row[$key]);
        if ($value !== '') return $value;
    }
    return '';
}

function kpParseCompanyExtract($text, $fallbackInn = '') {
    $text = kpNormalizeExtractText($text);
    $companyType = (preg_match('/\bОГРНИП\b/u', $text) || preg_match('/индивидуальн(?:ый|ого)\s+предпринимател/u', mb_strtolower($text, 'UTF-8')))
        ? 'ip'
        : 'ooo';
    $companyName = kpPickRegexValue($text, [
        '/Полное наименование(?: на русском языке)?\s+([^\n]+)/u',
        '/Наименование юридического лица\s+([^\n]+)/u',
        '/Фамилия,\s*имя,\s*отчество\s+([^\n]+)/u',
    ]);
    $legalName = kpPickRegexValue($text, [
        '/Полное наименование(?: на русском языке)?\s+([^\n]+)/u',
        '/Наименование юридического лица\s+([^\n]+)/u',
        '/Фамилия,\s*имя,\s*отчество\s+([^\n]+)/u',
    ]);
    $inn = kpPickRegexDigits($text, [
        '/\bИНН\b([^\n]+)/u',
    ]) ?: $fallbackInn;
    $ogrn = kpPickRegexDigits($text, [
        '/\bОГРНИП\b([^\n]+)/u',
        '/\bОГРН\b([^\n]+)/u',
    ]);
    $kpp = kpPickRegexDigits($text, [
        '/\bКПП\b([^\n]+)/u',
    ], 9);
    $email = kpPickRegexValue($text, [
        '/\bE-?mail\b[:\s]*([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})/iu',
        '/\bЭлектронная почта\b[:\s]*([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})/iu',
        '/([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})/iu',
    ]);
    $bankBik = kpPickRegexDigits($text, [
        '/\bБИК\b([^\n]+)/u',
        '/(?:банка|банк)\b([^\n]+)/iu',
    ], 9);
    $bankAccount = kpPickRegexDigits($text, [
        '/(?:Расчетн(?:ый|ого)\s+счет|Расч[её]тн(?:ый|ого)\s+сч[её]т)\s*([^\n]+)/u',
    ], 20);
    $corrAccount = kpPickRegexDigits($text, [
        '/(?:Корреспондентск(?:ий|ого)\s+счет|Корреспондентск(?:ий|ого)\s+сч[её]т|Корр\.\s*сч[её]т)\s*([^\n]+)/u',
    ], 20);
    $bankName = kpPickLineAfterLabel($text, [
        'Наименование банка',
        'Банк получателя',
        'Банк',
    ]);
    $address = kpPickRegexValue($text, [
        '/(?:Адрес юридического лица|Место нахождения и адрес юридического лица|Адрес места нахождения)\s+([^\n]+)/u',
        '/(?:Адрес места жительства в Российской Федерации)\s+([^\n]+)/u',
        '/(?:Адрес|Место нахождения)\s*[:\-]?\s*([^\n]+)/u',
    ]);
    $directorName = kpPickRegexValue($text, [
        '/(?:Лицо, имеющее право без доверенности действовать от имени юридического лица|Руководитель постоянно действующего исполнительного органа)\s+Фамилия\s+([^\n]+)/u',
        '/(?:Сведения о лице, имеющем право без доверенности действовать от имени юридического лица).*?Фамилия,\s*имя,\s*отчество\s+([^\n]+)/us',
    ]);

    return [
        'company_type' => $companyType,
        'company_name' => $companyName,
        'legal_name' => $legalName,
        'inn' => $inn,
        'ogrn' => $ogrn,
        'kpp' => $kpp,
        'address' => $address,
        'director_name' => $directorName,
        'bank_name' => $bankName,
        'bank_bik' => $bankBik,
        'bank_account' => $bankAccount,
        'corr_account' => $corrAccount,
        'email' => $email,
    ];
}

function kpFetchOfficialExtractByInn($inn) {
    $raw = kpHttpPost('https://egrul.nalog.ru/', [
        'query' => $inn,
        'page' => '',
        'region' => '',
        'PreventChromeAutocomplete' => '',
    ]);
    $tokenData = $raw ? json_decode($raw, true) : null;
    $searchToken = trim((string)($tokenData['t'] ?? ''));
    if ($searchToken === '') {
        throw new RuntimeException('Не удалось получить токен поиска ФНС');
    }

    $resultRaw = kpHttpGet('https://egrul.nalog.ru/search-result/' . rawurlencode($searchToken));
    $result = $resultRaw ? json_decode($resultRaw, true) : null;
    $item = is_array($result['rows'] ?? null) && !empty($result['rows']) ? $result['rows'][0] : null;
    if (!$item || empty($item['t'])) {
        throw new RuntimeException('ФНС не вернула запись по этому ИНН');
    }

    $extractToken = trim((string)$item['t']);
    if (kpHttpGet('https://egrul.nalog.ru/vyp-request/' . rawurlencode($extractToken)) === false) {
        throw new RuntimeException('Не удалось запросить официальную выписку ФНС');
    }

    $status = '';
    for ($i = 0; $i < 20; $i++) {
        usleep(500000);
        $statusRaw = kpHttpGet('https://egrul.nalog.ru/vyp-status/' . rawurlencode($extractToken));
        $statusData = $statusRaw ? json_decode($statusRaw, true) : null;
        $status = trim((string)($statusData['status'] ?? ''));
        if ($status === 'ready') break;
    }
    if ($status !== 'ready') {
        throw new RuntimeException('ФНС не успела подготовить выписку');
    }

    $pdf = kpHttpGet('https://egrul.nalog.ru/vyp-download/' . rawurlencode($extractToken));
    if (!$pdf || stripos($pdf, '%PDF') === false) {
        throw new RuntimeException('ФНС не вернула PDF-выписку');
    }
    return [
        'pdf' => $pdf,
        'row' => is_array($item) ? $item : [],
    ];
}

function kpQuoteListNumber($value): float {
    if ($value === null || $value === '') return 0.0;
    if (is_string($value)) {
        $value = str_replace(["\xC2\xA0", ' '], '', $value);
        $value = str_replace(',', '.', $value);
    }
    return is_numeric($value) ? (float)$value : 0.0;
}

function kpQuoteListLineTotal(array $item): float {
    if (!empty($item['excluded_from_calc'])) return 0.0;
    $qty = max(kpQuoteListNumber($item['quantity'] ?? 0), 0);
    if (array_key_exists('line_sum', $item) && $item['line_sum'] !== '') {
        return max(kpQuoteListNumber($item['line_sum']), 0);
    }
    if (array_key_exists('sum', $item) && $item['sum'] !== '') {
        return max(kpQuoteListNumber($item['sum']), 0);
    }
    $base = array_key_exists('final_price', $item) && $item['final_price'] !== ''
        ? kpQuoteListNumber($item['final_price'])
        : kpQuoteListNumber($item['base_price'] ?? ($item['retail_price'] ?? 0));
    return max($base * $qty, 0);
}

function kpQuoteListIsPercentIncidental(array $item): bool {
    return (string)($item['category_code'] ?? '') === 'incidental_expenses'
        && (string)($item['price_type'] ?? '') === 'percent';
}

function kpQuoteListLineTotalWithBase(array $item, float $percentBase): float {
    if (!kpQuoteListIsPercentIncidental($item)) return kpQuoteListLineTotal($item);
    if (!empty($item['excluded_from_calc'])) return 0.0;
    $qty = max(kpQuoteListNumber($item['quantity'] ?? 0), 0);
    $base = array_key_exists('final_price', $item) && $item['final_price'] !== ''
        ? kpQuoteListNumber($item['final_price'])
        : kpQuoteListNumber($item['base_price'] ?? ($item['retail_price'] ?? 0));
    return max($percentBase * ($base / 100) * $qty, 0);
}

function kpQuoteListVariantItems(array $variant): array {
    if (!empty($variant['items']) && is_array($variant['items'])) {
        return $variant['items'];
    }
    $items = [];
    $cats = is_array($variant['cats'] ?? null) ? $variant['cats'] : [];
    foreach ($cats as $cat) {
        $sections = is_array($cat['sections'] ?? null) ? $cat['sections'] : [];
        foreach ($sections as $section) {
            $rows = is_array($section['items'] ?? null) ? $section['items'] : [];
            foreach ($rows as $row) {
                if (is_array($row)) $items[] = $row;
            }
        }
    }
    return $items;
}

function kpQuoteListVariantTotal(array $variant): float {
    $total = 0.0;
    $items = kpQuoteListVariantItems($variant);
    $percentBase = 0.0;
    foreach ($items as $item) {
        if (is_array($item) && !kpQuoteListIsPercentIncidental($item)) {
            $percentBase += kpQuoteListLineTotal($item);
        }
    }
    foreach ($items as $item) {
        if (is_array($item)) $total += kpQuoteListLineTotalWithBase($item, $percentBase);
    }
    return $total;
}

function kpQuoteListChosenVariant(array $type): ?array {
    $variants = is_array($type['variants'] ?? null) ? $type['variants'] : [];
    if (!$variants) return null;
    $selectedId = (string)($type['selected_variant_id'] ?? '');
    if ($selectedId !== '') {
        foreach ($variants as $variant) {
            if (is_array($variant) && (string)($variant['id'] ?? '') === $selectedId) return $variant;
        }
    }
    $selectedIndex = isset($type['selected_variant_index']) ? intval($type['selected_variant_index']) : -1;
    if ($selectedIndex >= 0 && isset($variants[$selectedIndex]) && is_array($variants[$selectedIndex])) {
        return $variants[$selectedIndex];
    }
    foreach ($variants as $variant) {
        if (is_array($variant) && !empty($variant['selected'])) return $variant;
    }
    return null;
}

function kpQuoteListSummary(array $payload, string $selectedVariantLabel = ''): array {
    $summary = [
        'label' => '',
        'total' => null,
        'lines' => [],
        'kanban_order' => isset($payload['kanban_order']) ? intval($payload['kanban_order']) : null,
    ];
    $proposalTypes = is_array($payload['proposal_types'] ?? null) ? $payload['proposal_types'] : [];
    if ($proposalTypes) {
        $total = 0.0;
        $selectionMode = trim((string)($payload['selection_mode'] ?? $payload['client_selection_mode'] ?? ''));
        $selectedTypeId = trim((string)($payload['selected_type_id'] ?? ''));
        if ($selectionMode === 'type' && $selectedTypeId !== '') {
            foreach ($proposalTypes as $type) {
                if (!is_array($type) || (string)($type['id'] ?? '') !== $selectedTypeId) continue;
                $typeLabel = trim((string)($type['label'] ?? ''));
                foreach (($type['variants'] ?? []) as $variant) {
                    if (!is_array($variant)) continue;
                    $variantLabel = trim((string)($variant['label'] ?? ''));
                    $summary['lines'][] = [
                        'typeLabel' => $typeLabel,
                        'variantLabel' => $variantLabel,
                    ];
                    $total += kpQuoteListVariantTotal($variant);
                }
                if ($summary['lines']) {
                    $summary['label'] = $typeLabel !== '' ? $typeLabel : 'Выбранный тип';
                    $summary['selection_mode'] = 'type';
                    $summary['selected_type_id'] = $selectedTypeId;
                    $summary['typeLabel'] = $typeLabel;
                    $summary['total'] = $total;
                }
                return $summary;
            }
        }
        foreach ($proposalTypes as $type) {
            if (!is_array($type)) continue;
            $chosen = kpQuoteListChosenVariant($type);
            if (!$chosen) continue;
            $typeLabel = trim((string)($type['label'] ?? ''));
            $variantLabel = trim((string)($chosen['label'] ?? ''));
            $summary['lines'][] = [
                'typeLabel' => $typeLabel,
                'variantLabel' => $variantLabel,
            ];
            $total += kpQuoteListVariantTotal($chosen);
        }
        if ($summary['lines']) {
            $summary['label'] = count($summary['lines']) === 1 ? $summary['lines'][0]['variantLabel'] : ('Выбрано типов: ' . count($summary['lines']));
            $summary['total'] = $total;
        }
        return $summary;
    }

    $selectedVariantLabel = trim($selectedVariantLabel);
    if ($selectedVariantLabel === '') return $summary;
    $summary['label'] = $selectedVariantLabel;
    $summary['lines'][] = ['typeLabel' => '', 'variantLabel' => $selectedVariantLabel];
    $variants = is_array($payload['variants'] ?? null) ? $payload['variants'] : [];
    foreach ($variants as $variant) {
        if (!is_array($variant)) continue;
        if (trim((string)($variant['label'] ?? '')) !== $selectedVariantLabel) continue;
        $summary['total'] = kpQuoteListVariantTotal($variant);
        break;
    }
    return $summary;
}
