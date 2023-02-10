BEGIN;
INSERT INTO user_settings(interface_language) VALUES ('EN-en'), ('RU-ru');
INSERT INTO folder_settings(color, icon_size, viev)
VALUES (0, 16, 1), (1, 10, 2);
INSERT INTO tags(name) VALUES ('food'), ('pets'), ('youtube'), ('prog lang'), ('python');
INSERT INTO evaluations(name) VALUES ('liked'), ('disliked'), ('empty');

SELECT create_user('nik', 'admin');
SELECT create_user('roma', 'user');

INSERT INTO folders(name, parent_folder_id, user_id) VALUES
('univercity', null, 1), ('unit1', 1, 1), ('exam', 1, 1), ('A5', 2, 1), ('A4', 2, 1),
('roma-folder', null, 2);

INSERT INTO modules(name, user_id, folder_id) VALUES
('eng_b1', 1, 1), ('eng_b1', 2, null), ('general', 1, null), ('second', 2, null);

SELECT create_card(1, 1, 'cat', 'kot');
SELECT create_card(1, 1, 'dog', 'sobaka');
SELECT create_card(1, 1, 'chicken', 'kurica');

SELECT create_card(2, 2, 'cat22', 'kot22');
SELECT create_card(2, 2, 'dog22', 'sobaka22');
SELECT create_card(2, 2, 'chicken22', 'kurica22');

SELECT copy_card(2, 2, 1);

INSERT INTO modules_tags VALUES (2, 1);
INSERT INTO modules_tags VALUES (2, 2);

INSERT INTO users_modules_public(user_id, module_id, evaluation_id, comment)
VALUES (1, 2, 1, 'brilliant module');

COMMIT;