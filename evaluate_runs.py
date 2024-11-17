import os
import re
import pandas as pd
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root_dir', type=str)
    args = parser.parse_args()
    root_dir = args.root_dir
    subdirs = [d for d in os.listdir(root_dir) if os.path.isdir(os.path.join(root_dir, d))]
    subdirs.sort()

    # order of runs
    desired_order = ['SRR11648416', 'SRR11648417', 'SRR11648418', 'SRR11648419', 'SRR11648420', 'SRR11648421']

    for subdir in subdirs:
        subdir_path = os.path.join(root_dir, subdir)
        data = []
        txt_files = [f for f in os.listdir(subdir_path) if f.endswith('_eval.txt')]

        def file_sort_key(filename):
            run_id = filename.replace('_eval.txt', '')
            if run_id in desired_order:
                return desired_order.index(run_id)
            else:
                return float('inf')

        txt_files.sort(key=file_sort_key)

        for txt_file in txt_files:
            txt_file_path = os.path.join(subdir_path, txt_file)
            metrics = {}
            run_name = txt_file.replace('_eval.txt', '')
            metrics['Run'] = run_name

            metrics['Real Time (s)'] = None
            metrics['Peak RSS (GB)'] = None
            metrics['Number of Distinct Minimizers'] = None
            metrics['Singleton Rate'] = None
            metrics['Average Spacing'] = None
            metrics['Total Reads'] = None
            metrics['Mapped Reads'] = None
            metrics['Mapping Rate'] = None
            metrics['Unmapped Reads'] = None
            metrics['Unmapped Reads Rate'] = None
            metrics['High-Quality Reads'] = None

            if 'SR' in subdir:
                metrics['Properly Paired Reads'] = None
                metrics['Properly Paired Rate'] = None

            with open(txt_file_path, 'r') as f:
                lines = f.readlines()
            i = 0
            while i < len(lines):
                line = lines[i].strip()
                # Real Time and Peak RSS
                pattern = r"\[M::main\] Real time: ([\d.]+) sec; CPU: [\d.]+ sec; Peak RSS: ([\d.]+) GB"
                match = re.search(pattern, line)
                if match:
                    metrics['Real Time (s)'] = float(match.group(1))
                    metrics['Peak RSS (GB)'] = float(match.group(2))
                    i += 1
                    continue
                # Number of Distinct Minimizers, Singleton Rate, Average Spacing
                pattern = r"\[M::mm_idx_stat::.*\] distinct minimizers: ([\d]+) \(([\d.]+)% are singletons\);.*average spacing: ([\d.]+);"
                match = re.search(pattern, line)
                if match:
                    metrics['Number of Distinct Minimizers'] = int(match.group(1))
                    metrics['Singleton Rate'] = float(match.group(2))
                    metrics['Average Spacing'] = float(match.group(3))
                    i += 1
                    continue
                # Total Reads
                pattern = r"([\d]+) \+ [\d]+ in total \(QC-passed reads \+ QC-failed reads\)"
                match = re.search(pattern, line)
                if match:
                    metrics['Total Reads'] = int(match.group(1))
                    i += 1
                    continue
                # Mapped Reads
                pattern = r"([\d]+) \+ [\d]+ mapped \(([\d.]+)% : N/A\)"
                match = re.search(pattern, line)
                if match:
                    metrics['Mapped Reads'] = int(match.group(1))
                    metrics['Mapping Rate'] = float(match.group(2)) / 100.0
                    i += 1
                    continue
                # Properly Paired Reads (SR only)
                if 'SR' in subdir:
                    pattern = r"([\d]+) \+ [\d]+ properly paired \(([\d.]+)% : N/A\)"
                    match = re.search(pattern, line)
                    if match:
                        metrics['Properly Paired Reads'] = int(match.group(1))
                        metrics['Properly Paired Rate'] = float(match.group(2)) / 100.0
                        i += 1
                        continue
                # MAPQ(>=30):
                if 'MAPQ(>=30):' in line:
                    # Next non-empty line is High-Quality Reads
                    j = i + 1
                    while j < len(lines):
                        next_line = lines[j].strip()
                        if next_line != '':
                            metrics['High-Quality Reads'] = int(next_line)
                            break
                        j += 1
                    i = j
                    continue
                i += 1
            # compute rates
            if metrics['Total Reads'] is not None and metrics['Mapped Reads'] is not None:
                metrics['Unmapped Reads'] = metrics['Total Reads'] - metrics['Mapped Reads']
                metrics['Unmapped Reads Rate'] = metrics['Unmapped Reads'] / metrics['Total Reads']
            data.append(metrics)
        df = pd.DataFrame(data)
        df.set_index('Run', inplace=True
        df = df.reindex(desired_order)
        
        csv_filename = os.path.join(subdir_path, subdir + '.csv')
        df.to_csv(csv_filename)

if __name__ == "__main__":
    main()
