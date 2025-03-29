#!/bin/sh
# -------------------------------------------------------------------------------
# brief    server run in docker.
# author:  wenfh2020.com
# date:    2025-03-29
# note:    docker run -d --name my-blog -p 4000:4000 -v "$(pwd)":/home/blog crpi-ogok7v08unnpdeus.cn-shenzhen.personal.cr.aliyuncs.com/wenfh2020/ubuntu-jekyll-ruby-bundle:v1 /home/blog/run_blog_for_docker.sh
# -------------------------------------------------------------------------------

cd $(dirname $0)
work_path=$(pwd)
cd $work_path

# 有时候不能实时刷新，需要删除 _site 目录，重新启动。
[ -d _site ] && rm -r _site
# jekyll serve -wIt
/root/.rbenv/shims/bundle exec jekyll serve --host 0.0.0.0 --port 4000
