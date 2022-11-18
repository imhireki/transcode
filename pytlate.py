#!/bin/python3

import subprocess
import json
import sys

import requests


API = "https://api.reverso.net/translate/v1/translation"

DEFAULT_REQUIRED_DATA = {
    'format': 'text',
    'options': {
        'sentenceSplitter': True,
        'origin': 'translation.web',
        'contextResults': True,
        'languageDetection': True
    }
}


def fetch_translation_results(language_from: str, language_to: str,
                              input: str) -> list[dict]:
    request_data = DEFAULT_REQUIRED_DATA.copy()
    request_data.update({
        "from": language_from,
        "to": language_to,
        "input": input
    })
    response = requests.post(API, json=request_data,
                             headers={"User-Agent": "Mozilla/5.0"})
    return json.loads(response.text)['contextResults']['results']

def get_translation_examples(translation_results: list[dict],
                             translation: str,
                             example_type: str) -> list[str]:
    for result in translation_results:
        if translation == result['translation']:
            return result[example_type + 'Examples']
    return []

def get_translations(translation_results: list[dict]) -> list[str]:
    return [data['translation'] for data in translation_results]

def list_on_dmenu(items: list[str]) -> str | None:
    pipe_items = subprocess.Popen(['echo', '\n'.join(items)],
                                  stdout=subprocess.PIPE)
    selected_dmenu_item = subprocess.run(
        ['dmenu', '-c', '-l', str(len(items))],
        stdin=pipe_items.stdout,
        stdout=subprocess.PIPE)
    return selected_dmenu_item.stdout.decode('ascii')[:-1]


if __name__ == '__main__':
    language_from = sys.argv[1]  # eng, por, es, ...
    language_to = sys.argv[2]
    input = sys.argv[3]
    example_type='source'  # source / target

    translation_results = fetch_translation_results(
        language_from, language_to, input)
    translations = get_translations(translation_results)
    chosen_translation = list_on_dmenu(translations)

    if not chosen_translation:
        exit()

    examples = get_translation_examples(
        translation_results, chosen_translation, 'source')
    list_on_dmenu(examples) 
    
