import json
import os
import urllib.request

def openrouter_chat(model, prompt):
    key = os.environ.get('OPENROUTER_API_KEY', '')
    data = json.dumps({
        'model': model,
        'messages': [{'role': 'user', 'content': prompt}]
    }).encode('utf-8')
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions',
        data,
        {'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'}
    )
    response = urllib.request.urlopen(req).read()
    return json.loads(response)['choices'][0]['message']['content']

def openrouter_embed(model, text):
    key = os.environ.get('OPENROUTER_API_KEY', '')
    data = json.dumps({
        'model': model,
        'input': text
    }).encode('utf-8')
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/embeddings',
        data,
        {'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'}
    )
    response = urllib.request.urlopen(req).read()
    return json.loads(response)['data'][0]['embedding']
