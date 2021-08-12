#!/bin/bash
apt-get update
apt-get install -y nginx
wget https://raw.githubusercontent.com/CristianR11/IBM-Cloud-VPC-balanceo-de-carga/main/nginx-config/default
wget https://raw.githubusercontent.com/CristianR11/IBM-Cloud-VPC-balanceo-de-carga/main/nginx-config/index.html
rm /var/www/html/*
mv index.html /var/www/html/index.html
rm /etc/nginx/sites-enabled/*
mv default /etc/nginx/sites-enabled/default
service nginx start
nginx -s reload
nginx -s reload
sudo nginx -s reload