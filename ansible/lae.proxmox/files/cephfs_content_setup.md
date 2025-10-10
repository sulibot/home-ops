## ✅ Refined Goals: CephFS `content` Setup with Clean Pathing

### Target Design:

1. A **CephFS filesystem named** `content`.
2. Metadata stored on a **replicated NVMe pool** (`content_meta`).
3. The **root path (**``**)** backed by **replicated HDD** (`content_default`).
4. All content subvolumes stored in an **erasure-coded pool** (`content_ec`).
5. Subvolumes:
   - `media` → `/volumes/content/media`
   - `images` → `/volumes/content/images`
   - `backups` → `/volumes/content/backups`
6. CRUSH rule ensures EC chunk separation by physical drive.
7. Autoscaling enabled for all pools.

---

### 🔧 Pool & CRUSH Rule Setup

```bash
# Metadata pool (replicated NVMe)
ceph osd pool create content_meta 8 8 replicated_nvme --autoscale-mode on

# Root pool (replicated HDD)
ceph osd pool create content_default 8 8 replicated_hdd --autoscale-mode on

# Erasure code profile
ceph osd erasure-code-profile set ec-4-2-by-drive \
  k=4 m=2 plugin=jerasure technique=reed_sol_van \
  crush-failure-domain=drive crush-device-class=hdd

# EC pool
ceph osd pool create content_ec 16 16 erasure ec-4-2-by-drive --autoscale-mode on
```

#### Custom CRUSH Rule

```bash
ceph osd getcrushmap -o crushmap.bin
crushtool -d crushmap.bin -o crushmap.txt

# Add to crushmap.txt:
rule ec_4_2_by_drive_host {
    id 4
    type erasure
    step set_chooseleaf_tries 5
    step set_choose_tries 100
    step take default class hdd
    step chooseleaf indep 0 type drive
    step emit
}

crushtool -c crushmap.txt -o new_crushmap.bin
ceph osd setcrushmap -i new_crushmap.bin

ceph osd pool set content_ec crush_rule ec_4_2_by_drive_host
```

---

### 📁 Create Filesystem

```bash
ceph fs new content content_meta content_default
```

Enable EC pool usage:

```bash
ceph osd pool set content_ec allow_ec_overwrites true
ceph osd pool set content_ec bulk true
ceph fs add_data_pool content content_ec
```

---

### 📂 Setup Subvolume Group & Volumes

```bash
# Create subvolume group
ceph fs subvolumegroup create content content

# Create EC-backed subvolumes
ceph fs subvolume create content media   --group_name content --pool_layout content_ec
ceph fs subvolume create content images  --group_name content --pool_layout content_ec
ceph fs subvolume create content backups --group_name content --pool_layout content_ec
```

Verify:

```bash
ceph fs subvolume ls content --group_name content
```

Expected:

```json
[
  {"name": "backups"},
  {"name": "images"},
  {"name": "media"}
]
```

---

### ✅ Confirm Root Path Pool

```bash
# Confirm root (`/`) uses content_default (already true if created correctly)
ceph fs dump | grep -A3 "Filesystem 'content'"
```

---

### 📍 Get Subvolume Mount Paths

```bash
ceph fs subvolume getpath content media   --group_name content
ceph fs subvolume getpath content images  --group_name content
ceph fs subvolume getpath content backups --group_name content
```

Sample Output:

```
/volumes/content/media/...
/volumes/content/images/...
/volumes/content/backups/...
```

---

### 🧪 Optional Usage: Static Volumes

```yaml
volumeAttributes:
  fsName: content
  staticVolume: "true"
  rootPath: /volumes/content/media
```

---

### ✅ Summary Table

| Purpose        | Pool Name                    | Type            | Notes                            |
| -------------- | ---------------------------- | --------------- | -------------------------------- |
| Metadata       | `content_meta`               | Replicated      | NVMe for MDS metadata            |
| Root (`/`)     | `content_default`            | Replicated      | HDD-backed default path          |
| Subvolume data | `content_ec`                 | Erasure-coded   | EC pool for large files          |
| Subvolumes     | `media`, `images`, `backups` | On `content_ec` | Isolated subvolume group storage |

