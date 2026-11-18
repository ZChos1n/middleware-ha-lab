-- MySQL replica init: point at master via GTID auto-position.
-- In a real deploy you would source the credentials from a secret, not hardcode.
CHANGE MASTER TO
    MASTER_HOST='mysql-master',
    MASTER_USER='repl',
    MASTER_PASSWORD='replpass',
    MASTER_PORT=3306,
    MASTER_AUTO_POSITION=1;
START SLAVE;
