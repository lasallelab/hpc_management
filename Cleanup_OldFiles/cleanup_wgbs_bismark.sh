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

set -euo pipefail

DRYRUN=false
DO_DELETE=false
DO_MOVE=false
DEST_DIR="08_cytosine_reports"       # shared folder at the deSmith level
BASE_DIR="$(pwd)"
DIR_NAME="$(basename "$BASE_DIR")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$BASE_DIR/clean_up_wgbs_intermediates"
LOG_CSV="${LOG_DIR}/cleanup_bismark_log_${DIR_NAME}_${TIMESTAMP}.csv"

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

# ---------- intermediate file patterns ---------------------------------------
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
  # "*.deduplicated.bedGraph.gz"
  "*_bismark_bt2_pe.bam"
  "*.bam*"
  
  

)

# ---------- files to MOVE into shared 08_cytosine_reports/ -------------------
MOVE_PATTERNS=(
  "*.bismark.cov.gz"
  "*.CpG_report.merged_CpG_evidence.cov.gz"
  "*.CpG_report.txt.gz"
  "*.cytosine_context_summary.txt"
  "*.deduplicated.bedGraph.gz"
)

# ---------- init CSV ---------------------------------------------------------
mkdir -p "$LOG_DIR"
echo "action,sample,filename,source_path,status" > "$LOG_CSV"

log_csv() {
  echo "${1},${2},${3},${4},${5}" >> "$LOG_CSV"
}

# ---------- helpers ----------------------------------------------------------
find_by_patterns() {
  local dir="$1"; shift
  local patterns=("$@")
  for pattern in "${patterns[@]}"; do
    find "$dir" -maxdepth 1 -name "$pattern" -print0 2>/dev/null
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
echo "  Log CSV  : $(basename \"$LOG_CSV\")"
echo "============================================================"
echo ""

# Warn if destination already exists
if ( $DO_MOVE || $DRYRUN ) && [[ -d "$BASE_DIR/$DEST_DIR" ]]; then
  echo "NOTE: $DEST_DIR/ already exists — files will be added to it."
  echo ""
fi

total_delete=0
total_move=0
total_size_bytes=0

# ---------- main loop over sample subdirectories -----------------------------
while IFS= read -r -d '' sample_dir; do
  sample=$(basename "$sample_dir")

  # Skip the destination folder itself if it already exists
  [[ "$sample" == "$DEST_DIR" ]] && continue

  echo "--- Sample: $sample ---"

  # ---- PHASE 1: intermediates -----------------------------------------------
  if $DRYRUN || $DO_DELETE; then
    intermediate_found=0
    while IFS= read -r -d '' f; do
      [[ -z "$f" ]] && continue
      fname=$(basename "$f")
      fsize=$(du -sh "$f" 2>/dev/null | cut -f1)
      fbytes=$(stat -c%s "$f" 2>/dev/null || echo 0)
      total_size_bytes=$(( total_size_bytes + fbytes ))
      intermediate_found=1

      if $DRYRUN; then
        echo "  [DRY-RUN DELETE] $fname  ($fsize)"
        log_csv "DELETE" "$sample" "$fname" "$f" "dry-run"
      elif $DO_DELETE; then
        rm -f "$f"
        echo "  [DELETED]        $fname  ($fsize)"
        log_csv "DELETE" "$sample" "$fname" "$f" "deleted"
      fi
      (( total_delete++ )) || true
    done < <(find_by_patterns "$sample_dir" "${INTERMEDIATE_PATTERNS[@]}")

    [[ $intermediate_found -eq 0 ]] && echo "  (no intermediates found)"
  fi

  # ---- PHASE 2: move cytosine report files ----------------------------------
  if $DRYRUN || $DO_MOVE; then
    dest="$BASE_DIR/$DEST_DIR"
    move_found=0
    while IFS= read -r -d '' f; do
      [[ -z "$f" ]] && continue
      fname=$(basename "$f")
      move_found=1

      if $DRYRUN; then
        echo "  [DRY-RUN MOVE]   $fname  →  $DEST_DIR/"
        log_csv "MOVE" "$sample" "$fname" "$f" "dry-run → $dest"
      elif $DO_MOVE; then
        mkdir -p "$dest"
        mv "$f" "$dest/"
        echo "  [MOVED]          $fname  →  $DEST_DIR/"
        log_csv "MOVE" "$sample" "$fname" "$f" "moved → $dest"
      fi
      (( total_move++ )) || true
    done < <(find_by_patterns "$sample_dir" "${MOVE_PATTERNS[@]}")

    [[ $move_found -eq 0 ]] && echo "  (no cytosine report files found)"

    # ---- Check if sample folder is now empty and remove it ------------------
    if $DRYRUN; then
      remaining=$(find "$sample_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
      remaining=$(( remaining - move_found ))
      if [[ $remaining -le 0 ]]; then
        echo "  [DRY-RUN RMDIR]  $sample/  (would be empty after move)"
        log_csv "RMDIR" "$sample" "" "$sample_dir" "dry-run → would delete"
      else
        echo "  [KEEP DIR]       $sample/  ($remaining file(s) remaining after move)"
      fi
    elif $DO_MOVE; then
      remaining=$(find "$sample_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
      if [[ $remaining -eq 0 ]]; then
        rmdir "$sample_dir"
        echo "  [RMDIR]          $sample/  (empty — deleted)"
        log_csv "RMDIR" "$sample" "" "$sample_dir" "deleted"
      else
        echo "  [KEEP DIR]       $sample/  ($remaining file(s) remaining)"
        log_csv "RMDIR" "$sample" "" "$sample_dir" "kept — not empty ($remaining files)"
      fi
    fi
  fi

  echo ""

done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ---------- summary ----------------------------------------------------------
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"
if $DRYRUN || $DO_DELETE; then
  total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size_bytes" 2>/dev/null \
                    || echo "${total_size_bytes} bytes")
  echo "  Intermediates flagged/deleted : $total_delete  (~$total_size_human)"
fi
if $DRYRUN || $DO_MOVE; then
  echo "  Cytosine files flagged/moved  : $total_move  →  $DEST_DIR/"
fi
echo "  Log written to                : $LOG_DIR/$(basename \"$LOG_CSV\")"
echo "============================================================"
echo ""

if $DRYRUN; then
  echo "Dry run complete — no files were changed."
  echo "Re-run with --delete and/or --move to apply changes."
fi