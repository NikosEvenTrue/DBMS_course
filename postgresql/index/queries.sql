-- signin
SELECT user_credentials.login AS user_credentials_login, user_credentials.password AS user_credentials_password, user_credentials.user_id AS user_credentials_user_id
FROM user_credentials
WHERE user_credentials.login = 'nik';

-- create card
SELECT user_credentials.login AS user_credentials_login, user_credentials.password AS user_credentials_password, user_credentials.user_id AS user_credentials_user_id
FROM user_credentials
WHERE user_credentials.user_id = %(user_id_1)s

SELECT users.id AS users_id, users.name AS users_name
FROM users
WHERE users.id = %(pk_1)s

SELECT modules.id AS modules_id, modules.name AS modules_name, modules.user_id AS modules_user_id, modules.folder_id AS modules_folder_id
FROM modules
WHERE modules.id = %(pk_1)s

SELECT modules_tags.module_id AS modules_tags_module_id, modules_tags.tag_id AS modules_tags_tag_id
FROM modules_tags
WHERE modules_tags.module_id = %(module_id_1)s
 LIMIT %(param_1)s

SELECT create_card(%(create_card_2)s, %(create_card_3)s, %(create_card_4)s, %(create_card_5)s) AS create_card_1
 LIMIT %(param_1)s

SELECT cards.id AS cards_id, cards.face AS cards_face, cards.back AS cards_back
FROM cards
WHERE cards.id = %(pk_1)s

EXPLAIN ANALYSE
INSERT INTO cards(face, back) VALUES ('face', 'back');

EXPLAIN ANALYSE
INSERT INTO modules_cards(card_id, module_id, next_repeat_at, last_repeated_at)
            VALUES (1021, 2, now(), now());

SELECT * FROM user_settings;

SELECT * FROM folder_settings;

SELECT * FROM evaluations;

SELECT * FROM folders WHERE user_id = 1;

UPDATE folders SET parent_folder_id = 5 WHERE id = 1;