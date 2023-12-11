zypper install -y nginx postgresql
systemctl start nginx
echo __NAME__ > /srv/www/htdocs/name
sleep 10
curl localhost/name
