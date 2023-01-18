from requests import get, post


def url(string):
    return 'http://127.0.0.1:5000' + string


response = post(url('/signup'), json={"login": "example2000", "password": "strong"})
print(response.json())

response = post(url('/signup'), json={"login": "example2000", "password": "strong"})
print(response.json())

response = post(url('/signin'), json={"login": "example2000", "password": "strong"})
jwt = response.json()['access_token']
print(response.json())

response = get(url('/user'), headers={'Authorization': f'Bearer {jwt}'})
print(response.json())
