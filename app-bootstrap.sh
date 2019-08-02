#! /usr/bin/env bash

# Script to set up Canvas management and application servers from bare VM

set -o errtrace
set -o errexit
set -o pipefail

log()  { printf "%b\n" "$*"; }
fail() { fail_with_code 1 "$*" ; }
fail_with_code() { code="$1" ; shift ; log "\nERROR: $*\n" >&2 ; exit "$code" ; }

# Use the proxy for getting out to the internet
export http_proxy=http://proxy.sfu.ca:8080
export https_proxy=http://proxy.sfu.ca:8080

# Enable root ssh with key
/usr/local/canvas/enable-rootssh-nsx

# Update packages
log "Updating installed yum packages"
yum -y update || fail "Could not update yum packages"

# Enable other repos
subscription-manager repos --enable rhel-7-server-optional-rpms
subscription-manager repos --enable rhel-server-rhscl-7-rpms
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>&1 | tee /tmp/yum.output && cat /tmp/yum.output && rm /tmp/yum.output
yum-config-manager --enable epel 

# Add local canvasuser account
log "Adding local canvasuser account"
id -u canvasuser &>/dev/null || useradd canvasuser || fail "Could not add canvasuser account"

# Install passenger's license file
passenger_license_file=/usr/local/canvas/passenger/passenger-enterprise-license
if [ -f "$passenger_license_file" ]; then
  cp $passenger_license_file /etc/passenger-enterprise-license
else
  fail "Could not copy Passenger Enterprise License file"
fi

# Set passenger download token
passenger_download_token=$(cat /usr/local/canvas/passenger/passenger-download-token)

# Install packages
yum -y groupinstall "Development Tools"
yum install -y yum-utils scl-utils libcurl-devel zlib-devel openssl-devel

# Install Ruby 2.5.5 pre-compiled in /usr/local/canvas
cd /usr/local/canvas/src/rhel7/ruby/ruby-2.5.5 && make install && gem install bundler --version 1.17.3 --no-ri --no-rdoc && cd -

# Install apache
yum install -y httpd httpd-devel

# Install Passenger from Gems
gem source --add https://download:"$passenger_download_token"@www.phusionpassenger.com/enterprise_gems/
gem install passenger-enterprise-server --no-rdoc --no-ri
passenger-install-apache2-module --auto --languages ruby

# Validate passenger installation
# systemctl restart httpd
# passenger-config validate-install --validate-apache2 --auto || fail "Passenger installation verification failed"

# Remove git 1.8 and install git 2
yum -y remove git*
yum -y install  https://centos7.iuscommunity.org/ius-release.rpm
yum -y install  git2u-all

# Install Canvas dependencies
yum install -y https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-redhat96-9.6-3.noarch.rpm && \
yum install -y  \
  postgresql96-devel \
  postgresql96-libs \
  sqlite-devel \
  libxslt libxslt-devel \
  libxml2 libxml2-devel \
  xmlsec1-devel \
  xmlsec1-openssl-devel \
  libtool-ltdl-devel
ln -s /usr/pgsql-9.6/bin/pg_config /usr/local/bin

# Set up Canvas installation directory structure
mkdir -p /var/rails/canvas/{releases,shared/{log,tmp/pids}}
chown -R canvasuser: /var/rails
