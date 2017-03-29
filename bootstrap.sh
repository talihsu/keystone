#!/bin/bash
set -x

# Stop apache2 server
service apache2 stop

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
	sleep 3
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

# Set rabbitmq-server
service rabbitmq-server start
sleep 3
rabbitmqctl add_user openstack ${ADMIN_PASSWORD}
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Add hostname to /etc/hosts
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts

# Start mysql
service mysql start
sleep 3

# Create database
$MYSQL_BIN --user=root --password="$ADMIN_PASSWORD" <<eof 
CREATE DATABASE	if not exists keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$ADMIN_PASSWORD';
eof

# Populate the Identity service database
su -s /bin/sh -c "keystone-manage db_sync" keystone

# Initialize fernet keys
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Start keystone service 
uwsgi --http 0.0.0.0:35357 --wsgi-file $(which keystone-wsgi-admin) &
sleep 3

# Bootstrap the Identity service
keystone-manage bootstrap --bootstrap-password ${ADMIN_PASSWORD} --bootstrap-admin-url http://${HOSTNAME}:35357/v3/ --bootstrap-internal-url http://${HOSTNAME}:35357/v3/ --bootstrap-public-url http://${HOSTNAME}:5000/v3/ --bootstrap-region-id RegionOne

# Initialize keystone
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

openstack project create --domain default --description "Service Project" service
openstack role create user

# reboot services
pkill uwsgi
sleep 3
uwsgi --http 0.0.0.0:5000 --wsgi-file $(which keystone-wsgi-public) &
sleep 3
uwsgi --http 0.0.0.0:35357 --wsgi-file $(which keystone-wsgi-admin)
