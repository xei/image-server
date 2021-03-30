import base64
import hashlib

def generate_url_token(url, secret_key):
  md5_digest = hashlib.md5(
    ("%s %s" % (url, secret_key)).encode("utf-8")
  ).digest()
  base64_encoded = base64.b64encode(md5_digest).decode("utf-8")
  # Make the key look like Nginx expects.
  token = base64_encoded.replace('+', '-').replace('/', '_').rstrip('=')
  return token

def make_url_secure(url, secret_key):
  token = generate_url_token(url, secret_key)
  return "%s?token=%s" % (url, token)


def main():
  SECRET_KEY = "MY_SECRET_KEY"
  image_url = "https://img.example.com/img/nowm/watermark.png"
  secure_url = make_url_secure(image_url, SECRET_KEY)
  print(secure_url)


main()