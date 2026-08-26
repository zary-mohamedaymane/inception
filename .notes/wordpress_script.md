Here is the detailed, technical breakdown of your `wp-entrypoint.sh` script, followed by how **PHP-FPM** works under the hood and what **WordPress** actually does when processing a request.

---

### **1. Script Breakdown: Core Steps & Flags Explained**

#### **`set -e`**

* **What it does:** Instructs Bash to exit immediately if any command returns a non-zero exit code (an error).
* **Why it matters:** Prevents "cascade failures" (e.g., if `wp core download` fails due to network issues, the script won't blindly attempt to run `wp config create` on missing files).

#### **`mkdir -p /run/php` & `chown -R www-data:www-data /run/php**`

* **What it does:** Prepares the runtime directory needed by the PHP-FPM master process to store its PID tracking file (`/run/php/php8.2-fpm.pid`) and assigns execution ownership to `www-data`.

#### **Database Health Check Loop (`until mariadb ... do sleep 2 done`)**

```bash
until mariadb -h"${MYSQL_HOST:-mariadb}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; do

```

* **Why it is needed:** Docker starts containers in parallel. Even if the MariaDB container is "running", the database daemon inside (`mysqld`) might still be bootstrapping or initializing tables.
* **Flags & Syntax:**
* **`${MYSQL_HOST:-mariadb}`:** Parameter expansion syntax. Uses `$MYSQL_HOST` if set, otherwise defaults to `mariadb` (the compose service name).
* **`-e "SELECT 1;"`:** Executes a lightweight query. If MariaDB is accepting connections and credentials match, it returns exit code `0`.
* **`>/dev/null 2>&1`:** Redirects standard output and error output to the "black hole" device, keeping your container startup logs clean until the DB responds.



---

#### **First-Boot Installation Guard (`if [ ! -f wp-config.php ]; then`)**

Checks if `wp-config.php` exists in `/var/www/html`. If present, all WP-CLI steps are skipped (preventing data overwrite on container restarts).

##### **1. `wp core download --allow-root**`

* Downloads the latest official WordPress core archive over HTTPS, extracts the source files directly into `/var/www/html`, and sets up the base PHP files (`index.php`, `wp-settings.php`, `wp-includes/`, etc.).
* **`--allow-root`:** WP-CLI throws a hard security error if executed as root user. Since the Docker entrypoint script runs as `root` inside the container, this flag explicitly permits root execution.

##### **2. `wp config create ...**`

* Generates a dynamic `wp-config.php` file containing database connection parameters (`DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`) and automatically injects unique security authentication keys and salts (`AUTH_KEY`, `SECURE_AUTH_KEY`, etc.).

##### **3. `wp core install ...**`

Populates the MariaDB database tables with default values without needing a browser wizard.

* **`--url`:** Sets `siteurl` and `home` options in the database to match your domain (e.g., `[https://mzary.42.fr](https://mzary.42.fr)`).
* **`--admin_user`, `--admin_password`, `--admin_email`:** Creates the primary Administrator account (ID 1).
* **`--skip-email`:** Prevents WP-CLI from trying to send a confirmation email via local `sendmail`/postfix (which isn't installed in slim containers).

##### **4. `wp user create ... --role=author**`

* Creates a secondary, unprivileged user account.
* **`--role=author`:** Assigns limited access privileges (can publish and manage their own posts, but cannot alter site settings, install plugins, or modify code).

---

#### **`chown -R www-data:www-data /var/www/html`**

Recursively updates ownership of all downloaded WordPress files to `www-data` (the default HTTP user for Nginx/PHP-FPM in Debian). This allows WordPress to auto-update themes, uploads, and plugins directly through its dashboard.

#### **`exec php-fpm8.2 -F`**

* **`php-fpm8.2`:** Runs the FastCGI Process Manager binary.
* **`-F` (Foreground):** Tells PHP-FPM to run in the foreground rather than daemonizing into the background. Docker requires process PID 1 to stay attached to standard output/error—if PHP-FPM daemonized to background, Docker would assume the process died and immediately kill the container.
* **`exec`:** Replaces the current Bash shell process with the `php-fpm8.2` binary. The PHP-FPM process takes over PID 1, ensuring process signals (`SIGTERM`, `SIGQUIT`) from `docker stop` cleanly shut down PHP worker pools.

---

### **2. How PHP-FPM Works Under the Hood**

PHP-FPM (FastCGI Process Manager) is an alternative PHP implementation designed for high-load sites. It follows a **Master/Worker Process Architecture**.

```
                         [ Nginx Container ]
                                  |
                                  | FastCGI Request (TCP Port 9000)
                                  v
+-------------------------------------------------------------------+
| WordPress Container                                               |
|                                                                   |
|   +-----------------------------------------------------------+   |
|   |                  PHP-FPM Master Process                   |   |
|   |                        (PID 1)                            |   |
|   +-----------------------------------------------------------+   |
|                 /               |               \                 |
|                /                |                \                |
|               v                 v                 v               |
|      +-----------------+ +-----------------+ +-----------------+  |
|      | Worker Process  | | Worker Process  | | Worker Process  |  |
|      |   (www-data)    | |   (www-data)    | |   (www-data)    |  |
|      +-----------------+ +-----------------+ +-----------------+  |
|               |                 |                 |               |
|               +-----------------+-----------------+               |
|                                 |                                 |
|                                 v                                 |
|                        [ MariaDB Container ]                      |
|                           (TCP Port 3306)                         |
+-------------------------------------------------------------------+

```

1. **Master Process (PID 1):**
Starts as root, reads configuration files (`/etc/php/8.2/fpm/php-fpm.conf` and `pool.d/www.conf`), binds to port `0.0.0.0:9000`, and spawns worker processes under the `www-data` account. It continuously monitors worker health and scales worker pools up/down based on load.
2. **Worker Processes (`www-data`):**
Unprivileged processes waiting for incoming FastCGI network records. Each worker handles **one HTTP/FastCGI request at a time**.
3. **Execution Cycle:**
* A worker accepts a FastCGI request from Nginx containing environment variables (`SCRIPT_FILENAME=/var/www/html/index.php`, `QUERY_STRING`, etc.).
* The worker invokes the PHP engine, executes the requested code, streams the rendered HTML output back across the TCP socket to Nginx, and immediately clears its memory footprint to process the next request.



---

### **3. What WordPress Actually Does When Processing a Request**

WordPress is an event-driven, hook-based CMS written in PHP. Here is what happens under the hood when a user accesses your site:

```
Nginx -> FastCGI -> index.php -> wp-blog-header.php -> wp-load.php -> wp-config.php -> MariaDB -> Output

```

1. **Entry Point (`index.php`):**
Nginx routes all dynamic requests (e.g., `[https://mzary.42.fr/sample-page/](https://mzary.42.fr/sample-page/)`) to `/var/www/html/index.php`. `index.php` loads `wp-blog-header.php`.
2. **Configuration & DB Connection (`wp-load.php` & `wp-config.php`):**
`wp-load.php` locates and loads `wp-config.php`. PHP initializes the `wpdb` class (using the `php-mysql` extension) and opens a TCP connection over port `3306` to MariaDB.
3. **Core Initialization & Hooks (`wp-settings.php`):**
WordPress loads active plugins and theme `functions.php` files, registering action and filter hooks (`add_action()`, `add_filter()`).
4. **Main Query & Route Resolution (`wp()`):**
WordPress parses the requested URL path, queries the MariaDB `wp_posts` and `wp_postmeta` tables using SQL to match page titles or permalinks, and retrieves post data and user permissions.
5. **Template Rendering:**
Loads the active theme's matching template file (e.g., `single.php` or `page.php`). PHP renders HTML dynamically on the fly, injecting DB values.
6. **Response Delivery:**
The rendered HTML stream is sent from PHP-FPM back to Nginx, which encrypts it via SSL/TLS and transmits it to the user's web browser.

---
