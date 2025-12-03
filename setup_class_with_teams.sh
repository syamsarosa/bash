#!/bin/bash
set -euo pipefail

# =========================================
# Classroom multi-team LAMP + SFTP setup
# - 5 classes: MA, MB, MC, NA, NB
# - 8 teams per class (01..08)
# - Safe 12-char passwords (encoded team, not literal MA01)
# - Lecturer account with /var/www home + sudo + full MySQL access
# =========================================

# ---------- Helpers ----------
echoblock() {
  echo
  echo "========================================"
  echo " $1"
  echo "========================================"
}

# Generate a short random letter/digit from /dev/urandom
rand_lower() { tr -dc 'a-z' </dev/urandom | head -c1 || echo 'x'; }
rand_upper() { tr -dc 'A-Z' </dev/urandom | head -c1 || echo 'A'; }
rand_two_letters_upperlower() {
  echo -n "$(tr -dc 'A-Z' </dev/urandom | head -c1 || echo 'Q')"
  echo -n "$(tr -dc 'a-z' </dev/urandom | head -c1 || echo 'z')"
}
rand_two_digits() { tr -dc '0-9' </dev/urandom | head -c2 || echo '42'; }

# Encode team code: e.g., MA01 -> mA + O1  => mAO1 (0->O)
encode_team() {
  local cls="$1" num="$2"
  local a=${cls:0:1} b=${cls:1:1}
  local a_l=$(echo "$a" | tr '[:upper:]' '[:lower:]')
  local b_u=$(echo "$b" | tr '[:lower:]' '[:upper:]')
  # Replace leading zero with letter O for nicer obfuscation (01 -> O1)
  local num_enc
  if [[ "${num:0:1}" == "0" ]]; then
    num_enc="O${num:1:1}"
  else
    num_enc="$num"
  fi
  echo "${a_l}${b_u}${num_enc}"   # e.g. mAO1
}

# Make a 12-char safe password (letters, digits, '.' and '-' only)
# Pattern: <l><U>.<U><l><dd>-<encodedTeam>
# Count: 1+1+1 +1+1+2 +1 +4 = 12  (encodedTeam is 4 chars like mAO1)
make_password() {
  local cls="$1" num="$2"
  local p1=$(rand_lower)
  local p2=$(rand_upper)
  local mid=$(rand_two_letters_upperlower)
  local dd=$(rand_two_digits)
  local enc=$(encode_team "$cls" "$num")   # 4 chars
  echo "${p1}${p2}.${mid}${dd}-${enc}"
}

# ---------- Start script ----------
echoblock "Pre-check & update"
if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root: sudo bash $0"
  exit 1
fi

# Install required packages (if not present)
echoblock "Installing packages (apache2, php, mariadb, phpmyadmin, acl)"
apt update
apt install -y apache2 php php-mysql php-zip php-mbstring php-json php-curl php-xml mariadb-server phpmyadmin acl

# Ensure phpMyAdmin uses cookie auth (so users must enter MySQL creds)
PHPMA_CFG="/etc/phpmyadmin/config.inc.php"
if ! grep -q "\$cfg\['Servers'\]\[\$i\]\['auth_type'\] = 'cookie';" "$PHPMA_CFG" 2>/dev/null; then
  # append or modify minimal setting
  if grep -q "\$cfg\['Servers'\]\[\$i\]\['auth_type'\]" "$PHPMA_CFG" 2>/dev/null; then
    sed -i "s/\$cfg\['Servers'\]\[\$i\]\['auth_type'\].*/\$cfg['Servers'][\$i]['auth_type'] = 'cookie';/" "$PHPMA_CFG"
  else
    cat <<'EOF' >> "$PHPMA_CFG"

# enforce cookie auth so each user logs in with MySQL credentials
$cfg['Servers'][$i]['auth_type'] = 'cookie';

EOF
  fi
fi

# Symlink phpMyAdmin to webroot if not linked
if [ ! -L /var/www/html/phpmyadmin ]; then
  ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
fi

# Create groups
echoblock "Creating groups"
getent group sftpusers >/dev/null || groupadd sftpusers
getent group lecturers >/dev/null || groupadd lecturers

# Create lecturer linux user (home=/var/www), add to lecturers group and sudo
echoblock "Creating lecturer account"
if ! id -u lectureradmin &>/dev/null; then
  adduser --disabled-password --gecos "" lectureradmin
  usermod -aG lecturers lectureradmin
  # Set lecturer home to /var/www so SFTP lands there
  usermod -d /var/www lectureradmin
  echo "lectureradmin:Lecturer@123" | chpasswd
  # Give sudo (be careful: you can remove later)
  apt install -y sudo
  usermod -aG sudo lectureradmin
else
  echo "lectureradmin already exists, skipping creation"
fi

# Create a MySQL lecturer account with full privileges
echoblock "Creating MySQL lecturer account"
mysql -e "CREATE USER IF NOT EXISTS 'lecturer'@'localhost' IDENTIFIED BY 'Lecturer@123';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'lecturer'@'localhost' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"

# Team definitions
TEAM_CLASSES=(MA MB MC NA NB)

# CSV output file for credentials
CRED_OUT="/root/team_credentials.csv"
echo "TEAM,FTP_USER,PASSWORD,DB" > "$CRED_OUT"

echoblock "Creating team users, DBs, folders and ACLs"

for cls in "${TEAM_CLASSES[@]}"; do
  for num in 01 02 03 04 05 06 07 08; do
    team="${cls}${num}"
    db="${team}_db"
    pass="$(make_password "$cls" "$num")"

    echo "----------------------------------------"
    echo " Processing $team"
    echo "----------------------------------------"

    # Create Linux user (skip if exists)
    if ! id -u "$team" &>/dev/null; then
      useradd -m -g sftpusers -s /usr/sbin/nologin "$team"
      echo "$team:$pass" | chpasswd
    else
      echo "User $team already exists, skipping useradd"
      # optionally update password:
      echo "$team:$pass" | chpasswd
    fi

    # SFTP/chroot folder
    mkdir -p "/var/www/$team/www"
    chown root:root "/var/www/$team"
    chmod 755 "/var/www/$team"
    chown "$team":sftpusers "/var/www/$team/www"

    # Default index (owned by team)
    if [ ! -f "/var/www/$team/www/index.php" ]; then
      echo "<?php echo 'Welcome $team'; ?>" > "/var/www/$team/www/index.php"
      chown "$team":sftpusers "/var/www/$team/www/index.php"
    fi

    # MySQL: create DB and user. Grant privileges on own DB and allow create/drop globally
    echo "Creating DB and MySQL user for $team"
    mysql --protocol=socket -e "CREATE DATABASE IF NOT EXISTS \`${db}\`;"
    mysql --protocol=socket -e "CREATE USER IF NOT EXISTS '${team}'@'localhost' IDENTIFIED BY '${pass}';"
    mysql --protocol=socket -e "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${team}'@'localhost';"
    # allow create/drop globally so team can create additional DBs (use carefully)
    mysql --protocol=socket -e "GRANT CREATE, DROP ON *.* TO '${team}'@'localhost';"
    mysql --protocol=socket -e "FLUSH PRIVILEGES;"

    # Apache alias - add once per team
    if ! grep -q "Alias /${team} /var/www/${team}/www" /etc/apache2/sites-available/000-default.conf; then
      # Use indented heredoc (tabs will be stripped) for neat file content
      cat <<-EOF >> /etc/apache2/sites-available/000-default.conf

	Alias /${team} /var/www/${team}/www
	<Directory /var/www/${team}/www>
	    Options Indexes FollowSymLinks
	    AllowOverride All
	    Require all granted
	</Directory>

EOF
    fi

    # ACL: grant lecturers group rwx on the team folder and default ACL for new files
    setfacl -R -m g:lecturers:rwx "/var/www/$team"
    setfacl -R -m d:g:lecturers:rwx "/var/www/$team"

    # Save credentials
    echo "${team},${team},${pass},${db}" >> "$CRED_OUT"

    echo "Done ${team}"
  done
done

# Configure sshd to chroot sftpusers group (only once)
echoblock "Configuring SSHD for SFTP chroot"
if ! grep -q "Match Group sftpusers" /etc/ssh/sshd_config; then
  cat <<'EOF' >> /etc/ssh/sshd_config

Match Group sftpusers
    ChrootDirectory /var/www/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no

EOF
fi

# Ensure phpMyAdmin uses cookie auth in case the earlier edit didn't apply (extra safety)
if ! grep -q "\$cfg\['Servers'\]\[\$i\]\['auth_type'\] = 'cookie';" /etc/phpmyadmin/config.inc.php 2>/dev/null; then
  echo "\$cfg['Servers'][\$i]['auth_type'] = 'cookie';" >> /etc/phpmyadmin/config.inc.php
fi

echoblock "Restarting services"
systemctl restart apache2
systemctl restart mariadb
systemctl reload ssh || systemctl restart ssh

echoblock "Finished"
echo "Credentials saved to: $CRED_OUT"
echo "Example: open http://SERVER_IP/phpmyadmin and login as team user (username/password from CSV)."
echo ""
echo "Notes:"
echo " - Team users were granted CREATE and DROP globally to allow multiple DBs per team."
echo " - PLEASE instruct students to name their DBs using the team prefix (e.g. ${team}_proj1) to avoid collisions."
echo " - Lecturer linux user: lectureradmin (password Lecturer@123) -- home=/var/www, sudo-enabled."
echo " - Lecturer MySQL user: lecturer (password Lecturer@123) has full DB access."

exit 0
