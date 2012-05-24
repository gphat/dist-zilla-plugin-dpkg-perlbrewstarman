package Dist::Zilla::Plugin::Dpkg::PerlbrewStarman;
use Moose;

use Moose::Util::TypeConstraints;

extends 'Dist::Zilla::Plugin::Dpkg';

enum 'WebServer', [qw(apache nginx all)];

#ABSTRACT: Generate dpkg files for your perlbrew-backed, starman-based perl app

=head1 SYNOPSIS

  #  [Dpkg::PerlbrewStarman]
  
=head1 DESCRIPTION

Dist::Zilla::Plugin::Dpkg::PerlbrewStarman is an extension of
Dist::Zilla::Plugin::Dpkg. It generates Debian control files that are
suitable for a perl app that includes it's own Perlbrew and runs under
Starman.  It makes the following assumptions:

=over 4

=item XXX Perlbrew

=item Runs under L<Starman>

=item Starman is fronted by nginx or apache

=item It runs as a user called $packagename

=item It's installed at /srv/$packagename

=item Logs will be placed in /var/log/$packagename

=item psgi file is in script and is named $packagename.psgi

=item Config is in config/ and can be found by your app with nothing more than it's HOME variable set. (FOO_BAR_HOME)

=item Nginx config is in config/nginx/$packagename.conf or Apache config is at config/apache/$packagename.conf

=item Your app can be preloaded

=item Your app only listens on localhost (nginx/apache handles the rest)

=item You want 5 workers

=back

This module provides defaults for the following attribute:

=over 4

=item conffiles_template_default

=item control_template_default

=item default_template_default

=item init_template_default

=item install_template_default

=item postinst_template_default

=item postrm_template_default

=back

=cut

has '+conffiles_template_default' => (
    default => '/etc/default/{$package_name}
/etc/init.d/{$package_name}
'
);

has '+control_template_default' => (
    default => 'Source: {$package_name}
Section: {$package_section}
Priority: {$package_priority}
Maintainer: {$author}
Build-Depends: {$package_depends}
Standards-Version: 3.8.4

Package: {$package_name}
Architecture: {$architecture}
Depends: adduser {$package_binary_depends}
Description: {$package_description}
'
);

has '+default_template_default' => (
    default => '# Defaults for {$package_name} initscript
# sourced by /etc/init.d/{$package_name}
# installed at /etc/default/{$package_name} by the maintainer scripts

#
# This is a POSIX shell fragment
#

APP="{$package_name}"
APPDIR="/srv/$APP"
APPLIB="/srv/$APP/lib"
APPUSER={$package_name}

PSGIAPP="script/$APP.psgi"
PIDFILE="/var/run/$APP.pid"

PERLBREW_PATH="$APPDIR/perlbrew/bin"

DAEMON_ARGS="-Ilib $PSGIAPP --daemonize --user $APPUSER --preload-app --workers 5 --pid $PIDFILE --port {$starman_port} --host 127.0.0.1 --error-log /var/log/$APP/error.log"
'
);

has '+init_template_default' => (
    default => '#!/bin/sh
### BEGIN INIT INFO
# Provides:          {$package_name}
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: {$name}
# Description:       {$name}
#                    <...>
#                    <...>
### END INIT INFO

# Author: {$author}

DESC={$package_name}
NAME={$package_name}
SCRIPTNAME=/etc/init.d/$NAME

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

PATH=$PERLBREW_PATH:$PATH
DAEMON=`which starman`

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

check_running() \{
    [ -s $PIDFILE ] && kill -0 $(cat $PIDFILE) >/dev/null 2>&1
\}

check_compile() \{
  if ( cd $APPLIB ; find -type f -name \'*.pm\' | xargs perl -c ) ; then
    return 1
  else
    return 0
  fi
\}

_start() \{

  export {$package_shell_name}_HOME=$APPDIR
  /sbin/start-stop-daemon --start --pidfile $PIDFILE --chdir $APPDIR --exec $DAEMON -- \
    $DAEMON_ARGS \
    || return 2

  echo ""
  echo "Waiting for $APP to start..."

  for i in `seq {$startup_time}` ; do
    sleep 1
    if check_running ; then
      echo "$APP is now starting up"
      return 0
    fi
  done

  return 1
\}

start() \{
    log_daemon_msg "Starting $APP"
    echo ""

    if check_running; then
        log_progress_msg "already running"
        log_end_msg 0
        exit 0
    fi

    rm -f $PIDFILE 2>/dev/null

    _start
    log_end_msg $?
    return $?
\}

stop() \{
    log_daemon_msg "Stopping $APP"
    echo ""

    /sbin/start-stop-daemon --stop --oknodo --pidfile $PIDFILE
    sleep 3
    log_end_msg $?
    return $?
\}

restart() \{
    log_daemon_msg "Restarting $APP"
    echo ""

    if check_compile ; then
        log_failure_msg "Error detected; not restarting."
        log_end_msg 1
        exit 1
    fi

    /sbin/start-stop-daemon --stop --oknodo --pidfile $PIDFILE
    _start
    log_end_msg $?
    return $?
\}


# See how we were called.
case "$1" in
    start)
        start
    ;;
    stop)
        stop
    ;;
    restart|force-reload)
        restart
    ;;
    *)
        echo $"Usage: $0 \{start|stop|restart\}"
        exit 1
esac
exit $?
'
);

has '+install_template_default' => (
    default => 'config/* srv/{$package_name}/config
lib/* srv/{$package_name}/lib
root/* srv/{$package_name}/root
script/* srv/{$package_name}/script
perlbrew/* srv/{$package_name}/perlbrew
'
);

has '+postinst_template_default' => (
    default => '#!/bin/sh
# postinst script for {$package_name}
#
# see: dh_installdeb(1)

set -e

# summary of how this script can be called:
#        * <postinst> `configure` <most-recently-configured-version>
#        * <old-postinst> `abort-upgrade` <new version>
#        * <conflictor`s-postinst> `abort-remove` `in-favour` <package>
#          <new-version>
#        * <postinst> `abort-remove`
#        * <deconfigured`s-postinst> `abort-deconfigure` `in-favour`
#          <failed-install-package> <version> `removing`
#          <conflicting-package> <version>
# for details, see http://www.debian.org/doc/debian-policy/ or
# the debian-policy package

PACKAGE={$package_name}

case "$1" in
    configure)

        # Symlink /etc/$PACKAGE to our package`s config directory
        if [ ! -e /etc/$PACKAGE ]; then
            ln -s /srv/$PACKAGE/config /etc/$PACKAGE
        fi

        {$webserver_config_link}

        # Create user if it doesn`t exist.
        if ! id $PACKAGE > /dev/null 2>&1 ; then
            adduser --system {$uid} --home /srv/$PACKAGE --no-create-home \
                --ingroup nogroup --disabled-password --shell /bin/bash \
                $PACKAGE
        fi

        # Setup the perlbrew
        echo "export PATH=~/perlbrew/bin:$PATH" > /srv/$PACKAGE/.profile

        # Make sure this user owns the directory
        chown -R $PACKAGE:adm /srv/$PACKAGE

        # Make the log directory
        if [ ! -e /var/log/$PACKAGE ]; then
            mkdir /var/log/$PACKAGE
            chown -R $PACKAGE:adm /var/log/$PACKAGE
        fi

        {$webserver_restart}
    ;;

    abort-upgrade|abort-remove|abort-deconfigure)
    ;;

    *)
        echo "postinst called with unknown argument: $1" >&2
        exit 1
    ;;
esac

# dh_installdeb will replace this with shell code automatically
# generated by other debhelper scripts.

#DEBHELPER#

exit 0
'
);

has '+postrm_template_default' => (
    default => '#!/bin/sh

set -e

PACKAGE={$package_name}

case "$1" in
    purge)
        # Remove the config symlink
        rm /etc/$PACKAGE

        # Remove the nginx config
        if [ -h /etc/nginx/sites-available/$PACKAGE ]; then
            rm /etc/nginx/sites-available/$PACKAGE
        fi

        # Remove the apache config
        if [ -e /etc/apache2/sites-available/$PACKAGE ]; then
            rm /etc/apache2/sites-enabled/$PACKAGE
            rm /etc/apache2/sites-available/$PACKAGE
        fi

        # Remove the user
        userdel $PACKAGE || true

        # Remove logs
        rm -rf /var/log/$PACKAGE
        rm -rf /var/log/apache2/$PACKAGE

        # Remove the home directory
        rm -rf /srv/$PACKAGE
    ;;

    remove|upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
    ;;

    *)
        echo "postrm called with unknown argument: $1" >&2
        exit 1
    ;;
esac

#DEBHELPER#

exit 0
'
);

has '+rules_template_default' => (
    default => '#!/usr/bin/make -f
# -*- makefile -*-
# Sample debian/rules that uses debhelper.
# This file was originally written by Joey Hess and Craig Small.
# As a special exception, when this file is copied by dh-make into a
# dh-make output file, you may use that output file without restriction.
# This special exception was added by Craig Small in version 0.37 of dh-make.

# Uncomment this to turn on verbose mode.
export DH_VERBOSE=1

build:
	dh_testdir
	dh_auto_build

%:
	dh $@ --without perl --without auto_configure
'
);

=attr starman_port

The port to use for starman.

=cut

has 'starman_port' => (
    is => 'ro',
    isa => 'Str',
    required => 1
);

=attr startup_time

The amount of time (in seconds) that the init script will wait on startup. Some
applications may require more than the default amount of time (30 seconds).

=cut

has 'startup_time' => (
    is => 'ro',
    isa => 'Str',
    default => 30
);

=attr uid

The UID of the user we're adding for the package. This is helpful for syncing
UIDs across multiple installations

=cut

has 'uid' => (
  is => 'ro',
  isa => 'Int',
  predicate => 'has_uid'
);

=attr web_server

Set the web server we'll be working with for this package.  Supported values
are C<apache> and C<nginx>.

=cut

has 'web_server' => (
    is => 'ro',
    isa => 'WebServer',
    required => 1
);

around '_generate_file' => sub {
    my $orig = shift;
    my $self = shift;
    
    if($self->has_uid) {
      $_[2]->{uid} = '--uid '.$self->uid;
    }
    
    $_[2]->{starman_port} = $self->starman_port;
    $_[2]->{startup_time} = $self->startup_time;

    $_[2]->{webserver_config_link} = '';
    $_[2]->{webserver_restart} = '';

    if(($self->web_server eq 'apache') || ($self->web_server eq 'all')) {
        $_[2]->{webserver_config_link} .= '# Symlink to the apache config for the environment we`re in
        rm /etc/apache2/sites-available/$PACKAGE
        ln /srv/$PACKAGE/config/apache/$PACKAGE.conf /etc/apache2/sites-available/$PACKAGE
';
        $_[2]->{webserver_restart} .= 'a2enmod proxy proxy_http rewrite
        a2ensite $PACKAGE
        mkdir -p /var/log/apache2/$PACKAGE
        if which invoke-rc.d >/dev/null 2>&1; then
            invoke-rc.d apache2 restart
        else
            /etc/init.d/apache2 restart
        fi
';
    }
    if(($self->web_server eq 'nginx') || ($self->web_server eq 'all')) {
        $_[2]->{webserver_config_link} .= '# Symlink to the nginx config for the environment we`re in
        rm /etc/nginx/sites-available/$PACKAGE
        ln -s /srv/$PACKAGE/config/nginx/$PACKAGE.conf /etc/nginx/sites-available/$PACKAGE
';
        $_[2]->{webserver_restart} .= 'if which invoke-rc.d >/dev/null 2>&1; then
            invoke-rc.d nginx restart
        else
            /etc/init.d/nginx restart
        fi
';
    }
    $self->$orig(@_);
};

1;
