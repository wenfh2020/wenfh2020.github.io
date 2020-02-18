# wenfh2020/2020-02-18/auto commit to github

#!/bin/sh

cd `dirname $0`
work_path=`pwd`
cd $work_path

if [ $# == 0 ]; then
    echo 'pls input commit message'
    exit 1
fi

git add _posts && git commit -m $@ && git push -u origin master
