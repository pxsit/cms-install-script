#!/usr/bin/env bash

#Pre-Install
set -e
trap 'echo "Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR
CUR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CUR_USER=$(whoami)
CMS_PATH=/home/cmsuser/cms
TARGET_PATH=$CMS_PATH/target
CONFIG_PATH=$TARGET_PATH/etc/cms.toml

. /etc/os-release
if [[ "$ID" != ubuntu || ( "$VERSION_ID" != 24.04 && "$VERSION_ID" != 26.04 ) ]]; then
    echo "ERROR: This installer supports Ubuntu 24.04 and 26.04 only." >&2
    exit 1
fi

REINSTALL=0
REUSE_DATABASE=0
RESET_DATABASE=0
CONFIG_BACKUP=
CONFIG_WAS_EXISTING=0
if [[ -f "$CONFIG_PATH" ]]; then
    CONFIG_WAS_EXISTING=1
    read -r -p "CMS is already installed. Reinstall and keep its configuration? [Y/N] (default N): " REINSTALL_OPT
    REINSTALL_OPT=${REINSTALL_OPT:-N}
    REINSTALL_OPT=${REINSTALL_OPT,,}
    if [[ "$REINSTALL_OPT" == y || "$REINSTALL_OPT" == yes ]]; then
        REINSTALL=1
        CONFIG_BACKUP=$(mktemp)
        sudo cp "$CONFIG_PATH" "$CONFIG_BACKUP"
        read -r -p "Completely reinstall the database too? [Y/N] (default N): " RESET_DB_OPT
        RESET_DB_OPT=${RESET_DB_OPT:-N}
        RESET_DB_OPT=${RESET_DB_OPT,,}
        if [[ "$RESET_DB_OPT" == y || "$RESET_DB_OPT" == yes ]]; then
            RESET_DATABASE=1
        else
            REUSE_DATABASE=1
        fi
    else
        read -r -p "Use the same database? [Y/N] (default Y): " SAME_DB_OPT
        SAME_DB_OPT=${SAME_DB_OPT:-Y}
        SAME_DB_OPT=${SAME_DB_OPT,,}
        [[ "$SAME_DB_OPT" == y || "$SAME_DB_OPT" == yes ]] && REUSE_DATABASE=1
    fi
fi

if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
    echo "ERROR: No Internet connection. Exiting." >&2
    exit 1
fi

#Install Packages
read -p "Would you like a Full Install or a Minimal Install? [F/M] (default M): " INSTALL_OPT
INSTALL_OPT=${INSTALL_OPT:-M}
INSTALL_OPT=${INSTALL_OPT,,}
sudo apt-get update
if [[ "$INSTALL_OPT" == "f" || "$INSTALL_OPT" == "full" ]]; then
        sudo apt-get install -y \
            build-essential openjdk-11-jdk-headless fp-compiler postgresql postgresql-client \
            python3 cppreference-doc-en-html libffi-dev zip \
            python3-dev libpq-dev libyaml-dev php-cli \
            ghc rustc mono-mcs pypy3 python3-pycryptodome python3-venv \
        git python3-pip fp-units-base fp-units-fcl fp-units-misc fp-units-math fp-units-rtl
else
sudo apt-get install -y \
    build-essential postgresql postgresql-client \
    python3 libffi-dev zip \
    python3-dev libpq-dev libyaml-dev \
    python3-pycryptodome python3-venv git cppreference-doc-en-html \
    curl python3-pip
fi
sudo mkdir -p /etc/apt/keyrings
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/isolate.asc] http://www.ucw.cz/isolate/debian/ noble-isolate main' | sudo tee /etc/apt/sources.list.d/isolate.list
sudo curl https://www.ucw.cz/isolate/debian/signing-key.asc -o /etc/apt/keyrings/isolate.asc
sudo apt-get update
sudo apt-get install -y isolate
#Install CMS
if ! id cmsuser &>/dev/null; then
  sudo useradd --user-group --create-home --comment CMS cmsuser
fi
sudo usermod -aG isolate cmsuser
sudo usermod -aG sudo cmsuser
if [[ ! -d "$CMS_PATH/.git" ]]; then
    sudo -u cmsuser git clone https://github.com/cms-dev/cms.git "$CMS_PATH"
fi
sudo sed -i 's|default=\["C11 / gcc", "C++20 / g++", "Pascal / fpc"\])|default=\["C11 / gcc", "C++20 / g++"\])|' "$CMS_PATH/cms/db/contest.py"
if [[ $REINSTALL == 1 ]]; then
    sudo rm -rf "$TARGET_PATH"
fi
if [[ $REINSTALL == 1 || ! -x "$TARGET_PATH/bin/cmsInitDB" ]]; then
    sudo -u cmsuser bash -c 'cd /home/cmsuser/cms && /home/cmsuser/cms/install.py --dir=target cms'
    if [[ -n "$CONFIG_BACKUP" ]]; then
        sudo cp "$CONFIG_BACKUP" "$CONFIG_PATH"
        sudo chown cmsuser:cmsuser "$CONFIG_PATH"
    fi
fi
if [[ $CONFIG_WAS_EXISTING == 0 || $RESET_DATABASE == 1 ]]; then
    SECRET_KEY=$(sudo -u cmsuser "$TARGET_PATH/bin/python3" -c 'from cmscommon import crypto; print(crypto.get_hex_random_key())')
fi
rm -f "$CONFIG_BACKUP"

#Database
if [[ $REUSE_DATABASE != 1 ]]; then
read -r -p "Do you want to create a new database [Y/N] (default : Y) : " DB_OPTION
DB_OPTION=${DB_OPTION:-Y}
DB_OPTION=${DB_OPTION,,}
if [[ $RESET_DATABASE == 1 ]]; then
    DB_OPTION=y
fi
if [[ "$DB_OPTION" == "y" || "$DB_OPTION" == "Y" ]]; then
        read -p "Enter Database name [cmsdb]: " PG_DB
        PG_DB=${PG_DB:-cmsdb}
        [[ "$PG_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "ERROR: Invalid database name." >&2; exit 1; }
        if [[ $RESET_DATABASE == 1 ]]; then
            sudo -u postgres dropdb --if-exists --username=postgres "$PG_DB"
        fi
        read -p "Enter Database username [cmsuser]: " PG_USER
        PG_USER=${PG_USER:-cmsuser}
        [[ "$PG_USER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "ERROR: Invalid database username." >&2; exit 1; }
        read -s -p "Enter Database password (Blank for Random): " PG_PASS
        echo
        if [ -z "$PG_PASS" ]; then
            PG_PASS=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
        fi
        ESC_USER=$(PG_USER="$PG_USER" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_USER"], safe=""))')
        ESC_PASS=$(PG_PASS="$PG_PASS" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_PASS"], safe=""))')
        ESC_DB=$(PG_DB="$PG_DB" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_DB"], safe=""))')
        PG_USER_SQL=${PG_USER//\"/\"\"}
        PG_DB_SQL=${PG_DB//\"/\"\"}
        PG_PASS_SQL=${PG_PASS//\'/\'\'}
        if sudo -u postgres psql --username=postgres --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='${PG_USER//\'/\'\'}'" | grep -q 1; then
            printf 'ALTER ROLE "%s" WITH LOGIN PASSWORD '\''%s'\'';\n' "$PG_USER_SQL" "$PG_PASS_SQL" | sudo -u postgres psql --username=postgres
        else
            printf 'CREATE ROLE "%s" WITH LOGIN PASSWORD '\''%s'\'';\n' "$PG_USER_SQL" "$PG_PASS_SQL" | sudo -u postgres psql --username=postgres
        fi
        sudo -u postgres createdb --username=postgres "$PG_DB"
        sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="ALTER DATABASE \"$PG_DB_SQL\" OWNER TO \"$PG_USER_SQL\"; ALTER SCHEMA public OWNER TO \"$PG_USER_SQL\"; GRANT SELECT ON pg_largeobject TO \"$PG_USER_SQL\";"
        NEW_URL="url = \"postgresql+psycopg2://$ESC_USER:$ESC_PASS@localhost:5432/$ESC_DB\""
        sudo sed -i "s|^url = \".*\"|$NEW_URL|" "$CONFIG_PATH"
        if [[ $CONFIG_WAS_EXISTING == 0 || $RESET_DATABASE == 1 ]]; then
            sudo sed -i "s|^secret_key = \".*\"|secret_key = \"$SECRET_KEY\"|" "$CONFIG_PATH"
        fi
        sudo -u cmsuser bash -c '/home/cmsuser/cms/target/bin/cmsInitDB'
else
        read -p "Enter Database name [cmsdb]: " PG_DB
        PG_DB=${PG_DB:-cmsdb}
        [[ "$PG_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "ERROR: Invalid database name." >&2; exit 1; }
        read -p "Enter Database username [cmsuser]: " PG_USER
        PG_USER=${PG_USER:-cmsuser}
        [[ "$PG_USER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "ERROR: Invalid database username." >&2; exit 1; }
        read -s -p "Enter Database password: " PG_PASS
        ESC_USER=$(PG_USER="$PG_USER" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_USER"], safe=""))')
        ESC_PASS=$(PG_PASS="$PG_PASS" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_PASS"], safe=""))')
        ESC_DB=$(PG_DB="$PG_DB" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["PG_DB"], safe=""))')
        NEW_URL="url = \"postgresql+psycopg2://$ESC_USER:$ESC_PASS@localhost:5432/$ESC_DB\""
        sudo sed -i "s|^url = \".*\"|$NEW_URL|" "$CONFIG_PATH"
        if [[ $CONFIG_WAS_EXISTING == 0 || $RESET_DATABASE == 1 ]]; then
            sudo sed -i "s|^secret_key = \".*\"|secret_key = \"$SECRET_KEY\"|" "$CONFIG_PATH"
        fi
        read -p "Would you like to initialize the database? [Y/N] (default : N) : " INIT_DB_OPTION
        INIT_DB_OPTION=${INIT_DB_OPTION:-N}
        INIT_DB_OPTION=${INIT_DB_OPTION,,}
        if [[ "$INIT_DB_OPTION" == "Y" || "$INIT_DB_OPTION" == "y" ]]; then
                sudo -u cmsuser bash -c '/home/cmsuser/cms/target/bin/cmsInitDB'
        fi
fi
fi

#Docs
#Docs
if [ ! -d "/usr/share/cms" ]; then
    sudo mkdir /usr/share/cms
fi

if [ ! -d "/usr/share/cms/docs" ]; then
    sudo mkdir /usr/share/cms/docs
fi

if [ ! -L "/usr/share/cms/docs/cpp" ]; then
    sudo ln -s /usr/share/cppreference/doc/html/en/ /usr/share/cms/docs/cpp
fi

#Create CMS Services
sudo tee "$CUR_DIR/resource-service.conf" > /dev/null <<EOF
CONTEST_ID=ALL
EOF

sudo tee "/etc/systemd/system/cms-log.service" > /dev/null <<EOF
[Unit]
Description=CMS Log Service
Requires=postgresql.service
After=postgresql.service
[Service]
Type=simple
ExecStart=/home/cmsuser/cms/target/bin/cmsLogService
User=cmsuser
[Install]
WantedBy=multi-user.target
EOF

sudo tee "/etc/systemd/system/cms.service" > /dev/null <<EOF
[Unit]
Description=CMS Resource Service
Requires=cms-log.service postgresql.service
After=cms-log.service postgresql.service
[Service]
Type=simple
EnvironmentFile=$CUR_DIR/resource-service.conf
ExecStart=/home/cmsuser/cms/target/bin/cmsResourceService -a \$CONTEST_ID 0
User=cmsuser
Slice=cms.slice
[Install]
WantedBy=multi-user.target
EOF

sudo tee "/etc/systemd/system/cms-ranking.service" > /dev/null <<EOF
[Unit]
Description=CMS Ranking Web Service
Requires=cms-log.service postgresql.service
After=cms-log.service postgresql.service
[Service]
Type=simple
ExecStart=/home/cmsuser/cms/target/bin/cmsRankingWebServer
User=cmsuser
Slice=cms.slice
[Install]
WantedBy=multi-user.target
EOF

sudo chown cmsuser $CUR_DIR/resource-service.conf
sudo chgrp cmsuser $CUR_DIR/resource-service.conf

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable cms-log.service
sudo systemctl enable cms.service
sudo systemctl enable cms-ranking.service

sudo systemctl start cms-log.service
sudo systemctl start cms.service
sudo systemctl start cms-ranking.service

#Domain
read -p "Do you want to link the CMS to your website? [Y/N] (default N): " WEB_OPTION
WEB_OPTION=${WEB_OPTION:-N}
WEB_OPTION=${WEB_OPTION,,}
if [[ "$WEB_OPTION" == "y" || "$WEB_OPTION" == "yes" ]]; then
        sudo apt-get install -y nginx-full
        read -p "Contest Server Domain (Example : contest.cmswebsite.com): " CON_SERV
        read -p "Admin Server Domain (Example : admin.cmswebsite.com): " ADMIN_SERV
        read -p "Rankings Server Domain (Example : rankings.cmswebsite.com): " RANK_SERV
        for DOMAIN in "$CON_SERV" "$ADMIN_SERV" "$RANK_SERV"; do
            [[ -z "$DOMAIN" || "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || { echo "ERROR: Invalid domain name." >&2; exit 1; }
        done
        if [[ -n "$CON_SERV" || -n "$ADMIN_SERV" || -n "$RANK_SERV" ]]; then
                sudo tee "/etc/nginx/sites-available/cms" > /dev/null <<EOF
$( [[ -n "$CON_SERV" ]] && cat <<CONF
server {
    server_name $CON_SERV;

    location / {
        proxy_pass http://127.0.0.1:8888/;
    }
}
CONF
)
$( [[ -n "$ADMIN_SERV" ]] && cat <<CONF
server {
    server_name $ADMIN_SERV;
    client_max_body_size 500M;

    location / {
        proxy_pass http://127.0.0.1:8889;
    }
}
CONF
)
$( [[ -n "$RANK_SERV" ]] && cat <<CONF
server {
    server_name $RANK_SERV;

    location / {
        proxy_pass http://127.0.0.1:8890;
        proxy_buffering off;
    }
}
CONF
)
EOF
                if [[ ! -e /etc/nginx/sites-enabled/cms && ! -L /etc/nginx/sites-enabled/cms ]]; then
                        sudo ln -s /etc/nginx/sites-available/cms /etc/nginx/sites-enabled/cms
                fi
                read -p "Do you want to add a free SSL Certificate from certbot? [Y/N] (default Y): " CERT_OPTION
                CERT_OPTION=${CERT_OPTION:-y}
                CERT_OPTION=${CERT_OPTION,,}
                if [[ "$CERT_OPTION" == "y" || "$CERT_OPTION" == "yes" ]]; then
                        echo "Please wait..."
                        sleep 5
                        sudo apt-get install -y certbot python3-certbot-nginx
                        sudo certbot --nginx
                fi
        fi
fi
read -p "Please create an admin user (default admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
sudo -u cmsuser /home/cmsuser/cms/target/bin/cmsAddAdmin "$ADMIN_USER"

echo "Contest Web Server started at http://localhost:8888"
echo "Admin Web Server started at http://localhost:8889"
echo "Ranking Web Server started at http://localhost:8890"
