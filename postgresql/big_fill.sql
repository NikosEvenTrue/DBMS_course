BEGIN;

CREATE OR REPLACE FUNCTION randstr(len integer)
RETURNS varchar
LANGUAGE SQL AS $$
    SELECT left(md5(random()::text), len)
$$;

CREATE OR REPLACE FUNCTION randint(_from integer, until integer)
RETURNS integer
LANGUAGE SQL AS $$
    SELECT (random() * (until - _from))::int + _from;
$$;

CREATE OR REPLACE FUNCTION N()
RETURNS integer
LANGUAGE SQL AS $$
    SELECT 1000000;
$$;

CREATE OR REPLACE FUNCTION ru()
RETURNS text[] AS $$
DECLARE
    chars_ru text[] := array['А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ё', 'Ж', 'З', 'И', 'Й', 'К', 'Л', 'М', 'Н', 'О', 'П', 'Р', 'С', 'Т', 'У', 'Ф', 'Х', 'Ц', 'Ч', 'Ш', 'Щ', 'Ъ', 'Ы', 'Ь', 'Э', 'Ю', 'Я', 'а', 'б', 'в', 'г', 'д', 'е', 'ё', 'ж', 'з', 'и', 'й', 'к', 'л', 'м', 'н', 'о', 'п', 'р', 'с', 'т', 'у', 'ф', 'х', 'ц', 'ч', 'ш', 'щ', 'ъ', 'ы', 'ь', 'э', 'ю', 'я'];
BEGIN
    RETURN chars_ru;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION en()
RETURNS text[] AS $$
DECLARE
    chars_en text[] := array['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'];
BEGIN
    RETURN chars_en;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ascii_symbols()
RETURNS text[] AS $$
DECLARE
    chars_ru text[] := array[' ', '!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'];
BEGIN
    RETURN chars_ru;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION random_utf8_string(length integer, chars text[])
  RETURNS text AS
$BODY$
DECLARE
    i integer;
    random_int integer;
    result text;
BEGIN
    result := '';
    FOR i IN 1..length LOOP
        random_int := (randint(1, array_length(chars, 1)))::integer;
        result := result || chars[random_int];
    END LOOP;
    RETURN result;
END
$BODY$
    LANGUAGE plpgsql;


SELECT create_user((gs.generate_series + 2)::varchar,
    sha256(((gs.generate_series + 2)::text||:salt)::bytea))
FROM (
    SELECT generate_series(1, N() / 10)
     ) as gs;

INSERT INTO folders(user_id, name)
SELECT randint(1, N() / 10), randstr(randint(0, 32))
FROM generate_series(1, N())
order by random ();

INSERT INTO modules (user_id, name)
SELECT randint(1, N() / 10), randstr(randint(0, 32))
FROM generate_series(1, N())
order by random ();

SELECT create_card(randint(1, N() / 10), randint(1, N()),
    randstr(randint(1,128)), randstr(randint(1, 128)))
FROM (
    SELECT generate_series(1, N())
     ) as gs;

INSERT INTO modules_cards (module_id, card_id)
SELECT randint(1, N()), randint(1, N())
FROM generate_series(1, N() * 3)
order by random ()
ON CONFLICT DO NOTHING;

INSERT INTO tags (name)
SELECT name FROM
    (WITH vars AS (select ru() as chars)
    SELECT random_utf8_string(randint(5, 16), vars.chars) as name
    FROM generate_series(1, N()), vars) as _
ON CONFLICT DO NOTHING;

INSERT INTO tags (name)
SELECT name FROM
    (WITH vars AS (select en() as chars)
    SELECT random_utf8_string(randint(5, 32), vars.chars) as name
    FROM generate_series(1, N()), vars) as _
ON CONFLICT DO NOTHING;

INSERT INTO tags (name)
SELECT name FROM
    (WITH vars AS (select array_cat(ru(), en()) as chars)
    SELECT random_utf8_string(randint(5, 32), vars.chars) as name
    FROM generate_series(1, N()), vars) as _
ON CONFLICT DO NOTHING;

WITH rnd AS (
  SELECT module_id, tag_id
  FROM (
    SELECT randint(1, N()) AS module_id,
           randint(1, (SELECT max(id) FROM tags)) AS tag_id
    FROM generate_series(1, N())
  ) AS x
  WHERE tag_id IN (SELECT id FROM tags)
)
INSERT INTO modules_tags (module_id, tag_id)
SELECT module_id, tag_id
FROM rnd
ON CONFLICT DO NOTHING;

INSERT INTO users_modules_evaluations (user_id, module_id, comment, evaluation_id)
SELECT randint(1, N() / 10), randint(1, N()),
       randstr(randint(0, 216)), randint(1, 3)
FROM generate_series(1, N() * 3)
ON CONFLICT DO NOTHING;

COMMIT;