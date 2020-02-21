#!/bin/sh
# wenfh2020/2020-02-18/refresh for browser

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

jekyll serve -wIt
