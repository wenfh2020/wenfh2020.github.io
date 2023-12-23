#!/usr/bin/env python3
# -*- coding: UTF-8 -*-

import os
import time
import sys

my_path = r'E:\work\myself\wenfh2020.github.io'


def git_auto_command(repo_path='.', is_push=True):
    os.chdir(repo_path)
    try:
        if is_push:
            if os.system('git push') != 0:
                return False
        else:
            if os.system('git pull') != 0:
                return False
    except Exception as e:
        print("error: ", str(e))
        return False
    return True


is_push = True
if len(sys.argv) > 1:
    cmd = sys.argv[1]
    if cmd != 'push' and cmd != 'pull':
        print("pls input: auto_commit [push/pull]")
        exit(1)
    is_push = (cmd == 'push')

while True:
    if not git_auto_command(my_path, is_push):
        time.sleep(1)
    else:
        print("push done!") if is_push else print("pull done!")
        break
