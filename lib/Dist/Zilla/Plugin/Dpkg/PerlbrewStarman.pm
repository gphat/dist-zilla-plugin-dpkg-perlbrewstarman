package Dist::Zilla::Plugin::Dpkg::PerlbrewStarman;
use Moose;

extends 'Dist::Zilla::Plugin::Dpkg';

#ABSTRACT: Generate dpkg files for your perlbrew-backed, starman-based perl app

=head1 SYNOPSIS

  [Dpkg::PerlbrewStarman]
  
=head1 DESCRIPTION

Dist::Zilla::Plugin::Dpkg::PerlbrewStarman is an extension of
Dist::Zilla::Plugin::Dpkg. It generates Debian control files that are
suitable for a perl app that includes it's own Perlbrew and runs under
Starman.  It makes the following assumptions:

=over 4

=item XXX Perlbrew

=item Runs under L<Starman>

=item Starman is fronted by nginx

=item It's installed at /src/$packagename

=item Logs will be placed in /var/log/$packagename

=back

=cut

has '+default_template_default' => (
    default => '# Defaults for prg-site initscript
# sourced by /etc/init.d/prg-site
# installed at /etc/default/prg-site by the maintainer scripts

#
# This is a POSIX shell fragment
#

APP="{$package_name}"
APPDIR="/srv/$APP"
APPUSER={$package_name}

PSGIAPP="script/$APP.psgi"

PERLBREW_PATH="$APPDIR/perlbrew/bin"
PERLBREW_ROOT="$APPDIR/perl5/perlbrew"

DAEMON=`which starman`
DAEMON_ARGS="-Ilib $PSGIAPP --daemonize --user $APPUSER --preload-app --workers 5 --pid /var/run/${APP}.pid --port 5002 --host 127.0.0.1 --error-log /var/log/$APP/error.log"
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

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

DESC=$APP
NAME=$APP
SCRIPTNAME=/etc/init.d/$NAME

PATH=$PERLBREW_PATH:$PATH

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

check_running() \{
    [ -s $PIDFILE ] && kill -0 $(cat $PIDFILE) >/dev/null 2>&1
\}

check_compile() \{
  if ( cd $APPDIR ; perl -Ilib -M$APPLIB -ce1 ) ; then
    return 1
  else
    return 0
  fi
\}

_start() \{

  /sbin/start-stop-daemon --background --start --pidfile $PIDFILE --chdir $APPDIR --exec $DAEMON -- \
    $DAEMON_ARGS \
    || return 2

  echo ""
  echo "Waiting for $APP to start..."

  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 ; do
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
    default => 'prg_site.yml srv/prg-site
config/* srv/{$package_name}/config
lib/* srv/{$package_name}/lib
root/* srv/{$package_name}/root
script/* srv/{$package_name}/script
perlbrew/* srv/{$package_name}/perlbrew
'
);

has '+postinst_template_default' => (
    default => '#!/bin/sh
# postinst script for prg-site
#
# see: dh_installdeb(1)

set -e

. /usr/share/debconf/confmodule

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

PACKAGE=${package_name}

case "$1" in
    configure)

        # Symlink /etc/$PACKAGE to our package`s config directory
        if [ ! -e /etc/$PACKAGE ]; then
            ln -s /srv/$PACKAGE/config /etc/$PACKAGE
        fi

        # Link to the appropriate config file based on the eiv
        # if [ ! -e /srv/$PACKAGE/config/$PACKAGE.yml ]; then
        #     ln -s /srv/$PACKAGE/config/labor.prg.com.$RUNNING_ENV.yml /srv/$PACKAGE/config/$PACKAGE.yml
        # fi

        # Symlink to the nginx config for the senvironment we`re in
        #if [ ! -e /etc/nginx/sites-available/$PACKAGE ]; then
        #    ln -s /srv/$PACKAGE/config/nginx/$RUNNING_ENV.conf /etc/nginx/sites-available/$PACKAGE
        #fi

        # Create user if it doesn`t exist.
        if ! id $PACKAGE > /dev/null 2>&1 ; then
            adduser --system --home /srv/$PACKAGE --no-create-home \
                --ingroup nogroup --disabled-password --shell /bin/bash \
                $PACKAGE
        fi

        # Setup the perlbrew
        # if [ ! -e /srv/$PACKAGE/.perlbrew ]; then
        #     mkdir /srv/$PACKAGE/.perlbrew
        #     echo "source ~/perl5/perlbrew/etc/bashrc" > /srv/$PACKAGE/.profile
        # 
        #     echo "export PERLBREW_PERL=perl-5.14.2-$PACKAGE" > /srv/$PACKAGE/.perlbrew/init
        #     echo "export PERLBREW_VERSION=0.28" >> /srv/$PACKAGE/.perlbrew/init
        #     echo "export PERLBREW_PATH=/srv/$PACKAGE/perl5/perlbrew/bin:/srv/$PACKAGE/perl5/perlbrew/perls/perl-5.14.2-$PACKAGE/bin" >> /srv/$PACKAGE/.perlbrew/init
        #     echo "export PERLBREW_ROOT=/srv/$PACKAGE/perl5/perlbrew" >> /srv/$PACKAGE/.perlbrew/init
        # fi
        chown -R $PACKAGE:adm /srv/$PACKAGE


        # Make sure this user owns the directory
        chown -R $PACKAGE:adm /srv/$PACKAGE

        # Make the log directory
        if [ ! -e /var/log/$PACKAGE ]; then
            mkdir /var/log/$PACKAGE
            chown -R $PACKAGE:adm /var/log/$PACKAGE
        fi
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
        if [ -e /etc/$PACKAGE ]; then
            rm /etc/$PACKAGE
        fi

        # Remove the nginx config
        if [ -e /etc/nginx/sites-available/$PACKAGE ]; then
            rm /etc/nginx/sites-available/$PACKAGE
        fi

        # Remove the user
        userdel $PACKAGE || true

        # Remove logs
        rm -rf /var/log/$PACKAGE

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

1;
