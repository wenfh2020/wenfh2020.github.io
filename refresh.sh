# wenfh2020/2020-02-18/refresh for browser

#!/bin/sh

cd `dirname $0`
work_path=`pwd`
cd $work_path

[ -d _site ] rm -r _site
jekyll s --incremental
