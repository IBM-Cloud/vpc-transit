zypper install -y nginx
systemctl start nginx
echo __NAME__ > /srv/www/htdocs/name
sleep 10
curl localhost/name
