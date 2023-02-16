-- tables size
select table_name, pg_size_pretty(pg_relation_size(quote_ident(table_name)))
from information_schema.tables
where table_schema = 's265074'
order by 2;

-- check datav
SELECT index, rows, pg_size_pretty(avg(size)::bigint) as size, avg(cost) as cost, avg(plan) as plan, avg(exec) as exec
            FROM data WHERE rows BETWEEN 0 AND 100000000 AND
                            at BETWEEN '2023-02-08 13:20:39+3'::timestamptz AND '2023-02-19 13:30:39+3'::timestamptz
                      GROUP BY index, rows order by rows, avg(size);

SELECT index, rows, pg_size_pretty(avg(size)::bigint) as size, AVGNOOUT(cost) as cost, AVGNOOUT(plan) as plan, AVGNOOUT(exec) as exec
            FROM data WHERE rows BETWEEN 0 AND 100000000 AND
                            at BETWEEN '2023-02-08 13:20:39+3'::timestamptz AND '2023-02-19 13:30:39+3'::timestamptz
                      GROUP BY index, rows order by rows, avg(size);

SELECT rows, count(*) FROM data GROUP BY rows;
SELECT count(*) FROM users_modules_evaluations;

-- AVNNOOUT
DROP FUNCTION Q(real[]);
DROP TYPE Qs;
DROP AGGREGATE avgnoout(real);
DROP FUNCTION avgnoout_func(real[]);


CREATE TYPE Qs AS
(
    Q2 double precision,
    Q1 double precision,
    Q3 double precision
);

CREATE OR REPLACE FUNCTION Q(nums real[])
  RETURNS Qs AS
$$
    SELECT
        asorted[ceiling(array_upper(asorted, 1) / 2.0)],
        asorted[trunc(array_upper(asorted, 1) / 4.0)],
        asorted[trunc(array_upper(asorted, 1) / 4.0 * 3.0)]
    FROM (SELECT ARRAY(SELECT (nums)[n] FROM
generate_series(1, array_upper(nums, 1)) AS n
    WHERE (nums)[n] IS NOT NULL
            ORDER BY (nums)[n]
) As asorted) As foo ;
$$
  LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION AVGNOOUT_func(nums real[])
RETURNS real
LANGUAGE plpgsql AS $$
    DECLARE
        low double precision = (SELECT Q1 - (Q3 - Q1) * 1.5 as low FROM
            (SELECT (Q(nums)).*) as _1);
        high double precision = (SELECT Q3 + (Q3 - Q1) * 1.5 as high FROM
            (SELECT (Q(nums)).*) as _1);
    BEGIN
        RETURN (SELECT AVG(filtred) FROM unnest(ARRAY(SELECT (nums)[n] FROM
            generate_series(1, array_upper(nums, 1)) AS n
                WHERE (nums)[n] BETWEEN low and high)) as filtred);
    END;
$$;

CREATE AGGREGATE AVGNOOUT(real) (
  SFUNC=array_append,
  STYPE=real[],
  FINALFUNC=AVGNOOUT_func
);

-- check big_data filled
SELECT count(*) FROM users;
SELECT count(*) FROM user_credentials;
SELECT count(*) FROM user_descriptions;
SELECT count(*) FROM folders;
SELECT count(*) FROM modules;
SELECT count(*) FROM cards;
SELECT count(*) FROM modules_cards;
SELECT count(*) FROM tags;
SELECT count(*) FROM modules_tags;
SELECT count(*) FROM users_modules_evaluations;

SELECT count(*) FROM user_settings;
SELECT count(*) FROM folder_settings;
SELECT count(*) FROM evaluations;

-- user_credentials
EXPLAIN ANALYSE
SELECT * FROM user_credentials
WHERE user_credentials.login = 'nik'
LIMIT 1;
    -- already exists due UNIQUE CONSTRAINT
-- users
EXPLAIN ANALYSE
SELECT * FROM users
WHERE users.id = 1;
    -- already exists due PRIMARY KEY
-- user_descriptions
EXPLAIN ANALYSE
SELECT *  FROM user_descriptions
WHERE user_descriptions.user_id = 1
LIMIT 1;
-- delete user
    -- folders

DROP INDEX  folders_user_id_btree;
CREATE INDEX folders_user_id_btree ON folders(user_id);
SELECT pg_size_pretty (pg_table_size('folders_user_id_btree'));

DROP INDEX  folders_user_id_hash;
CREATE INDEX folders_user_id_hash ON folders USING hash(user_id);
SELECT pg_size_pretty (pg_table_size('folders_user_id_hash'));

vacuum analyse folders;

EXPLAIN
DELETE FROM folders WHERE user_id = 101;

EXPLAIN
SELECT * FROM folders WHERE user_id = 101;

    -- modules

DROP INDEX  modules_user_id_btree;
CREATE INDEX modules_user_id_btree ON modules(user_id);
SELECT pg_size_pretty (pg_table_size('modules_user_id_btree'));

DROP INDEX  modules_user_id_hash;
CREATE INDEX modules_user_id_hash ON modules USING hash(user_id);
SELECT pg_size_pretty (pg_table_size('modules_user_id_hash'));

vacuum analyse modules;

EXPLAIN
DELETE FROM modules WHERE user_id = 101;

    -- modules_cards
DROP INDEX modules_cards_module_id_btree;
CREATE INDEX modules_cards_module_id_btree ON modules_cards(module_id);
SELECT pg_size_pretty (pg_table_size('modules_cards_module_id_btree'));

DROP INDEX modules_cards_module_id_hash;
CREATE INDEX modules_cards_module_id_hash ON modules_cards USING hash(module_id);
SELECT pg_size_pretty (pg_table_size('modules_cards_module_id_hash'));

vacuum analyse users_modules_evaluations;

EXPLAIN
DELETE FROM modules_cards WHERE module_id = 101;

    -- trigger on module delete

EXPLAIN
SELECT COUNT(DISTINCT module_id) FROM modules_cards WHERE card_id = 21312;
        -- already exists PK

EXPLAIN ANALYSE
DELETE FROM cards
WHERE id IN (
    SELECT cards.id FROM cards
    JOIN modules_cards mc on cards.id = mc.card_id
    WHERE module_id = 1
    )
AND count_owners(id) = 0;
        -- created modules_cards_module_id_hash

    -- users_modules_evaluations
DROP INDEX users_modules_evaluations_user_id_btree;
CREATE INDEX users_modules_evaluations_user_id_btree ON users_modules_evaluations(user_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_user_id_btree'));

DROP INDEX users_modules_evaluations_user_id_hash;
CREATE INDEX users_modules_evaluations_user_id_hash ON users_modules_evaluations USING hash(user_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_user_id_hash'));

vacuum analyse users_modules_evaluations;

EXPLAIN
UPDATE users_modules_evaluations SET user_id = NULL
WHERE user_id = 3123;


DROP INDEX users_modules_evaluations_module_id_btree;
CREATE INDEX users_modules_evaluations_module_id_btree ON users_modules_evaluations(module_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_btree'));

DROP INDEX users_modules_evaluations_module_id_hash;
CREATE INDEX users_modules_evaluations_module_id_hash ON users_modules_evaluations USING hash(module_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_hash'));

vacuum analyse users_modules_evaluations;

EXPLAIN
DELETE FROM users_modules_evaluations WHERE module_id = 3123;

EXPLAIN
SELECT * FROM users_modules_evaluations WHERE module_id = 3123;

DROP INDEX users_modules_evaluations_user_id_module_id_btree;
CREATE INDEX users_modules_evaluations_user_id_module_id_btree ON users_modules_evaluations(user_id, module_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_user_id_module_id_btree'));

DROP INDEX users_modules_evaluations_module_id_user_id_btree;
CREATE INDEX users_modules_evaluations_module_id_user_id_btree ON users_modules_evaluations(module_id, user_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_user_id_btree'));


vacuum analyse users_modules_evaluations;


EXPLAIN
SELECT * FROM users_modules_evaluations
WHERE user_id = 31413 AND module_id = 12312
LIMIT 1;


    -- modules_tags

EXPLAIN
DELETE FROM modules_tags WHERE module_id = 323;
        -- already exists PK

EXPLAIN
SELECT * FROM modules_tags WHERE module_id = 323 LIMIT 1;

-- folders

EXPLAIN ANALYSE
SELECT * FROM folders WHERE user_id = 102;
    -- already created "folders_user_id_btree"

EXPLAIN
DELETE FROM folders WHERE id = 1000007;
    -- already exists PK

DROP INDEX folders_parent_folder_id_btree;
CREATE INDEX folders_parent_folder_id_btree ON folders(parent_folder_id);
SELECT pg_size_pretty (pg_table_size('folders_parent_folder_id_btree'));

DROP INDEX folders_parent_folder_id_hash;
CREATE INDEX folders_parent_folder_id_hash ON folders USING hash(parent_folder_id);
SELECT pg_size_pretty (pg_table_size('folders_parent_folder_id_hash'));

vacuum analyse folders;

EXPLAIN ANALYSE
SELECT id FROM folders WHERE parent_folder_id = 2;

EXPLAIN
DELETE FROM folders WHERE parent_folder_id = 101002;
    -- already createdfolders_parent_folder_id_btree
-- modules
EXPLAIN ANALYSE
SELECT * FROM modules
WHERE modules.user_id = 12312;

    -- already created modules_user_id_btree
EXPLAIN ANALYSE
SELECT * FROM modules_tags WHERE module_id = 1048 LIMIT 1;
    -- already created modules_tags_pkey

-- tags
EXPLAIN ANALYSE
SELECT * FROM tags
WHERE tags.name IN ('python', 'new');
    -- already exists tags_name_key UNIQUE

EXPLAIN ANALYSE
SELECT tags.*
FROM tags JOIN modules_tags ON tags.id = modules_tags.tag_id
WHERE modules_tags.module_id = 1046;
    -- already exists modules_tags_pkey PK
-- users_modules_evaluations
EXPLAIN ANALYSE
SELECT * FROM users_modules_evaluations
WHERE user_id = 102 AND users_modules_evaluations.module_id = 2
LIMIT 1;
    -- already created users_modules_evaluations_module_id_btree
    -- already created users_modules_evaluations_user_id_btree
-- cards
EXPLAIN ANALYSE
SELECT c.id, c.face, c.back, mc.next_repeat_at, mc.last_repeated_at
FROM cards c JOIN modules_cards mc ON c.id = mc.card_id
WHERE mc.module_id = 1048;
    -- already created modules_cards_module_id_hash
    -- already exists cards_pkey PK
--

-- search?tag=<tag_name>
SELECT
    tags.id,
    tags.name,
    (SELECT count(*) FROM modules_tags
        WHERE tag_id = tags.id) as count
FROM tags
WHERE id IN (
    SELECT id
    FROM tags
          JOIN modules_tags ON id = tag_id
    GROUP BY id
    ORDER BY count(*) DESC
    LIMIT 10
);

DROP INDEX  modules_tags_tag_id_btree;
CREATE INDEX modules_tags_tag_id_btree ON modules_tags(tag_id);
SELECT pg_size_pretty (pg_table_size('modules_tags_tag_id_btree'));

DROP INDEX  modules_tags_tag_id_hash;
CREATE INDEX modules_tags_tag_id_hash ON modules_tags USING hash(tag_id);
SELECT pg_size_pretty (pg_table_size('modules_tags_tag_id_hash'));

EXPLAIN ANALYSE
SELECT modules.id AS modules_id, modules.name AS modules_name, modules.user_id AS modules_user_id, modules.folder_id AS modules_folder_id
FROM modules JOIN modules_tags ON modules.id = modules_tags.module_id JOIN tags ON tags.id = modules_tags.tag_id
WHERE tags.name = 'food';

-- get public info
SELECT
    (SELECT user_id FROM modules m
        WHERE m.id = module_id) AS user_id,
    module_id,
    count(*)
FROM users_modules_evaluations ume
GROUP BY module_id
ORDER BY count(*) DESC
LIMIT 10;

DROP INDEX users_modules_evaluations_module_id_btree;
CREATE INDEX users_modules_evaluations_module_id_btree ON users_modules_evaluations(module_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_btree'));

DROP INDEX users_modules_evaluations_module_id_hash;
CREATE INDEX users_modules_evaluations_module_id_hash ON users_modules_evaluations USING hash(module_id);
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_hash'));

vacuum analyse users_modules_evaluations;

EXPLAIN ANALYSE
WITH vars (r) as (values(randint(N() - 1) + 1))
SELECT ume.id, ume.user_id, ume.module_id, ume.comment, ume.evaluation_id
FROM users_modules_evaluations ume, vars
WHERE ume.module_id = r;

EXPLAIN ANALYSE
WITH vars (r) as (values(randint(N() - 1) + 1))
DELETE FROM users_modules_evaluations
WHERE id = (SELECT r FROM vars);

-- get tags
SELECT
    tags.id,
    tags.name,
    (SELECT count(*) FROM modules_tags
        WHERE tag_id = tags.id) as count
FROM tags
WHERE id IN (
    SELECT id
    FROM tags
          JOIN modules_tags ON id = tag_id
    WHERE name LIKE 'abcd%'
    GROUP BY id
    ORDER BY count(*) DESC
    LIMIT 10
);

-- old query
EXPLAIN ANALYSE
SELECT name
FROM tags
WHERE tags.id IN (SELECT tags.id
FROM tags JOIN modules_tags ON tags.id = modules_tags.tag_id
WHERE tags.name LIKE 'abcd%' GROUP BY tags.id ORDER BY count(modules_tags.module_id) DESC
LIMIT 10);

-- new query
EXPLAIN ANALYSE
SELECT * FROM tags
WHERE id IN (SELECT tag_id
             FROM modules_tags
             WHERE tag_id IN (SELECT id
                              FROM tags
                              WHERE name LIKE 'foo%')
             GROUP BY tag_id
             ORDER BY count(tag_id) DESC
             LIMIT 10);

DROP INDEX modules_tags_tag_id_btree;
CREATE INDEX modules_tags_tag_id_btree ON modules_tags(tag_id);
SELECT pg_size_pretty (pg_table_size('modules_tags_tag_id_btree'));

DROP INDEX modules_tags_tag_id_hash;
CREATE INDEX modules_tags_tag_id_hash ON modules_tags USING hash(tag_id);
SELECT pg_size_pretty (pg_table_size('modules_tags_tag_id_hash'));

DROP INDEX tags_name_btree;
CREATE INDEX tags_name_btree ON tags(name varchar_pattern_ops);
SELECT pg_size_pretty (pg_table_size('tags_name_btree'));
SELECT pg_size_pretty (pg_table_size('"tags_name_key"'));

-- search

EXPLAIN ANALYSE
SELECT modules.*
FROM modules
JOIN modules_tags ON modules.id = modules_tags.module_id
JOIN tags ON tags.id = modules_tags.tag_id
WHERE tags.name = 'abcd9d0b';

--


-- modules_cards

EXPLAIN ANALYSE
SELECT cards.id FROM cards
JOIN modules_cards mc on cards.id = mc.card_id
WHERE module_id = 1048;

EXPLAIN
DELETE FROM modules_cards WHERE module_id = 1042;

EXPLAIN ANALYSE
SELECT c.id, c.face, c.back, mc.next_repeat_at, mc.last_repeated_at
FROM cards c JOIN modules_cards mc ON c.id = mc.card_id
WHERE mc.module_id = 1047;

EXPLAIN ANALYSE
SELECT cards.id FROM cards
JOIN modules_cards mc on cards.id = mc.card_id
WHERE module_id = 1048;

    -- already exists PK

DROP INDEX modules_cards_card_id_btree;
CREATE INDEX modules_cards_card_id_btree ON modules_cards(card_id);
SELECT pg_size_pretty (pg_table_size('modules_cards_card_id_btree'));

DROP INDEX modules_cards_card_id_hash;
CREATE INDEX modules_cards_card_id_hash ON modules_cards USING hash(card_id);
SELECT pg_size_pretty (pg_table_size('modules_cards_card_id_hash'));

vacuum analyse users_modules_evaluations;

EXPLAIN ANALYSE
SELECT COUNT(DISTINCT module_id) FROM modules_cards WHERE card_id = 3123;



SELECT pg_table_size('users_modules_evaluations_module_id_btree');
SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_hash'));



--
SELECT
    routine_schema,
    routine_name,
    routine_type
FROM
    information_schema.routines
WHERE
    routine_type IN ('PROCEDURE', 'FUNCTION', 'TRIGGER') and routine_schema = 's265074';

SELECT  event_object_table AS table_name ,trigger_name
FROM information_schema.triggers
GROUP BY table_name , trigger_name
ORDER BY table_name ,trigger_name;
