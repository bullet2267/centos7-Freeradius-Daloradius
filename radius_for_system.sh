#!/bin/bash
function centos1_ntp(){
	setenforce 0
	sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
	yum -y install ntp
	service ntpd restart
	cd /root
	echo '0-59/10 * * * * /usr/sbin/ntpdate -u cn.pool.ntp.org' >> /tmp/crontab.back
	crontab /tmp/crontab.back
	systemctl restart crond
	yum install net-tools -y
	yum install epel-release -y
	systemctl stop firewalld
    systemctl disable firewalld
    yum install lynx wget expect iptables -y
}
function set_shell_input1() {
	sqladmin=radius
	yum install lynx -y
	public_ip=`lynx --source www.monip.org | sed -nre 's/^.* (([0-9]{1,3}\.){3}[0-9]{1,3}).*$/\1/p'`
	#解决ssh访问慢的问题,可以安装完脚本后手工重启ssh
	sed -i "s/GSSAPIAuthentication yes/GSSAPIAuthentication no/g" /etc/ssh/sshd_config
	alias cp='cp'
	yum groupinstall "Development tools" -y
	yum install wget zip nano unzip vim expect telnet net-tools httpd mariadb-server php php-mysql php-gd php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap curl curl-devel -y
	yum install freeradius freeradius-mysql freeradius-utils -y
	systemctl restart mariadb
	systemctl restart httpd
}
#配置radius数据库并导入数据
function set_mysql2() {
	systemctl restart mariadb
	sleep 3
	mysqladmin -u root password ""${sqladmin}""
	mysql -uroot -p${sqladmin} -e "create database radius;"
	mysql -uroot -p${sqladmin} -e "grant all privileges on radius.* to radius@localhost identified by 'radius';"
	mysql -uradius -p'radius' radius < /etc/raddb/mods-config/sql/main/mysql/schema.sql  
	systemctl restart mariadb
}

function set_freeradius3(){
	ln -s /etc/raddb/mods-available/sql /etc/raddb/mods-enabled/
	sed -i "s/auth = no/auth = yes/g" /etc/raddb/radiusd.conf
	sed -i "s/auth_badpass = no/auth_badpass = yes/g" /etc/raddb/radiusd.conf
	sed -i "s/auth_goodpass = no/auth_goodpass = yes/g" /etc/raddb/radiusd.conf
	sed -i "s/\-sql/sql/g" /etc/raddb/sites-available/default
	#在查找到的session {字符串后面插入内容
	sed -i '/session {/a\        sql' /etc/raddb/sites-available/default
	sed -i 's/driver = "rlm_sql_null"/driver = "rlm_sql_mysql"/g' /etc/raddb/mods-available/sql	
	#查找到字符串，去掉首字母为的注释#
	sed -i '/read_clients = yes/s/^#//' /etc/raddb/mods-available/sql
	sed -i '/dialect = "sqlite"/s/^#//' /etc/raddb/mods-available/sql
	sed -i 's/dialect = "sqlite"/dialect = "mysql"/g' /etc/raddb/mods-available/sql	
	sed -i '/server = "localhost"/s/^#//' /etc/raddb/mods-available/sql
	sed -i '/port = 3306/s/^#//' /etc/raddb/mods-available/sql
	sed -i '/login = "radius"/s/^#//' /etc/raddb/mods-available/sql
	sed -i '/password = "radpass"/s/^#//' /etc/raddb/mods-available/sql
	sed -i 's/password = "radpass"/password = "radius"/g' /etc/raddb/mods-available/sql	
	systemctl restart radiusd
	sleep 3
}
function set_daloradius4(){
	cd /var/www/html/
	wget https://github.com/bullet2267/daloradius/archive/refs/heads/master.zip >/dev/null 2>&1
	unzip master.zip
	mv daloradius-master/ daloradius
	chown -R apache:apache /var/www/html/daloradius/
	chmod 664 /var/www/html/daloradius/library/daloradius.conf.php
	cd /var/www/html/daloradius/
	mysql -uradius -p'radius' radius < contrib/db/fr2-mysql-daloradius-and-freeradius.sql
	mysql -uradius -p'radius' radius < contrib/db/mysql-daloradius.sql
	sleep 3
	sed -i "s/\['CONFIG_DB_USER'\] = 'root'/\['CONFIG_DB_USER'\] = 'radius'/g"  /var/www/html/daloradius/library/daloradius.conf.php
	sed -i "s/\['CONFIG_DB_PASS'\] = ''/\['CONFIG_DB_PASS'\] = 'radius'/g" /var/www/html/daloradius/library/daloradius.conf.php
	yum -y install epel-release
	yum -y install php-pear-DB
	systemctl restart mariadb.service 
	systemctl restart radiusd.service
	systemctl restart httpd
	chmod 644 /var/log/messages
	chmod 755 /var/log/radius/
	chmod 644 /var/log/radius/radius.log
	touch /tmp/daloradius.log
	chmod 644 /tmp/daloradius.log
	chown -R apache:apache /tmp/daloradius.log
}

function set_fix_radacct_table5(){
	cd /tmp
	sleep 3
	wget http://180.188.197.212/down/radacct_new.sql.tar.gz
	tar xzvf radacct_new.sql.tar.gz
	mysql -uradius -p'radius' radius < /tmp/radacct_new.sql
	rm -rf radacct_new.sql.tar.gz
	rm -rf radacct_new.sql
	systemctl restart radiusd
}

function set_iptables6(){
cat >>  /etc/rc.local <<EOF
systemctl start mariadb
systemctl start httpd
systemctl start radiusd
iptables -I INPUT -p tcp --dport 9090 -j ACCEPT
EOF
systemctl start mariadb
systemctl start httpd
systemctl start radiusd
iptables -I INPUT -p tcp --dport 9090 -j ACCEPT
}

function set_web_config7(){
echo  "
Listen 9090
<VirtualHost *:9090>
 DocumentRoot "/var/www/html/daloradius"
 ServerName daloradius
 ErrorLog "logs/daloradius-error.log"
 CustomLog "logs/daloradius-access.log" common
</VirtualHost>
" >> /etc/httpd/conf/httpd.conf
cd /var/www/html/
rm -rf *
wget https://github.com/bullet2267/daloradius/archive/refs/heads/master.zip 
unzip master.zip 
rm -rf master.zip
chown -R apache:apache /var/www/html/daloradius
service httpd restart
mkdir /usr/mysys/
cd /usr/mysys/
wget http://180.188.197.212/down/dbback.tar.gz
tar xzvf dbback.tar.gz
rm -rf dbback.tar.gz
echo 'mysql -uradius -pradius -e "UPDATE radius.radacct SET acctstoptime = acctstarttime + acctsessiontime WHERE ((UNIX_TIMESTAMP(acctstarttime) + acctsessiontime + 240 - UNIX_TIMESTAMP())<0) AND acctstoptime IS NULL;"' >> /usr/mysys/clearsession.sh
chmod +x /usr/mysys/clearsession.sh
echo '0-59/10 * * * * /usr/mysys/clearsession.sh' >> /tmp/crontab.back
echo '0 0 1 * * /usr/mysys/dbback/backup_radius_db.sh' >> /tmp/crontab.back
crontab /tmp/crontab.back
systemctl restart crond
}

function set_radiusclient8(){
yum install radiusclient-ng -y
echo "localhost testing123" >> /etc/radiusclient-ng/servers
echo "switch auth to radius"
sed -i "s/#auth = \"radius\[config=\/etc\/radiusclient-ng\/radiusclient.conf,groupconfig=true\]\"/auth = \"radius\[config=\/etc\/radiusclient-ng\/radiusclient.conf,groupconfig=true\]\"/g" /etc/ocserv/ocserv.conf 
sed -i "s/#acct = \"radius\[config=\/etc\/radiusclient-ng\/radiusclient.conf\]\"/acct = \"radius\[config=\/etc\/radiusclient-ng\/radiusclient.conf\]\"/g" /etc/ocserv/ocserv.conf
sed -i "s/auth = \"plain\[passwd=\/etc\/ocserv\/ocpasswd\]\"/#auth = \"plain\[passwd=\/etc\/ocserv\/ocpasswd\]\"/g" /etc/ocserv/ocserv.conf
#
echo "==========================================================================
                  Centos7 Radius+Daloradius                           
										 
				  /root/info.txt
          
                   mysql root passw:radius      

		          Daloradius URL：http://$public_ip:9090
		                             Login：administrator Password:radius
		           
			  
			   

==========================================================================" > /root/info.txt
	cat /root/info.txt
	exit;
}

function shell_install() {
centos1_ntp
set_shell_input1
set_mysql2
set_freeradius3
set_daloradius4
set_fix_radacct_table5
set_iptables6
set_web_config7
set_radiusclient8
}
shell_install
