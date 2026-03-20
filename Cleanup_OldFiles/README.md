# cleanup_bismark.sh

Post-alignment cleanup script for WGBS (Whole Genome Bisulfite Sequencing) data processed with  [CpG_Me](https://github.com/ben-laufer/CpG_Me). The script removes intermediate QC and alignment files to free up storage, consolidates final cytosine report outputs into a single shared folder, and removes empty sample directories left behind after the move.

All actions are logged to a timestamped CSV file stored under `clean_up_wgbs_intermediates/`.

---

## Script Location

| Location | Path |
|----------|------|
| HPC (local) | `/quobyte/lasallegrp/projects/hpc_management/Cleanup_OldFiles/cleanup_bismark.sh` |
| GitHub | https://github.com/lasallelab/hpc_management/blob/main/Cleanup_OldFiles/cleanup_bismark.sh |

---

## Expected Input Directory Structure

The script is designed to be run from a **cohort-level directory** (e.g. `deSmith`, `deLange`) that contains one subdirectory per sample. Each sample subdirectory should contain Bismark output files from a standard paired-end WGBS pipeline, for example:

```
deSmith/
├── 198001/
│   ├── 198001_1.fq.gz_trimming_report.txt
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bam
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bedGraph.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.CpG_report.merged_CpG_evidence.cov.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.CpG_report.txt.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.cytosine_context_summary.txt
│   ├── 198001_1_val_1_fastqc.html
│   ├── 198001_1_val_1_fastqc.zip
│   ├── ...
├── 198007/
│   ├── ...
```

> ⚠️ The script only looks **one level deep** inside each sample subdirectory (`-maxdepth 1`). Files nested further will not be touched.

---

## What the Script Does

### Phase 1 — Delete intermediate files

The following file types are removed from each sample subdirectory:

| Category | File pattern(s) |
|----------|----------------|
| Trimming reports | `*_trimming_report.txt` |
| FastQC | `*_fastqc.html`, `*_fastqc.zip` |
| FastQ Screen | `*_screen.html`, `*_screen.txt` |
| M-bias | `*.M-bias.txt` |
| Nucleotide stats | `*.nucleotide_stats.txt` |
| Insert size | `*.insert.txt`, `*.histogram.pdf` |
| Alignment reports | `*_PE_report.html`, `*_PE_report.txt` |
| Deduplication reports | `*.deduplication_report.txt`, `*_splitting_report.txt` |
| CpG context split files | `CpG_context_*.txt.gz` |
| Deduplicated BAM | `*.deduplicated.bam` |
| Deduplicated bedGraph | `*.deduplicated.bedGraph.gz` |

### Phase 2 — Move cytosine report files

The following final output files are moved from each sample subdirectory into a **single shared folder** at the cohort level (`deSmith/08_cytosine_reports/`):

| File pattern | Description |
|--------------|-------------|
| `*.bismark.cov.gz` | Bismark coverage file |
| `*.CpG_report.merged_CpG_evidence.cov.gz` | Merged CpG evidence coverage |
| `*.CpG_report.txt.gz` | Full CpG report |
| `*.cytosine_context_summary.txt` | Cytosine context summary |

### Phase 3 — Remove empty sample directories

After moving files out, the script checks whether each sample subdirectory is now empty. If it is, the directory is automatically deleted with `rmdir`.

---

## Expected Output Structure

After a full run (`--delete --move`), the cohort directory will look like:

```
deSmith/
├── 08_cytosine_reports/                    ← all cytosine reports consolidated here
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.CpG_report.merged_CpG_evidence.cov.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.CpG_report.txt.gz
│   ├── 198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz.cytosine_context_summary.txt
│   ├── 198007_...
│   └── ...
├── clean_up_wgbs_intermediates/            ← log files written here
│   └── cleanup_bismark_log_deSmith_20260320_143022.csv
│   (sample subdirectories deleted if empty after move)
```

---

## Usage

### Step 1 — Copy the script to your cohort directory

```bash
cp /quobyte/lasallegrp/projects/hpc_management/Cleanup_OldFiles/cleanup_bismark.sh \
   /path/to/your/cohort/
```

Or clone from GitHub and copy as needed.

### Step 2 — Change into the cohort directory

> ⚠️ **This is critical.** The script uses `pwd` to determine the base directory. You must `cd` into the cohort folder before running it — do not run it from a parent directory or it will process the wrong level.

```bash
cd /quobyte/lasallegrp/Ben/DownSyndrome/deSmith
```

### Step 3 — Dry run first (always recommended)

Preview everything that would be deleted or moved — no files are changed:

```bash
bash cleanup_bismark.sh --dryrun
```

Example output:
```
============================================================
  Bismark Cleanup Script
  Base dir : /quobyte/lasallegrp/Ben/DownSyndrome/deSmith
  Dry run  : true
  Delete   : false
  Move     : false
  Move dst : /quobyte/lasallegrp/Ben/DownSyndrome/deSmith/08_cytosine_reports/
  Log dir  : /quobyte/lasallegrp/Ben/DownSyndrome/deSmith/clean_up_wgbs_intermediates/
  Log CSV  : cleanup_bismark_log_deSmith_20260320_143022.csv
============================================================

--- Sample: 198001 ---
  [DRY-RUN DELETE] 198001_1.fq.gz_trimming_report.txt  (12K)
  [DRY-RUN DELETE] 198001_1_val_1_fastqc.html  (340K)
  [DRY-RUN MOVE]   198001_1_val_1_bismark_bt2_pe.deduplicated.bismark.cov.gz  →  08_cytosine_reports/
  [DRY-RUN RMDIR]  198001/  (would be empty after move)
```

### Step 4 — Delete intermediate files

```bash
bash cleanup_bismark.sh --delete
```

### Step 5 — Move cytosine reports to shared folder

```bash
bash cleanup_bismark.sh --move
```

### Or run both steps at once

```bash
bash cleanup_bismark.sh --delete --move
```

---

## Flags Summary

| Flag | Action |
|------|--------|
| `--dryrun` | Preview all actions — no files are changed |
| `--delete` | Delete intermediate files only |
| `--move` | Move cytosine report files and clean up empty dirs only |
| `--delete --move` | Full cleanup: delete intermediates, move reports, remove empty dirs |

> Flags can be combined freely. At least one flag is required — running the script with no flags will exit with an error.

---

## Log File

Every run writes a CSV log to `clean_up_wgbs_intermediates/` inside the cohort directory. The filename includes the cohort name and a timestamp so logs from different cohorts or runs never overwrite each other:

```
cleanup_bismark_log_deSmith_20260320_143022.csv
```

The CSV has the following columns:

| Column | Description |
|--------|-------------|
| `action` | `DELETE`, `MOVE`, or `RMDIR` |
| `sample` | Sample subdirectory name |
| `filename` | File name (blank for `RMDIR` entries) |
| `source_path` | Full path to the file or directory |
| `status` | `dry-run`, `deleted`, `moved → ...`, `kept — not empty (N files)`, or `deleted` (for dirs) |

---

## Notes and Cautions

- **Always run `--dryrun` first** and inspect the log CSV before proceeding with `--delete` or `--move`.
- The script will **not touch** `08_cytosine_reports/` or `clean_up_wgbs_intermediates/` even if they already exist when iterating over sample directories.
- If `08_cytosine_reports/` already exists when running `--move`, files are added to it (not overwritten). A note is printed to the terminal.
- The script uses `rmdir` (not `rm -rf`) to remove sample directories — this means it will **only delete truly empty directories** and will never silently remove remaining files.
- Files not matching any pattern are **never touched**, regardless of mode.
