Here is the comprehensive breakdown of your Nginx server block configuration, followed by a step-by-step trace of how Nginx handles different real-world browser request scenarios.

---

### **1. Configuration Directives Explained**

#### **Networking & Server Identification**

* **`listen 443 ssl;`**: Tells Nginx to listen for encrypted HTTPS connections over IPv4 on port `443`.
* **`listen [::]:443 ssl;`**: Listens on port `443` over IPv6 (`[::]` represents the IPv6 wildcard address).
* **`server_name mzary.42.fr;`**: Defines the virtual host domain name. Nginx matches incoming TLS SNI (Server Name Indication) and HTTP `Host` headers against this string to choose this `server` block.

#### **SSL/TLS Cryptographic Settings**

* **`ssl_certificate ...;`**: Specifies the path to the public SSL certificate (contains your public key and domain identity).
* **`ssl_certificate_key ...;`**: Specifies the private key used to decrypt session keys and authenticate the TLS handshake.
* **`ssl_protocols TLSv1.2 TLSv1.3;`**: Restricts accepted TLS versions to 1.2 and 1.3 only, disabling outdated, vulnerable protocols (SSLv3, TLSv1.0, TLSv1.1).

#### **Document Root & Defaults**

* **`root /var/www/html;`**: Sets the base filesystem directory on the Nginx container where site files live.
* **`index index.php index.html;`**: Defines default filenames Nginx checks when a client requests a directory path (e.g., `[https://mzary.42.fr/](https://mzary.42.fr/)`). It checks for `index.php` first, falling back to `index.html`.

#### **Location Matching Rules**

* **`location / { ... }`**: Catch-all location block matching any request path starting with `/`.
* **`try_files $uri $uri/ /index.php?$args;`**: Nginx’s main routing engine for WordPress. It checks for files in order:
1. `$uri`: Does an exact static file exist matching the request? (e.g., `style.css`)
2. `$uri/`: Does a directory exist matching the request? (e.g., `wp-admin/`)
3. `/index.php?$args`: Fallback! Pass the request to `index.php`, preserving URL query parameters via `$args`.




* **`location ~ \.php$ { ... }`**: Regex location block (`~`) matching any request URI ending in `.php`.
* **`include fastcgi_params;`**: Imports standard environment variable definitions (like `REQUEST_METHOD`, `QUERY_STRING`, `CONTENT_TYPE`).
* **`fastcgi_pass wordpress:9000;`**: Forwards the FastCGI request over TCP to the container named `wordpress` on port `9000` (where PHP-FPM is listening).
* **`fastcgi_index index.php;`**: Sets the default file name if `$fastcgi_script_name` ends with a slash.
* **`fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;`**: Critical setting! Tells PHP-FPM the absolute file path on disk to execute (e.g., `/var/www/html/index.php`).



---

### **2. How Nginx Handles Browser Requests (Case-by-Case)**

Here is how Nginx processes three common request scenarios under the hood:

```
[ Browser ] --(HTTPS :443)--> [ Nginx ] --(FastCGI :9000)--> [ PHP-FPM ] --(SQL :3306)--> [ MariaDB ]

```

---

#### **Case 1: Direct Request for a Static File (`[https://mzary.42.fr/wp-content/uploads/image.png](https://mzary.42.fr/wp-content/uploads/image.png)`)**

1. **TLS Handshake:** The browser initiates an HTTPS connection on port `443`. Nginx completes the TLS 1.2/1.3 handshake using `nginx-selfsigned.crt` and `key`.
2. **Server Matching:** Nginx checks the SNI / `Host` header (`mzary.42.fr`) and selects this `server` block.
3. **Location Matching:** The request path `/wp-content/uploads/image.png` does not end in `.php`, so it falls into `location /`.
4. **`try_files` Processing:**
* Checks `$uri`: Does `/var/www/html/wp-content/uploads/image.png` exist on disk? **Yes.**


5. **Response:** Nginx reads the image directly from `/var/www/html`, sets the appropriate MIME `Content-Type: image/png` header, and sends the raw file bytes back to the browser **without touching PHP-FPM or MariaDB**.

---

#### **Case 2: WordPress Pretty Permalinks (`[https://mzary.42.fr/about-us](https://mzary.42.fr/about-us)`)**

1. **TLS Handshake & Server Match:** Browser connects securely to port `443` on `mzary.42.fr`.
2. **Location Matching:** `/about-us` falls into `location /`.
3. **`try_files` Processing:**
* Checks `$uri`: Does a physical file named `/var/www/html/about-us` exist? **No.**
* Checks `$uri/`: Does a physical directory `/var/www/html/about-us/` exist? **No.**
* **Fallback:** Rewrites the internal request to `/index.php` (passing any URL parameters via `$args`).


4. **Internal Re-routing:** Nginx re-evaluates `/index.php` against all location blocks.
5. **PHP Location Match:** `/index.php` matches `location ~ \.php$`.
6. **FastCGI Delegation:**
* Constructs environment variables: `SCRIPT_FILENAME` becomes `/var/www/html/index.php`.
* Sends a binary FastCGI packet over TCP network to `wordpress:9000`.


7. **Execution & Return:** PHP-FPM executes `index.php`, queries MariaDB, renders the HTML page for "About Us", and returns it to Nginx. Nginx streams the rendered HTML back to the browser over HTTPS.

---

#### **Case 3: Direct PHP File Request (`[https://mzary.42.fr/wp-login.php](https://mzary.42.fr/wp-login.php)`)**

1. **TLS Handshake & Server Match:** Handshake completes on port `443`.
2. **Location Matching:** The URI `/wp-login.php` ends in `.php`, directly matching `location ~ \.php$`. (It skips `location /` entirely).
3. **FastCGI Parameter Build:**
* `$document_root` = `/var/www/html`
* `$fastcgi_script_name` = `/wp-login.php`
* `SCRIPT_FILENAME` = `/var/www/html/wp-login.php`


4. **Hand-Off:** Nginx packs the client HTTP request details into FastCGI protocol format and opens a TCP stream to `wordpress:9000`.
5. **Response:** PHP-FPM executes `/var/www/html/wp-login.php` and returns the dynamic login page HTML stream to Nginx, which relays it to the browser.

---


Here is the clear breakdown of what `include fastcgi_params;` and `fastcgi_index index.php;` do, why they exist, and how they bridge Nginx and PHP-FPM.

---

### **1. `include fastcgi_params;**`

#### **What it is:**

This line imports a file named `fastcgi_params` (located in `/etc/nginx/fastcgi_params` inside the Nginx container) into your configuration block.

#### **Why it is needed:**

HTTP and FastCGI are two completely different networking protocols:

* **HTTP:** What browsers talk (Headers, Cookies, GET/POST body).
* **FastCGI:** What PHP-FPM understands (Binary packets containing environment variables).

PHP-FPM does **not** read raw HTTP request headers. Instead, PHP relies on its global `$_SERVER` superglobal array (e.g., `$_SERVER['REQUEST_METHOD']`, `$_SERVER['QUERY_STRING']`).

The `fastcgi_params` file contains a list of directives that map Nginx’s internal HTTP variables into standard CGI environment variables:

```nginx
# Inside /etc/nginx/fastcgi_params:
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;
fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

```

#### **What happens if you remove it:**

If you remove `include fastcgi_params;`, PHP-FPM will receive the file request, but it **won't know**:

* Whether it was a `GET` or `POST` request.
* What URL parameters were passed (`?page=2`).
* What IP address the client has.
* What headers or cookies were sent.

WordPress will fail completely because functions like `$_SERVER['REQUEST_METHOD']` will return `NULL`.

---

### **2. `fastcgi_index index.php;**`

#### **What it is:**

Sets a default filename that Nginx appends to `$fastcgi_script_name` if the requested URI ends with a forward slash (`/`).

#### **How it works:**

Suppose a browser makes a direct request to a directory inside the PHP location block, like:
`[https://mzary.42.fr/wp-admin/](https://mzary.42.fr/wp-admin/)`

1. The URI is `/wp-admin/`.
2. Nginx sees that `$fastcgi_script_name` ends with `/`.
3. `fastcgi_index index.php;` tells Nginx: *"Since this ends in a trailing slash, append `index.php` to the script name."*
4. `$fastcgi_script_name` automatically becomes `/wp-admin/index.php`.
5. When Nginx runs the next line:
```nginx
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

```


It evaluates to `/var/www/html/wp-admin/index.php` and tells PHP-FPM to execute that specific file.

#### **Why it feels redundant in WordPress:**

In your specific configuration, `try_files $uri $uri/ /index.php?$args;` already catches most directory requests in `location /` and rewrites them. However, `fastcgi_index index.php;` acts as a **safety net** directly inside the PHP handler block for any raw directory requests that bypass `try_files` or get sent directly to a subfolder like `/wp-admin/`.

---

### **Summary Table**

| Directive | Simple Definition | What PHP Gets From It |
| --- | --- | --- |
| **`include fastcgi_params;`** | Imports the map that translates HTTP headers into CGI variables. | Populates `$_SERVER` (`$_SERVER['REQUEST_METHOD']`, `$_SERVER['QUERY_STRING']`, etc.). |
| **`fastcgi_index index.php;`** | Appends `index.php` to folder requests ending in `/`. | Ensures PHP receives `/path/index.php` instead of just `/path/` when a directory is requested. |
