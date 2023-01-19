BEGIN;
SET search_path TO flash_cards_repeat_system;

SELECT create_user('nik', 'kek');
SELECT create_user('roma', 'lol');

INSERT INTO folders(name, parent_folder, owner) VALUES
('univercity', NULL, 1), ('unit1', 1, 1), ('exam', 1, 1);

INSERT INTO modules(name, user_id) VALUES
('eng_b1', 1), ('eng_b1', 2);

SELECT create_card(1, 1, 'cat', 'kot');
SELECT create_card(1, 1, 'dog', 'sobaka');
SELECT create_card(1, 1, 'chicken', 'kurica');

SELECT create_card(2, 2, 'cat22', 'kot22');
SELECT create_card(2, 2, 'dog22', 'sobaka22');
SELECT create_card(2, 2, 'chicken22', 'kurica22');

INSERT INTO cards_modules VALUES (1, 2);

COMMIT;