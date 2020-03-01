#!/bin/sh
# -------------------------------------------------------------------------------
# project  blog
# file:    commit.sh
# brief    整合多个 git 命令，方便提交文章。
# author:  wenfh2020
# date:    2020-02-18
# note:    ./commit.sh msg1 msg2
# -------------------------------------------------------------------------------

cd `dirname $0`
work_path=`pwd`
cd $work_path

if [ $# -lt 1 ]; then
    echo 'pls input commit message'
    exit 1
fi

_files='images _posts commit.sh refresh.sh _config.yml'
git pull && git add $_files && git commit -m "$(echo "$@")" && git push -u origin master && git status
