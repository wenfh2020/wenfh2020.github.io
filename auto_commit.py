import os
import time


def git_auto_commit(commit_message, repo_path='.'):
    os.chdir(repo_path)
    try:
        # os.system('git add .')
        # os.system('git commit -m "{}"'.format(commit_message))
        if os.system('git push') != 0:
            return False
    except Exception as e:
        print("出现错误: ", str(e))
        return False
    return True


while True:
    r = git_auto_commit("自动提交", r'E:\work\myself\wenfh2020.github.io')
    if not r:
        time.sleep(1)
    else:
        print("done!")
        break
