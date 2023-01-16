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

