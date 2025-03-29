#!/bin/bash

cd $(dirname $0)
work_path=$(pwd)
cd $work_path

docker run -d --name my-blog -p 4000:4000 -v "$(pwd)":/home/blog crpi-ogok7v08unnpdeus.cn-shenzhen.personal.cr.aliyuncs.com/wenfh2020/ubuntu-jekyll-ruby-bundle:v1 /home/blog/run_blog_for_docker.sh
