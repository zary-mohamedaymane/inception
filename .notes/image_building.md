Here is the detailed, step-by-step technical breakdown of what happens when you run `docker build` (or `docker compose build`), covering the exact processes, execution flow, storage format, and layer assembly under the hood.

---

### **1. Who Does What? (The Processes Involved)**

```
+-------------------+       HTTP / REST        +------------------+
|   docker CLI      |  --------------------->  |     dockerd      |
| (Client Process)  |  /var/run/docker.sock    |  (Daemon Engine) |
+-------------------+                          +------------------+
                                                        |
                                                        | gRPC calls
                                                        v
                                               +------------------+
                                               |    containerd    |
                                               | (Core Runtime)   |
                                               +------------------+
                                                        |
                                                        | High-level execution
                                                        v
                                               +------------------+
                                               |       runc       |
                                               | (OCI Runtime)    |
                                               +------------------+

```

* **`docker` CLI (Client Process):** Reads your `Dockerfile`, creates a tarball of your **build context** (the files in `./srcs/requirements/wordpress` for example), and sends an HTTP POST request containing that tar stream over the Unix socket (`/var/run/docker.sock`) to the daemon.
* **`dockerd` (Docker Daemon / Engine):** The coordinator. It receives the build request, parses the `Dockerfile` instructions into an execution tree, manages layer caching logic, and delegates low-level execution and snapshotting to `containerd` (or its modern build engine, **BuildKit**).
* **`containerd` (Container Runtime Daemon):** Manages image content, snapshots, and layer storage. During a build, whenever a `RUN` command needs execution, `containerd` asks `runc` to launch a temporary container.
* **`runc` (OCI Low-Level Runtime):** The ephemeral process executor. It talks directly to Linux kernel primitives (`namespaces`, `cgroups`, `chroot`/`pivot_root`) to run temporary commands (e.g., `apt-get install -y php8.2-fpm`) inside an isolated environment.

---

### **2. How the Image is Built Step-by-Step**

#### **Step A: Parsing & Context Transfer**

1. When you run `docker compose build wordpress`, the CLI packages the contents of `./srcs/requirements/wordpress` into a `.tar` payload (the **Build Context**).
2. The CLI sends the tarball and `Dockerfile` to `dockerd`.
3. `dockerd` parses the `Dockerfile` top-to-bottom into an Abstract Syntax Tree (AST).

#### **Step B: Processing Instructions & Layer Execution**

##### **1. `FROM debian:bookworm-slim` (Base Layer Retrieval)**

* `dockerd` asks `containerd` if `debian:bookworm-slim` exists locally in its content store.
* If missing, `containerd` fetches the **OCI Image Manifest** from Docker Hub.
* The manifest contains a list of layer digests (SHA256 hashes). `containerd` downloads these compressed layer tarballs and uncompresses them into `/var/lib/docker/overlay2/` (or `/var/lib/containerd/` under modern engines).

##### **2. `RUN apt-get update && apt-get install -y ...` (Diff Layer Generation)**

1. **Cache Lookup:** Before running the step, `dockerd` calculates a hash of the current parent layer digest plus the exact instruction string (`RUN apt-get update...`). If an existing layer matches this hash, it reuses the cache.
2. **Ephemeral Container Creation:** If no cache matches:
* `containerd` uses the **OverlayFS** driver to create a temporary read-write filesystem snapshot stacked on top of the `debian:bookworm-slim` base layer.
* `dockerd` requests `runc` to execute `apt-get update && apt-get install -y ...` inside a temporary container using this snapshot.


3. **Diff Extraction (Snapshotting):**
* While `apt-get` runs, files are created/modified in the temporary container's writeable layer (`/etc/php/`, `/usr/bin/php`, etc.).
* Once the command succeeds with exit code `0`, `dockerd` stops the temporary container.
* `containerd` inspects the filesystem changes (the **diff**) compared to the parent layer, packages these modified/added files into an uncompressed tarball, and computes its SHA256 cryptographic digest.
* The temporary container is destroyed, and this new diff tarball becomes an **immutable, read-only layer**.



##### **3. `COPY tools/wp-entrypoint.sh /usr/local/bin/**`

* `dockerd` takes the file from the transferred build context, computes its SHA256 checksum, and writes it directly into a new filesystem layer snapshot without needing to invoke `runc`.

---

### **3. How and Where Is the Image Stored?**

Images are **not** single monolithic files; they are a collection of decoupled layers connected by a JSON manifest.

#### **Directory Location on Host Disk**

On Linux hosts, Docker stores all layer content in:

```bash
/var/lib/docker/overlay2/

```

Inside this directory, each layer gets its own folder named after an internal ID:

```
/var/lib/docker/overlay2/
├── <layer_1_hash>/
│   ├── diff/        <-- The actual modified/added files (e.g. /usr/bin/php)
│   ├── link        <-- A shortened ID alias for lowerdir references
│   └── committed   <-- Marks layer as read-only
├── <layer_2_hash>/
│   ├── diff/
│   └── lower       <-- Text file pointing to layer_1_hash (parent dependency)

```

#### **Image Manifest & Configuration JSON**

When all steps finish, `containerd` registers the final image in `/var/lib/docker/image/overlay2/imagedb/content/sha256/<image_id>` with two critical files:

1. **Manifest (Image Tag Mapping):** Maps human-readable names like `wordpress:latest` or `mariadb:latest` to a specific **Image ID** (a SHA256 digest).
2. **Configuration JSON:** Contains:
* **`DiffIDs`:** An ordered array of layer SHA256 hashes from bottom (base OS) to top.
* **`Config`:** Default execution instructions (`ENTRYPOINT`, `CMD`, `ENV` variables, exposed ports).



---

### **Summary Sequence Diagram**

```
CLI                      dockerd                 containerd               runc / Kernel
 |                          |                        |                          |
 |-- 1. Send Tar Context ->|                        |                          |
 |                          |-- 2. Pull Base Image ->|                          |
 |                          |                        |-- Download & Store ----->| /var/lib/docker/overlay2
 |                          |                        |                          |
 |                          |-- 3. Run Instruction ->|                          |
 |                          |                        |-- 4. Spawn Temp Cont. -->| Create Namespaces
 |                          |                        |                          | Exec "apt-get install"
 |                          |                        |<-- 5. Command Done ------| Exit 0
 |                          |                        |                          |
 |                          |-- 6. Capture Diff ---->| Snapshot Layer Tarball   |
 |                          |                        | Write SHA256 Digest     |
 |                          |                        |                          |
 |<-- 7. Build Finished ----| Register Manifest      |                          |

```

---
