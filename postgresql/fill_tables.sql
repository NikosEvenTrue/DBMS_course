BEGIN;

INSERT INTO users(name) VALUES ('nik'), ('roma');
INSERT INTO user_descriptions (user_id) VALUES (1), (2);
INSERT INTO user_credentionals(login, password, user_info_id)
VALUES ('nik', 'kek', 1), ('roma', 'lol', 2);

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

COMMIT;