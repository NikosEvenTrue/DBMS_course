import os


class cfg:
    PGPASSWORD = os.getenv('PGPASSWORD')
    SECRET_KEY = os.getenv('SECRET_KEY')
    USER = 'postgres'
    POSTGRES_ADDRESS = 'localhost'
    POSTGRES_PORT = '5432'
    POSTGRES_DB = 'postgres'
    POSTGRES_SCHEMA = 'flash_cards_repeat_system'
