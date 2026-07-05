import os
import sys
import subprocess

def run_command(cmd):
    print(f"Running command: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR executing command:\n{result.stderr}")
        sys.exit(result.returncode)
    print(result.stdout)

def main():
    print("=== STARTING COMPLETE PROPENSITY SCORE MATCHING (PSM) PIPELINE ===")
    
    # Base directory
    base_dir = "/Users/tylermuffly/private_equity"
    
    # 1. Export control candidates with covariates from DuckDB
    export_script = os.path.join(base_dir, "export_control_candidates.py")
    if not os.path.exists(export_script):
        print(f"ERROR: Export script not found at {export_script}")
        sys.exit(1)
    run_command(f'python3 "{export_script}"')
    
    # 2. Run R script to calculate propensity scores and match controls
    r_matching_script = os.path.join(base_dir, "build_matched_control_group_psm.R")
    if not os.path.exists(r_matching_script):
        print(f"ERROR: R matching script not found at {r_matching_script}")
        sys.exit(1)
    run_command(f'Rscript "{r_matching_script}"')
    
    # 3. Subsample exactly 300 matched generalist pairs
    subsample_script = os.path.join(base_dir, "subsample_300_pairs.R")
    if not os.path.exists(subsample_script):
        print(f"ERROR: Subsampling script not found at {subsample_script}")
        sys.exit(1)
    run_command(f'Rscript "{subsample_script}"')
    
    # 4. Append symmetric cohort-compliant backups to the calling sheet
    backup_script = os.path.join(base_dir, "add_symmetric_backups.py")
    if not os.path.exists(backup_script):
        print(f"ERROR: Backup script not found at {backup_script}")
        sys.exit(1)
    run_command(f'python3 "{backup_script}"')
    
    # 5. Regenerate REDCap dropdown choices and simplified call tracking fields
    redcap_script = os.path.join(base_dir, "generate_redcap_data_dictionary.py")
    if not os.path.exists(redcap_script):
        print(f"ERROR: REDCap dictionary script not found at {redcap_script}")
        sys.exit(1)
    run_command(f'python3 "{redcap_script}"')
    
    # 6. Recalculate pairwise distances for validation
    distance_script = os.path.join(base_dir, "calculate_pair_distances.R")
    if not os.path.exists(distance_script):
        print(f"ERROR: Distance calculation script not found at {distance_script}")
        sys.exit(1)
    run_command(f'Rscript "{distance_script}"')
    
    # 7. Validate phone numbers in final calling sheet
    validation_script = os.path.join(base_dir, "verify_phones.py")
    if not os.path.exists(validation_script):
        print(f"ERROR: Phone validation script not found at {validation_script}")
        sys.exit(1)
    run_command(f'python3 "{validation_script}"')
    
    print("=== COMPLETE PIPELINE EXECUTED SUCCESSFULLY ===")

if __name__ == "__main__":
    main()
