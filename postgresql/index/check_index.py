if __name__ != "__main__":
    print("It is not module")
    exit(-1)

from dataclasses import dataclass
from typing import Callable
import psycopg2
import re


@dataclass
class Data:
    index: str
    size: int
    rows: int
    cost: float
    plan: float
    exec: float

    def __init__(self):
        pass

# db config
dbname = 'postgres'
user = 'postgres'
schema = 'flash_cards_repeat_system'
host = 'localhost'
port = '5432'

conn = psycopg2.connect(f"dbname={dbname} user={user} host={host} port={port} options=--search-path={schema}")
    # conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
conn.autocommit = True
with conn.cursor() as cur:
    def create_data_table():
        cur.execute('''
                    DROP VIEW IF EXISTS datav;
                    DROP TABLE IF EXISTS data;
                    CREATE TABLE data (
                        id serial PRIMARY KEY,
                        index varchar(5),
                        size integer,
                        rows integer,
                        cost real,
                        plan real,
                        exec real,
                        at timestamptz
                    );
                    
                    CREATE OR REPLACE VIEW datav AS
                    SELECT
                        id, index,
                        pg_size_pretty(size::bigint) as size,
                        rows, cost, plan, exec, at
                    FROM data;
                    ''')

    def create_users_models_evaluations():
        cur.execute('''
            DROP TABLE IF EXISTS users_modules_evaluations;
            CREATE TABLE users_modules_evaluations (
                id serial PRIMARY KEY,
                user_id integer REFERENCES users ON DELETE SET NULL,
                module_id integer REFERENCES modules ON DELETE CASCADE,
                comment varchar(216),
                evaluation_id smallint REFERENCES evaluations
            );
        ''')

    def create_btree():
        cur.execute('''
                        DROP INDEX IF EXISTS users_modules_evaluations_module_id_btree;
                        CREATE INDEX users_modules_evaluations_module_id_btree ON users_modules_evaluations(module_id);
                        SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_btree'));
                    ''')
        return 'btree'


    def drop_btree():
        cur.execute('''
                        DROP INDEX users_modules_evaluations_module_id_btree;
                    ''')


    def size_btree():
        cur.execute("SELECT pg_table_size('users_modules_evaluations_module_id_btree');")
        return cur.fetchone()[0]


    def create_hash():
        cur.execute('''
                        DROP INDEX IF EXISTS users_modules_evaluations_module_id_hash;
                        CREATE INDEX users_modules_evaluations_module_id_hash ON users_modules_evaluations USING hash(module_id);
                        SELECT pg_size_pretty (pg_table_size('users_modules_evaluations_module_id_hash'));
                    ''')
        return 'hash'


    def drop_hash():
        cur.execute('''
                        DROP INDEX users_modules_evaluations_module_id_hash;
                    ''')


    def size_hash():
        cur.execute("SELECT pg_table_size('users_modules_evaluations_module_id_hash');")
        return cur.fetchone()[0]


    def create_no():
        return 'no'


    def drop_no():
        pass


    def size_no():
        return 0


    def explain():
        cur.execute('vacuum analyse users_modules_evaluations;')
        cur.execute('''
                        EXPLAIN ANALYSE
                        WITH vars (r) as (values(randint(N() - 1) + 1))
                        SELECT ume.id, ume.user_id, ume.module_id, ume.comment, ume.evaluation_id
                        FROM users_modules_evaluations ume, vars
                        WHERE ume.module_id = r;
                    ''')
        resp = cur.fetchall()
        return (re.search(r'cost=\d+\.\d+\.\.(\d+\.\d+)', resp[0][0]).group(1),
                re.search(r'Planning Time: (\d+[.]\d+)', resp[-2][0]).group(1),
                re.search(r'Execution Time: (\d+[.]\d+)', resp[-1][0]).group(1))


    def test_index(precision: int, create_index: Callable, drop_index: Callable, index_size: Callable):
        data = Data()
        cur.execute('''
            SELECT count(*) FROM users_modules_evaluations;
        ''')
        data.rows = cur.fetchone()[0]
        data.index = create_index()
        data.size = index_size()
        for i in range(precision):
            data.cost, data.plan, data.exec = explain()
            print(data)
            cur.execute(f'''
                INSERT INTO data(index, size, rows, cost, plan, exec)
                VALUES ('{data.index}', {data.size}, {data.rows}, {data.cost}, {data.plan}, {data.exec})
            ''')
            conn.commit()
        drop_index()


    def insert_data(count: int):
        cur.execute(f'''
            INSERT INTO users_modules_evaluations (user_id, module_id, comment, evaluation_id)
            SELECT randint(1, N() / 10), randint(1, N()),
                   randstr(randint(0, 216)), randint(1, 3)
            FROM generate_series(1, {count})
            ON CONFLICT DO NOTHING;
        ''')


    def create_gen(start: int, end: int):
        #      10     1000      100_000       500_000      1_000_000     2_000_000     4M
        #         100      10_000      250_000       750_000      1_500_000       3M
        lst = [10, 90, 900, 9000, 90e3, 150e3, 250e3, 250e3, 250e3, 500e3, 500e3, 1e6, 1e6,
        #      5M   6M   7M   8M   9M   10M  20M   30M   40M   50M   60M
               1e6, 1e6, 1e6, 1e6, 1e6, 1e6, 10e6, 10e6, 10e6, 10e6, 10e6,
        #      70M   80M   90M   100M
               10e6, 10e6, 10e6, 10e6];
        sum = 0
        start_i = 0
        end_i = 0
        for i, e in enumerate(lst):
            sum += e
            if sum <= start:
                start_i = i
            if sum <= end:
                end_i = i
        for i in range(start_i + 1, end_i + 1):
            yield lst[i]


    # config
    is_no_on = False
    precision = 100
    gen = create_gen(10e6, 100e6)
    is_drop_users_models_evaluations = False
    is_drop_data= False
    # end config

    if is_drop_users_models_evaluations:
        create_users_models_evaluations()
    if is_drop_data:
        create_data_table()

    for i in gen:
        insert_data(i)
        if is_no_on:
            test_index(precision, create_no, drop_no, size_no)
        test_index(precision, create_btree, drop_btree, size_btree)
        test_index(precision, create_hash, drop_hash, size_hash)
