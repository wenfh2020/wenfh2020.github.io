#!/bin/sh
# -------------------------------------------------------------------------------
# project  refresh
# file:    refresh.sh
# brief    rebuild blog to run.
# author:  wenfh2020
# date:    2020-02-18
# note:    nohup ./refresh.sh >> /tmp/blog_log.txt 2>&1 &
# -------------------------------------------------------------------------------

cd `dirname $0`
work_path=`pwd`
cd $work_path

# find and kill
_pids=`ps -ef | grep 'jekyll serve' | grep -v grep | awk '{print $2}'`
for p in $_pids
do
    echo "kill pid=$p"
    kill -9 $p
done

git pull
[ -d _site ] && rm -r _site
jekyll serve -wIt
