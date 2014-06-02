#!/bin/bash

git pull origin master

rm ../_posts/evernote/*.html
mkdir -p ../_posts/evernote
mkdir -p ../assets/evernote

coffee fetch.coffee

git add ../_posts
git add ../assets
git commit -m 'update posts from Evernote'

git push origin master

cd ..
./_deploy.sh
