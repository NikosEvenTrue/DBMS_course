import binascii
import hashlib
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
from sqlalchemy import func, inspect, select, desc
from sqlalchemy.exc import IntegrityError, InternalError

from hashlib import sha256

from config import cfg

app = Flask(__name__)

app.config['JWT_SECRET_KEY'] = cfg.SECRET_KEY
app.config['SQLALCHEMY_DATABASE_URI'] = f'postgresql+psycopg2://{cfg.USER}:{cfg.PGPASSWORD}' \
                                        f'@{cfg.POSTGRES_ADDRESS}:{cfg.POSTGRES_PORT}' \
                                        f'/{cfg.POSTGRES_DB}?options=-csearch_path={cfg.POSTGRES_SCHEMA}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JSON_SORT_KEYS'] = False
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=1)
app.config['SQLALCHEMY_ECHO'] = cfg.ECHO_QUERIES

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

    @staticmethod
    def salt(password):
        return sha256((password + cfg.SALT).encode('utf-8')).digest()

    def check_password(self, password):
        return self.password == self.salt(password)


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


class ModuleTag(db.Model):
    __table__ = db.metadata.tables['modules_tags']


class Tag(db.Model, Serializer):
    __table__ = db.metadata.tables['tags']


class UserModuleEvaluation(db.Model, Serializer):
    __table__ = db.metadata.tables['users_modules_evaluations']


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
    return UserCredential.query.filter_by(user_id=user_credentials).one_or_none()


@jwt.token_in_blocklist_loader
def check_if_token_is_revoked(jwt_header, jwt_payload: dict):
    return jwt_payload['jti'] in revoked_jwts


def expire_jwt(jwt):
    revoked_jwts.append(jwt['jti'])


@app.post('/signin')
def signin():
    user_credentials = UserCredential.query.filter_by(login=request.json.get('login')).first()
    if not user_credentials or not user_credentials.check_password(request.json.get('password')):
        return jsonify(error='Wrong username or password'), 401
    access_token = create_access_token(identity=user_credentials)
    return jsonify(access_token=access_token, user_id=user_credentials.user_id)


# FIXME users_nex_val skip integer when exception
@app.post('/signup')
def signup():
    try:
        user_id = db.session.query(func.create_user(
            request.json.get('login'),
            UserCredential.salt(request.json.get('password'))
        )).one()[0]
        db.session.commit()
    except IntegrityError as ex:
        return jsonify(error='User with such login already exists'), 400
    return jsonify(user_id=user_id)


@app.post('/logout')
@jwt_required()
def logout():
    expire_jwt(get_jwt())
    return jsonify(user_id=current_user.user_id)


def id_validator(func):
    def decor(*args, **kwargs):
        try:
            ids = []
            for name, _id in kwargs.items():
                ids.append(int(_id))
        except ValueError:
            return jsonify(error=f'wrong {name}({_id})'), 400
        return func(*ids)

    decor.__name__ = func.__name__
    return decor


def user_validator(func):
    def decor(*args):
        if current_user.user_id != args[0]:
            return jsonify(error=f'you have no permission to perform {request.method} with user({args[0]})'), 403
        user = User.query.get(args[0])
        if not user:
            return jsonify(error=f'no user with id = {args[0]}'), 400
        return func(*args)

    decor.__name__ = func.__name__
    return decor


# TODO optional description
@app.route('/users/<user_id>', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required(optional=True)
@id_validator
def users_id(user_id):
    user = User.query.get(user_id)
    user_description = UserDescription.query.filter_by(user_id=user_id).first()
    if not user:
        return jsonify(error=f'no user with id = {user_id}'), 400
    if request.method == 'GET':
        return jsonify(user={'name': user.name, 'description': user_description.profile_description})
    if not current_user:
        return jsonify(error=f'Unauthorized'), 401
    if current_user.user_id != user_id:
        return jsonify(error=f'you have no permission to perform {request.method} with user({user_id})'), 403
    if request.method == 'PATCH':
        user.name = request.json.get('name', user.name)
        user_description.profile_description = request.json.get('description', user_description.profile_description)
        db.session.commit()
        return jsonify(user={'name': user.name, 'description': user_description.profile_description})
    else:
        user_id = current_user.user_id
        db.session.delete(user)
        db.session.commit()
        expire_jwt(get_jwt())
        return jsonify(user_id=user_id, deleted=True)


@app.route('/users/<u_id>/folders', methods=['GET', "POST"])
@jwt_required()
@id_validator
@user_validator
def folders(user_id):
    if request.method == 'GET':
        _folders = Folder.query.filter_by(user_id=current_user.user_id).all()
        return jsonify(folders=Folder.serialize_list(_folders))
    else:
        folder_name = request.json.get('name')
        if folder_name is None:
            return jsonify(error='parameter name is required'), 400
        parent_folder_id = request.json.get('parent_folder_id')
        if parent_folder_id is not None:
            parent_folder = Folder.query.get(parent_folder_id)
            if not parent_folder:
                return jsonify(error=f'no such parent folder, parent_folder_id = {parent_folder_id}'), 400
            if parent_folder.user_id != current_user.user_id:
                return jsonify(error=f'you aren\'t parent folder owner, parent_folder_id = {parent_folder_id}'), 400
            folder = Folder(name=folder_name,
                            parent_folder_id=parent_folder_id,
                            user_id=current_user.user_id)
        else:
            folder = Folder(name=folder_name,
                            user_id=current_user.user_id)
        db.session.add(folder)
        db.session.commit()
        return jsonify(folder=folder.serialize())


@app.route('/users/<user_id>/folders/<folder_id>', methods=['GET', 'PATCH', 'DELETE'])
@jwt_required()
@id_validator
@user_validator
def folders_id(user_id, folder_id):
    folder = Folder.query.get(folder_id)
    if folder:
        if folder.user_id == current_user.user_id:
            if request.method == 'GET':
                return jsonify(folder=folder.serialize())
            elif request.method == 'PATCH':
                try:
                    parent_folder_id = request.json.get('parent_folder_id')
                    if parent_folder_id:
                        parent_folder = Folder.query.get(parent_folder_id)
                        if parent_folder and parent_folder.user_id != current_user.user_id:
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
        return jsonify(error=f'not such folder, folder_id = {folder_id}'), 400


schema_module = {
    'type': 'object',
    'properties': {
        'name': {'type': 'string', 'maxLength': 32},
        'folder_id': {'type': ['integer', 'null']}
    },
    'required': ['name']
}


@app.route('/users/<user_id>/modules', methods=['GET', 'POST'])
@jwt_required()
@expects_json(schema_module, ignore_for=['GET'])
@id_validator
def modules(user_id):
    user = User.query.get(user_id)
    if not user:
        return jsonify(error=f'no user with id = {user_id}'), 400
    if request.method == 'GET':
        _modules = Module.query.filter_by(user_id=user_id)
        if current_user.user_id == user_id:
            return jsonify(modules=Module.serialize_list(_modules))
        else:
            public_modules_ids = ModuleTag.query.distinct(ModuleTag.module_id). \
                filter(ModuleTag.module_id.in_([m.id for m in _modules])).all()
            public_modules = [m for m in _modules if m.id in [m.module_id for m in public_modules_ids]]
            return jsonify(modules=Module.serialize_list(public_modules))
    else:
        if current_user.user_id != user_id:
            return jsonify(error=f'you have no permission to perform {request.method} with user({user_id})'), 403
        try:
            module = Module(name=request.json['name'], user_id=current_user.user_id,
                            folder_id=request.json.get('folder_id'))
            db.session.add(module)
            db.session.commit()
        except IntegrityError as ex:
            return jsonify(error=str(ex)), 400
        return jsonify(module=module.serialize())


@app.route('/users/<user_id>/modules/<module_id>', methods=['GET', 'PATCH', 'DELETE', 'POST', 'COPY'])
@jwt_required()
@id_validator
def modules_id(user_id, module_id):
    user = User.query.get(user_id)
    if user is None:
        return jsonify(error=f'no such user({user_id})'), 400
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}'), 400
    if user_id != module.user_id:
        return jsonify(error=f'user({user_id}) has no module({module_id})'), 400
    is_public = ModuleTag.query.filter_by(module_id=module_id).first()
    if module.user_id != current_user.user_id and not is_public:
        return jsonify(error=f'you aren\'t module owner, module id = {module_id}'), 400
    if request.method == 'POST':
        if module.user_id != current_user.user_id:
            # evaluate the module
            evaluation_id = request.json.get('evaluation_id')
            if evaluation_id is None:
                evaluation_id = 3
            comment = request.json.get('comment')
            user_module_evaluation = UserModuleEvaluation.query.filter_by(user_id=current_user.user_id,
                                                                          module_id=module_id).first()
            if user_module_evaluation is None:
                user_module_evaluation = UserModuleEvaluation(user_id=current_user.user_id,
                                                              module_id=module_id,
                                                              evaluation_id=evaluation_id,
                                                              comment=comment)
                db.session.add(user_module_evaluation)
            else:
                user_module_evaluation.evaluation_id = evaluation_id
                user_module_evaluation.comment = user_module_evaluation.comment if comment is None else comment
            db.session.commit()
            return jsonify(evaluation=user_module_evaluation.serialize())
        else:
            # public the module
            tags_str = request.json.get('tags')
            if not tags_str:
                return jsonify(error='tags can\'t be empty'), 400
            existing_tags = Tag.query.filter(Tag.name.in_(tags_str)).all()
            new_tags = [Tag(name=t_name) for t_name in
                        (t_name for t_name in tags_str if t_name not in [t.name for t in existing_tags])]
            db.session.add_all(new_tags)
            already_tagged = ModuleTag.query.filter_by(module_id=module_id).all()
            new_tagged_ids = [t.id for t in existing_tags
                              if t.id not in [tagged.tag_id for tagged in already_tagged]]
            new_tagged_ids.extend((t.id for t in new_tags))
            modules_tags = [ModuleTag(module_id=module_id, tag_id=tag_id) for tag_id in new_tagged_ids]
            db.session.add_all(modules_tags)
            db.session.commit()
            return jsonify(msg=f'tags were added')
    if request.method == 'COPY':
        new_folder_id = request.json.get('folder_id')
        if new_folder_id:
            folder = Folder.query.get(new_folder_id)
            if folder is None:
                return jsonify(error=f'no such folder({new_folder_id})'), 400
            if folder.user_id != current_user.user_id:
                return jsonify(error=f'you aren\'t folder({new_folder_id}) owner'), 400
        new_module = Module(name=module.name, user_id=current_user.user_id, folder_id=new_folder_id)
        db.session.add(new_module)
        db.session.commit()
        modules_cards = ModuleCard.query.filter_by(module_id=module_id).all()
        new_modules_cards = [ModuleCard(module_id=new_module.id, card_id=mc.card_id)
                             for mc in modules_cards]
        db.session.add_all(new_modules_cards)
        db.session.commit()
        return jsonify(module=new_module.serialize())
    elif request.method == 'GET':
        if request.args.get('public_info') in ['True', 'true', 'T', 't']:
            public_info = UserModuleEvaluation.query.filter_by(module_id=module_id).all()
            tags = Tag.query.join(ModuleTag).filter(ModuleTag.module_id == module_id).all()
            return jsonify(tags=Tag.serialize_list(tags),
                           evaluations=UserModuleEvaluation.serialize_list(public_info))
        return jsonify(module=module.serialize())
    if module.user_id != current_user.user_id:
        return jsonify(error=f'you aren\'t module owner, module id = {module_id}')
    if request.method == 'PATCH':
        try:
            module.name = request.json.get('name', module.name)
            parent_folder_id = request.json.get('folder_id')
            if parent_folder_id:
                parent_folder = Folder.query.get(parent_folder_id)
                if not parent_folder:
                    return jsonify(error=f'no such folder({parent_folder_id})')
                if parent_folder.user_id != current_user.user_id:
                    return jsonify(error=f'you aren\'t folder({parent_folder_id}) owner')
                module.folder_id = parent_folder_id
            db.session.commit()
        except IntegrityError as ex:
            return jsonify(error=str(ex)), 400
        return jsonify(folder=module.serialize())
    elif request.method == 'DELETE':
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


@app.route('/users/<user_id>/modules/<module_id>/cards', methods=['GET', 'POST'])
@jwt_required()
@expects_json(schema_cards, ignore_for=['GET'])
@id_validator
def cards(user_id, module_id):
    user = User.query.get(user_id)
    if user is None:
        return jsonify(error=f'no such user({user_id})'), 400
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}'), 400
    if user_id != module.user_id:
        return jsonify(error=f'user({user_id}) has no module({module_id})'), 400
    is_public = ModuleTag.query.filter_by(module_id=module_id).first()
    if request.method == 'GET':
        if module.user_id != current_user.user_id and not is_public:
            return jsonify(error=f'you aren\'t module owner with id = {module_id}')
        if module.user_id != current_user.user_id:
            _cards = Card.query.join(ModuleCard).filter(ModuleCard.module_id == module_id).all()
            return jsonify(cards=Card.serialize_list(_cards))
        _cards = db.session.query(Card.id, Card.face, Card.back,
                                  ModuleCard.next_repeat_at, ModuleCard.last_repeated_at
                                  ).join(ModuleCard).filter(ModuleCard.module_id == module_id).all()
        return jsonify(cards=[{'id': c.id, 'face': c.face, 'back': c.back,
                               'next_repeat_at': c.next_repeat_at,
                               'last_repeated_at': c.last_repeated_at}
                              for c in _cards])
    if module.user_id != current_user.user_id:
        return jsonify(error=f'you aren\'t module owner with id = {module_id}')
    if request.method == 'POST':
        card_id = db.session.query(func.create_card(current_user.user_id, module_id,
                                                    request.json.get('face'), request.json.get('back'))).first()[0]
        db.session.commit()
        card = Card.query.get(card_id)
        return jsonify(card=card.serialize())


@app.route('/users/<user_id>/modules/<module_id>/cards/<card_id>', methods=['GET', 'PATCH', 'DELETE', 'COPY'])
@jwt_required()
@id_validator
def cards_id(user_id, module_id, card_id):
    user = User.query.get(user_id)
    if user is None:
        return jsonify(error=f'no such user({user_id})'), 400
    module = Module.query.get(module_id)
    if not module:
        return jsonify(error=f'no such module with id = {module_id}')
    if user_id != module.user_id:
        return jsonify(error=f'user({user_id}) has no module({module_id})'), 400
    is_public = ModuleTag.query.filter_by(module_id=module_id).first()
    if module.user_id != current_user.user_id and not is_public:
        return jsonify(error=f'you aren\'t owner of the module with id = {module_id}')
    card = Card.query.join(ModuleCard).filter_by(module_id=module_id, card_id=card_id).first()
    if not card:
        return jsonify(error=f'no such card with id = {card_id} in module with id = {module_id}')
    if request.method == 'GET':
        if module.user_id != current_user.user_id:
            return jsonify(card=Card.query.filter_by(id=card_id).first().serialize())
        expiration = ModuleCard.query.filter_by(module_id=module_id, card_id=card_id).first()
        return jsonify(card={'id': card.id, 'face': card.face, 'back': card.back,
                             'next_repeat_at': expiration.next_repeat_at,
                             'last_repeated_at': expiration.last_repeated_at})
    if request.method == 'COPY':
        new_module_id = request.json.get('module_id')
        if new_module_id is None:
            return jsonify(error='parament module_id is required'), 400
        new_module = Module.query.filter_by(id=new_module_id).first()
        if not new_module:
            return jsonify(error=f'module({new_module_id}) doesn\'t exist'), 400
        if new_module.user_id != current_user.user_id:
            return jsonify(error=f'you aren\'t owner of the module with id = {new_module_id}')
        module_card = ModuleCard(module_id=new_module_id, card_id=card_id)
        db.session.add(module_card)
        try:
            db.session.commit()
            return jsonify(card={'id': card.id, 'face': card.face, 'back': card.back,
                                 'next_repeat_at': module_card.next_repeat_at,
                                 'last_repeated_at': module_card.last_repeated_at})
        except IntegrityError as ex:
            return jsonify(error=f'the card({card_id}) already in the module({module_id})')
    if module.user_id != current_user.user_id:
        return jsonify(error=f'you aren\'t owner of the module with id = {module_id}')
    if request.method == 'PATCH':
        parent_module = None
        if request.json.get('module_id'):
            parent_module = Module.query.get(request.json.get('module_id'))
        _module_card = ModuleCard.query.filter_by(module_id=module_id, card_id=card_id).first()
        face = request.json.get('face')
        back = request.json.get('back')
        if (face or back) and (face != card.face or back != card.back):
            if parent_module and parent_module.user_id != current_user.user_id:
                return jsonify(error=f'you aren\'t owner of the module with id = {request.json.get("module_id")}')
            count_card_owners = db.session.query(func.count_owners(card_id)).first()[0]
            if count_card_owners != 1:
                card = Card(face=request.json.get('face', card.face), back=request.json.get('back', card.back))
                db.session.add(card)
                db.session.commit()
                _module_card.card_id = card.id
            else:
                card.face = request.json.get('face', card.face)
                card.back = request.json.get('back', card.back)
        _module_card.module_id = request.json.get('module_id', _module_card.module_id)
        _module_card.next_repeat_at = request.json.get('next_repeat_at', _module_card.next_repeat_at)
        _module_card.last_repeated_at = request.json.get('last_repeated_at',
                                                         _module_card.last_repeated_at)
        db.session.commit()
        return jsonify(card={'id': card.id, 'face': card.face, 'back': card.back,
                             'next_repeat_at': _module_card.next_repeat_at,
                             'last_repeated_at': _module_card.last_repeated_at})
    if request.method == 'DELETE':
        if db.session.query(func.count_owners(card_id)).first()[0] == 1:
            db.session.delete(card)
        else:
            module_card = ModuleCard.query.filter_by(module_id=module_id, card_id=card_id).first()
            db.session.delete(module_card)
        db.session.commit()
        return jsonify(card_id=card_id, deleted=True)


@app.route('/tags', methods=['GET'])
def tags():
    start = request.args.get('start')
    if not start:
        return jsonify(error='parameter start is required'), 400
    limit = request.args.get('limit', 10)
    _tags = Tag.query.filter(Tag.id.in_(
        select(ModuleTag.tag_id).filter(ModuleTag.tag_id.in_(
            select(Tag.id).filter(Tag.name.like(f'{start}%')).subquery()
        )).group_by(ModuleTag.tag_id).order_by(desc(func.count(ModuleTag.tag_id))).limit(limit).subquery()
    )).all()
    return jsonify(tags=Tag.serialize_list(_tags))


@app.route('/search', methods=['GET'])
def search():
    tag = request.args.get('tag')
    if tag is None:
        return jsonify(error='parameter tag is required'), 400
    _modules = Module.query.join(ModuleTag).join(Tag). \
        filter(Tag.name == tag).all()
    return jsonify(modules=Module.serialize_list(_modules))
