# Load .env file variables
cd ..
export $(grep -v '^#' .env | xargs)
mysql --user=root --password="$DB_PASSWORD" -h mariadb <<-EOSQL
    CREATE DATABASE IF NOT EXISTS testing;
    GRANT ALL PRIVILEGES ON \`testing%\`.* TO '$DB_USERNAME'@'%';
EOSQL
