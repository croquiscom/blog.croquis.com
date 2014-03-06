#!/bin/bash
SERVER=croquis@homepage.croquis.com
TARGET=_site/blog.croquis.com

jekyll build
cd _site
rsync -az --delete --exclude .git . $SERVER:$TARGET
