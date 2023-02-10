-- tables size
select table_name, pg_size_pretty(pg_relation_size(quote_ident(table_name)))
from information_schema.tables
where table_schema = 's265074' -- 'flash_cards_repeat_system'
order by 2;

-- indexes size
SELECT pg_size_pretty (pg_table_size('modules_cards_module_id_btree'));
SELECT pg_size_pretty(pg_table_size('modules_cards_module_id_hash'));

SELECT pg_size_pretty(pg_table_size('user_credentials_pkey'));
SELECT pg_size_pretty(pg_table_size('user_credentials_login_key'));
SELECT pg_size_pretty(pg_table_size('user_credentials_login_password_btree'));
SELECT pg_size_pretty(pg_table_size('user_credentials_user_id_key'));

-- check datav
SELECT index, rows, pg_size_pretty(avg(size)::bigint) as size, avg(cost) as cost, avg(plan) as plan, avg(exec) as exec
            FROM data WHERE rows BETWEEN 0 AND 100000000 AND
                            at BETWEEN '2023-02-08 13:20:39+3'::timestamptz AND '2023-02-19 13:30:39+3'::timestamptz
                      GROUP BY index, rows order by rows, avg(size);

-- test
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
        -- FIXME 1.5? how to find outliers
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

SELECT AVGNOOUT(data.exec) FROM data WHERE rows BETWEEN 45000000 and 51000000 and index = 'hash';
SELECT AVG(data.exec) FROM data WHERE rows BETWEEN 45000000 and 51000000 and index = 'hash';
SELECT * FROM data WHERE rows BETWEEN 45000000 and 51000000 and index = 'hash';
-- end test

-- search?tag=<tag_name>
SELECT
    tags.id,
    tags.name,
    (SELECT count(*) FROM modules_tags
        WHERE tag_id = tags.id) as count
FROM tags
WHERE id IN (1
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
    WHERE name LIKE 'b%'
    GROUP BY id
    ORDER BY count(*) DESC
    LIMIT 10
);

EXPLAIN ANALYSE
SELECT tags.id AS tags_id, tags.name AS tags_name
FROM tags
WHERE tags.id IN (SELECT tags.id
FROM tags JOIN modules_tags ON tags.id = modules_tags.tag_id
WHERE tags.name LIKE 'b%' GROUP BY tags.id ORDER BY count(modules_tags.module_id) DESC
LIMIT 10);