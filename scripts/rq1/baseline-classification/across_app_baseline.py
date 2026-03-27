import csv
import os
import pickle
from datetime import datetime
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score
from sklearn.svm import SVC
import sqlite3
import sys, pathlib
sys.path.append(str(pathlib.Path(__file__).resolve().parents[3]))

def get_db_retained(sqlite_db_path, table_name):
    conn = sqlite3.connect(sqlite_db_path)
    query = f"""
        SELECT
            appname,
            state1,
            state2,
            HUMAN_CLASSIFICATION,
            is_retained
        FROM {table_name}
        WHERE is_retained = 1
    """
    df_db_retained = pd.read_sql_query(query, conn)
    conn.close()
    return df_db_retained

def filter_dataframes(df_train, df_test, df_db_retained):
    merge_cols = ["appname", "state1", "state2"]

    df_train_filtered = pd.merge(
        df_train,
        df_db_retained[merge_cols],
        on=merge_cols,
        how="inner"
    )

    df_test_filtered = pd.merge(
        df_test,
        df_db_retained[merge_cols],
        on=merge_cols,
        how="inner"
    )

    return df_train_filtered, df_test_filtered

if __name__ == '__main__':
    '''
    Coder Adapted from WEBEMBED replication package
    https://arxiv.org/abs/2306.07400
    '''

    '''
    RQ1: configuration 2/3 ACROSS APPS
    Doc2Vec trained on DS + commoncrawl
    Classifiers trained on 8 apps in SS (or 1 app only)
    Classifiers tested on 1 apps in SS (or 8 apps)
    '''

    OUTPUT_CSV  = True
    SAVE_MODELS = True
    filename    = ''
    base_path   = os.getcwd()

    embedding_type = ['DOM_RTED', 'VISUAL_PDiff']
    apps           = ['addressbook', 'claroline', 'ppma', 'mrbs', 'mantisbt', 'dimeshift', 'pagekit', 'phoenix', 'petclinic']

    baseline_model_dir = f"{base_path}/baseline-models"
    sqlite_db_path     = f"{base_path}/dataset/SS_refined.db"
    results_dir_path   = f"{base_path}/results/rq1"
    threshold_Set      = f"{base_path}/resources/baseline-dataset/SS_threshold_set.csv"
    table_name         = 'nearduplicates'

    os.makedirs(baseline_model_dir, exist_ok=True)
    comparison_df = None

    for app in apps:
        start_time = datetime.now()
        for emb in embedding_type:
            print("app: %s\tembedding: %s" % (app, emb))

            names = [
                # "Dummy",
                # "Threshold",
                # "Nearest Neighbors",
                "SVM RBF", # => best classifier according to the paper
                # "Decision Tree",
                # "Gaussian Naive Bayes",
                # "Random Forest",
                # "Ensemble",
                # "Neural Network",
                # "XGBoost"
            ]

            classifiers = [
                # DummyClassifier(strategy="stratified"),
                # "Threshold",
                # KNeighborsClassifier(),
                SVC(), # => best classifier according to the paper
                # DecisionTreeClassifier(),
                # GaussianNB(),
                # RandomForestClassifier(),
                # VotingClassifier(estimators=[('knn', KNeighborsClassifier()),
                #                             ('svm', SVC()),
                #                             ('dt', DecisionTreeClassifier()),
                #                             ('gnb', GaussianNB()),
                #                             ('rf', RandomForestClassifier())]),
                # MLPClassifier(max_iter=1000),
                # GradientBoostingClassifier(n_estimators=100, max_depth=1)
            ]

            for name, model in zip(names, classifiers):
                if emb in {'content_tags', 'DOM_RTED', 'VISUAL_PDiff'}:
                    feature = emb
                else:
                    feature = 'doc2vec_distance_' + emb

                if name == "Threshold":
                    df_train = pd.read_csv(threshold_Set)
                    df_test = pd.read_csv(threshold_Set)

                    df_train = df_train.query("appname == @app")
                    df_test = df_test.query("appname != @app")

                    #do the filtering
                    print("data size prev .", len(df_train)+ len(df_test))
                    df_db_retained = get_db_retained(sqlite_db_path, table_name)
                    df_train, df_test = filter_dataframes(
                        df_train,
                        df_test,
                        df_db_retained
                    )
                    print("data size after .", len(df_train)+ len(df_test))

                    X_train = np.array(df_train[feature]).reshape(-1, 1)
                    y_train = np.array(df_train['HUMAN_CLASSIFICATION'])

                    X_test = np.array(df_test[feature]).reshape(-1, 1)
                    y_test = np.array(df_test['HUMAN_CLASSIFICATION'])

                    # 0, 1 = clones; 2 = distinct
                    y_train[y_train == 1] = 0  # harmonize near-duplicates as 0's
                    y_train[y_train == 2] = 1  # convert distinct as 1's

                    y_test[y_test == 1] = 0  # harmonize near-duplicates as 0's
                    y_test[y_test == 2] = 1  # convert distinct as 1's

                    df_train = pd.DataFrame(list(zip(X_train, y_train)),
                                            columns=[feature,
                                                        'HUMAN_CLASSIFICATION'])

                    # 0, 1 = clones; 2 = distinct
                    df_clones = df_train.query("HUMAN_CLASSIFICATION != 2")
                    df_clones = df_clones[feature].to_list()

                    df_distinct = df_train.query("HUMAN_CLASSIFICATION == 2")
                    df_distinct = df_distinct[feature].to_list()

                    df_test = pd.DataFrame(list(zip(X_test, y_test)),
                                            columns=[feature,
                                                    'HUMAN_CLASSIFICATION'])

                    threshold = 0.8
                    # 0, 1 = clones; 2 = distinct
                    df_clones = df_test.query("HUMAN_CLASSIFICATION != 2")
                    df_clones_test = df_clones[feature]
                    tp = df_clones_test[df_clones_test > threshold].count()
                    fn = len(df_clones_test) - tp

                    df_distinct = df_test.query("HUMAN_CLASSIFICATION == 2")
                    df_distinct_test = df_distinct[feature]
                    fp = df_distinct_test[df_distinct_test > threshold].count()
                    tn = len(df_distinct_test) - fp

                    accuracy = (tp + tn) / (tp + tn + fp + fn)
                    precision = tp / (tp + fp)
                    recall = tp / (tp + fn)
                    f1_0 = 2 * ((precision * recall) / (precision + recall))
                    f1_1 = 2 * ((precision * recall) / (precision + recall))
                else:
                    df_train = pd.read_csv(threshold_Set, quotechar='"', escapechar='\\', on_bad_lines='warn')
                    df_test = pd.read_csv(threshold_Set)

                    df_train = df_train.query("appname == @app")
                    df_test = df_test.query("appname != @app")

                    # we only consider the SS dataset with is_retain flagged 1 pairs for analysis
                    print("data size prev .", len(df_train) + len(df_test))
                    df_db_retained = get_db_retained(sqlite_db_path, table_name)
                    df_train, df_test = filter_dataframes(
                        df_train,
                        df_test,
                        df_db_retained
                    )
                    print("data size after .", len(df_train) + len(df_test))

                    # load Labeled(DS) as training set
                    X_train = np.array(df_train[feature]).reshape(-1, 1)
                    y_train = np.array(df_train['HUMAN_CLASSIFICATION'])

                    # load SS as test set (all apps)
                    X_test = np.array(df_test[feature]).reshape(-1, 1)
                    y_test = np.array(df_test['HUMAN_CLASSIFICATION'])

                    # updated here - positive class should be near duplicate
                    # 0, 1 = clones; 2 = distinct
                    # prev -> 0,1 -> 0; 2 -> 1
                    # now -> 0,1 -> 1 and 2 -> 0
                    y_train[y_train == 0] = 1  # harmonize near-duplicates as 1's
                    y_train[y_train == 2] = 0  # convert distinct as 0's

                    y_test[y_test == 0] = 1  # harmonize near-duplicates as 1's
                    y_test[y_test == 2] = 0  # convert distinct as 0's

                # train the classifier
                model = model.fit(X_train, y_train)

                # save the classifier
                if SAVE_MODELS:
                    classifier_path = f'{baseline_model_dir}/across-apps-' + app + '-' + \
                                        name.replace(" ", "-").replace("_", "-").lower() + \
                                        '-' + \
                                        feature.replace(" ", "-").replace("_", "-").lower() + \
                                        '.sav'
                    pickle.dump(model, open(classifier_path, 'wb'))
                    print(f'Saved classifier at {classifier_path}')

                # predict the scores
                y_pred = model.predict(X_test)

                # compute metrics
                accuracy = accuracy_score(y_test, y_pred)
                f1_0 = f1_score(y_test, y_pred, pos_label=0)
                f1_1 = f1_score(y_test, y_pred, pos_label=1)
                precision = precision_score(y_test, y_pred)
                recall = recall_score(y_test, y_pred)
                f1_weighted = f1_score(y_test, y_pred, average='weighted', zero_division=0)

                print(f'{name}, '
                        f'accuracy: {accuracy}, '
                        f'precision: {precision}, '
                        f'recall: {recall}, '
                        f'f1_0: {f1_0}, '
                        f'f1_1: {f1_1}',
                        f'f1_w: {f1_weighted}',
                      )

                if OUTPUT_CSV:
                    a = ''
                    if emb == 'content':
                        a = 'Content only'
                    elif emb == 'tags':
                        a = 'Tags only'
                    elif emb == 'content_tags':
                        a = 'Content and tags'
                    elif emb == 'all':
                        a = "Ensemble"
                    elif emb == 'DOM_RTED':
                        a = 'DOM_RTED'
                    elif emb == 'VISUAL_Hyst':
                        a = 'VISUAL_Hyst'
                    elif emb == 'VISUAL_PDiff':
                        a = 'VISUAL_PDiff'
                    else:
                        print('nope')

                    d1 = pd.DataFrame(
                        {'App': app,
                            'Model': ['DS_' + emb + '_' + 'modelsize100' + 'epoch31'],
                            'Embedding': [a],
                            'Classifier': [name],
                            'Accuracy': [accuracy],
                            'Precision': [precision],
                            'Recall': [recall],
                            'F1_0': [f1_0],
                            'F1_1': [f1_1],
                            'F1_w': [f1_weighted]})

                    comparison_df = pd.concat([comparison_df, d1])

    if OUTPUT_CSV:
        comparison_df.to_csv(f'{results_dir_path}/baselines-across-apps.csv', index=False)
