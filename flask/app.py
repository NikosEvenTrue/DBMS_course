from datetime import timedelta

from flask import Flask, make_response
from flask import jsonify
from flask import request
from flask_expects_json import expects_json
from flask_sqlalchemy import SQLAlchemy

from flask_jwt_extended import create_access_token, get_jwt
from flask_jwt_extended import current_user
from flask_jwt_extended import jwt_required
from flask_jwt_extended import JWTManager
from jsonschema.exceptions import ValidationError
from sqlalchemy import func, inspect, select, column, text
from sqlalchemy.exc import IntegrityError, InternalError

from config import cfg

app = Flask(__name__)

app.config['JWT_SECRET_KEY'] = cfg.SECRET_KEY
app.config['SQLALCHEMY_DATABASE_URI'] = f'postgresql+psycopg2://postgres:{cfg.PGPASSWORD}' \
                                        f'@{cfg.POSTGRES_ADDRESS}:{cfg.POSTGRES_PORT}' \
                                        f'/{cfg.POSTGRES_DB}?options=-csearch_path={cfg.POSTGRES_SCHEMA}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JSON_SORT_KEYS'] = False
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=1)
# app.config['SQLALCHEMY_ECHO'] = True
""
jwt = JWTManager(app)
db = SQLAlchemy(app)

revoked_jwts = []

with app.app_context():
    db.reflect()


class Serializer(object):

    def serialize(self):
        return {c: getattr(self, c) for c in inspect(self).attrs.keys()}

    @staticmethod
    def serialize_list(l):
        return [m.serialize() for m in l]


class UserCredential(db.Model):
    __table__ = db.metadata.tables['user_credentials']

    def check_password(self, password):
        return self.password == password


class User(db.Model):
    __table__ = db.metadata.tables['users']


class UserDescription(db.Model):
    __table__ = db.metadata.tables['user_descriptions']


class Folder(db.Model, Serializer):
    __table__ = db.metadata.tables['folders']


class Module(db.Model, Serializer):
    __table__ = db.metadata.tables['modules']


class Card(db.Model, Serializer):
    __table__ = db.metadata.tables['cards']


class ModuleCard(db.Model):
    __table__ = db.metadata.tables['modules_cards']


class UserCardExpiration(db.Model):
    __table__ = db.metadata.tables['users_cards_expirations']


@app.errorhandler(400)
def bad_request(error):
    if isinstance(error.description, ValidationError):
        original_error = error.description
        return make_response(jsonify({'error': original_error.message}), 400)
    return error


@app.errorhandler(404)
def not_found(error):
    return jsonify(error=error.description), 404


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
    # FIXME add password salt
    user_credentials = UserCredential.query.filter_by(login=request.json.get('login')).first()
    if not user_credentials or not user_credentials.check_password(request.json.get('password')):
        return jsonify(error='Wrong username or password'), 401
    access_token = create_access_token(identity=user_credentials)
    return jsonify(access_token=access_token)


# FIXME users_nex_val skip integer when exception
@app.post('/signup')
def signup():
    # FIXME add password salt
    try:
        user_id = db.session.query(func.create_user(request.json.get('login'),
                                                    request.json.get('password'))).one()[0]
        db.session.commit()
    except IntegrityError as ex:
        return jsonify(error='User with such login already exists'), 400
    return jsonify(id=user_id)


@app.post('/logout')
@jwt_required()
def logout():
    expire_jwt(get_jwt())
    return jsonify(id=current_user.id)


@app.route('/users', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required()
def users():
    user = User.query.get(current_user.id)
    user_description = UserDescription.query.filter_by(user_id=current_user.id).first()
    if request.method == 'GET':
        return jsonify(name=user.name, description=user_description.profile_description)
    elif request.method == 'PATCH':
        user.name = request.json.get('name', user.name)
        user_description.profile_description = request.json.get('description', user_description.profile_description)
        db.session.commit()
        return jsonify(user={'name': user.name, 'description': user_description.profile_description})
    else:
        user_id = current_user.id
        expire_jwt(get_jwt())
        db.session.delete(user)
        db.session.commit()
        return jsonify(id=user_id, deleted=True)


@app.route('/users/<_id>', methods=['GET'])
def users_id(_id):
    user = User.query.get(_id)
    user_description = UserDescription.query.filter_by(user_id=_id).first()
    if user:
        return jsonify(user={'name': user.name, 'description': user_description.profile_description})
    else:
        return jsonify(error=f'no user with id = {_id}'), 400


@app.route('/users/folders', methods=['GET', "POST"])
@jwt_required()
def folders():
    if request.method == 'GET':
        _folders = Folder.query.filter_by(user_id=current_user.id).all()
        return jsonify(folders=Folder.serialize_list(_folders))
    else:
        parent_folder_id = request.json.get('parent_folder_id')
        parent_folder = Folder.query.get(parent_folder_id)
        if not parent_folder:
            return jsonify(error=f'no such parent folder, parent_folder_id = {parent_folder_id}'), 400
        if parent_folder.user_id == current_user.id:
            try:
                folder = Folder(name=request.json.get('name'),
                                parent_folder_id=parent_folder_id,
                                user_id=current_user.id)
                db.session.add(folder)
                db.session.commit()
            except IntegrityError as ex:
                return jsonify(error=str(ex)), 400
            return jsonify(folder=folder.serialize())
        else:
            return jsonify(error=f'you aren\'t parent folder owner, parent_folder_id = {parent_folder_id}'), 400


@app.route('/users/folders/<folder_id>', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required()
def folders_id(folder_id):
    folder = Folder.query.get(folder_id)
    if folder:
        if folder.user_id == current_user.id:
            if request.method == 'GET':
                return jsonify(folder=folder.serialize())
            elif request.method == 'PATCH':
                try:
                    parent_folder = Folder.query.get(request.json.get('parent_folder_id'))
                    if parent_folder and parent_folder.user_id != current_user.id:
                        return jsonify(
                            error=f'you aren\'t owner of the parent folder with id = {parent_folder.id}'), 400
                    folder.name = request.json.get('name', folder.name)
                    folder.parent_folder_id = request.json.get('parent_folder_id', folder.parent_folder_id)
                    folder.folder_settings_id = request.json.get('folder_settings_id', folder.folder_settings_id)
                    db.session.commit()
                except IntegrityError as ex:
                    return jsonify(error=str(ex)), 400
                except InternalError as ex:
                    return jsonify(error=str(ex)), 400
                return jsonify(folder=folder.serialize())
            else:
                db.session.delete(folder)
                db.session.commit()
                return jsonify(folder_id=folder.id, deleted=True)
        else:
            return jsonify(error=f'you aren\'t folder owner, folder_id = {folder_id}'), 400
    else:
        return f'not such folder, folder_id = {folder_id}', 400


@app.route('/users/modules', methods=['GET'])
@jwt_required()
def modules():
    _modules = Module.query.filter_by(user_id=current_user.id)
    return jsonify(modules=Module.serialize_list(_modules))


schema_module = {
    'type': 'object',
    'properties': {
        'name': {'type': 'string', 'maxLength': 32},
        'folder_id': {'type': ['integer', 'null']}
    },
    'required': ['name', 'folder_id']
}


@app.route('/users/modules', methods=['POST'])
@jwt_required()
@expects_json(schema_module)
def modules_fid():
    try:
        module = Module(name=request.json['name'], user_id=current_user.id, folder_id=request.json['folder_id'])
        db.session.add(module)
        db.session.commit()
    except IntegrityError as ex:
        return jsonify(error=str(ex)), 400
    return jsonify(module=module.serialize())


@app.route('/users/modules/<module_id>', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required()
def modules_fid_id(module_id):
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}')
    if module.user_id != current_user.id:
        return jsonify(error=f'you aren\'t module owner, module id = {module_id}')
    if request.method == 'GET':
        return jsonify(module=module.serialize())
    elif request.method == 'PATCH':
        try:
            module.name = request.json.get('name', module.name)
            module.folder_id = request.json.get('folder_id', module.folder_id)
            db.session.commit()
        except IntegrityError as ex:
            return jsonify(error=str(ex)), 400
        return jsonify(folder=module.serialize())
    else:
        db.session.delete(module)
        db.session.commit()
        return jsonify(module_id=module.id, deleted=True)


schema_cards = {
    'type': 'object',
    'properties': {
        'face': {'type': 'string', 'maxLength': 512},
        'back': {'type': 'string', 'maxLength': 512}
    },
    'required': ['face', 'back']
}


@app.route('/users/modules/<module_id>/cards', methods=['GET', 'POST'])
@jwt_required()
@expects_json(schema_cards, ignore_for=['GET'])
def cards(module_id):
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}'), 400
    if module.user_id != current_user.id:
        return jsonify(error=f'you aren\'t module owner with id = {module_id}')
    if request.method == 'GET':
        ready = request.args.get('ready')
        if ready in ['True', 'true', 'T', 't']:
            ready_cards = db.session.execute(text(f'select * from ready_cards({current_user.id}, {module_id})')).all()
            return jsonify(cards=Card.serialize_list(Card(id=c.id, face=c.face, back=c.back) for c in ready_cards))
        else:
            _cards = Card.query.join(ModuleCard).filter(ModuleCard.module_id == module_id).all()
            return jsonify(cards=Card.serialize_list(_cards))
    else:
        card_id = db.session.query(func.create_card(current_user.id, module_id,
                                                    request.json.get('face'), request.json.get('back'))).first()[0]
        db.session.commit()
        card = Card.query.get(card_id)
        return jsonify(card=card.serialize())


@app.route('/users/modules/<module_id>/cards/<card_id>', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required()
def cards_id(module_id, card_id):
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}')
    if module.user_id != current_user.id:
        return jsonify(error=f'you aren\'t owner of the module with id = {module_id}')
    card = Card.query.join(ModuleCard).filter_by(module_id=module_id, card_id=card_id).first()
    if not card:
        return jsonify(error=f'no such card with id = {card_id} in module with id = {module_id}')
    if request.method == 'GET':
        return jsonify(card=card.serialize())
    elif request.method == 'PATCH':
        parent_module = Module.query.get(request.json.get('module_id'))
        user_card_expiration = UserCardExpiration.query.filter_by(user_id=current_user.id,
                                                                  card_id=card_id).first()
        if request.json.get('face') or request.json.get('back'):
            if parent_module and parent_module.user_id != current_user.id:
                return jsonify(error=f'you aren\'t owner of the module with id = {request.json.get("module_id")}')
            module_card = ModuleCard.query.filter_by(module_id=module_id, card_id=card_id).first()
            count_card_owners = db.session.query(func.count_owners(card_id)).first()[0]
            if count_card_owners != 1:
                card = Card(face=request.json.get('face', card.face), back=request.json.get('back', card.back))
                db.session.add(card)
                db.session.commit()
                module_card.card_id = card.id
                user_card_expiration.card_id = card.id
            else:
                card.face = request.json.get('face', card.face)
                card.back = request.json.get('back', card.back)
        module_card.module_id = request.json.get('module_id', module_card.module_id)
        print(user_card_expiration.next_repeat_at)
        user_card_expiration.next_repeat_at = request.json.get('next_repeat_at', user_card_expiration.next_repeat_at)
        user_card_expiration.last_repeated_at = request.json.get('last_repeated_at',
                                                                 user_card_expiration.last_repeated_at)
        db.session.commit()
        return jsonify(card=card.serialize())
    else:
        if db.session.query(func.count_owners(card_id)).first()[0] == 1:
            db.session.delete(card)
        module_card = ModuleCard.query.filter_by(module_id=module_id, card_id=card_id).first()
        db.session.delete(module_card)
        user_card_expiration = UserCardExpiration.query.filter_by(user_id=current_user.id,
                                                                  card_id=card_id).first()
        db.session.delete(user_card_expiration)
        db.session.commit()
        return jsonify(card_id=card_id, deleted=True)
