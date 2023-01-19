from flask import Flask
from flask import jsonify
from flask import request
from flask_sqlalchemy import SQLAlchemy

from flask_jwt_extended import create_access_token, get_jwt
from flask_jwt_extended import current_user
from flask_jwt_extended import jwt_required
from flask_jwt_extended import JWTManager
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError

app = Flask(__name__)

# FIXME change secret-key
app.config['JWT_SECRET_KEY'] = 'super-secret'
# FIXME hide password
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql+psycopg2://postgres:damdin4k@localhost/postgres?options=-csearch_path=flash_cards_repeat_system'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JSON_SORT_KEYS'] = False

jwt = JWTManager(app)
db = SQLAlchemy(app)

revoked_jwts = []

with app.app_context():
    db.reflect()


class UserCredential(db.Model):
    __table__ = db.metadata.tables['user_credentials']

    def check_password(self, password):
        return self.password == password


class User(db.Model):
    __table__ = db.metadata.tables['users']


class UserDescription(db.Model):
    __table__ = db.metadata.tables['user_descriptions']

    @staticmethod
    def get_by_id(id):
        return UserDescription.query.add_columns(
            User.name,
            UserDescription.profile_description).filter(User.id == id).first()


@app.get('/')
def index():
    current = UserDescription.query.add_columns(
        UserDescription.id,
        UserDescription.profile_description).filter(User.id == current_user).first()
    print(current)
    return jsonify(s=200)


@jwt.user_identity_loader
def user_identity_lookup(user_credentials):
    return user_credentials.user_id


@jwt.user_lookup_loader
def user_lookup_callback(_jwt_header, jwt_data):
    user_credentials = jwt_data['sub']
    return UserCredential.query.filter_by(id=user_credentials).one_or_none()


@jwt.token_in_blocklist_loader
def check_if_token_is_revoked(jwt_header, jwt_payload: dict):
    return jwt_payload['jti'] in revoked_jwts


def expire_jwt(jwt):
    revoked_jwts.append(jwt['jti'])


@app.post('/signin')
def signin():
    login = request.json.get('login', None)
    password = request.json.get('password', None)

    # FIXME add password salt
    user_credentials = UserCredential.query.filter_by(login=login).one_or_none()
    if not user_credentials or not user_credentials.check_password(password):
        return jsonify('Wrong username or password'), 401

    access_token = create_access_token(identity=user_credentials)
    return jsonify(access_token=access_token)


# FIXME users_nex_val skip integer when exception
@app.post('/signup')
def signup():
    login = request.json.get('login', None)
    password = request.json.get('password', None)

    # FIXME add password salt
    try:
        user_id = db.session.query(func.create_user(login, password)).one()[0]
        db.session.commit()
    except IntegrityError as ex:
        return jsonify('User with such login already exists')

    return jsonify(id=user_id)


@app.post('/logout')
@jwt_required()
def logout():
    expire_jwt(get_jwt())
    return jsonify(id=current_user.id)


@app.get('/user')
@jwt_required()
def user():
    current = UserDescription.get_by_id(current_user.id)
    return jsonify(name=current.name, description=current.profile_description)


@app.get('/user/<id>')
def user_id(id):
    current = UserDescription.get_by_id(id)
    return jsonify(name=current.name, description=current.profile_description)


@app.delete('/user')
@jwt_required()
def user_delete():
    user_id = current_user.id
    expire_jwt(get_jwt())
    res = db.session.query(func.delete_user(current_user.id)).one()[0]
    db.session.commit()
    return jsonify(user=user_id, deleted=res)

