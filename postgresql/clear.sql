BEGIN;

DROP TABLE IF EXISTS users_modules_public;
DROP TABLE IF EXISTS evaluations CASCADE;
DROP TABLE IF EXISTS modules_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS modules_cards CASCADE;
DROP TABLE IF EXISTS cards;
DROP TABLE IF EXISTS modules CASCADE;
DROP TABLE IF EXISTS folders;
DROP TABLE IF EXISTS folder_settings;
DROP TABLE IF EXISTS user_credentials;
DROP TABLE IF EXISTS user_descriptions;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS user_settings;
DROP TABLE IF EXISTS users_modules_evaluations;

DROP FUNCTION IF EXISTS ready_cards(_module_id integer);
DROP FUNCTION IF EXISTS create_card(_user_id integer, _module_id integer, face varchar, back varchar);
DROP FUNCTION IF EXISTS create_user(_login varchar, _password varchar);
DROP FUNCTION IF EXISTS count_owners(_card_id integer);
DROP PROCEDURE IF EXISTS delete_unknown_owner_cards(_module_id integer);
DROP FUNCTION IF EXISTS delete_unlinked_cards();
DROP FUNCTION IF EXISTS check_cycle_parents();

DROP FUNCTION IF EXISTS N();
DROP FUNCTION IF EXISTS randstr(len integer);
DROP FUNCTION IF EXISTS randint(_from integer, until integer);
DROP FUNCTION IF EXISTS ru();
DROP FUNCTION IF EXISTS en();
DROP FUNCTION IF EXISTS ascii_symbols();
DROP FUNCTION IF EXISTS random_utf8_string(length integer, chars text[]);

COMMIT;