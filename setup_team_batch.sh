#!/bin/bash
set -e

# =================================
# Ensure script is run as root
# =================================
if [ "$EUID" -ne 0 ]; then
    echo "Please run with: sudo bash setup.sh"
    exit
fi

# =================================
# Install LAMP stack and phpMyAdmin
# =================================
echo "Installing LAMP stack..."
apt update
apt install apache2 php php-mysql php-zip php-mbstring php-json php-curl php-xml mariadb-server -y
a2enmod rewrite

echo "Installing phpMyAdmin..."
apt install phpmyadmin -y

# Enable phpMyAdmin symlink (only once)
if [ ! -L /var/www/html/phpmyadmin ]; then
    ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
fi

# =================================
# Create SFTP group (skip if exists)
# =================================
echo "Ensuring SFTP group exists..."
getent group sftpusers >/dev/null || groupadd sftpusers

# =================================
# Create user folders, DB, Apache config
# =================================
for i in {01..08}
do
    TEAM="team$i"
    DB="${TEAM}_db"
    PASS="pass_t3am$i"

    echo "Processing $TEAM..."

    # Linux user (skip if exists)
    if ! id "$TEAM" &>/dev/null; then
        useradd -m "$TEAM" -g sftpusers -s /usr/sbin/nologin
        echo "$TEAM:$PASS" | chpasswd

        # SFTP folder structure
        mkdir -p /var/www/$TEAM
        chown root:root /var/www/$TEAM
        chmod 755 /var/www/$TEAM

        mkdir -p /var/www/$TEAM/www
        chown $TEAM:sftpusers /var/www/$TEAM/www

        # Default index
        if [ ! -f /var/www/$TEAM/www/index.php ]; then
            echo "This is $TEAM default page" > /var/www/$TEAM/www/index.php
        fi

        # MariaDB
        mysql --protocol=socket -e "CREATE DATABASE IF NOT EXISTS $DB;"
        mysql --protocol=socket -e "CREATE USER IF NOT EXISTS '$TEAM'@'localhost' IDENTIFIED BY '$PASS';"
        mysql --protocol=socket -e "GRANT ALL PRIVILEGES ON $DB.* TO '$TEAM'@'localhost';"
        mysql --protocol=socket -e "FLUSH PRIVILEGES;"

        # Apache alias (add only once)
        if ! grep -q "Alias /team$i /var/www/team$i/www" /etc/apache2/sites-available/000-default.conf; then
            cat <<-EOF >> /etc/apache2/sites-available/000-default.conf

            Alias /team$i /var/www/team$i/www
            <Directory /var/www/team$i/www>
                Options Indexes FollowSymLinks
                AllowOverride All
                Require all granted
            </Directory>

EOF
        fi
    fi

    echo "✔ $TEAM: Folder /var/www/$TEAM | DB: $DB | Password: $PASS"
done

# =================================
# Add SSH SFTP lock config (only once)
# =================================
echo "Ensuring SSHD SFTP config exists..."

if ! grep -q "Match Group sftpusers" /etc/ssh/sshd_config; then
cat <<EOF >> /etc/ssh/sshd_config

Match Group sftpusers
    ChrootDirectory /var/www/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no

EOF
fi

# =================================
# Restart services safely
# =================================
echo "Restarting services..."
systemctl restart apache2
systemctl restart mariadb

# safer than restart (reload first)
systemctl reload ssh || systemctl restart ssh

echo "====================================="
echo " Setup completed successfully! "
echo "====================================="