if __name__ != "__main__":
    print("It is not module")
    exit(-1)

import psycopg2
import matplotlib.pyplot as plt

# db config
dbname = 'postgres'
user = 'postgres'
schema = 'flash_cards_repeat_system'
host = 'localhost'
port = '5432'
# config
is_no_on = False
start_rows = 0
end_rows = 100e6
time_start = '2023-02-08 13:20:39+3'
time_end = '2023-02-11 13:30:39+3'
# end config

with psycopg2.connect(f"dbname={dbname} user={user} host={host} port={port} options=--search-path={schema}") as conn:
    with conn.cursor() as cur:
        def plot(kind: str, description: str, metr: str, is_no_on: bool = True):
            plt.plot(index['btree']['rows'], index['btree'][kind], color='green', label='btree')
            plt.plot(index['hash']['rows'], index['hash'][kind], color='orange', label='hash')
            if is_no_on:
                plt.plot(index['no']['rows'], index['no'][kind], color='blue', label='no')
            plt.xlabel('Rows in db')
            plt.ylabel(f'{description}{" ("+metr+")" if metr != "" else ""}')
            plt.title(description)
            plt.legend(loc='upper left')
            file_name = f'plots/{description}{"_with_no" if is_no_on else ""}(rows {start_rows:g}-{end_rows:g})' \
                        f'(time {time_start.replace(":", "-")} to {time_end.replace(":", "-")}).png'
            plt.savefig(file_name)
            print(f'{file_name} saved')
            plt.clf()

        cur.execute(f'''
            SELECT index, rows, avg(size)::int as size, avg(cost) as cost, avg(plan) as plan, avg(exec) as exec 
            FROM data WHERE rows BETWEEN {start_rows} AND {end_rows} AND
                at BETWEEN '{time_start}'::timestamptz AND '{time_end}'::timestamptz
            GROUP BY index, rows order by rows;
        ''')
        resp = cur.fetchall()
        index = {
            'btree': {'sizes': [], 'rows': [], 'costs': [], 'plans': [], 'execs': []},
            'hash': {'sizes': [], 'rows': [], 'costs': [], 'plans': [], 'execs': []},
            'no': {'sizes': [], 'rows': [], 'costs': [], 'plans': [], 'execs': []}
        }
        for row in resp:
            index[row[0]]['sizes'].append(row[2] / 1024 / 1024)
            index[row[0]]['rows'].append(row[1])
            index[row[0]]['costs'].append(row[3])
            index[row[0]]['plans'].append(row[4])
            index[row[0]]['execs'].append(row[5])

        st = {False}
        st.add(is_no_on)
        for is_no_on in st:
            plot('sizes', 'Index size', 'Mb', is_no_on)
            plot('costs', 'Cost', '', is_no_on)
            plot('plans', 'Planning Time', 'ms', is_no_on)
            plot('execs', 'Execution Time', 'ms', is_no_on)