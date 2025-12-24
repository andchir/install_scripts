#!/usr/bin/env python3
"""Quick verification script to see the actual API output"""
import os
import sys
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

from app import app

if __name__ == '__main__':
    app.config['TESTING'] = True
    client = app.test_client()

    response = client.get('/api/scripts_list')
    data = response.get_json()

    print("API Response:")
    print(json.dumps(data, indent=2))

    print("\nScript names:")
    for script in data['scripts']:
        print(f"  - {script['name']}")
