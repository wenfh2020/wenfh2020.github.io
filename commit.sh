#!/bin/sh
# wenfh2020/2020-02-18/./commit.sh msg1 msg2

cd `dirname $0`
work_path=`pwd`
cd $work_path

if [ $# -lt 1 ]; then
    echo 'pls input commit message'
    exit 1
fi

echo $@
exit 1

git pull && git add _posts && git commit -m "$(echo "$@")" && git push -u origin master