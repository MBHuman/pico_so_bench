import argparse
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import glob
import os
import re
import numpy as np
from scipy import stats


def parse_prefix(p):
    base = re.sub(r'_i\d+$', '', p)
    match = re.search(r'_s(\d+)', base)
    scale = int(match.group(1)) if match else 1
    version = re.sub(r'_s\d+.*', '', base)
    return version, scale


def load_data(results_path="results"):
    all_files = glob.glob(os.path.join(results_path, "**/summary.csv"), recursive=True)
    if not all_files:
        print("No summary.csv files found.")
        return None

    df_list = []
    for filename in all_files:
        df = pd.read_csv(filename)
        df[['version', 'scale']] = df['prefix'].apply(lambda x: pd.Series(parse_prefix(str(x))))
        df_list.append(df)

    return pd.concat(df_list, axis=0, ignore_index=True)


def plot_significance(df, output_dir="plots_stat"):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    sns.set_theme(style="whitegrid")
    df['label'] = df['label'].str.strip()

    benchmarks = df['benchmark'].unique()

    for bench in benchmarks:
        bench_df = df[df['benchmark'] == bench].copy()
        labels = bench_df['label'].unique()

        n_labels = len(labels)
        cols = 2
        rows = (n_labels + 1) // cols
        fig, axes = plt.subplots(rows, cols, figsize=(15, 5 * rows), sharex=True)
        axes = axes.flatten()

        for i, label in enumerate(labels):
            ax = axes[i]
            label_df = bench_df[bench_df['label'] == label].sort_values('scale')

            sns.lineplot(
                data=label_df,
                x="scale",
                y="tps",
                hue="version",
                marker="o",
                ax=ax,
                errorbar=('ci', 95),
            )

            ax.set_title(f"Op: {label}")
            ax.set_ylabel("TPS")
            ax.set_xlabel("Scale")

        for j in range(i + 1, len(axes)):
            fig.delaxes(axes[j])

        plt.tight_layout(rect=[0, 0.03, 1, 0.95])
        fig.suptitle(f"Statistical Performance: {bench} (95% CI)", fontsize=16)

        save_path = os.path.join(output_dir, f"{bench}_statistical.png")
        plt.savefig(save_path)
        print(f"Saved statistical plot: {save_path}")
        plt.close()


def plot_speedup_matrix(df, output_dir="plots_stat", base="master", target="so"):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    def get_stats(group):
        vals_base = group[group['version'] == base]['tps']
        vals_target = group[group['version'] == target]['tps']

        if len(vals_base) < 2 or len(vals_target) < 2:
            return pd.Series({'speedup': np.nan, 'p_val': np.nan})

        mean_base = vals_base.mean()
        mean_target = vals_target.mean()
        _, p = stats.ttest_ind(vals_base, vals_target, equal_var=False)

        return pd.Series({
            'speedup': (mean_target / mean_base) - 1,
            'p_val': p,
        })

    summary = df.groupby(['benchmark', 'label', 'scale']).apply(get_stats, include_groups=False).reset_index()

    benchmarks = summary['benchmark'].unique()
    for bench in benchmarks:
        bench_data = summary[summary['benchmark'] == bench]

        matrix = bench_data.pivot(index='label', columns='scale', values='speedup')
        p_matrix = bench_data.pivot(index='label', columns='scale', values='p_val')

        plt.figure(figsize=(10, 8))
        annot = matrix.copy().map(lambda x: f"{x:+.1%}")
        for r in range(len(matrix.index)):
            for c in range(len(matrix.columns)):
                p = p_matrix.iloc[r, c]
                if p < 0.05:
                    annot.iloc[r, c] += "*"

        sns.heatmap(
            matrix,
            annot=annot,
            fmt="",
            cmap="RdYlGn",
            center=0,
            cbar_kws={'label': f'Speedup ({target} vs {base})'},
        )

        plt.title(f"Speedup Heatmap: {bench}\n(* denotes p < 0.05)", fontsize=14)
        save_path = os.path.join(output_dir, f"{bench}_speedup_heatmap.png")
        plt.savefig(save_path)
        print(f"Saved heatmap: {save_path}")
        plt.close()


def main():
    parser = argparse.ArgumentParser(description="Plot benchmark statistics.")
    parser.add_argument("--base", default="master", help="Base branch name (prefix in CSV)")
    parser.add_argument("--target", default="so", help="Target branch name (prefix in CSV)")
    parser.add_argument("--results", default="results", help="Path to results directory")
    parser.add_argument("--output", default="plots_stat", help="Output directory for plots")
    parser.add_argument(
        "--no-sort-order",
        action="store_true",
        help="Exclude bench_sort_order from plots (use when target branch lacks sort_order support)",
    )
    args = parser.parse_args()

    data = load_data(args.results)
    if data is None:
        return

    if args.no_sort_order:
        data = data[data['benchmark'] != 'bench_sort_order']
        print("bench_sort_order excluded (--no-sort-order)")

    versions_present = data['version'].unique().tolist()
    for v in [args.base, args.target]:
        if v not in versions_present:
            print(f"Warning: version '{v}' not found in data. Available: {versions_present}")

    plot_significance(data, output_dir=args.output)
    plot_speedup_matrix(data, output_dir=args.output, base=args.base, target=args.target)


if __name__ == "__main__":
    main()
