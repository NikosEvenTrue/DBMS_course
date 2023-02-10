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

SELECT create_user((gs.generate_series + 2)::varchar, randstr(randint(0, 32)))
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
FROM generate_series(1, N() * 10)
order by random ()
ON CONFLICT DO NOTHING;

INSERT INTO tags (name)
SELECT randstr(randint(5, 32))
FROM generate_series(1, N())
order by random ()
ON CONFLICT DO NOTHING;

WITH vars (t_id) as (values(randint(1, N())))
INSERT INTO modules_tags(module_id, tag_id)
SELECT randint(1, N()), t_id
FROM generate_series(1, N()), vars
WHERE EXISTS(SELECT id FROM tags WHERE id = t_id)
order by random()
ON CONFLICT DO NOTHING;

INSERT INTO users_modules_evaluations (user_id, module_id, comment, evaluation_id)
SELECT randint(1, N() / 10), randint(1, N()),
       randstr(randint(0, 216)), randint(1, 3)
FROM generate_series(1, N() * 10)
ON CONFLICT DO NOTHING;