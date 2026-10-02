#!/bin/bash

set -e

: ${MOODLE_SITE_FULLNAME:=Moodle}
: ${MOODLE_SITE_SHORTNAME:=Moodle}
: ${MOODLE_SITE_LANG:=en}
: ${MOODLE_ADMIN_USER:=admin}
: ${MOODLE_ADMIN_PASS:=password}
: ${MOODLE_ADMIN_EMAIL:=admin@example.com}
: ${MOODLE_DATABASE_TYPE:=mariadb}
: ${MOODLE_ENABLE_SSL:=false}
: ${MOODLE_UPDATE:=false}

if [ -z "$MOODLE_DATABASE_HOST" ]; then
	if [ -n "$MYSQL_PORT_3306_TCP_ADDR" ]; then
		MOODLE_DATABASE_HOST=$MYSQL_PORT_3306_TCP_ADDR
	elif [ -n "$POSTGRES_PORT_5432_TCP_ADDR" ]; then
		MOODLE_DATABASE_TYPE=pgsql
		MOODLE_DATABASE_HOST=$POSTGRES_PORT_5432_TCP_ADDR
	elif [ -n "$DB_PORT_3306_TCP_ADDR" ]; then
		MOODLE_DATABASE_HOST=$DB_PORT_3306_TCP_ADDR
	elif [ -n "$DB_PORT_5432_TCP_ADDR" ]; then
		MOODLE_DATABASE_TYPE=pgsql
		MOODLE_DATABASE_HOST=$DB_PORT_5432_TCP_ADDR
	else
		echo >&2 'error: missing MOODLE_DATABASE_HOST environment variable'
		echo >&2 '	Did you forget to --link your database?'
		exit 1
	fi
fi

if [ -z "$MOODLE_DATABASE_USER" ]; then
	if [ "$MOODLE_DATABASE_TYPE" = "mysql" -o "$MOODLE_DATABASE_TYPE" = "mariadb" ]; then
		echo >&2 'info: missing MOODLE_DATABASE_USER environment variable, defaulting to "root"'
		MOODLE_DATABASE_USER=root
	elif [ "$MOODLE_DATABASE_TYPE" = "pgsql" ]; then
		echo >&2 'info: missing MOODLE_DATABASE_USER environment variable, defaulting to "postgres"'
		MOODLE_DATABASE_USER=postgres
	else
		echo >&2 'error: missing required MOODLE_DATABASE_USER environment variable'
		exit 1
	fi
fi

if [ -z "$MOODLE_DATABASE_PASSWORD" ]; then
	if [ -n "$MYSQL_ENV_MYSQL_ROOT_PASSWORD" ]; then
		MOODLE_DATABASE_PASSWORD=$MYSQL_ENV_MYSQL_ROOT_PASSWORD
	elif [ -n "$POSTGRES_ENV_POSTGRES_PASSWORD" ]; then
		MOODLE_DATABASE_PASSWORD=$POSTGRES_ENV_POSTGRES_PASSWORD
	elif [ -n "$DB_ENV_MYSQL_ROOT_PASSWORD" ]; then
		MOODLE_DATABASE_PASSWORD=$DB_ENV_MYSQL_ROOT_PASSWORD
	elif [ -n "$DB_ENV_POSTGRES_PASSWORD" ]; then
		MOODLE_DATABASE_PASSWORD=$DB_ENV_POSTGRES_PASSWORD
	else
		echo >&2 'error: missing required MOODLE_DATABASE_PASSWORD environment variable'
		echo >&2 '	Did you forget to -e MOODLE_DATABASE_PASSWORD=... ?'
		echo >&2
		echo >&2 '	(Also of interest might be MOODLE_DATABASE_USER and MOODLE_DATABASE_NAME)'
		exit 1
	fi
fi

: ${MOODLE_DATABASE_NAME:=moodle}

if [ -z "$MOODLE_DB_PORT" ]; then
	if [ -n "$MYSQL_PORT_3306_TCP_PORT" ]; then
		MOODLE_DB_PORT=$MYSQL_PORT_3306_TCP_PORT
	elif [ -n "$POSTGRES_PORT_5432_TCP_PORT" ]; then
		MOODLE_DB_PORT=$POSTGRES_PORT_5432_TCP_PORT
	elif [ -n "$DB_PORT_3306_TCP_PORT" ]; then
		MOODLE_DB_PORT=$DB_PORT_3306_TCP_PORT
	elif [ -n "$DB_PORT_5432_TCP_PORT" ]; then
		MOODLE_DB_PORT=$DB_PORT_5432_TCP_PORT
	elif [ "$MOODLE_DATABASE_TYPE" = "mysql" -o "$MOODLE_DATABASE_TYPE" = "mariadb" ]; then
		MOODLE_DB_PORT="3306"
	elif [ "$MOODLE_DATABASE_TYPE" = "pgsql" ]; then
		MOODLE_DB_PORT="5432"
	fi
fi

# Wait for the DB to come up
while [ `/bin/nc -w 1 $MOODLE_DATABASE_HOST $MOODLE_DB_PORT < /dev/null > /dev/null; echo $?` != 0 ]; do
    echo "Waiting for $MOODLE_DATABASE_TYPE database to come up at $MOODLE_DATABASE_HOST:$MOODLE_DB_PORT..."
    sleep 1
done
echo "Database is up and running."

export MOODLE_DATABASE_TYPE MOODLE_DATABASE_HOST MOODLE_DATABASE_USER MOODLE_DATABASE_PASSWORD MOODLE_DATABASE_NAME

TERM=dumb php -- <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

if (getenv('MOODLE_DATABASE_TYPE') == 'mysql' || getenv('MOODLE_DATABASE_TYPE') == 'mariadb') {

    $mysql = new mysqli(getenv('MOODLE_DATABASE_HOST'), getenv('MOODLE_DATABASE_USER'), getenv('MOODLE_DATABASE_PASSWORD'), '', (int)getenv('MOODLE_DB_PORT'));

    if ($mysql->connect_error) {
        file_put_contents('php://stderr', 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
        exit(1);
    }

    if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string(getenv('MOODLE_DATABASE_NAME')) . '`')) {
        file_put_contents('php://stderr', 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
    }

    $mysql->close();
}
EOPHP

cd /var/www/html

: ${MOODLE_SHARED:=/moodledata}
if [ ! -d "$MOODLE_SHARED" ]; then
    echo "Created $MOODLE_SHARED directory."
    mkdir -p $MOODLE_SHARED
fi
#mkdir -p "$MOODLE_SHARED/images"
#
## If the images directory only contains a README, then link it to
## $MOODLE_SHARED/images, creating the shared directory if necessary
#if [ "$(ls images)" = "README" -a ! -L images ]; then
#    rm -fr images
#    ln -s "$MOODLE_SHARED/images" images
#fi
#
## If an extensions folder exists inside the shared directory, as long as
## /var/www/html/extensions is not already a symbolic link, then replace it
#if [ -d "$MOODLE_SHARED/extensions" -a ! -h /var/www/html/extensions ]; then
#    echo >&2 "Found 'extensions' folder in data volume, creating symbolic link."
#    rm -rf /var/www/html/extensions
#    ln -s "$MOODLE_SHARED/extensions" /var/www/html/extensions
#fi
#
## If a skins folder exists inside the shared directory, as long as
## /var/www/html/skins is not already a symbolic link, then replace it
#if [ -d "$MOODLE_SHARED/skins" -a ! -h /var/www/html/skins ]; then
#    echo >&2 "Found 'skins' folder in data volume, creating symbolic link."
#    rm -rf /var/www/html/skins
#    ln -s "$MOODLE_SHARED/skins" /var/www/html/skins
#fi
#
## If a vendor folder exists inside the shared directory, as long as
## /var/www/html/vendor is not already a symbolic link, then replace it
#if [ -d "$MOODLE_SHARED/vendor" -a ! -h /var/www/html/vendor ]; then
#    echo >&2 "Found 'vendor' folder in data volume, creating symbolic link."
#    rm -rf /var/www/html/vendor
#    ln -s "$MOODLE_SHARED/vendor" /var/www/html/vendor
#fi

# Attempt to enable SSL support if explicitly requested
if [ $MOODLE_ENABLE_SSL = true ]; then
    if [ ! -f $MOODLE_SHARED/ssl.key -o ! -f $MOODLE_SHARED/ssl.crt -o ! -f $MOODLE_SHARED/ssl.bundle.crt ]; then
        echo >&2 'error: Detected MOODLE_ENABLE_SSL flag but found no data volume';
        echo >&2 '	Did you forget to mount the volume with -v?'
        exit 1
    fi
    echo >&2 'info: enabling ssl'
    a2enmod ssl

    cp "$MOODLE_SHARED/ssl.key" /etc/apache2/ssl.key
    cp "$MOODLE_SHARED/ssl.crt" /etc/apache2/ssl.crt
    cp "$MOODLE_SHARED/ssl.bundle.crt" /etc/apache2/ssl.bundle.crt
elif [ -e "/etc/apache2/mods-enabled/ssl.load" ]; then
    echo >&2 'warning: disabling ssl'
    a2dismod ssl
fi

# Install database if installed file doesn't exist
if sudo -E -H -u www-data php admin/cli/isinstalled.php >/dev/null 2>&1; then
    echo "Moodle already installed."
    touch "$MOODLE_SHARED/installed"
else
    echo "Moodle database is not initialized. Initializing..."
    touch "$MOODLE_SHARED/install.lock"

    set +e
    INSTALL_OUTPUT=$(
        sudo -E -H -u www-data php admin/cli/install_database.php \
            --agree-license \
            --lang="$MOODLE_SITE_LANG" \
            --adminuser="$MOODLE_ADMIN_USER" \
            --adminpass="$MOODLE_ADMIN_PASS" \
            --adminemail="$MOODLE_ADMIN_EMAIL" \
            --fullname="$MOODLE_SITE_FULLNAME" \
            --shortname="$MOODLE_SITE_SHORTNAME" 2>&1
    )
    INSTALL_RC=$?
    set -e

    echo "$INSTALL_OUTPUT"

    if [ $INSTALL_RC -eq 0 ]; then
        echo "Moodle installation completed."
        touch "$MOODLE_SHARED/installed"

    elif echo "$INSTALL_OUTPUT" | grep -q "Database tables already present"; then
        echo "Database already initialized. Skipping installation."
        touch "$MOODLE_SHARED/installed"

    else
        rm -f "$MOODLE_SHARED/install.lock"
        exit $INSTALL_RC
    fi

    rm -f "$MOODLE_SHARED/install.lock"
fi

# Sync SMTP / noreply settings from env into Moodle's mdl_config on every
# container start so that changes to chart values propagate to existing
# deployments. Previously these calls lived inside the install-once block,
# which meant SMTP_HOST changes had no effect after the first boot. Each
# cfg.php call is idempotent (no-op when value already matches).
#
# Only runs if Moodle has been installed — mdl_config doesn't exist before
# install_database.php has run.
if [ -e "$MOODLE_SHARED/installed" ]; then
    if [ -n "$SMTP_HOST" ]; then
        smtphosts="$SMTP_HOST"
        if [ -n "$SMTP_PORT" ]; then
            smtphosts="$SMTP_HOST:$SMTP_PORT"
        fi
        sudo -E -H -u www-data php admin/cli/cfg.php --name=smtphosts --set="$smtphosts"
    fi
    if [ -n "$SMTP_USER" ]; then
        sudo -E -H -u www-data php admin/cli/cfg.php --name=smtpuser --set="$SMTP_USER"
    fi
    if [ -n "$SMTP_PASSWORD" ]; then
        sudo -E -H -u www-data php admin/cli/cfg.php --name=smtppass --set="$SMTP_PASSWORD"
    fi
    if [ -n "$SMTP_PROTOCOL" ]; then
        sudo -E -H -u www-data php admin/cli/cfg.php --name=smtpsecure --set="$SMTP_PROTOCOL"
    fi
    if [ -n "$SMTP_AUTH" ]; then
        sudo -E -H -u www-data php admin/cli/cfg.php --name=smtpauthtype --set="$SMTP_AUTH"
    fi
    if [ -n "$MOODLE_NOREPLY_ADDRESS" ]; then
        sudo -E -H -u www-data php admin/cli/cfg.php --name=noreplyaddress --set="$MOODLE_NOREPLY_ADDRESS"
    fi

    # Register the redis_app cache store via cache_config_writer when redis
    # is available. Idempotent — script no-ops if already registered.
    # Mode mappings (Application/Request -> redis_app) are still admin-UI only.
    if [ -n "$MOODLE_REDIS_HOST" ]; then
        sudo -E -H -u www-data php /var/www/html/register-redis-cache-store.php
    fi
fi

# Install extensions
#if [[ $MOODLE_EXTENSIONS ]]; then
#    echo "<?php" > CustomExtensions.php
#    IFS="," read -ra exts <<< "$MOODLE_EXTENSIONS"
#    for i in "${exts[@]}"; do
#        if [[ -f /var/www/html/extensions/$i/extension.json ]]; then
#            echo "wfLoadExtension('$i');" >> CustomExtensions.php
#        fi
#    done
#fi

# If LocalSettings.php exists, then attempt to run the update.php maintenance
# script. If already up to date, it won't do anything, otherwise it will
# migrate the database if necessary on container startup. It also will
# verify the database connection is working.
if [ "$MOODLE_UPDATE" = 'true' -a ! -f "$MOODLE_SHARED/update.lock" ]; then
    echo "Updating Moodle..."
    touch $MOODLE_SHARED/update.lock
    sudo -E -H -u www-data /usr/local/bin/php admin/cli/maintenance.php --enable
    sudo -E -H -u www-data /usr/local/bin/php admin/cli/upgrade.php
    sudo -E -H -u www-data /usr/local/bin/php admin/cli/maintenance.php --disable
    rm $MOODLE_SHARED/update.lock
    echo "Done."
fi

# Run additional init scripts
DIR=/docker-entrypoint.d

if [[ -d "$DIR"  ]]
then
    /bin/run-parts --verbose "$DIR"
fi

exec "$@"
