BEGIN;

CREATE TABLE user_settings (
	id serial primary key,
	interface_language char(5)
);

INSERT INTO user_settings(interface_language) VALUES ('EN-en'), ('RU-ru');

CREATE TABLE users (
	id serial primary key,
	name varchar(32) NOT NULL
);

INSERT INTO users(id, name) VALUES (0, 'public');

-- bind user_id, create trigger
CREATE TABLE user_descriptions (
	id serial primary key,
	profile_description varchar(4096),
	user_id integer REFERENCES users,
	user_settings_id integer NOT NULL DEFAULT 1 REFERENCES user_settings
);

CREATE TABLE user_credentionals (
	id serial primary key,
	login varchar(32) UNIQUE NOT NULL,
	password varchar(128) NOT NULL,
	token varchar(128),
	user_info_id integer UNIQUE REFERENCES users
);


CREATE TABLE folder_settings (
	id serial primary key,
	color integer NOT NULL,
	icon_size smallint NOT NULL,
	viev smallint NOT NULL
);

INSERT INTO folder_settings(color, icon_size, viev)
VALUES (0, 16, 1);

-- can't have cycle links, create a trigger
-- only one owner of folder, create trigger
-- it isn't many-to-many rather it's one to one, one parent to one child folder, change flow-chart
-- folder settings is one to many, change flow-chart
CREATE TABLE folders (
	id serial primary key,
	name varchar(32) NOT NULL,
	parent_folder integer REFERENCES folders,
	owner integer NOT NULL REFERENCES users,
	folder_settings_id integer NOT NULL DEFAULT 1 REFERENCES folder_settings
);

INSERT INTO folders(name, parent_folder, owner)
VALUES ('all', NULL, 0), ('b1_book', 1, 0), ('youtube', 1, 0),
('program languages', 1, 0), ('python', 4, 0);

CREATE TABLE modules (
	id serial primary key,
	name varchar(32) NOT NULL,
	user_id integer REFERENCES users
);

CREATE TABLE folders_modules (
	folder_id integer REFERENCES folders,
	module_id integer REFERENCES modules,
	PRIMARY KEY (folder_id, module_id)
);

CREATE TABLE modules_users (
	module_id integer REFERENCES modules,
	user_id integer REFERENCES users,
	liked integer DEFAULT 0,
	disliked integer DEFAULT 0,
	followed integer DEFAULT 0,
	PRIMARY KEY (module_id, user_id)
);

CREATE TABLE cards (
	id serial primary key,
	face varchar(512),
	back varchar(512)
);

CREATE TABLE cards_modules (
	card_id integer REFERENCES cards,
	module_id integer REFERENCES modules,
	PRIMARY KEY (card_id, module_id)
);

CREATE TABLE cards_users_expirations (
	id serial primary key,
	next_repeat_at timestamptz NOT NULL,
	last_repeated_at timestamptz NOT NULL,
	card_id integer NOT NULL REFERENCES cards,
	user_id integer NOT NULL REFERENCES users
);

CREATE OR REPLACE FUNCTION ready_cards(_user_id integer, _module_id integer)
RETURNS TABLE(id integer, face varchar, back varchar)
LANGUAGE SQL AS $$
SELECT cards.id, face, back FROM cards
JOIN cards_users_expirations ON cards.id = cards_users_expirations.card_id
WHERE cards.id IN (
	SELECT card_id FROM cards_users_expirations
	WHERE 
		next_repeat_at < now() AND
		user_id = _user_id AND
		card_id IN (SELECT card_id FROM cards_modules 
					WHERE module_id = _module_id))
ORDER BY last_repeated_at DESC;
$$;



CREATE OR REPLACE FUNCTION create_card(_user_id integer, _module_id integer,
		face varchar, back varchar)
RETURNS integer
LANGUAGE PLPGSQL AS $$
	DECLARE
		_card_id integer = nextval('cards_id_seq');
	BEGIN
		INSERT INTO cards(id ,face, back) VALUES (_card_id, face, back);
		INSERT INTO cards_modules(card_id, module_id) VALUES (_card_id, _module_id);
		INSERT INTO cards_users_expirations(next_repeat_at, last_repeated_at, card_id, user_id)
		VALUES (now(), now(), _card_id, _user_id);
		RETURN _card_id;
	END;
$$;



CREATE OR REPLACE PROCEDURE update_card(_user_id integer, _module_id integer, _card_id integer,
	_face varchar, _back varchar)
LANGUAGE PLPGSQL AS $$
	DECLARE
		_new_card_id integer;
	BEGIN
		IF (SELECT count(*) FROM cards_modules WHERE card_id = _card_id) > 1 THEN
			_new_card_id = (SELECT create_card(_user_id, _module_id, _face, _back));
			UPDATE cards_modules SET card_id = _new_card_id WHERE card_id = _card_id 
				AND module_id = _module_id;
			UPDATE cards_users_expirations SET card_id = _new_card_id WHERE card_id = _card_id
				AND user_id = _user_id;
		ELSE
			UPDATE cards SET face = _face, back = _back WHERE id = _card_id;
		END IF;
	END;
$$;

CREATE OR REPLACE VIEW users_cards AS
SELECT
    users.id AS user_id,
    users.name AS user,
    modules.id AS module_id,
    modules.name AS module,
    cards.id AS card_id,
    cards.face,
    cards.back,
    cue.next_repeat_at,
    cue.last_repeated_at
FROM users
JOIN modules ON users.id = modules.user_id
JOIN cards_modules ON modules.id = cards_modules.module_id
JOIN cards ON cards_modules.card_id = cards.id
JOIN cards_users_expirations cue ON cards.id = cue.card_id AND users.id = cue.user_id;

-- CREATE OR REPLACE PROCEDURE delete_card(_user_id integer)
COMMIT;