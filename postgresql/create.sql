BEGIN;
SET search_path TO flash_cards_repeat_system;

CREATE TABLE user_settings (
	id serial primary key,
	interface_language char(5)
);

INSERT INTO user_settings(interface_language) VALUES ('EN-en'), ('RU-ru');

CREATE TABLE users (
	id serial primary key,
	name varchar(32) NOT NULL
);

CREATE TABLE user_descriptions (
	profile_description varchar(4096),
	user_id integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
	user_settings_id integer NOT NULL DEFAULT 1 REFERENCES user_settings
);

CREATE TABLE user_credentials (
	id serial primary key,
	login varchar(32) UNIQUE NOT NULL,
	password varchar(128) NOT NULL,
	user_id integer UNIQUE REFERENCES users ON DELETE CASCADE
);


CREATE TABLE folder_settings (
	id serial primary key,
	color integer NOT NULL,
	icon_size smallint NOT NULL,
	viev smallint NOT NULL
);

INSERT INTO folder_settings(color, icon_size, viev)
VALUES (0, 16, 1), (1, 10, 2);

-- can't have cycle links, create a trigger
CREATE TABLE folders (
	id serial primary key,
	name varchar(32) NOT NULL,
	parent_folder_id integer REFERENCES folders ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users ON DELETE CASCADE,
	folder_settings_id integer NOT NULL DEFAULT 1 REFERENCES folder_settings
);

CREATE TABLE modules (
	id serial primary key,
	name varchar(32) NOT NULL,
	user_id integer REFERENCES users ON DELETE CASCADE,
	folder_id integer REFERENCES folders ON DELETE CASCADE
-- 	,author_id integer REFERENCES users ON DELETE SET NULL
);

CREATE TABLE module_public_info (
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

CREATE TABLE modules_cards (
    module_id integer REFERENCES modules ON DELETE CASCADE,
	card_id integer REFERENCES cards ON DELETE CASCADE,
	PRIMARY KEY (card_id, module_id)
);

CREATE TABLE cards_users_expirations (
	id serial primary key,
	next_repeat_at timestamptz NOT NULL,
	last_repeated_at timestamptz NOT NULL,
	card_id integer NOT NULL REFERENCES cards ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users ON DELETE CASCADE
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
		card_id IN (SELECT card_id FROM modules_cards
					WHERE module_id = _module_id))
ORDER BY last_repeated_at DESC;
$$;

CREATE OR REPLACE FUNCTION create_card(_user_id integer, _module_id integer,
		face varchar, back varchar)
RETURNS integer
LANGUAGE PLPGSQL AS $$
	DECLARE
		_card_id integer = nextval('flash_cards_repeat_system.cards_id_seq');
	BEGIN
		INSERT INTO cards(id ,face, back) VALUES (_card_id, face, back);
		INSERT INTO modules_cards(card_id, module_id) VALUES (_card_id, _module_id);
		INSERT INTO cards_users_expirations(next_repeat_at, last_repeated_at, card_id, user_id)
		VALUES (now(), now(), _card_id, _user_id);
		RETURN _card_id;
	END;
$$;

CREATE OR REPLACE FUNCTION copy_card(_user_id integer, _module_id integer, _card_id integer)
RETURNS integer
LANGUAGE  PLPGSQL AS $$
    BEGIN
       INSERT INTO modules_cards VALUES (_module_id, _card_id);
       INSERT INTO cards_users_expirations(next_repeat_at, last_repeated_at, card_id, user_id)
        VALUES (now(), now(), _card_id, _user_id);
       RETURN _card_id;
    END;
$$;

CREATE OR REPLACE FUNCTION count_owners(_card_id integer)
RETURNS integer
LANGUAGE SQL AS $$
        SELECT COUNT(DISTINCT user_id) FROM modules_cards
            JOIN modules ON modules.id = module_id WHERE card_id = _card_id;
$$;

CREATE OR REPLACE PROCEDURE update_card(_user_id integer, _module_id integer, _card_id integer,
	_face varchar, _back varchar)
LANGUAGE PLPGSQL AS $$
	DECLARE
		_new_card_id integer;
	BEGIN
		IF count_owners(_card_id) = 1 THEN
		    UPDATE cards SET face = _face, back = _back WHERE id = _card_id;
		ELSE
			_new_card_id = (SELECT create_card(_user_id, _module_id, _face, _back));
			UPDATE modules_cards SET card_id = _new_card_id WHERE card_id = _card_id
				AND module_id = _module_id;
			UPDATE cards_users_expirations SET card_id = _new_card_id WHERE card_id = _card_id
				AND user_id = _user_id;
		END IF;
	END;
$$;

CREATE OR REPLACE FUNCTION create_user(_login varchar, _password varchar)
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

CREATE OR REPLACE PROCEDURE delete_unknown_owner_cards()
LANGUAGE SQL AS $$
    DELETE FROM cards WHERE count_owners(id) = 0;
$$;

CREATE OR REPLACE FUNCTION delete_unlinked_cards()
RETURNS trigger
LANGUAGE PLPGSQL AS $$
    BEGIN
        CALL delete_unknown_owner_cards();
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
            RAISE NOTICE 'the folder(id = %) can''t be a parent(id = %) of itself', NEW.id, NEW.parent_folder_id;
            RETURN null;
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
    cue.next_repeat_at,
    cue.last_repeated_at
FROM users
JOIN modules ON users.id = modules.user_id
JOIN modules_cards ON modules.id = modules_cards.module_id
JOIN cards ON modules_cards.card_id = cards.id
JOIN cards_users_expirations cue ON cards.id = cue.card_id AND users.id = cue.user_id;

COMMIT;

