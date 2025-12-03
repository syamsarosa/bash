#!/bin/bash

# ========================================
#  CHECK ROOT PERMISSION
# ========================================
if [ "$EUID" -ne 0 ]; then
  echo "Run this script with: sudo bash setup_class_env.sh"
  exit
fi


echo ""
echo "========================================"
echo " INSTALL LAMP + PHPMyAdmin"
echo "========================================"

apt update
apt install apache2 php php-mysql php-zip php-mbstring php-json php-curl php-xml mariadb-server acl -y
a2enmod rewrite

apt install phpmyadmin -y

# Link phpMyAdmin into web root
if [ ! -L /var/www/html/phpmyadmin ]; then
    ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
fi


echo ""
echo "========================================"
echo " CREATE GROUPS"
echo "========================================"

groupadd sftpusers        # students
groupadd lecturers        # lecturer group


echo ""
echo "========================================"
echo " CREATE LECTURER MASTER ACCOUNT"
echo "========================================"

# Create lecturer linux user (home=/var/www), add to lecturers group and sudo
echoblock "Creating lecturer account"
if ! id -u lectureradmin &>/dev/null; then
  adduser --disabled-password --gecos "" lectureradmin
  usermod -aG lecturers lectureradmin
  # Set lecturer home to /var/www so SFTP lands there
  usermod -d /var/www lectureradmin
  echo "lectureradmin:L3cturer@123" | chpasswd
  # Give sudo (be careful: you can remove later)
  apt install -y sudo
  usermod -aG sudo lectureradmin
else
  echo "lectureradmin already exists, skipping creation"
fi

# Lecturer DB account (full privileges)
echoblock "Creating MySQL lecturer account"
mysql -e "CREATE USER IF NOT EXISTS 'lecturer'@'localhost' IDENTIFIED BY 'L3cturer@123';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'lecturer'@'localhost' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"


echo ""
echo "========================================"
echo " TEAM LIST LOADING"
echo "========================================"

TEAM_CODES=(
    mA mB mC
    nA nB
)

echo "Teams to be created:"
echo "MA01..MA08, MB01..MB08, MC01..MC08, NA01..NA08, NB01..NB08"
echo ""

echo ""
echo "========================================"
echo " START CREATING ACCOUNTS"
echo "========================================"

for CODE in "${TEAM_CODES[@]}"; do
    for NUM in {01..08}; do

        TEAM="${CODE}${NUM}"          # MA01, MA02, ...
        DB="${TEAM}_db"

        # Password format: 12 chars
        # base prefix + @TEAM_ + suffix
        # Students think it's random but you can guess it
        PASS="xk.${CODE}Rp47-O${NUM}"

        echo "----------------------------------------"
        echo " Creating $TEAM"
        echo "----------------------------------------"

        #
        # 1. Linux SFTP user (locked to /var/www/TEAM )
        #
        useradd -m $TEAM -g sftpusers -s /usr/sbin/nologin
        echo "$TEAM:$PASS" | chpasswd

        mkdir -p /var/www/$TEAM/www
        chown root:root /var/www/$TEAM
        chmod 755 /var/www/$TEAM
        chown $TEAM:sftpusers /var/www/$TEAM/www

        echo "<?php echo 'Welcome $TEAM'; ?>" > /var/www/$TEAM/www/index.php
        chown $TEAM:sftpusers /var/www/$TEAM/www/index.php

        #
        # 2. MySQL: create DB and user. Grant privileges on own DB and allow create/drop globally
        #
        echo "Creating DB and MySQL user for $TEAM"
        mysql --protocol=socket -e "CREATE DATABASE IF NOT EXISTS \`${DB}\`;"
        mysql --protocol=socket -e "CREATE USER IF NOT EXISTS '${TEAM}'@'localhost' IDENTIFIED BY '${PASS}';"
        mysql --protocol=socket -e "GRANT ALL PRIVILEGES ON \`${DB}\`.* TO '${TEAM}'@'localhost';"
        # allow create/drop globally so team can create additional DBs (use carefully)
        mysql --protocol=socket -e "GRANT CREATE, DROP ON *.* TO '${TEAM}'@'localhost';"
        mysql --protocol=socket -e "FLUSH PRIVILEGES;"

        #
        # 3. Apache Alias for each team
        #
        grep -q "Alias /${TEAM}" /etc/apache2/sites-available/000-default.conf || cat <<EOF >> /etc/apache2/sites-available/000-default.conf

Alias /$TEAM /var/www/$TEAM/www
<Directory /var/www/$TEAM/www>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

EOF

        #
        # 4. ACL → Lecturer can access ALL folders
        #
        setfacl -R -m g:lecturers:rwx /var/www/$TEAM
        setfacl -dR -m g:lecturers:rwx /var/www/$TEAM

        echo "✔ $TEAM done.   User: $TEAM   Password: $PASS"
    done
done


echo ""
echo "========================================"
echo "  SSH JAIL FOR SFTP USERS"
echo "========================================"

grep -q "Match Group sftpusers" /etc/ssh/sshd_config || cat <<EOF >> /etc/ssh/sshd_config

Match Group sftpusers
    ChrootDirectory /var/www/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no

EOF


echo ""
echo "========================================"
echo " RESTART SERVICES"
echo "========================================"

systemctl restart apache2
systemctl restart mariadb
systemctl restart ssh


echo ""
echo "========================================"
echo " SETUP COMPLETE"
echo "========================================"
echo "Lecturer accounts:"
echo "  Linux SFTP: lecturer / Lecturer@123"
echo "  MySQL root access: lecturer / Lecturer@123"
echo ""
echo "Student accounts pattern:"
echo "  Username: MA01"
echo "  Password: x#@MA01_J!o2"
echo "  (Same pattern for every team)"
echo "========================================"