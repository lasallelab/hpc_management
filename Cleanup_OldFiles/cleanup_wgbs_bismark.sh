#!/usr/bin/env bash
# =============================================================================
# cleanup_bismark.sh
#
# USAGE (run from the deSmith directory or directory of interest):
#   bash cleanup_bismark.sh --dryrun          # Preview only, no changes
#   bash cleanup_bismark.sh --delete          # Delete intermediates only
#   bash cleanup_bismark.sh --move            # Move cytosine reports only
#   bash cleanup_bismark.sh --delete --move   # Full cleanup (recommended order)
#
# A CSV log is always written: cleanup_bismark_log.csv
#
# FILES DELETED (intermediates):
#   *_trimming_report.txt | *_fastqc.html/zip | *_screen.html/txt
#   *.M-bias.txt | *.nucleotide_stats.txt | *.insert.txt | *.histogram.pdf
#   *_PE_report.html/txt | *.deduplication_report.txt | *_splitting_report.txt
#   CpG_context_*.txt.gz | *.deduplicated.bam | *.deduplicated.bedGraph.gz
#
# FILES MOVED to deSmith/08_cytosine_reports/:
#   *.bismark.cov.gz | *.CpG_report.merged_CpG_evidence.cov.gz
#   *.CpG_report.txt.gz | *.cytosine_context_summary.txt
# =============================================================================

set -uo pipefail

DRYRUN=false
DO_DELETE=false
DO_MOVE=false

DEST_DIR="08_cytosine_reports"
BASE_DIR="$(pwd)"
DIR_NAME="$(basename "$BASE_DIR")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$BASE_DIR/clean_up_wgbs_intermediates"
LOG_CSV="$LOG_DIR/cleanup_bismark_log_${DIR_NAME}_${TIMESTAMP}.csv"

# ---------- parse args -------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --dryrun) DRYRUN=true ;;
    --delete) DO_DELETE=true ;;
    --move)   DO_MOVE=true ;;
    *) echo "ERROR: Unknown argument: $arg"; exit 1 ;;
  esac
done

if ! $DRYRUN && ! $DO_DELETE && ! $DO_MOVE; then
  echo "ERROR: Specify at least one of --dryrun, --delete, --move"
  exit 1
fi

# ---------- patterns ---------------------------------------------------------
INTERMEDIATE_PATTERNS=(
  "*_trimming_report.txt"
  "*trimmed*"
  "*_fastqc.html"
  "*_fastqc.zip"
  "*_screen.html"
  "*_screen.txt"
  "*.M-bias.txt"
  "*.nucleotide_stats.txt"
  "*.insert.txt"
  "*.histogram.pdf"
  "CpG_context_*.txt.gz"
  "Non_CpG_context_*.txt.gz"
  "*_PE_report.html"
  "*_PE_report.txt"
  "*.deduplication_report.txt"
  "*_splitting_report.txt"
  "*.deduplicated.bam"
  "*.deduplicated.sorted.bam*"
  "*.deduplicated.bedGraph.gz"
  "*_bismark_bt2_pe.bam"
  "*.bam*"
)

MOVE_PATTERNS=(
  "*.bismark.cov.gz"
  "*.CpG_report.merged_CpG_evidence.cov.gz"
  "*.CpG_report.txt.gz"
  "*.cytosine_context_summary.txt"
)

# ---------- init logging -----------------------------------------------------
mkdir -p "$LOG_DIR"
echo "action,sample,filename,source_path,status" > "$LOG_CSV"

log_csv() {
  echo "${1},${2},${3},${4},${5}" >> "$LOG_CSV"
}

log_err() {
  echo "[ERROR] $*" >&2
}

find_by_patterns() {
  local dir="$1"
  shift
  local patterns=("$@")
  for pattern in "${patterns[@]}"; do
    find "$dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null
  done
}

# ---------- preflight --------------------------------------------------------
echo ""
echo "============================================================"
echo "  Bismark Cleanup Script"
echo "  Base dir : $BASE_DIR"
echo "  Dry run  : $DRYRUN"
echo "  Delete   : $DO_DELETE"
echo "  Move     : $DO_MOVE"
echo "  Move dst : $BASE_DIR/$DEST_DIR/"
echo "  Log dir  : $LOG_DIR/"
echo "  Log CSV  : $(basename "$LOG_CSV")"
echo "============================================================"
echo ""

if ( $DO_MOVE || $DRYRUN ) && [[ -d "$BASE_DIR/$DEST_DIR" ]]; then
  echo "NOTE: $DEST_DIR/ already exists — files will be added to it."
  echo ""
fi

total_delete=0
total_move=0
total_size_bytes=0
total_samples=0
failed_samples=0

# ---------- process one sample -----------------------------------------------
process_sample() {
  local sample_dir="$1"
  local sample
  local intermediate_found=0
  local move_found=0
  local remaining=0

  sample="$(basename "$sample_dir")"

  echo "--- Sample: $sample ---"

  # ---- delete phase ---------------------------------------------------------
  if $DRYRUN || $DO_DELETE; then
    while IFS= read -r -d '' f; do
      [[ -z "$f" ]] && continue

      local fname fsize fbytes
      fname="$(basename "$f")"
      fsize="$(du -sh "$f" 2>/dev/null | cut -f1 || echo '?')"
      fbytes="$(stat -c%s "$f" 2>/dev/null || echo 0)"

      total_size_bytes=$(( total_size_bytes + fbytes ))
      intermediate_found=1

      if $DRYRUN; then
        echo "  [DRY-RUN DELETE] $fname  ($fsize)"
        log_csv "DELETE" "$sample" "$fname" "$f" "dry-run"
      elif $DO_DELETE; then
        if rm -f "$f"; then
          echo "  [DELETED]        $fname  ($fsize)"
          log_csv "DELETE" "$sample" "$fname" "$f" "deleted"
        else
          echo "  [DELETE-FAILED]  $fname  ($fsize)"
          log_csv "DELETE" "$sample" "$fname" "$f" "failed"
        fi
      fi

      total_delete=$(( total_delete + 1 ))
    done < <(find_by_patterns "$sample_dir" "${INTERMEDIATE_PATTERNS[@]}")

    [[ $intermediate_found -eq 0 ]] && echo "  (no intermediates found)"
  fi

  # ---- move phase -----------------------------------------------------------
  if $DRYRUN || $DO_MOVE; then
    local dest="$BASE_DIR/$DEST_DIR"
    mkdir -p "$dest"

    while IFS= read -r -d '' f; do
      [[ -z "$f" ]] && continue

      local fname
      fname="$(basename "$f")"
      move_found=1

      if $DRYRUN; then
        echo "  [DRY-RUN MOVE]   $fname  →  $DEST_DIR/"
        log_csv "MOVE" "$sample" "$fname" "$f" "dry-run → $dest"
      elif $DO_MOVE; then
        if mv -f "$f" "$dest/"; then
          echo "  [MOVED]          $fname  →  $DEST_DIR/"
          log_csv "MOVE" "$sample" "$fname" "$f" "moved → $dest"
        else
          echo "  [MOVE-FAILED]    $fname  →  $DEST_DIR/"
          log_csv "MOVE" "$sample" "$fname" "$f" "failed"
        fi
      fi

      total_move=$(( total_move + 1 ))
    done < <(find_by_patterns "$sample_dir" "${MOVE_PATTERNS[@]}")

    [[ $move_found -eq 0 ]] && echo "  (no cytosine report files found)"
  fi

  # ---- remove sample dir if empty ------------------------------------------
  if $DRYRUN; then
    remaining="$(find "$sample_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$remaining" -eq 0 ]]; then
      echo "  [DRY-RUN RMDIR]  $sample/  (would be empty after cleanup)"
      log_csv "RMDIR" "$sample" "" "$sample_dir" "dry-run → would delete"
    else
      echo "  [KEEP DIR]       $sample/  ($remaining file(s) remaining)"
      log_csv "RMDIR" "$sample" "" "$sample_dir" "dry-run → kept ($remaining files)"
    fi
  else
    remaining="$(find "$sample_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$remaining" -eq 0 ]]; then
      if rmdir "$sample_dir"; then
        echo "  [RMDIR]          $sample/  (empty — deleted)"
        log_csv "RMDIR" "$sample" "" "$sample_dir" "deleted"
      else
        echo "  [RMDIR-FAILED]   $sample/  (empty but could not remove)"
        log_csv "RMDIR" "$sample" "" "$sample_dir" "failed"
      fi
    else
      echo "  [KEEP DIR]       $sample/  ($remaining file(s) remaining)"
      log_csv "RMDIR" "$sample" "" "$sample_dir" "kept — not empty ($remaining files)"
    fi
  fi

  echo ""
}

# ---------- main loop --------------------------------------------------------
while IFS= read -r -d '' sample_dir; do
  sample="$(basename "$sample_dir")"

  # Skip non-sample directories
  [[ "$sample" == "$DEST_DIR" ]] && continue
  [[ "$sample" == "$(basename "$LOG_DIR")" ]] && continue

  total_samples=$(( total_samples + 1 ))

  if ! process_sample "$sample_dir"; then
    failed_samples=$(( failed_samples + 1 ))
    log_err "Sample failed: $sample"
    echo ""
    continue
  fi
done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ---------- summary ----------------------------------------------------------
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"

if $DRYRUN || $DO_DELETE; then
  total_size_human="$(numfmt --to=iec-i --suffix=B "$total_size_bytes" 2>/dev/null || echo "${total_size_bytes} bytes")"
  echo "  Intermediates flagged/deleted : $total_delete  (~$total_size_human)"
fi

if $DRYRUN || $DO_MOVE; then
  echo "  Cytosine files flagged/moved  : $total_move  →  $DEST_DIR/"
fi

echo "  Sample directories scanned    : $total_samples"
echo "  Sample failures               : $failed_samples"
echo "  Log written to                : $LOG_CSV"
echo "============================================================"
echo ""

if $DRYRUN; then
  echo "Dry run complete — no files were changed."
  echo "Re-run with --delete and/or --move to apply changes."
fi