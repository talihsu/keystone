#!/bin/bash
set -x

# Check if init is done
INIT_DONE=/etc/init_done
if ! [ -f $INIT_DONE ]; then
    touch $INIT_DONE
else
    service memcached start
    service rabbitmq-server start
    service mysql start

    # keystone
    uwsgi --http 0.0.0.0:5000 --wsgi-file $(which keystone-wsgi-public) &
	sleep 5
	uwsgi --http 0.0.0.0:35357 --wsgi-file $(which keystone-wsgi-admin)
	exit 0
fi

# Init the arguments
ADMIN_TENANT_NAME=${ADMIN_TENANT_NAME:-admin}
ADMIN_USER_NAME=${ADMIN_USERNAME:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-password}

OS_TOKEN=ADMIN_TOKEN
OS_URL=${OS_AUTH_URL:-"http://127.0.0.1:35357/v3"}
OS_IDENTITY_API_VERSION=3

MYSQL_BIN='/usr/bin/mysql'
HOSTNAME=${HOSTNAME:-keystone}

KEYSTONE_CONFIG_FILE=/etc/keystone/keystone.conf
#APACHE_CONF=/etc/apache2/apache2.conf
MEMCACHE_FILE=/etc/memcached.conf

# Stop apache2 to stop keystone
#service apache2 stop
#sleep 5

# Update apache2.conf
#sed -i "1 i\ServerName $HOSTNAME" $APACHE_CONF

# Set rabbitmq-server
service rabbitmq-server start
sleep 5
rabbitmqctl add_user openstack ${ADMIN_PASSWORD}
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Install MySQL
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password password $ADMIN_PASSWORD"
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password $ADMIN_PASSWORD" 

sudo apt-get install -y mariadb-server 
sudo mv /etc/openstack.cnf /etc/mysql/conf.d

service mysql restart
sleep 5

# Create database
$MYSQL_BIN --user=root --password="$ADMIN_PASSWORD" <<eof 
CREATE DATABASE	if not exists keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$ADMIN_PASSWORD';
eof

# Add hostname to /etc/hosts
echo "127.0.0.1	${HOSTNAME}" >> /etc/hosts

# Populate the Identity service database
su -s /bin/sh -c "keystone-manage db_sync" keystone

# Initialize fernet keys
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Enable the Identity service virtual hosts
ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled

# Start keystone service 
uwsgi --http 0.0.0.0:35357 --wsgi-file $(which keystone-wsgi-admin) &
sleep 5
#service apache2 start
#sleep 10 # wait for start

# Initialize keystone
export OS_TOKEN OS_URL OS_IDENTITY_API_VERSION

openstack service create  --name keystone identity
openstack endpoint create --region RegionOne identity public http://${HOSTNAME}:5000/v3
openstack endpoint create --region RegionOne identity internal http://${HOSTNAME}:5000/v3
openstack endpoint create --region RegionOne identity admin http://${HOSTNAME}:35357/v3
openstack domain create --description "Default Domain" default
openstack project create --domain default --description "Admin Project" admin
openstack user create --domain default --password ${ADMIN_PASSWORD} admin
openstack role create admin
openstack role add --project admin --user admin admin
openstack project create --domain default --description "Service Project" service
openstack role create user
openstack role create heat_stack_owner # for heat

unset OS_TOKEN OS_URL

# Write openrc to disk
cat >~/adminrc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASSWORD}
export OS_AUTH_URL=http://${HOSTNAME}:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat ~/adminrc
source ~/adminrc

# reboot services
pkill uwsgi
sleep 5
uwsgi --http 0.0.0.0:5000 --wsgi-file $(which keystone-wsgi-public) &
sleep 5
uwsgi --http 0.0.0.0:35357 --wsgi-file $(which keystone-wsgi-admin)
