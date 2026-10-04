SET search_path TO __TENANT_SCHEMA__, public;

-- Внешняя отправка PDF КП, ПКП и комплектаций в Telegram-группу и по почте.

INSERT INTO permissions (code, name, group_name)
VALUES
    ('outbound.settings.manage', 'Настройка внешней отправки', 'Внешняя отправка'),
    ('documents.send', 'Отправка документов', 'Внешняя отправка')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

-- Единственная строка настроек организации. Токен бота и пароль почты
-- хранятся только зашифрованными (AES-GCM, ключ выводится сервером из
-- Security:TotpEncryptionKey) и никогда не возвращаются клиенту.
CREATE TABLE outbound_settings (
    id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    telegram_bot_token bytea,
    telegram_chat_id varchar(64),
    telegram_uses_topics boolean NOT NULL DEFAULT false,
    telegram_default_topic_id bigint CHECK (telegram_default_topic_id > 0),
    telegram_caption_template varchar(1024) NOT NULL DEFAULT '{документ} №{номер} — {название}',
    email_address varchar(320),
    email_password bytea,
    email_sender_name varchar(200),
    email_smtp_host varchar(255),
    email_smtp_port integer CHECK (email_smtp_port BETWEEN 1 AND 65535),
    email_subject_template varchar(500) NOT NULL DEFAULT '{документ} №{номер} — {название}',
    email_body_template text,
    email_default_recipient varchar(320),
    updated_by uuid,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO outbound_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

-- Справочник топиков Telegram-группы: идентификатор топика и понятное название.
CREATE TABLE outbound_telegram_topics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id bigint NOT NULL UNIQUE CHECK (topic_id > 0),
    name varchar(120) NOT NULL CHECK (btrim(name) <> ''),
    sort_order integer NOT NULL
);

-- Первичная настройка получила шаг «Внешняя отправка»: шагов теперь десять.
ALTER TABLE onboarding_draft
    DROP CONSTRAINT onboarding_draft_current_step_check;

ALTER TABLE onboarding_draft
    ADD CONSTRAINT onboarding_draft_current_step_check
    CHECK (current_step BETWEEN 1 AND 10);
