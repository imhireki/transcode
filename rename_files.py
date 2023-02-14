#!/usr/bin/python3

import sys
import os


def get_file_extension(file_name: str) -> str:
    splitted_file_name = file_name.split('.')
    if len(splitted_file_name) > 1:
        return '.' + splitted_file_name[-1]
    return ''

def get_numeric_units(sequence: list) -> int:
    """list(range(100)) -> 3"""
    return len(str(len(sequence)))

def add_zeros_to_file_id(file_id: str, sorted_files: list) -> str:
    numeric_units = get_numeric_units(sorted_files)
    file_id_numeric_units = len(file_id)

    if file_id_numeric_units < numeric_units:
        # 00X / 0XX
        zeros = (numeric_units - file_id_numeric_units) * '0'
        file_id = f'{zeros}{file_id}'
    elif file_id_numeric_units == 1:
        # 0X
        file_id = f'0{file_id}'
    return file_id


def rename_directory_files(directory: str, prefix: str = '') -> None:
    sorted_files = sorted(os.listdir(directory))

    for file_id, file_name in enumerate(sorted_files, start=1):
        absolute_file_name = f'{directory}/{file_name}'
        file_id_with_zeros = add_zeros_to_file_id(str(file_id), sorted_files)

        file_extension = get_file_extension(file_name)
        new_absolute_file_name = f'{directory}/{prefix}'\
                                 f'{file_id_with_zeros}{file_extension}'

        os.rename(absolute_file_name, new_absolute_file_name)

if __name__ == '__main__':
    rename_directory_files(sys.argv[1], sys.argv[2])

