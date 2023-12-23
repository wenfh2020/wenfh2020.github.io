import os
import time
import sys

my_path = r'E:\work\myself\wenfh2020.github.io'


def git_auto_commit(commit_message, repo_path='.', is_push=True):
    os.chdir(repo_path)
    try:
        if is_push:
            # os.system('git add .')
            # os.system('git commit -m "{}"'.format(commit_message))
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
    if not git_auto_commit("auto commit", my_path, is_push):
        time.sleep(1)
    else:
        if is_push:
            print("push done!")
        else:
            print("pull done!")
        break
