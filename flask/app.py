from hmac import compare_digest

from flask import Flask
from flask import jsonify
from flask import request
from flask_sqlalchemy import SQLAlchemy

from flask_jwt_extended import create_access_token
from flask_jwt_extended import current_user
from flask_jwt_extended import jwt_required
from flask_jwt_extended import JWTManager
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError

app = Flask(__name__)

# FIXME change secret-key
app.config['JWT_SECRET_KEY'] = 'super-secret'
# FIXME hide password
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql+psycopg2://postgres:damdin4k@localhost/postgres?options=-csearch_path=flash_cards_repeat_system'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

jwt = JWTManager(app)
db = SQLAlchemy(app)

app.app_context().push()
# db.metadata.schema = 'flash_cards_repeat_system'

with app.app_context():
# user_credentials = db.Table('user_credentials', db.metadata, autoload=True, autoload_with=db.engine)
# user_descriptions = db.Table('user_descriptions', db.metadata, autoload=True, autoload_with=db.engine)
# users = db.Table('users', db.metadata, autoload=True, autoload_with=db.engine)
    db.reflect()


class UserCredential(db.Model):
    __table__ = db.metadata.tables['user_credentials']

    def check_password(self, password):
        return self.password == password


@app.get('/')
def index():
    us = UserCredential.query.filter_by(login='example2000').first()
    print(us, type(us))
    return jsonify(code=200)


@jwt.user_identity_loader
def user_identity_lookup(user):
    return user.id


@jwt.user_lookup_loader
def user_lookup_callback(_jwt_header, jwt_data):
    identity = jwt_data['sub']
    return UserCredential.query.filter_by(id=identity).one_or_none()


@app.post('/signin')
def signin():
    login = request.json.get('login', None)
    password = request.json.get('password', None)

    # FIXME add password salt
    user = UserCredential.query.filter_by(login=login).one_or_none()
    if not user or not user.check_password(password):
        return jsonify('Wrong username or password'), 401

    access_token = create_access_token(identity=user)
    return jsonify(access_token=access_token)


# FIXME users_nex_val skip integer when exception
@app.post('/signup')
def signup():
    login = request.json.get('login', None)
    password = request.json.get('password', None)

    # FIXME create password salt
    try:
        user_id = db.session.query(func.create_user(login, password)).one()[0]
        db.session.commit()
    except IntegrityError as ex:
        return jsonify('User with such login already exists')

    return jsonify(id=user_id)


@app.get('/user')
@jwt_required()
def user():
    print(current_user.login)

    return jsonify(resp='tet')

@app.get('/who_am_i')
@jwt_required()
def protected():
    # We can now access our sqlalchemy User object via `current_user`.
    return jsonify(
        id=current_user.id,
        full_name=current_user.login,
        username=current_user.password,
    )
