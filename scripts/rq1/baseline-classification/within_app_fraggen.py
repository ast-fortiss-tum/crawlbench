import os
import json
import pandas as pd
import numpy as np
from sklearn import metrics
import sqlite3

APPS = ['addressbook', 'petclinic', 'claroline', 'dimeshift', 'pagekit', 'phoenix', 'ppma', 'mantisbt']
base_path = os.getcwd()

'''
FragGen Results with Refined DB
'''
def test_fraggen_rq1_with_refinedData():
    conn = sqlite3.connect(f'{base_path}/dataset/ss_refined.db')

    db_query = """
        SELECT
            appname,
            state1,
            state2
        FROM nearduplicates
        WHERE is_retained = 1
    """
    df_db = pd.read_sql_query(db_query, conn)

    # this file directly get from the fraggen replication package
    with open(f'{base_path}/resources/baseline-dataset/combinedEntries.json', "r", encoding="utf-8") as f:
        all_entries = json.load(f)

    # Name the columns according to your JSON structure
    columns = [
        "appname",  # index 0
        "col1",  # index 1
        "state1",  # index 2
        "state2",  # index 3
        "col4",
        "col5",
        "col6",
        "col7",
        "col8",
        "col9",
        "col10",
        "col11",
        "col12",
        "col13",
        "y_actual",  # index 14
        "col15",
        "hybrid",  # index 16
        "col17"
    ]
    df_json = pd.DataFrame(all_entries, columns=columns)
    print("Total entries before merge:", len(df_json))

    # Merge (inner join) to keep only records where (appname, state1, state2) match
    # and is_retained=1 in the DB.
    print(df_json[:1])
    print(df_db[:1])
    df_merged = pd.merge(df_json, df_db, how='inner',
                         on=["appname", "state1", "state2"])

    if df_merged.empty:
        print("No matching entries found in DB with is_retained=1. Exiting.")
        conn.close()
        return

    print("Total retained entries after merge:", len(df_merged))

    # Convert y_actual and hybrid to integers
    y_actual = df_merged["y_actual"].astype(int).values
    hybrid = df_merged["hybrid"].astype(int).values

    # -----------------------------------------------------
    # Map the labels so that:
    #  0 -> 1
    #  1 -> 1
    #  2 -> 0
    #
    # In other words, old [0,1] become new label 1, old 2 becomes new label 0.
    # -----------------------------------------------------
    def map_to_binary(x):
        # If x is 0 or 1 => 1, else => 0
        return 1 if x in [0, 1] else 0

    vectorized_map = np.vectorize(map_to_binary)
    y_actual_bin = vectorized_map(y_actual)
    hybrid_bin = vectorized_map(hybrid)

    # -----------------------------------------------------
    # Calculate metrics
    # -----------------------------------------------------

    accuracy = metrics.accuracy_score(y_actual_bin, hybrid_bin)
    precision_bin, recall_bin, f1_bin, _ = metrics.precision_recall_fscore_support(
        y_actual_bin, hybrid_bin, average="binary", pos_label=1
    )
    f1_per_class = metrics.f1_score(y_actual_bin, hybrid_bin, average=None, labels=[0, 1])
    f1_weighted = metrics.f1_score(y_actual_bin, hybrid_bin, average="weighted")

    print(f"Accuracy: {accuracy}")
    print(f"Precision (class=1): {precision_bin}")
    print(f"Recall    (class=1): {recall_bin}")
    print(f"F1 (class=0): {f1_per_class[0]}")
    print(f"F1 (class=1): {f1_per_class[1]}")
    print(f"F1 weighted average: {f1_weighted}")
    conn.close()


if __name__ == "__main__":
    '''
    Coder Adapted from FragGen replication package
    https://zenodo.org/records/5981993
    https://arxiv.org/abs/2110.14043
    '''
    test_fraggen_rq1_with_refinedData()
