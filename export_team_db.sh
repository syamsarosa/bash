#!/bin/bash
set -e

# =================================
# Export DB and move it to respective team
# =================================
for i in {01..08}
do
    TEAM="teamA$i"
    DB="A${TEAM}_db"
    FILENAME="$DB.sql"
    SQLPATH="/var/www/$TEAM"

    mysqldump -u root $DB > $DB.sql
    mv $DB.sql /var/www/$TEAM

    echo "✔ TEAM: $TEAM | DB: $DB | FILENAME: $FILENAME | SQLPATH: $SQLPATH"
done

echo "====================================="
echo " Export Complete Successfully! "
echo "====================================="