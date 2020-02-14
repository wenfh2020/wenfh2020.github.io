#!/bin/sh

cd `dirname $0`
work_path=`pwd`
cd $work_path

rm -r _site
jekyll s --incremental