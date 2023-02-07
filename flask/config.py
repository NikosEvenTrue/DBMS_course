import os


class cfg:
    PGPASSWORD = os.getenv('PGPASSWORD')
    SECRET_KEY = os.getenv('SECRET_KEY')
    USER = 's265074'
    POSTGRES_ADDRESS = 'localhost'
    POSTGRES_PORT = '65432'
    POSTGRES_DB = 'studs'
    POSTGRES_SCHEMA = 's265074'
