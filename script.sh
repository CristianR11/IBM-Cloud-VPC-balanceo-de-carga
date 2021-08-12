#!/bin/bash
apt-get update
apt-get install -y nginx
wget 
rm /var/www/html/*
mv index.html /var/www/html/index.html
rm /etc/nginx/sites-enabled/*
mv default /etc/nginx/sites-enabled/default
service nginx start
nginx -s reload