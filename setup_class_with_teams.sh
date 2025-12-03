#!/bin/bash

##############################################
# Ensure script is run as root
##############################################
if [ "$EUID" -ne 0 ]; then
  echo "Please run using: sudo bash setup_classes.sh"
  exit
fi


##############################################
# Install LAMP + phpMyAdmin
##############################################
echo "===== INSTALLING LAMP + PHPMYADMIN ====="
apt update
apt install -y apache2 php php-mysql php-zip php-mbstring php-json php-curl php-xml mariadb-server phpmyadmin
a2enmod rewrite

# phpMyAdmin symlink
if [ ! -L /var/www/html/phpmyadmin ]; then
    ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
fi


##############################################
# Create SFTP group
##############################################
echo "===== CREATING SFTP GROUP ====="
groupadd sftpusers 2>/dev/null


##############################################
# Lecturer account
##############################################
echo "===== CREATING LECTURER ACCOUNT ====="
LECTURER_PASS="Lecturer#2024!"

adduser lecturer --gecos "" --disabled-password
echo "lecturer:$LECTURER_PASS" | chpasswd

# Lecturer should start in /var/www
usermod -d /var/www lecturer

# Give lecturer full access to all dirs
echo "Lecturer password: $LECTURER_PASS"


##############################################
# Class list: 5 classes × 8 teams each
##############################################
CLASSES=("MA" "MB" "MC" "NA" "NB")


##############################################
# Function to generate password
##############################################
gen_pass() {
    CLASS="$1"   # MA
    NUM="$2"     # 01
    echo "dxGA.${CLASS}Qgz1842-${NUM}"
}


##############################################
# Create all teams
##############################################
echo "===== CREATING TEAM ACCOUNTS ====="

for CLASS in "${CLASSES[@]}"; do
  for n in {01..08}; do

    TEAM="${CLASS}${n}"
    PASS=$(gen_pass "$CLASS" "$n")
    DB_PREFIX="${TEAM}_"

    echo "---- Setting up $TEAM ----"

    # Create Linux SFTP user
    useradd -m "$TEAM" -g sftpusers -s /usr/sbin/nologin
    echo "$TEAM:$PASS" | chpasswd

    ##############################
    # Create folder structure
    ##############################
    mkdir -p /var/www/$TEAM/www

    # Strict permissions for SFTP chroot
    chown root:root /var/www/$TEAM
    chmod 755 /var/www/$TEAM

    chown $TEAM:sftpusers /var/www/$TEAM/www
    chmod 755 /var/www/$TEAM/www

    echo "Team $TEAM Home" > /var/www/$TEAM/www/index.php

    ##############################
    # MySQL user + DB access
    ##############################
    mysql -e "DROP USER IF EXISTS '$TEAM'@'localhost';"
    mysql -e "CREATE USER '$TEAM'@'localhost' IDENTIFIED BY '$PASS';"

    # Allow DB creation only with prefix: MA01_*, MB02_*, NB08_* etc.
    mysql -e "GRANT CREATE, DROP ON ${DB_PREFIX}% TO '$TEAM'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_PREFIX}% TO '$TEAM'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    ##############################
    # Apache alias
    ##############################
    CONF="/etc/apache2/sites-available/000-default.conf"
    if ! grep -q "/$TEAM " "$CONF"; then
      cat <<EOF >> "$CONF"

Alias /$TEAM /var/www/$TEAM/www
<Directory /var/www/$TEAM/www>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

EOF
    fi

    echo "$TEAM → PASS: $PASS"

  done
done


##############################################
# SSH config for team SFTP
##############################################
echo "===== CONFIGURE SFTP LOCKDOWN ====="

if ! grep -q "Match Group sftpusers" /etc/ssh/sshd_config; then
cat <<EOF >> /etc/ssh/sshd_config

Match Group sftpusers
    ChrootDirectory /var/www/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no

EOF
fi


##############################################
# Restart services
##############################################
echo "===== RESTARTING SERVICES ====="
systemctl restart apache2
systemctl restart mariadb
systemctl restart ssh

echo "===== SETUP COMPLETE ====="
