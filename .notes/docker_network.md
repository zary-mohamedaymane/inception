When you execute a command like `docker run -v my_vol:/var/lib/mysql -d mariadb`, Docker initiates a modular multi-tier execution chain. Modern Docker splits container management across four distinct layers:

```
[ Docker CLI ] 
      │ (REST API / Unix Socket)
      ▼
  [ dockerd ] (High-level daemon: API, images, volumes, network)
      │ (gRPC)
      ▼
 [ containerd ] (Container lifecycle & image management)
      │ (gRPC / TTRPC)
      ▼
[ containerd-shim ] (One per container: decouples container from daemon)
      │ (CLI execution)
      ▼
    [ runc ] (OCI Runtime: creates cgroups, namespaces, executes pivot_root)
      │
      ▼
[ Container Process ] (PID 1 inside its own isolated namespaces)

```

---

### **1. Component Breakdown & Execution Flow**

#### **Step 1: Docker CLI to `dockerd` (Request Processing & Mount Preparation)**

1. The **Docker CLI** translates your command into an HTTP REST API call (`POST /containers/create` and `POST /containers/(id)/start`) and sends it over `/var/run/docker.sock` to `dockerd`.
2. **`dockerd` (Docker Daemon)** performs high-level orchestration:
* **Image Verification:** Confirms the requested image manifests and rootfs layers exist locally.
* **Networking:** Allocates an IP address on the designated bridge network and sets up `iptables` port-forwarding rules if needed.
* **Volume Resolution:** Resolves the named volume (`my_vol`). It looks up the volume entry in its internal database to extract the absolute host path (`/var/lib/docker/volumes/my_vol/_data`).


3. `dockerd` constructs an **OCI (Open Container Initiative) Specification** (a standardized `config.json` file) detailing all namespaces, cgroup limits, environment variables, mounts, and execution binaries.
4. `dockerd` passes this specification to **`containerd`** over a gRPC connection.

---

#### **Step 2: `containerd` (Lifecycle Supervision & Storage Overlay)**

1. **`containerd`** acts as the high-level container runtime. It manages image layers, storage snapshots, and container execution.
2. **Root File System Assembly:**
* It asks the storage driver (typically `overlay2`) to prepare a writable container layer.
* `overlay2` mounts the read-only image layers (`lowerdir`) combined with the container's writable layer (`upperdir` and `workdir`) into an combined root file system (`merged` dir).


3. `containerd` takes the merged rootfs path, injects the volume mount specifications into the OCI `config.json`, and prepares to spawn the runtime process.

---

#### **Step 3: `containerd-shim` (Daemon Decoupling & Process Holding)**

1. `containerd` does **not** launch the container process directly. Instead, it spawns a small, dedicated daemon called **`containerd-shim`** for that specific container.
2. **Why the Shim exists:**
* **Daemon Reboots:** If `dockerd` or `containerd` crashes or restarts during runtime, the shim stays alive so the container process doesn't die.
* **File Descriptors:** Holds open `stdin`, `stdout`, and `stderr` pipes for the container, streaming logs back to `containerd`.
* **Exit Code Collection:** Captures the exit code of the container process when it terminates and reports it back to `containerd`.


3. The `containerd-shim` process invokes **`runc`** via a command-line call, passing the target root directory containing `config.json`.

---

#### **Step 4: `runc` (Low-Level OCI Runtime Container Creation)**

`runc` is a lightweight, short-lived CLI tool that communicates directly with the Linux kernel to assemble the container isolation boundaries:

1. **Linux Namespaces Allocation:** `runc` issues system calls (`clone()` or `unshare()`) to create isolated kernel namespaces:
* **`PID`**: Isolates process IDs (the entrypoint process becomes PID 1 inside the container).
* **`NET`**: Creates an isolated network stack (virtual loopback, veth interfaces).
* **`MNT`**: Isolates filesystem mount points.
* **`IPC`**: Isolates System V IPC and POSIX message queues.
* **`UTS`**: Isolates hostname and domain name.
* **`USER`**: Maps user/group IDs (optional user namespace mapping).


2. **Cgroups Configuration:** `runc` writes rules directly to `/sys/fs/cgroup/` (cgroups v1 or v2) to enforce CPU, memory, memory swap, and I/O limits specified in `config.json`.
3. **Filesystem Pivot (`pivot_root`):**
* `runc` mounts the container's `overlay2` `merged` directory.
* It issues the **`pivot_root()`** system call, swapping the host's root filesystem with the container's root filesystem directory.
* It unmounts access to the host's root filesystem, trapping the container within its isolated filesystem.


4. **Process Execution:** `runc` drops Linux capabilities, applies Seccomp security profiles, and calls `execve()` to execute the container entrypoint process (e.g., `mysqld`).
5. Once the container process is running, **`runc` exits immediately**. The process remains attached directly to `containerd-shim` as its parent process.

---

### **2. Deep Dive: How an Existing Volume is Mounted**

When mounting a named volume (e.g., `my_vol` mapped to `/var/lib/mysql`), the process occurs during **Step 4** inside `runc` right before `pivot_root()` is executed.

```
Host Path:     /var/lib/docker/volumes/my_vol/_data
                            │
                            │ (Linux MS_BIND mount inside MNT namespace)
                            ▼
Container Path: /var/lib/mysql  (Overlays target directory inside container rootfs)

```

#### **Technical Execution Steps:**

1. **Path Resolution by `dockerd`:**
* `dockerd` looks up `my_vol` in its local volume registry database (`/var/lib/docker/volumes/metadata.db`).
* It converts the logical name `my_vol` to its absolute host mount point:
`/var/lib/docker/volumes/my_vol/_data`


2. **Injection into OCI `config.json`:**
* `dockerd` inserts a mount entry into the `mounts` array of the container’s OCI specification:
```json
{
  "destination": "/var/lib/mysql",
  "type": "bind",
  "source": "/var/lib/docker/volumes/my_vol/_data",
  "options": ["rbind", "rw"]
}

```




3. **Kernel Mount Call inside the New Mount Namespace:**
* When `runc` creates the container's isolated **Mount Namespace (`MNT`)**, it performs the mount sequence using Linux kernel system calls **before calling `pivot_root()**`:
* It creates the destination directory `/var/lib/mysql` inside the merged container rootfs if it doesn't already exist.
* It calls the Linux kernel system call `mount()`:
```c
mount(
  "/var/lib/docker/volumes/my_vol/_data", /* source on host */
  "/merged_rootfs/var/lib/mysql",          /* target path */
  NULL, 
  MS_BIND | MS_REC,                        /* recursive bind mount */
  NULL
);

```




4. **How the Volume Bypasses the Storage Driver:**
* Because the kernel `mount()` operation maps the host directory `/var/lib/docker/volumes/my_vol/_data` directly into the container process's mount tree, any read or write operation inside `/var/lib/mysql` bypasses the `overlay2` copy-on-write driver entirely.
* Writes are executed at native Linux ext4/xfs speed directly onto the host disk block layer, ensuring persistent storage even if the container filesystem layer is destroyed.



---

### **Summary of Component Roles**

| Component | Lifespan | Primary Responsibility |
| --- | --- | --- |
| **`dockerd`** | Persistent Daemon | Manages API requests, networks, volumes, image pulls, and creates OCI configs. |
| **`containerd`** | Persistent Daemon | Manages container lifecycle states, delegates snapshots, and spawns shims. |
| **`containerd-shim`** | Runs for the lifespan of 1 container | Holds STDIO pipes open, captures exit status, and keeps container alive if daemon restarts. |
| **`runc`** | Ephemeral (runs for milliseconds) | Interfaces with Linux kernel to construct cgroups, namespaces, mounts, and calls `execve()`. |

To understand how a Docker network is created—and precisely which component handles each step—we must trace the execution path across **`dockerd`**, **`containerd`**, and **`runc`**.

While **`runc`** creates the isolated process namespace for a container, it is **`dockerd`** that acts as the network architect. `runc` and `containerd` know almost nothing about higher-level Docker networks, IP pools, or `iptables` rules.

---

### **1. Component Responsibility Matrix for Networking**

| Component | Responsibility in Networking | Key Actions |
| --- | --- | --- |
| **`dockerd`** | **Network Management & IPAM** | • Manages network state, subnets, and IP allocation.<br>

<br>• Creates the Linux software bridge (`br-xxx`).<br>

<br>• Writes `iptables` / `nftables` NAT and filter rules.<br>

<br>• Runs the embedded DNS server (`127.0.0.11`).<br>

<br>• Creates `veth` pairs and binds one end to the bridge. |
| **`containerd`** | **Namespace Plumbing & CNM/CNI Integration** | • Passes network namespace file descriptors from `dockerd` down to the container runtime.<br>

<br>• Manages container state events (start/stop) to trigger interface cleanup. |
| **`runc`** | **Namespace Isolation** | • Calls `unshare(CLONE_NEWNET)` or `setns()` to create/join the Linux network namespace (`NET`).<br>

<br>• Has **zero awareness** of bridges, `veth` pairs, IP addresses, or `iptables`. |

---

### **2. Deep Dive: Phase 1 — Creating a User-Defined Network**

When you execute:

```bash
docker network create --driver bridge --subnet 172.20.0.0/16 my_custom_net

```

`containerd` and `runc` are **not involved at all**. This phase is handled entirely by `dockerd` via its internal **Libnetwork** subsystem (Container Network Model - CNM):

```
[ User CLI ] ──(POST /networks/create)──> [ dockerd (Libnetwork) ]
                                                   │
                                     ┌─────────────┴─────────────┐
                                     ▼                           ▼
                        [ Linux Kernel Netlink ]       [ iptables / Netfilter ]
                         • Create bridge interface      • Add MASQUERADE (SNAT)
                         • Assign Gateway IP (172.20.0.1) • Add isolation rules

```

#### **Step-by-step Kernel Actions by `dockerd`:**

1. **IPAM (IP Address Management) Allocation:**
`dockerd` allocates the requested subnet (`172.20.0.0/16`) and reserves `172.20.0.1` as the gateway address for the host.
2. **Creating the Virtual Bridge Interface:**
`dockerd` issues Netlink system calls to the Linux kernel to instantiate a new software bridge interface:
```bash
# Equivalent kernel operations executed by dockerd:
ip link add dev br-a1b2c3d4e5f6 type bridge
ip addr add 172.20.0.1/16 dev br-a1b2c3d4e5f6
ip link set dev br-a1b2c3d4e5f6 up

```


3. **Writing Outbound NAT (`iptables`) Rules:**
To allow future containers on this bridge to reach external networks, `dockerd` writes `iptables` rules into the host's `nat` table:
```bash
iptables -t nat -A POSTROUTING -s 172.20.0.0/16 ! -o br-a1b2c3d4e5f6 -j MASQUERADE

```


4. **Writing Inter-Network Isolation Rules:**
To prevent containers on `my_custom_net` from cross-communicating with containers on `docker0` or other bridges, `dockerd` inserts rules into the `FORWARD` chain:
```bash
iptables -A FORWARD -i br-a1b2c3d4e5f6 ! -o br-a1b2c3d4e5f6 -j DROP

```


5. **Registering Embedded DNS Metadata:**
`dockerd` stores `my_custom_net` in its internal DNS map so its daemon-level DNS resolver (`127.0.0.11`) can dynamically map container names to IP addresses on this network.

---

### **3. Deep Dive: Phase 2 — Attaching a Container to the Network**

When you launch a container on this network:

```bash
docker run -d --name web --net my_custom_net -p 8080:80 nginx

```

This is where all three components (`dockerd`, `containerd`, and `runc`) coordinate to construct and attach the container's network stack.

```
[ dockerd ] ─────────────────────────────────────────────────────────────┐
   │ 1. Reserve IP (172.20.0.2)                                          │
   │ 2. Create veth pair (veth_host <-> veth_cont)                        │
   │ 3. Attach veth_host to br-a1b2c3d4e5f6                              │
   │ 4. Configure port mapping (DNAT: 8080 -> 172.20.0.2:80)             │
   │                                                                     │ 7. Move veth_cont into
   ▼ (gRPC create call with NetNS path)                                  │    container NetNS, rename
[ containerd ]                                                           │    to eth0, assign IP &
   │                                                                     │    default gateway
   ▼ (Executes runc)                                                     │
[ runc ] ──(unshare CLONE_NEWNET)──> Creates NetNS (/proc/PID/ns/net) ───┘

```

#### **Step 1: Network Pre-Allocation (`dockerd`)**

* `dockerd` queries its IPAM driver and assigns an available IP address (e.g., `172.20.0.2`) from the `172.20.0.0/16` pool.
* It generates a new **Virtual Ethernet (`veth`) pair** using Netlink:
* Host side: `veth_host` (e.g., `veth3a4b5c`)
* Container side: `veth_cont`


* It attaches `veth_host` to the bridge interface `br-a1b2c3d4e5f6` and brings `veth_host` UP.

#### **Step 2: Namespace Creation (`runc`)**

* `dockerd` sends the container execution spec to `containerd`, which invokes `runc`.
* `runc` executes the `unshare(CLONE_NEWNET)` system call to create a fresh, empty **Network Namespace (`NET`)**.
* At this moment, the new namespace only has an unconfigured loopback interface (`lo`). It has no `eth0`, no IP address, and no default route.
* `runc` exposes this namespace path in the host filesystem (e.g., `/proc/<PID>/ns/net` or `/var/run/netns/<container_id>`).

#### **Step 3: Network Plumbing (`dockerd`)**

* While the container process is being initialized by `runc`, `dockerd` receives confirmation of the container's namespace PID.
* `dockerd` performs the network plumbing across the host-to-container boundary:
1. **Move Interface:** It moves `veth_cont` into the container's network namespace (`/proc/<PID>/ns/net`).
2. **Rename Interface:** Inside the container namespace, it renames `veth_cont` to **`eth0`**.
3. **Configure IP Address:** It assigns `172.20.0.2/16` to `eth0`.
4. **Configure Default Route:** It sets the default gateway inside the container namespace to point to the bridge interface (`172.20.0.1`).
5. **Bring Interfaces UP:** It turns on `eth0` and the local loopback interface (`lo`).



#### **Step 4: Inbound Port Forwarding (`dockerd`)**

Because `-p 8080:80` was specified, `dockerd` inserts a Destination NAT (DNAT) rule into the host's `iptables` `DOCKER` chain:

```bash
iptables -t nat -A DOCKER -p tcp --dport 8080 -j DNAT --to-destination 172.20.0.2:80

```

*(Note: If `userland-proxy=true` is enabled in Nginx/Docker settings, `dockerd` also spawns a small binary called `docker-proxy` to forward TCP/UDP traffic on the host port to the container IP as a fallback).*

#### **Step 5: DNS Injection (`dockerd`)**

`dockerd` writes a customized `/etc/resolv.conf` into the container's filesystem mount:

```
nameserver 127.0.0.11
options ndots:0

```

Any DNS query originating inside the container is directed to `127.0.0.11`. `dockerd` captures this traffic inside the host network thread, checks its container name map for `my_custom_net`, and either responds with the internal IP or forwards the request to the host's upstream DNS server.

---

### **4. Summary: End-to-End Packet Lifecycle**

To see how all these parts fit together during actual network traffic:

```
[ External Client ] 
        │
        │ 1. Request to http://<HOST_IP>:8080
        ▼
[ Host physical interface (eth0) ]
        │
        │ 2. Kernel matches iptables DNAT rule written by dockerd:
        │    Rewrites destination: <HOST_IP>:8080 -> 172.20.0.2:80
        ▼
[ Software Bridge (br-a1b2c3d4e5f6) ]
        │
        │ 3. Bridge inspects destination IP (172.20.0.2)
        │    Forwards L2 frames down the associated veth_host interface
        ▼
[ veth_host (Host NS) ] ===== (Virtual Patch Cable) ===== [ eth0 (Container NS) ]
                                                                   │
                                                                   │ 4. Received by Nginx
                                                                   ▼
                                                         [ Container Process ]

```

### **Key Takeaway**

* **`dockerd`** is the master network engineer (allocating IPs, creating Linux bridges, writing `iptables` NAT rules, running DNS, and wiring `veth` interfaces).
* **`containerd`** acts as the broker (relaying network namespace file descriptors).
* **`runc`** is the isolation enforcer (executing the Linux `unshare` call to create the network namespace boundary).
