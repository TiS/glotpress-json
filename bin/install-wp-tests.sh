#!/usr/bin/env bash

if [ $# -lt 3 ]; then
	echo "usage: $0 <db-name> <db-user> <db-pass> [db-host] [wp-version]"
	exit 1
fi

DB_NAME=$1
DB_USER=$2
DB_PASS=$3
DB_HOST=${4-localhost}
WP_VERSION=${5-latest}

WP_CORE_DIR=${WP_CORE_DIR-/tmp/wordpress/}
WP_TESTS_DIR=${WP_CORE_DIR}/tests/phpunit
export WP_CORE_DIR
export WP_TESTS_DIR

download() {
    if [ `which curl` ]; then
        curl -s "$1" > "$2";
    elif [ `which wget` ]; then
        wget -nv -O "$2" "$1"
    fi
}

set -ex

install_wp() {

	if [ -d $WP_CORE_DIR ]; then
		return;
	fi

	if [ "$( type -t svn )" == '' ]; then
		echo "install_wp failure: svn is not installed"
		return 1
	fi

	if grep -isqE 'nightly|trunk|alpha|beta|rc' <<< "$WP_VERSION"; then
		local SVN_URL=https://develop.svn.wordpress.org/trunk/
	elif [ "$WP_VERSION" == 'latest' ]; then
		local TAG=$( svn ls https://develop.svn.wordpress.org/tags | tail -n 1 | sed 's:/$::' )
		local SVN_URL="https://develop.svn.wordpress.org/tags/$TAG/"
	else
		local SVN_URL="https://develop.svn.wordpress.org/tags/$WP_VERSION/"
	fi

	echo "Installing WP from $SVN_URL to $WP_CORE_DIR"

	svn export -q "$SVN_URL" "$WP_CORE_DIR"

	download https://raw.github.com/markoheijnen/wp-mysqli/master/db.php "$WP_CORE_DIR/src/wp-content/db.php"
}

install_gp() {
	if [ "$( type -t svn )" == '' ]; then
		echo "install_wp failure: svn is not installed"
		return 1
	fi

	# Set up GlotPress
	echo "Loading GlotPress..."
	svn export -q https://github.com/glotpress/glotpress-wp/trunk "$WP_CORE_DIR/src/wp-content/plugins/glotpress"
	export GP_TESTS_DIR="$WP_CORE_DIR/src/wp-content/plugins/glotpress/tests/phpunit"
}

install_test_suite() {
	cd $WP_CORE_DIR

	if [ ! -f wp-tests-config.php ]; then
		cp wp-tests-config-sample.php wp-tests-config.php
		sed -i "s/youremptytestdbnamehere/$DB_NAME/" wp-tests-config.php
		sed -i "s/yourusernamehere/$DB_USER/" wp-tests-config.php
		sed -i "s/yourpasswordhere/$DB_PASS/" wp-tests-config.php
		sed -i "s|localhost|${DB_HOST}|" wp-tests-config.php
	fi

	cd - > /dev/null
}

install_db() {
	# parse DB_HOST for port or socket references
	local PARTS=(${DB_HOST//\:/ })
	local DB_HOSTNAME=${PARTS[0]};
	local DB_SOCK_OR_PORT=${PARTS[1]};
	local EXTRA=""

	if ! [ -z $DB_HOSTNAME ] ; then
		if [ $(echo $DB_SOCK_OR_PORT | grep -e '^[0-9]\{1,\}$') ]; then
			EXTRA=" --host=$DB_HOSTNAME --port=$DB_SOCK_OR_PORT --protocol=tcp"
		elif ! [ -z $DB_SOCK_OR_PORT ] ; then
			EXTRA=" --socket=$DB_SOCK_OR_PORT"
		elif ! [ -z $DB_HOSTNAME ] ; then
			EXTRA=" --host=$DB_HOSTNAME --protocol=tcp"
		fi
	fi

	# create database
	mysqladmin create $DB_NAME --user="$DB_USER" --password="$DB_PASS"$EXTRA
}

install_wp
install_gp
install_test_suite
install_db
