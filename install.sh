#!/bin/bash
reset
install_basics() {
	# INSTALLING REQUIRED PACKAGES
	yum install nano epel-release wget -y;
	yum install unzip net-tools iperf3 htop atop nload net-snmp net-snmp-utils -y;
	
	# DISABLING SELINUX
	setenforce 0;
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux;
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config;

	# INSTALLING REMI RELEASE
	sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	sudo yum -y install https://rpms.remirepo.net/enterprise/remi-release-7.rpm
	sudo yum -y install yum-utils

	# DISABLING NETWORK MANAGER
	service NetworkManager stop;
	chkconfig NetworkManager off;

	# DISABLING FIREWALL
	service firewalld stop;
	chkconfig firewalld off;

	echo "Basic preparation has been completed successfully."
}


install_mariadb() {
	cat >/etc/yum.repos.d/MariaDB.repo <<EOL
# MariaDB 10.5 CentOS repository list - created 2021-05-13 17:27 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOL

	yum install MariaDB-server MariaDB-client -y;
	# RESTARTING SERVICES & ENABLING SERVICES FOR AUTOSTART ON BOOT
	sleep 1;
	service mariadb restart;
	sleep 1;
	chkconfig mariadb on;

	echo "MariaDB has been installed successfully."
}

install_nginx() {
	yum install nginx -y
	# RESTARTING SERVICES & ENABLING SERVICES FOR AUTOSTART ON BOOT
	service nginx restart;
	chkconfig nginx on;

	echo "nginx has been installed successfully."
}

install_php() {
	# INSTALLING PHP PACKAGES
	yum --enablerepo=remi-php74 install php php-cli -y;
	yum --enablerepo=remi-php74 install php-fpm php-opcache php-pdo php-gd php-mbstring php-mcrypt php-pear php-mysqlnd php-bcmath php-json php-xml php-sqlite3 php-curl -y;
	pear channel-update pear.php.net
	pear install Net_IPv4;

	# CHANGING USER & GROUP PERMISSIONS TO NGINX
	find /etc/php-fpm.d/ -type f -exec sed -i 's/apache/nginx/g' {} +;
	mkdir /var/www/html;
	mkdir /var/lib/php/session;
	mkdir /var/lib/php/wsdlcache;
	chown nginx:nginx /var/lib/php/session;
	chown nginx:nginx /var/lib/php/wsdlcache;
	chown nginx:nginx /var/lib/php/opcache;
	# RESTARTING SERVICES & ENABLING SERVICES FOR AUTOSTART ON BOOT
	sleep 1;
	service php-fpm restart;
	sleep 1;
	chkconfig php-fpm on;

	echo "PHP-FPM has been installed successfully."
}


create_db() {
	DBNAME="${1}"
    DBUSER="${2}"
    DBPASS="${3}"

	#CREATING MYSQL USER WITH GRANT PRIVILEGES & DATABASE
    mysql -e "CREATE USER '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${DBUSER}'@'localhost' with GRANT OPTION;"
	mysql -e "CREATE DATABASE ${DBNAME}";
	mysql -e "ALTER DATABASE ${DBNAME} DEFAULT CHARSET=utf8 COLLATE utf8_general_ci";

	echo "Database has been created successfully."
}

install_phpmyadmin() {
	wget "https://files.phpmyadmin.net/phpMyAdmin/5.1.0/phpMyAdmin-5.1.0-english.tar.gz" -O "/var/www/html/phpMyAdmin-5.1.0-english.tar.gz";
	tar -zxf "/var/www/html/phpMyAdmin-5.1.0-english.tar.gz" --directory /var/www/html;
	mv "/var/www/html/phpMyAdmin-5.1.0-english" "/var/www/html/phpmyadmin";
	mv "/var/www/html/phpmyadmin/config.sample.inc.php" "/var/www/html/phpmyadmin/config.inc.php";
	RANDOMHASH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
	sed -i 's/\$cfg\[\x27blowfish_secret\x27\] = \x27\x27;/\$cfg\[\x27blowfish_secret\x27\] = \x27'"$RANDOMHASH"'\x27;/g' "/var/www/html/phpmyadmin/config.inc.php"
	chown nginx:nginx /var/www/html/ -R -f;
	rm -Rf "/var/www/html/phpMyAdmin-5.1.0-english.tar.gz";
}

configure_nginx() {

	cat >/etc/nginx/default.d/php.conf <<EOL
		root   /var/www/html;
		location / {
                index index.php index.html index.htm;
                try_files \$uri \$uri/ /index.php?\$query_string;
    	}	

    	add_header 'X-Frame-Options' 'DENY';
    	add_header 'X-Frame-Options' 'SAMEORIGIN';
    	add_header 'Access-Control-Allow-Origin' '*';
    	add_header 'X-Content-Type-Options' 'nosniff';
    	add_header 'X-XSS-Protection' '1; mode=block';

    	server_tokens off;

    	location ~* \.php\$ {
        	root           /var/www/html;
        	try_files $uri =404;
        	fastcgi_pass   127.0.0.1:9000;
        	fastcgi_index  index.php;
        	fastcgi_param  SCRIPT_FILENAME  /var/www/html\$fastcgi_script_name;
        	include        fastcgi_params;
        	fastcgi_buffers 16 16k;
        	fastcgi_buffer_size 32k;
    	}

    	# deny access to .htaccess files, if Apache's document root
    	# concurs with nginx's one
    	
    	location ~ /\.ht {
        deny  all;
    	}
EOL
	sed -i 's/root/#root/g' /etc/nginx/nginx.conf;
	sed -i.bak '47d;48d' /etc/nginx/nginx.conf
	service php-fpm restart;
	service httpd stop;
	chkconfig httpd off;
	service nginx restart;

}


configure_nginx_laravel() {

	cat >/etc/nginx/default.d/laravel.conf <<EOL
		root   /var/www/html/laravel/public;
		location / {
                index index.php index.html index.htm;
                try_files \$uri \$uri/ /index.php?\$query_string;
    	}	

    	add_header 'X-Frame-Options' 'DENY';
    	add_header 'X-Frame-Options' 'SAMEORIGIN';
    	add_header 'Access-Control-Allow-Origin' '*';
    	add_header 'X-Content-Type-Options' 'nosniff';
    	add_header 'X-XSS-Protection' '1; mode=block';

    	server_tokens off;

        location /phpmyadmin {
            root /var/www/html;
            index index.php;
            location ~ ^/phpmyadmin/(.+\.php)\$ {
                    try_files \$uri =404;
                    root /var/www/html;
                    fastcgi_pass 127.0.0.1:9000;
                    fastcgi_index index.php;
                    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                    include fastcgi_params;
                    fastcgi_buffers 16 16k;
                    fastcgi_buffer_size 32k;
            }
            location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
                    root /var/www/html;
            }
		}

    	location ~ \.php\$ {
        	root           /var/www/html/laravel/public;
        	fastcgi_pass   127.0.0.1:9000;
        	fastcgi_index  index.php;
        	fastcgi_param  SCRIPT_FILENAME  /var/www/html/laravel/public\$fastcgi_script_name;
        	include        fastcgi_params;
        	fastcgi_buffers 16 16k;
        	fastcgi_buffer_size 32k;
    	}

    	# deny access to .htaccess files, if Apache's document root
    	# concurs with nginx's one
    	
    	location ~ /\.ht {
        deny  all;
    	}
EOL
	sed -i 's/root/#root/g' /etc/nginx/nginx.conf;
	sed -i.bak '47d;48d' /etc/nginx/nginx.conf
}

install_laravel() {
	php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
	php composer-setup.php
	php -r "unlink('composer-setup.php');"
	mv composer.phar /usr/local/bin/composer;
	composer create-project laravel/laravel /var/www/html/laravel;
	chown nginx:nginx /var/www/html/ -R -f;
	sed -i 's/;cgi\.fix_pathinfo=1/cgi\.fix_pathinfo=0/g' /etc/php.ini;
	service php-fpm restart;
	service httpd stop;
	chkconfig httpd off;
	service nginx restart;
}


echo "CentOS 7 | nginx + MariaDB + PHP-FPM Stack Kickstart Installer"
echo "----------------------------------------------------------------"
echo "  1) Install NMP Stack"
echo "  2) Install NMP Stack + phpMyAdmin 5.x"
echo "  3) Install NMP Stack + phpMyAdmin 5.x + Create a DB with grant privileged user"
echo "  4) Install NMP Stack + phpMyAdmin 5.x + Create a DB with grant privileged user + Laravel"
echo "  5) Quit" 

read n
case $n in
  1) 
	echo "You chose Install NMP Stack"
	install_basics
	install_nginx
	install_php
	install_mariadb
	;;
  2) 
	echo "You chose NMP Stack + phpMyAdmin 5.x"
	install_basics
	install_nginx
	install_php
	install_mariadb
	install_phpmyadmin
	;;
  3) 
	echo "You chose Install NMP Stack + phpMyAdmin 5.x + Create a DB with grant privileged user"
	read -p "Enter database name: " DBNAME
	read -p "Enter database username: " DBUSER
	read -p "Enter database password: " DBPASS
	
	echo "Don't forget to copy the following information, Creation will start after 5 seconds ...";
	echo "Database name:" $DBNAME;
	echo "Database username:" $DBUSER;
	echo "Database password:" $DBPASS;
	sleep 5;
	

	if [ -z "$DBNAME" ] || [ -z "$DBUSER" ] || [ -z "$DBPASS" ]
	then
		echo 'Input cannot be blank, Please try again.'
		exit 0
	fi

	install_basics
	install_nginx
	install_php
	install_mariadb
	create_db $DBNAME $DBUSER $DBPASS;
	install_phpmyadmin
	configure_nginx

	;;
  4) 
	echo "You chose Install NMP Stack + phpMyAdmin 5.x + Create a DB with grant privileged user"
	read -p "Enter database name: " DBNAME
	read -p "Enter database username: " DBUSER
	read -p "Enter database password: " DBPASS
	
	echo "Don't forget to copy the following information, Creation will start after 5 seconds ...";
	echo "Database name:" $DBNAME;
	echo "Database username:" $DBUSER;
	echo "Database password:" $DBPASS;
	sleep 5;
	

	if [ -z "$DBNAME" ] || [ -z "$DBUSER" ] || [ -z "$DBPASS" ]
	then
		echo 'Input cannot be blank, Please try again.'
		exit 0
	fi

	install_basics
	install_nginx
	install_php
	install_mariadb
	create_db $DBNAME $DBUSER $DBPASS;
	install_phpmyadmin
	install_laravel
	configure_nginx_laravel

	;;
  5) 
	echo "Bye Bye"
	exit
	
	;;
  *) 
	echo "invalid option"

	;;
esac


