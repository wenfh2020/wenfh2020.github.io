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

git pull && git add images _posts && git commit -m "$(echo "$@")" && git push -u origin master
