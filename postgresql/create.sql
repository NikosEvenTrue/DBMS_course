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

CREATE TABLE user_settings (
	id smallserial primary key,
	interface_language char(5)
);

CREATE TABLE users (
	id serial primary key,
	name varchar(32) NOT NULL
);

CREATE TABLE user_descriptions (
	profile_description varchar(4096),
	user_id integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
	user_settings_id smallint NOT NULL DEFAULT 1 REFERENCES user_settings
);

CREATE TABLE user_credentials (
	login varchar(32) UNIQUE NOT NULL,
	password bytea NOT NULL,
	user_id integer PRIMARY KEY UNIQUE REFERENCES users ON DELETE CASCADE
);

CREATE TABLE folder_settings (
	id smallserial primary key,
	color integer NOT NULL,
	icon_size smallint NOT NULL,
	view smallint NOT NULL
);

CREATE TABLE folders (
	id serial primary key,
	name varchar(32) NOT NULL,
	parent_folder_id integer REFERENCES folders ON DELETE CASCADE DEFAULT NULL,
	user_id integer NOT NULL REFERENCES users ON DELETE CASCADE,
	folder_settings_id smallint NOT NULL DEFAULT 1 REFERENCES folder_settings
);


CREATE TABLE modules (
	id serial primary key,
	name varchar(32) NOT NULL,
	user_id integer REFERENCES users ON DELETE CASCADE,
	folder_id integer REFERENCES folders ON DELETE CASCADE
);

CREATE TABLE cards (
	id serial primary key,
	face varchar(512),
	back varchar(512)
);

CREATE TABLE modules_cards (
    module_id integer REFERENCES modules ON DELETE CASCADE,
	card_id integer REFERENCES cards ON DELETE CASCADE,
	next_repeat_at timestamptz NOT NULL DEFAULT now(),
	last_repeated_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (module_id, card_id)
);

CREATE TABLE tags (
    id serial PRIMARY KEY,
    name varchar(32) NOT NULL UNIQUE
);

CREATE TABLE modules_tags (
    module_id integer REFERENCES modules ON DELETE CASCADE,
    tag_id integer REFERENCES tags,
    PRIMARY KEY (module_id, tag_id)
);

CREATE TABLE evaluations (
    id smallserial PRIMARY KEY,
    name varchar(8) NOT NULL UNIQUE
);

CREATE TABLE users_modules_evaluations (
    id serial PRIMARY KEY,
    user_id integer REFERENCES users ON DELETE SET NULL,
    module_id integer REFERENCES modules ON DELETE CASCADE,
    comment varchar(216),
    evaluation_id smallint REFERENCES evaluations
);

CREATE OR REPLACE FUNCTION ready_cards(_module_id integer)
RETURNS TABLE(id integer, face varchar, back varchar)
LANGUAGE SQL AS $$
    SELECT cards.id, face, back FROM cards
    JOIN modules_cards mc ON cards.id = mc.card_id
    WHERE mc.next_repeat_at < now() AND mc.module_id = _module_id
    ORDER BY mc.last_repeated_at DESC;
$$;

CREATE OR REPLACE FUNCTION create_card(_user_id integer, _module_id integer,
		face varchar, back varchar)
RETURNS integer
LANGUAGE PLPGSQL AS $$
	DECLARE
		_card_id integer;
	BEGIN
		INSERT INTO cards(face, back) VALUES (face, back) RETURNING id INTO _card_id;
        INSERT INTO modules_cards(card_id, module_id, next_repeat_at, last_repeated_at)
            VALUES (_card_id, _module_id, now(), now());
		RETURN _card_id;
	END;
$$;

CREATE OR REPLACE FUNCTION create_user(_login varchar, _password bytea)
RETURNS integer
LANGUAGE PLPGSQL AS $$
    DECLARE
		_user_id integer;
    BEGIN
        INSERT INTO users(name) VALUES (_login) RETURNING id INTO _user_id;
        INSERT INTO user_descriptions(user_id) VALUES (_user_id);
        INSERT INTO user_credentials(login, password, user_id) VALUES (_login, _password, _user_id);
        RETURN _user_id;
    END;
$$;

CREATE OR REPLACE FUNCTION count_owners(_card_id integer)
RETURNS integer
LANGUAGE SQL AS $$
        SELECT COUNT(DISTINCT module_id) FROM modules_cards WHERE card_id = _card_id;
$$;

CREATE OR REPLACE PROCEDURE delete_unknown_owner_cards(_module_id integer)
LANGUAGE SQL AS $$
    DELETE FROM cards
    WHERE id IN (
        SELECT cards.id FROM cards
        JOIN modules_cards mc on cards.id = mc.card_id
        WHERE module_id = _module_id
        )
    AND count_owners(id) = 0;
$$;

CREATE OR REPLACE FUNCTION delete_unlinked_cards()
RETURNS trigger
LANGUAGE PLPGSQL AS $$
    BEGIN
        CALL delete_unknown_owner_cards(OLD.id);
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE TRIGGER on_module_delete
    AFTER DELETE ON modules
    FOR EACH ROW
    EXECUTE FUNCTION delete_unlinked_cards();

CREATE OR REPLACE FUNCTION check_cycle_parents()
RETURNS trigger
LANGUAGE PLPGSQL AS $$
    DECLARE
        folder_id integer;
    BEGIN
        IF NEW.id = NEW.parent_folder_id THEN
            RAISE EXCEPTION 'the folder(id = %) can''t be a parent(id = %) of itself', NEW.id, NEW.parent_folder_id;
        END IF;
        FOR folder_id IN
            SELECT id FROM folders
            WHERE parent_folder_id = OLD.id
        LOOP
            UPDATE folders SET parent_folder_id = OLD.parent_folder_id WHERE id = folder_id;
        END LOOP;
        RETURN NEW;
    END;
$$;

CREATE OR REPLACE TRIGGER on_folder_insert_or_update
    BEFORE INSERT OR UPDATE OF parent_folder_id ON folders
    FOR EACH ROW
    WHEN (pg_trigger_depth() = 0)
    EXECUTE FUNCTION check_cycle_parents();

CREATE OR REPLACE VIEW users_cards AS
SELECT
    users.id AS user_id,
    users.name AS user,
    modules.id AS module_id,
    modules.name AS module,
    cards.id AS card_id,
    cards.face,
    cards.back,
    mc.next_repeat_at,
    mc.last_repeated_at
FROM users
JOIN modules ON users.id = modules.user_id
JOIN modules_cards mc ON modules.id = mc.module_id
JOIN cards ON mc.card_id = cards.id;

CREATE INDEX folders_user_id_btree ON folders(user_id);
CREATE INDEX folders_parent_folder_id_btree ON folders USING hash(parent_folder_id);
CREATE INDEX modules_user_id_btree ON modules(user_id);
CREATE INDEX modules_cards_card_id_hash ON modules_cards(card_id);
CREATE INDEX users_modules_evaluations_module_id_user_id_btree
    ON users_modules_evaluations(module_id, user_id);
CREATE INDEX users_modules_evaluations_user_id_btree ON users_modules_evaluations(user_id);
CREATE INDEX modules_tags_tag_id_btree ON modules_tags(tag_id);
CREATE INDEX tags_name_btree ON tags(name varchar_pattern_ops);
COMMIT;
