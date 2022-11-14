#!/bin/python3

import sys
import os


def get_file_extension(file_name: str) -> str:
    splitted_file_name = file_name.split('.')
    if len(splitted_file_name) > 1:
        return '.' + splitted_file_name[-1]
    return ''

def rename_directory_files(directory: str, prefix: str = '') -> None:
    sorted_files = sorted(os.listdir(directory))

    for file_id, file_name in enumerate(sorted_files, start=1):
        absolute_file_name = f'{directory}/{file_name}'

        file_extension = get_file_extension(file_name)
        new_absolute_file_name = f'{directory}/{prefix}'\
                                 f'{file_id}{file_extension}'

        os.rename(absolute_file_name, new_absolute_file_name)

if __name__ == '__main__':
    rename_directory_files(sys.argv[1], sys.argv[2])

