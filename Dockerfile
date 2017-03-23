FROM ubuntu:14.04
MAINTAINER Joe "joe_cl_hsu@wiwynn.com"

# Install prerequisite
RUN set -x \
    && apt-get -y update \
    && apt-get install curl nano vim software-properties-common python-pip python-dev -y \
    && add-apt-repository cloud-archive:mitaka -y \
	&& apt-get update && apt-get dist-upgrade -y
	
# Install OpenStack	
RUN set -x \
    && apt-get install python-openstackclient rabbitmq-server memcached python-memcache mysql-client python-mysqldb -y \
	&& echo "manual" > /etc/init/keystone.override \
	&& apt-get install keystone libapache2-mod-wsgi -y \
	&& rm -f /var/lib/keystone/keystone.db
	
RUN set -x \
	&& pip install uwsgi
	
# Copy conf files
#COPY wsgi-keystone.conf /etc/apache2/sites-available/wsgi-keystone.conf
COPY keystone.conf /etc/keystone/keystone.conf
COPY openstack.cnf /etc/openstack.cnf

# Add bootstrap script and make it executable
COPY bootstrap.sh /etc/bootstrap.sh
RUN chown root:root /etc/bootstrap.sh && chmod a+x /etc/bootstrap.sh

ENTRYPOINT ["/etc/bootstrap.sh"]
EXPOSE 5000 35357