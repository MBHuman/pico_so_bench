import pandas as pd
import glob
import os
import re
import numpy as np
from scipy import stats

def parse_prefix(p):
    """
    Extracts version and scale from directory prefix.
    Example: 'so_s10_i3' -> version='so', scale=10
    """
    # Remove iteration suffix if it exists (_i1, _i2...)
    base = re.sub(r'_i\d+$', '', p)
    # Extract scale (_s10)
    match = re.search(r'_s(\d+)', base)
    scale = int(match.group(1)) if match else 1
    # Extract version (the part before _s)
    version = re.sub(r'_s\d+.*', '', base)
    return version, scale

def load_all_results(results_dir="results"):
    # Recursively find all summary.csv files
    files = glob.glob(os.path.join(results_dir, "**/summary.csv"), recursive=True)
    if not files:
        print(f"No summary.csv files found in {results_dir}")
        return None
    
    all_data = []
    for f in files:
        try:
            df = pd.read_csv(f)
            # Ensure labels are clean
            df['label'] = df['label'].astype(str).str.strip()
            # Extract metadata from the 'prefix' column if scale/version aren't already explicit columns
            if 'version' not in df.columns:
                df[['version', 'scale']] = df['prefix'].apply(lambda x: pd.Series(parse_prefix(str(x))))
            all_data.append(df)
        except Exception as e:
            print(f"Error reading {f}: {e}")
    
    if not all_data:
        return None
        
    return pd.concat(all_data, ignore_index=True)

def compare_builds(df, base="master", target="so"):
    # Group by everything except iteration to get lists of TPS values
    grouped = df.groupby(['benchmark', 'label', 'scale', 'version'])['tps'].apply(list).unstack('version')
    
    if base not in grouped.columns or target not in grouped.columns:
        print(f"Error: Missing builds. Need '{base}' and '{target}'. Available: {grouped.columns.tolist()}")
        return

    print("\n" + "="*115)
    header = f"{'Benchmark':<15} {'Operation':<22} {'Scale':<6} {base.upper():>12} {target.upper():>12} {'Diff %':>9} {'CV %':>8} {'P-Value':>10}"
    print(header)
    print("-" * 115)
    
    results = []
    for idx, row in grouped.iterrows():
        bench, label, scale = idx
        vals_base = np.array(row[base]) if isinstance(row[base], list) else np.array([])
        vals_target = np.array(row[target]) if isinstance(row[target], list) else np.array([])
        
        if len(vals_base) == 0 or len(vals_target) == 0:
            continue

        mean_base = np.mean(vals_base)
        mean_target = np.mean(vals_target)
        
        # Coefficient of Variation (Stability)
        cv_base = (np.std(vals_base) / mean_base) * 100 if mean_base > 0 else 0
        cv_target = (np.std(vals_target) / mean_target) * 100 if mean_target > 0 else 0
        max_cv = max(cv_base, cv_target)
        
        # T-Test for significance
        # Use Welch's t-test (equal_var=False) as variances might differ
        t_stat, p_val = stats.ttest_ind(vals_base, vals_target, equal_var=False)
        
        diff_pct = ((mean_target - mean_base) / mean_base) * 100
        
        # Formatting
        sig_marker = "*" if p_val < 0.05 else " "
        color = "\033[92m" if (diff_pct > 0.5 and p_val < 0.05) else ("\033[91m" if (diff_pct < -0.5 and p_val < 0.05) else "")
        reset = "\033[0m" if color else ""
        
        print(f"{bench:<15} {label:<22} {scale:<6} {mean_base:>12.0f} {mean_target:>12.0f} {color}{diff_pct:>+8.1f}%{sig_marker}{reset} {max_cv:>7.1f}% {p_val:>10.3f}")

    print("="*115)
    print("Notes:")
    print("  * Diff %: Positive means target is faster.")
    print("  * CV %: Coefficient of Variation (max across builds). Lower is better (<5% is ideal).")
    print("  * P-Value: Statistically significant if < 0.05 (marked with *).")
    print("  * T-Test requires multiple iterations (run_repeated_scaling.sh).\n")

if __name__ == "__main__":
    print("Aggregating results from results/ directory...")
    data = load_all_results()
    if data is not None:
        compare_builds(data)
    else:
        print("Failed to load results. Ensure the 'results/' directory contains summary.csv files.")
