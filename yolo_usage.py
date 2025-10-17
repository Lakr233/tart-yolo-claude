#!/usr/bin/env python3

import requests
import os
import json

token = os.getenv("OPENROUTER_API_KEY")

url = "https://openrouter.ai/api/v1/key"
headers = {"Authorization": f"Bearer {token}"}
response = requests.get(url, headers=headers)
print(json.dumps(response.json(), indent=4))
