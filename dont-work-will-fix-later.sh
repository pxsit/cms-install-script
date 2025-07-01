#!/usr/bin/env bash

#Prerequisites
set -e
trap 'echo "Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR
CUR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CUR_USER=$(whoami)

#Install Packages
read -p "Would you like a Full Install or a Minimal Install? [F/M] (default F): " INSTALL_OPT
INSTALL_OPT=${INSTALL_OPT:-F}
INSTALL_OPT=${INSTALL_OPT,,}
sudo apt-get update
if [[ "$INSTALL_OPT" == "f" || "$INSTALL_OPT" == "full" ]]; then
	sudo apt-get install -y \
	    build-essential openjdk-11-jdk-headless fp-compiler postgresql postgresql-client \
	    python3.12 cppreference-doc-en-html libffi-dev zip \
	    python3.12-dev libpq-dev libcups2-dev libyaml-dev php-cli \
	    texlive-latex-base a2ps ghc rustc mono-mcs pypy3 python3-pycryptodome python3-venv git python3-pip
	read -p "Do you want to install additional Free Pascal Units? [Y/N] (default Y): " PASCAL_UNITS_INSTALL
	PASCAL_UNITS_INSTALL=${PASCAL_UNITS_INSTALL:-Y}
	PASCAL_UNITS_INSTALL=${PASCAL_UNITS_INSTALL,,}
	if [[ "$PASCAL_UNITS_INSTALL" == "y" || "$PASCAL_UNITS_INSTALL" == "yes" ]]; then
	    sudo apt-get install -y fp-units-base fp-units-fcl fp-units-misc fp-units-math fp-units-rtl
	fi
else
sudo apt-get install -y \
    build-essential postgresql postgresql-client \
    python3.12 libffi-dev zip \
    python3.12-dev libpq-dev libcups2-dev libyaml-dev \
    python3-pycryptodome python3-venv git cppreference-doc-en-html \
    curl python3-pip
fi


# Install Isolate from upstream package repository
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/isolate.asc] http://www.ucw.cz/isolate/debian/ noble-isolate main' | sudo tee /etc/apt/sources.list.d/isolate.list > /dev/null
sudo curl https://www.ucw.cz/isolate/debian/signing-key.asc | sudo tee /etc/apt/keyrings/isolate.asc > /dev/null
sudo apt update && sudo apt install -y isolate

#Install CMS
sudo useradd --user-group --create-home --comment CMS cmsuser
sudo usermod -a -G isolate cmsuser
sudo usermod -a -G sudo cmsuser
sudo usermod -aG cmsuser pasit
sudo chmod 640 $CUR_DIR
sudo chown $CUR_USER:cmsuser $CUR_DIR
sudo chmod 640 /home/cmsuser
sudo chown $CUR_USER:cmsuser /home/cmsuser
#sudo chown -R $CUR_USER $CUR_DIR 
#sudo chown -R cmsuser $CUR_DIR
#sudo chown -R $CUR_USER /home/cmsuser
sudo -u cmsuser git clone https://github.com/cms-dev/cms.git /home/cmsuser/cms
cd /home/cmsuser/cms
sudo sed -i 's|default=\["C11 / gcc", "C++20 / g++", "Pascal / fpc"\])|default=\["C11 / gcc", "C++20 / g++"\])|' /home/cmsuser/cms/cms/db/contest.py
sudo -u cmsuser /home/cmsuser/cms/install.py --dir=$CUR_DIR/cms cms
source "$CUR_DIR/cms/bin/activate"
CONFIG_PATH="$CUR_DIR/cms/etc/cms.toml"
SECRET_KEY=$(python3 -c 'from cmscommon import crypto; print(crypto.get_hex_random_key())')

#Database
read -p "Enter Database name [cmsdb]: " PG_DB
PG_DB=${PG_DB:-cmsdb}
read -p "Enter Database username [cmsuser]: " PG_USER
PG_USER=${PG_USER:-cmsuser}
read -s -p "Enter Database password (Blank for Random): " PG_PASS
echo
if [ -z "$PG_PASS" ]; then
    PG_PASS=$(< /dev/urandom tr -dc 'A-Za-z0-9!@#$%^&*()_+=' | head -c32)
fi
ESC_USER=$(printf '%q' "$PG_USER")
ESC_PASS=$(env PG_PASS="$PG_PASS" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ['PG_PASS']))")
ESC_DB=$(printf '%q' "$PG_DB")
sudo -u postgres psql --username=postgres --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | grep -q 1 || \
sudo -u postgres psql --username=postgres --command="CREATE ROLE \"$PG_USER\" WITH LOGIN PASSWORD '$PG_PASS';"
sudo -u postgres createdb --username=postgres "$PG_DB"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="ALTER DATABASE \"$PG_DB\" OWNER TO \"$PG_USER\";"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="ALTER SCHEMA public OWNER TO \"$PG_USER\";"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="GRANT SELECT ON pg_largeobject TO \"$PG_USER\";"
NEW_URL="database = \"postgresql+psycopg2://$ESC_USER:$ESC_PASS@localhost:5432/$ESC_DB\""
sudo sed -i "s|^database = \".*\"|$NEW_URL|" "$CONFIG_PATH"
sudo sed -i "s|^secret_key = \".*\"|secret_key = \"$SECRET_KEY\"|" "$CONFIG_PATH"
$CUR_DIR/cms/bin/cmsInitDB
FOLDERS=(
  AdminWebServer-0
  Checker-0
  cms
  ContestWebServer-0
  EvaluationService-0
  LogService-0
  PrintingService-0
  ProxyService-0
  ResourceService-0
  ScoringService-0
  Worker-0
  Worker-1
  Worker-2
  Worker-3
  Worker-4
  Worker-5
  Worker-6
  Worker-7
  Worker-8
  Worker-9
  Worker-10
  Worker-11
  Worker-12
  Worker-13
  Worker-14
  Worker-15
)
for folder in "${FOLDERS[@]}"; do
  sudo mkdir -p "$CUR_DIR/cms/log/$folder"
done

#Docs
sudo mkdir /usr/share/cms
sudo mkdir /usr/share/cms/docs
sudo ln -s /usr/share/cppreference/doc/html/en/ /usr/share/cms/docs/cpp

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
ExecStart=$CUR_DIR/cms/bin/cmsLogService
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
ExecStart=$CUR_DIR/cms/bin/cmsResourceService -a \$CONTEST_ID 0
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
ExecStart=$CUR_DIR/cms/bin/cmsRankingWebServer
User=cmsuser
Slice=cms.slice
[Install]
WantedBy=multi-user.target
EOF

sudo chown cmsuser "$CUR_DIR/resource-service.conf"

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
		sudo ln -s /etc/nginx/sites-available/cms /etc/nginx/sites-enabled/cms 
		read -p "Do you want to add a free SSL Certificate from certbot? [Y/N] (default Y): " CERT_OPTION
		CERT_OPTION=${CERT_OPTION:-y}
		CERT_OPTION=${CERT_OPTION,,}
		if [[ "$CERT_OPTION" == "y" || "$CERT_OPTION" == "yes" ]]; then
			sudo apt-get install -y certbot python3-certbot-nginx
			sudo certbot --nginx
		fi
  	fi
fi
read -p "Please create an admin user (default admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
$CUR_DIR/cms/bin/cmsAddAdmin $ADMIN_USER
