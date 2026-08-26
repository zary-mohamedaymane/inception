Here is the complete technical breakdown of your Nginx entrypoint script, including flag definitions, process management, OpenSSL certificate generation, and an in-depth explanation of the SSL/TLS handshake.

---

### **1. Script Breakdown & Command Flags**

#### **`set -e`**

* **What it does:** Tells Bash to exit immediately if any command exits with a non-zero status. If OpenSSL fails or directory creation fails, the script halts instead of blindly launching Nginx.

#### **`mkdir -p /etc/ssl/certs /etc/ssl/private /run/nginx`**

* **`-p` (parents):** Creates missing directories without throwing an error if they already exist.
* **Why `/run/nginx` is created:** Nginx needs `/run/nginx` at boot time to write its primary process ID file (`nginx.pid`). In minimal Linux environments, missing this directory causes Nginx to crash on startup.

---

### **2. OpenSSL Certificate Generation**

```bash
if [ ! -f /etc/ssl/certs/nginx-selfsigned.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/C=MA/ST=BeniMellal/L=Khouribga/O=1337/OU=student/CN=mzary.42.fr"
fi

```

The `if [ ! -f ... ]` check ensures the certificate is generated only on the first boot, preserving existing certificates across container restarts.

#### **OpenSSL Flag Breakdown**

| Flag | Meaning & Technical Function |
| --- | --- |
| **`req`** | Invokes the PKCS#10 X.509 certificate request and generation utility. |
| **`-x509`** | Outputs a self-signed X.509 certificate directly instead of creating a Certificate Signing Request (CSR) to send to a Certificate Authority (CA). |
| **`-nodes`** | Stands for **"No DES"** (No encryption for key). Stores the private key unencrypted on disk without a passphrase. This allows Nginx to read the key automatically on container startup without requiring a human to type a password. |
| **`-days 365`** | Sets the certificate validity duration to 1 year from the creation date. |
| **`-newkey rsa:2048`** | Generates a brand-new RSA public/private key pair with a bit length of 2048 bits (the standard minimum for secure modern encryption). |
| **`-keyout`** | Specifies where to write the created private key file (`nginx-selfsigned.key`). |
| **`-out`** | Specifies where to write the created public certificate file (`nginx-selfsigned.crt`). |
| **`-subj "..."`** | Suppresses the interactive prompt and passes the Certificate Subject field directly in X.500 distinguished name format: |
|  | • **`C=MA`**: Country (Morocco) |
|  | • **`ST=BeniMellal`**: State/Province |
|  | • **`L=Khouribga`**: Locality/City |
|  | • **`O=1337`**: Organization |
|  | • **`OU=student`**: Organizational Unit |
|  | • **`CN=mzary.42.fr`**: Common Name (the exact domain name Nginx serves). |

---

### **3. Netcat (`nc`) Port Checking**

```bash
until nc -z -v -w3 wordpress 9000; do
    sleep 2
done

```

* **Purpose:** Prevents Nginx from starting up before PHP-FPM is ready to process requests. If Nginx receives a browser request before PHP-FPM is listening on TCP port `9000`, Nginx returns a `502 Bad Gateway` error to the user.

#### **Netcat Flags Explained**

* **`-z` (Zero-I/O mode):** Scans for listening daemons without sending any payload data to the target socket.
* **`-v` (Verbose):** Prints connection attempt status to standard error for debugging logs.
* **`-w3` (Timeout):** Sets a hard timeout of 3 seconds per connection attempt.
* **`wordpress 9000`:** Targets host `wordpress` (resolved via Docker internal DNS) on TCP port `9000`.

---

### **4. Process Execution (`exec nginx -g "daemon off;"`)**

* **`-g "daemon off;"`**: Overrides default Nginx behavior (which daemonizes into the background) and forces it to stay in the **foreground**.
* **`exec`**: Replaces the current shell process with the Nginx binary, transferring process **PID 1** directly to Nginx. This ensures process control signals like `docker stop` (`SIGTERM`) gracefully shut down Nginx worker processes immediately.

---

### **5. Deep Dive: How HTTPS and SSL/TLS Work**

HTTPS (HTTP Secure) wraps normal HTTP traffic inside an encrypted **TLS (Transport Layer Security)** tunnel. It provides three primary security guarantees:

1. **Confidentiality:** Encryption hides sensitive data from packet sniffers.
2. **Integrity:** Digital signatures prevent attackers from modifying data in transit.
3. **Authentication:** Certificates verify the server identity.

#### **How Public Key Infrastructure (PKI) Works**

TLS relies on **Asymmetric Encryption** (Public/Private key pairs) to establish connection safety, and **Symmetric Encryption** (AES-GCM or ChaCha20) to encrypt actual web traffic.

* **Private Key (`.key`):** Stored strictly on the server. Used to decrypt data and sign cryptographic challenges. **Never shared.**
* **Public Certificate (`.crt`):** Sent to any client connecting over HTTPS. Contains the server's public key and domain identity (`CN=mzary.42.fr`).

---

#### **Step-by-Step TLS 1.2 / 1.3 Handshake Workflow**

```
[ Browser (Client) ]                                       [ Nginx Server ]
         |                                                        |
         | -------------- 1. ClientHello (TLS 1.3) -------------> |
         |                                                        |
         | <--- 2. ServerHello + Certificate + Key Exchange ----- |
         |                                                        |
         | [3. Verify Certificate & Generate Session Keys]        |
         |                                                        |
         | -------------- 4. Finished (Symmetric Encrypted) ----> |
         |                                                        |
         | <============= 5. Encrypted HTTPS Application Data ===> |

```

#### **Phase 1: Negotiation & Hello**

1. **ClientHello:** The browser sends supported TLS versions (TLS 1.2, 1.3), cipher suites (e.g., `TLS_AES_256_GCM_SHA384`), and SNI (Server Name Indication: `mzary.42.fr`).
2. **ServerHello:** Nginx selects the highest shared TLS protocol (TLS 1.3) and cipher suite, then sends its public certificate (`nginx-selfsigned.crt`).

#### **Phase 2: Authentication & Key Exchange**

3. **Certificate Verification:**
* *In Production:* The browser checks if the certificate is signed by a trusted root CA (e.g., Let's Encrypt, DigiCert).
* *In Local/Self-Signed Setup:* Because `nginx-selfsigned.crt` is self-signed (signed by your own key, not a trusted CA), the browser displays a security warning (`NET::ERR_CERT_AUTHORITY_INVALID`). Accepting the warning bypasses root CA validation while maintaining full encryption.


4. **ECDHE Key Exchange:** The client and server use an **Elliptic Curve Diffie-Hellman** key exchange algorithm. Both sides independently calculate a shared secret key without ever sending the key over the wire.

#### **Phase 3: Symmetric Data Transmission**

5. **Session Encryption:** Once the shared symmetric key is created, both sides switch to fast symmetric encryption.
6. **Data Transfer:** All incoming and outgoing HTTP data (headers, HTML, cookies, form posts) is encrypted into binary TLS frames on port `443` before traveling over the network.

---

## 1. TLS 1.2 Handshake (2-RTT)
The classic handshake requires two full round trips before actual application data can be securely transmitted. Encryption only begins at the very end of the second round trip.

[ Client ]                                                   [ Server ]

    |                                                             |
    | ===================== ROUND TRIP 1 ======================= |
    |                                                             |
    | ------------ 1. ClientHello ------------------------------> |
    |                 (Supported Ciphers, Client Random)          |
    |                                                             |
    | <----------- 2. ServerHello ------------------------------- |
    |                 (Selected Cipher, Server Random)            |
    | <-----------    Certificate ------------------------------- |
    |                 (Server Public Key)                         |
    | <-----------    ServerKeyExchange (If DH) ----------------- |
    |                 (Server DH Parameters & Signature)          |
    | <-----------    ServerHelloDone --------------------------- |
    |                                                             |
    | ===================== ROUND TRIP 2 ======================= |
    |                                                             |
    | ------------ 3. ClientKeyExchange ------------------------> |
    |                 (Encrypted Secret OR Client DH Params)      |
    | ------------    ChangeCipherSpec -------------------------> |
    |                 (Switching to symmetric encryption)         |
    | ------------    Finished ---------------------------------> |
    |                 (Encrypted verification message)            |
    |                                                             |
    | <----------- 4. ChangeCipherSpec ------------------------- |
    | <-----------    Finished ---------------------------------- |
    |                                                             |
    | =================== SECURE CHANNEL ======================== |
    |                                                             |
    | <========== 5. Encrypted Application Data ================> |

------------------------------
## 2. TLS 1.3 Handshake (1-RTT)
The modern handshake guesses the server's cryptographic preference and combines the hello and key exchange steps. This cuts latency down to one single round trip and encrypts the server's certificate.

[ Client ]                                                   [ Server ]

    |                                                             |
    | ===================== ROUND TRIP 1 ======================= |
    |                                                             |
    | ------------ 1. ClientHello + Key Share ------------------> |
    |                 (Client Random, DH Parameters Guess)        |
    |                                                             |
    |                                    [Server Computes Key]    |
    |                                                             |
    |  |
    |                 (Encrypted verification message)            |
    |                                                             |
    | =================== SECURE CHANNEL ======================== |
    |                                                             |
    | <========== 4. Encrypted Application Data ================> |

------------------------------
## Note-Taking Summary

* TLS 1.2: 2 Round Trips. The certificate is sent in cleartext (unencrypted).
* TLS 1.3: 1 Round Trip. The certificate is fully encrypted to protect privacy.

If you are expanding your network notes, let me know if you would like to include a breakdown of TLS Session Resumption (0-RTT) for returning visitors or the structure of a Cipher Suite string.

