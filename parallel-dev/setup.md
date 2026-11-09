# One-time setup

parallel-dev needs nginx, PHP-FPM, MariaDB and WP-CLI on the machine, plus one nginx server
block and one PHP-FPM pool. After that, creating a site needs no root access and no config
change. Every step that writes system files uses `sudo`: show the user these commands and let
them run them, or get their go-ahead first.

Set `SKILL` to this skill's folder before starting, for example
`SKILL=~/.claude/skills/parallel-dev`.

## Ubuntu, Debian and WSL2

Tested on a clean Ubuntu 24.04 by `tests/test-setup-ubuntu.sh`, which runs these exact lines.

```bash
sudo apt update
sudo apt install -y nginx mariadb-server php-fpm php-mysql php-xml php-mbstring php-curl \
    php-zip php-gd php-intl unzip curl
curl -sSLO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar && sudo mv wp-cli.phar /usr/local/bin/wp

PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
SOCK=/run/php/php$PHPV-fpm-parallel-dev.sock

# Where sites live, owned by you.
sudo install -d -o "$USER" -g "$USER" /var/www/sites

# A PHP-FPM pool whose workers run as you, so they can read the plugin repositories.
sed -e "s|__USER__|$USER|g" -e "s|__WEB_USER__|www-data|g" -e "s|__FPM_SOCKET__|$SOCK|g" \
    "$SKILL/config/php-fpm-parallel-dev.conf" | sudo tee /etc/php/$PHPV/fpm/pool.d/parallel-dev.conf >/dev/null

# The wildcard server block.
sed -e "s|__FPM_SOCKET__|$SOCK|g" "$SKILL/config/parallel-dev-common.conf" \
    | sudo tee /etc/nginx/parallel-dev-common.conf >/dev/null
sed -e "s|__SITES_ROOT__|/var/www/sites|g" -e "s|__CONF_DIR__|/etc/nginx|g" \
    "$SKILL/config/nginx-parallel-dev.conf" | sudo tee /etc/nginx/sites-enabled/parallel-dev.conf >/dev/null

# A database account for you, authenticated by your login (no password stored anywhere).
# The scripts use it to create one database and one scoped user per site.
sudo mariadb -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED VIA unix_socket;
                 GRANT ALL PRIVILEGES ON *.* TO '$USER'@'localhost' WITH GRANT OPTION;"

sudo nginx -t && sudo systemctl reload nginx && sudo systemctl restart php$PHPV-fpm

# The pristine core every new site is copied from.
"$SKILL/scripts/update-core.sh"
```

nginx itself runs as `www-data` and serves CSS, JavaScript and images straight from disk,
including from the plugin repositories the sites symlink to. If your home directory is not
traversable by other users (Ubuntu 21.04 and later create it with mode 750), plugin assets
return 403. Allow traversal only, without making anything readable:

```bash
chmod o+x "$HOME"
```

## macOS with Homebrew

The same parts, at Homebrew's paths. nginx run by `brew services` runs as you, so the pool's
socket belongs to you too.

```bash
brew install nginx mariadb php wp-cli
brew services start mariadb

PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
BREW=$(brew --prefix)
SOCK=$BREW/var/run/php-fpm-parallel-dev.sock
SITES=$BREW/var/www/sites
mkdir -p "$SITES" "$BREW/var/run"
mkdir -p ~/.config/parallel-dev && echo "PD_SITES_ROOT=$SITES" >> ~/.config/parallel-dev/env

sed -e "s|__USER__|$USER|g" -e "s|__WEB_USER__|$USER|g" -e "s|__FPM_SOCKET__|$SOCK|g" \
    -e "s|^group = .*|group = staff|" \
    "$SKILL/config/php-fpm-parallel-dev.conf" > "$BREW/etc/php/$PHPV/php-fpm.d/parallel-dev.conf"
sed -e "s|__FPM_SOCKET__|$SOCK|g" "$SKILL/config/parallel-dev-common.conf" \
    > "$BREW/etc/nginx/parallel-dev-common.conf"
sed -e "s|__SITES_ROOT__|$SITES|g" -e "s|__CONF_DIR__|$BREW/etc/nginx|g" \
    "$SKILL/config/nginx-parallel-dev.conf" > "$BREW/etc/nginx/servers/parallel-dev.conf"

nginx -t && brew services restart nginx && brew services restart php

"$SKILL/scripts/update-core.sh"
```

Homebrew's MariaDB already gives your macOS user a passwordless account over the local socket.

## Check it works

```bash
"$SKILL/scripts/create-site.sh" hello-world
curl -s -o /dev/null -w '%{http_code}\n' http://hello-world.localhost:8081/
```

`200` means the setup is complete. Delete the check site with
`"$SKILL/scripts/delete-site.sh" hello-world`.
