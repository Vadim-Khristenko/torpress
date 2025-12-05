FROM wordpress:6.9-php8.5-apache
LABEL org.opencontainers.image.authors="Dmitry Danilov <dima.danilov9867@gmail.com>"

ARG MARIADB_VERSION='11.4'
ARG DEBIAN_FRONTEND=noninteractive

# Install tor, supervisor and MariaDB
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        tor \
        supervisor \
        gosu \
        wget \
        ca-certificates \
        gnupg \
        dirmngr \
        lsb-release \
    ; \
        # Add MariaDB repository (try multiple mirrors; import GPG key to keyring)
        wget -qO- https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor -o /usr/share/keyrings/mariadb-archive-keyring.gpg; \
        for mirror in \
                https://mirrors.cicku.me/mariadb \
                https://mirrors.xtom.nl/mariadb \
                https://mirrors.xtom.com/mariadb \
                https://mirror.alwyzon.net/mariadb \
                https://mirror.one.com/mariadb; do \
            echo "deb [arch=amd64,arm64,ppc64el signed-by=/usr/share/keyrings/mariadb-archive-keyring.gpg] ${mirror}/${MARIADB_VERSION}/debian $(lsb_release -sc) main" > /etc/apt/sources.list.d/mariadb.list; \
            if apt-get update >/dev/null 2>&1; then \
                echo "Using MariaDB mirror: ${mirror}"; \
                break; \
            else \
                echo "MariaDB mirror ${mirror} failed, trying next..." >&2; \
                rm -f /etc/apt/sources.list.d/mariadb.list; \
            fi; \
        done; \
        if [ -f /etc/apt/sources.list.d/mariadb.list ]; then \
            apt-get update; \
            apt-get install -y --no-install-recommends mariadb-server; \
        else \
            echo "No working MariaDB mirror found — installing mariadb from Debian repositories"; \
            apt-get update; \
            apt-get install -y --no-install-recommends mariadb-server; \
        fi; \
    # Create runtime directories and clean database dir for fresh init on first run
    mkdir -p /run/mysqld /docker-entrypoint-initdb.d; \
    chown -R mysql:mysql /run/mysqld || true; \
    rm -rf /var/lib/mysql/*; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

COPY files/mariadb-entrypoint.sh /usr/local/bin/mariadb-entrypoint.sh
RUN chmod +x /usr/local/bin/mariadb-entrypoint.sh

COPY files/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY files/torrc /etc/tor/torrc
COPY files/mytune.cnf /etc/mysql/mariadb.conf.d/99-mytune.cnf

VOLUME /var/www/html
VOLUME /var/lib/tor
VOLUME /var/lib/mysql

EXPOSE 80
EXPOSE 3306

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD ["bash", "-lc", "mysqladmin ping -u root --silent || exit 1"]

CMD ["/usr/bin/supervisord", "-n"]