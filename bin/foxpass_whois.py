#!/usr/bin/env python

import json
import requests
import sys

API_KEY="<key>"

def main(args):
   headers = {"Authorization" : "Token " + API_KEY}
   for item in args:
       response = requests.get(
           "https://api.foxpass.com/v1/users/{}/".format(item),
                            headers=headers)
   data = json.loads(response.text)['data']
   print(data)

if __name__ == "__main__":
    main(sys.argv)
