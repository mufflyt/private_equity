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
    print("=== STARTING PROPENSITY SCORE MATCHING (PSM) PIPELINE ===")
    
    # 1. Export control candidates with covariates from DuckDB using Python script
    export_script = "/Users/tylermuffly/.gemini/antigravity/brain/3559c6d4-837e-47d8-9183-059d4fa833d5/scratch/export_control_candidates.py"
    if not os.path.exists(export_script):
        print(f"ERROR: Export script not found at {export_script}")
        sys.exit(1)
        
    run_command(f'python3 "{export_script}"')
    
    # 2. Run R script to calculate propensity scores and match controls
    r_matching_script = "/Users/tylermuffly/private_equity/build_matched_control_group_psm.R"
    if not os.path.exists(r_matching_script):
        print(f"ERROR: R matching script not found at {r_matching_script}")
        sys.exit(1)
        
    run_command(f'Rscript "{r_matching_script}"')
    
    print("=== PROPENSITY SCORE MATCHING PIPELINE COMPLETED SUCCESSFULLY ===")

if __name__ == "__main__":
    main()
