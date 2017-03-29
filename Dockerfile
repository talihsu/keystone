FROM ubuntu:16.04
MAINTAINER Joe "talihsu@gmail.com"

# Install prerequisite
RUN set -x \
    && apt-get -y update \
    && apt-get install nano software-properties-common python-pip python-dev -y \
    && add-apt-repository cloud-archive:newton -y \
    && apt-get update && apt dist-upgrade -y 

# Install OpenStack
RUN set -x \
    && echo "mysql-server mysql-server/root_password password password" | debconf-set-selections \
    && echo "mysql-server mysql-server/root_password_again password password" | debconf-set-selections \
    && apt-get install mysql-server mysql-client -y \
    && apt-get install python-openstackclient rabbitmq-server memcached python-memcache python-mysqldb -y \
    && pip install uwsgi \
    && apt-get install keystone libapache2-mod-wsgi -y \
    && apt-get clean && apt-get autoclean && apt-get autoremove \
    && rm -f /var/lib/keystone/keystone.db

# Copy conf files
COPY keystone.conf /etc/keystone/keystone.conf 
COPY keystone-paste.ini /etc/keystone/keystone-paste.ini
COPY mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf

# Add bootstrap script and make it executable
COPY bootstrap.sh /etc/bootstrap.sh
RUN chown root:root /etc/bootstrap.sh && chmod a+x /etc/bootstrap.sh

ENTRYPOINT ["/etc/bootstrap.sh"]
EXPOSE 5000 35357
