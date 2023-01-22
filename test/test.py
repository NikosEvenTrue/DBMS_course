from unittest import TestCase, TestLoader

from requests import post, delete, get, patch


def url(string):
    return 'http://127.0.0.1:5000' + string


class TestAuthentication(TestCase):
    def test_signin_valid_credentials(self):
        response = post(url('/signin'), json={'login': 'nik', 'password': 'admin'})
        self.assertEqual(200, response.status_code)
        self.assertNotEqual(None, response.json()['access_token'])

    def test_signin_valid_login_wrong_password(self):
        response = post(url('/signin'), json={'login': 'nik', 'password': 'fake'})
        self.assertEqual(401, response.status_code)
        self.assertEqual('Wrong username or password', response.json()['error'])

    def test_signin_wrong_credentials(self):
        response = post(url('/signin'), json={'login': 'fake', 'password': 'fake'})
        self.assertEqual(401, response.status_code)
        self.assertEqual('Wrong username or password', response.json()['error'])

    def test_signup(self):
        signup_response = post(url('/signup'), json={'login': 'example2000', 'password': 'strong'})
        self.assertEqual(200, signup_response.status_code)
        user_id = signup_response.json()['id']

        signin_response = post(url('/signin'), json={'login': 'example2000', 'password': 'strong'})
        self.assertEqual(200, signin_response.status_code)
        self.assertNotEqual(None, signin_response.json()['access_token'])
        jwt = signin_response.json()['access_token']

    def test_signup_same_login(self):
        signup_response_2 = post(url('/signup'), json={'login': 'example2000', 'password': 'strong'})
        self.assertEqual(400, signup_response_2.status_code)
        self.assertEqual('User with such login already exists', signup_response_2.json()['error'])

    def test_logout(self):
        response = post(url('/signin'), json={'login': 'nik', 'password': 'admin'})
        jwt = response.json()['access_token']

        get_response = get(url('/users'), headers={'Authorization': f'Bearer {jwt}'})
        self.assertEqual(200, get_response.status_code)

        logout_response = post(url('/logout'), headers={'Authorization': f'Bearer {jwt}'})
        self.assertEqual(200, logout_response.status_code)

        get_response_2 = get(url('/users'), headers={'Authorization': f'Bearer {jwt}'})
        self.assertEqual(401, get_response_2.status_code)


def signin():
    response = post(url('/signin'), json={'login': 'nik', 'password': 'admin'})
    return response.json()['access_token']


def auth(jwt):
    return {'Authorization': f'Bearer {jwt}'}


class TestUsers(TestCase):
    def test_user_get(self):
        jwt = signin()
        get_response = get(url('/users'), headers={'Authorization': f'Bearer {jwt}'})
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('nik', get_response.json()['name'])
        self.assertEqual(None, get_response.json()['description'])

    def test_user_patch_name(self):
        jwt = signin()
        patch_response = patch(url('/users'), headers=auth(jwt),
                               json={'name': 'nikita'})
        get_response = get(url('/users'), headers={'Authorization': f'Bearer {jwt}'})
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('nikita', get_response.json()['name'])

    def test_user_patch_description(self):
        jwt = signin()
        patch_response = patch(url('/users'), headers=auth(jwt),
                               json={'description': 'hello, my name is nikita'})
        get_response = get(url('/users'), headers=auth(jwt))
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('hello, my name is nikita', get_response.json()['description'])

    def test_user_patch_name_and_description(self):
        jwt = signin()
        patch_response = patch(url('/users'), headers=auth(jwt),
                               json={'name': 'anton', 'description': 'hello, my name is anton'})
        get_response = get(url('/users'), headers=auth(jwt))
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('anton', get_response.json()['name'])
        self.assertEqual('hello, my name is anton', get_response.json()['description'])


class TestUsersId(TestCase):
    def test_user_get(self):
        get_response = get(url('/users/2'))
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('roma', get_response.json()['user']['name'])

    def test_user_get_wrong(self):
        get_response = get(url('/users/1000'))
        self.assertEqual(400, get_response.status_code)


class TestFolders(TestCase):
    def test_folder_1_get(self):
        jwt = signin()
        folder_resp = get(url('/users/folders'), headers=auth(jwt))
        expected_folders = {'folders': [{'folder_settings_id': 1,
                                         'id': 1,
                                         'name': 'univercity',
                                         'parent_folder_id': None,
                                         'user_id': 1},
                                        {'folder_settings_id': 1,
                                         'id': 2,
                                         'name': 'unit1',
                                         'parent_folder_id': 1,
                                         'user_id': 1},
                                        {'folder_settings_id': 1,
                                         'id': 3,
                                         'name': 'exam',
                                         'parent_folder_id': 1,
                                         'user_id': 1},
                                        {'folder_settings_id': 1,
                                         'id': 4,
                                         'name': 'A5',
                                         'parent_folder_id': 2,
                                         'user_id': 1},
                                        {'folder_settings_id': 1,
                                         'id': 5,
                                         'name': 'A4',
                                         'parent_folder_id': 2,
                                         'user_id': 1}]}
        self.assertEqual(expected_folders, folder_resp.json())

    def test_folder_add_correct_jwt(self):
        jwt = signin()
        post_response = post(url('/users/folders'), headers=auth(jwt),
                             json={'name': 'example', 'parent_folder_id': 1})
        self.assertEqual(200, post_response.status_code)
        print(post_response.json())
        folder_id = post_response.json()['folder']['id']
        get_response = get(url(f'/users/folders/{folder_id}'), headers=auth(jwt))
        self.assertEqual(200, get_response.status_code)
        self.assertEqual('example', get_response.json()['folder']['name'])
        self.assertEqual(1, get_response.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_response.json()['folder']['user_id'])
        self.assertEqual(1, get_response.json()['folder']['folder_settings_id'])

    def test_folder_add_wrong_jwt(self):
        signin_response = post(url('/signin'), json={'login': 'roma', 'password': 'user'})
        jwt = signin_response.json()['access_token']
        add_folder_response = post(url('/users/folders'), headers=auth(jwt),
                                   json={'name': 'example', 'parent_folder_id': 6})
        self.assertEqual(400, add_folder_response.status_code)

    def test_folder_add_wrong_parent(self):
        jwt = signin()
        add_folder_response = post(url('/users/folders'), headers=auth(jwt),
                                   json={'name': 'example', 'parent_folder_id': 1000})
        self.assertEqual(400, add_folder_response.status_code)

    def test_folder_add_wrong_params(self):
        jwt = signin()
        add_folder_response = post(url('/users/folders'), headers=auth(jwt),
                                   json={})
        self.assertEqual(400, add_folder_response.status_code)


class TestFoldersId(TestCase):
    def test_folder_id_1_get(self):
        jwt = signin()
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('univercity', get_resp.json()['folder']['name'])
        self.assertEqual(None, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(1, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_2_patch(self):
        jwt = signin()
        patch_resp = patch(url(f'/users/folders/{1}'), headers=auth(jwt),
                           json={'name': 'test', 'folder_settings_id': 2, 'parent_folder_id': 3})
        self.assertEqual(200, patch_resp.status_code)
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('test', get_resp.json()['folder']['name'])
        self.assertEqual(3, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(2, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_3_patch_fake(self):
        jwt = signin()
        patch_resp = patch(url(f'/users/folders/{1}'), headers=auth(jwt),
                           json={'fake_property_1': 'fake', 'fake_property_2': 1})
        self.assertEqual(200, patch_resp.status_code)
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('test', get_resp.json()['folder']['name'])
        self.assertEqual(3, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(2, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_4_patch_denied(self):
        jwt = signin()
        patch_resp = patch(url(f'/users/folders/{1}'), headers=auth(jwt),
                           json={'user_id': 2, 'id': 1})
        self.assertEqual(200, patch_resp.status_code)
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('test', get_resp.json()['folder']['name'])
        self.assertEqual(3, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(2, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_5_patch_wrong_parent_folder(self):
        jwt = signin()
        patch_resp = patch(url(f'/users/folders/{1}'), headers=auth(jwt),
                           json={'parent_folder_id': 1000})
        self.assertEqual(400, patch_resp.status_code)
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('test', get_resp.json()['folder']['name'])
        self.assertEqual(3, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(2, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_6_patch_wrong_settings_id(self):
        jwt = signin()
        patch_resp = patch(url(f'/users/folders/{1}'), headers=auth(jwt),
                           json={'folder_settings_id': 1000})
        self.assertEqual(400, patch_resp.status_code)
        get_resp = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        self.assertEqual('test', get_resp.json()['folder']['name'])
        self.assertEqual(3, get_resp.json()['folder']['parent_folder_id'])
        self.assertEqual(1, get_resp.json()['folder']['user_id'])
        self.assertEqual(2, get_resp.json()['folder']['folder_settings_id'])

    def test_folder_id_7_delete(self):
        jwt = signin()
        delete_resp = delete(url(f'/users/folders/{3}'), headers=auth(jwt))
        self.assertEqual(200, delete_resp.status_code)
        get_folder_3 = get(url(f'/users/folders/{3}'), headers=auth(jwt))
        self.assertEqual(400, get_folder_3.status_code)
        get_folder_1 = get(url(f'/users/folders/{1}'), headers=auth(jwt))
        self.assertEqual(400, get_folder_1.status_code)

    def test_folder_id_8_delete_wrong_id(self):
        jwt = signin()
        delete_resp = delete(url(f'/users/folders/{1000}'), headers=auth(jwt))
        self.assertEqual(400, delete_resp.status_code)


class TestModules(TestCase):
    def test_modules_1_get(self):
        jwt = signin()
        get_resp = get(url(f'/users/modules'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        expected = {'modules': [{'id': 2, 'name': 'general', 'user_id': 1, 'folder_id': None}]}
        self.assertEqual(expected, get_resp.json())

    def test_modules_2_post(self):
        jwt = signin()
        post_resp = post(url(f'/users/folders/{4}/modules'), headers=auth(jwt),
                         json={'name': 'set1'})
        self.assertEqual(200, post_resp.status_code)
        get_resp = get(url(f'/users/modules'), headers=auth(jwt))
        self.assertEqual(200, get_resp.status_code)
        expected = {'modules': [{'folder_id': None, 'id': 2, 'name': 'general', 'user_id': 1},
                                {'folder_id': 4, 'id': 4, 'name': 'set1', 'user_id': 1}]}
        self.assertEqual(expected, get_resp.json())

    def test_modules_3_post_wrong_parent_id(self):
        jwt = signin()
        post_resp = post(url(f'/users/folders/{1000}/modules'), headers=auth(jwt),
                         json={'name': 'set1'})
        self.assertEqual(400, post_resp.status_code)

    def test_modules_3_post_no_name(self):
        jwt = signin()
        post_resp = post(url(f'/users/folders/{1000}/modules'), headers=auth(jwt))
        self.assertEqual(400, post_resp.status_code)
