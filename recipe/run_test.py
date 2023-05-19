import subprocess
import pkgutil
import platform

import catboost
import numpy as np

from catboost import Pool, CatBoost, CatBoostRegressor
from catboost.datasets import adult, amazon
from catboost.text_processing import Tokenizer


py_impl = platform.python_implementation().lower()
machine = platform.machine().lower()

print("Python implementation:", py_impl)
print("              Machine:", machine)

subprocess.run(["pip", "check"])


# datasets:
# adult:
print("Loading datasets...")
adult_train, adult_test = adult()

print("Adult dataset:\n")
print(adult_train.head(3))


# Tokenizer
text="Still, I would love to see you at 12, if you don't mind"

tokenized = Tokenizer(lowercasing=True,
                    separator_type='BySense',
                    token_types=['Word', 'Number']).tokenize(text)
print("Tokenized text:\n")
print(tokenized)

# CatboostRegressor

# initialize data
train_data = np.random.randint(0, 
                               100, 
                               size=(100, 10))
train_label = np.random.randint(0, 
                                1000, 
                                size=(100))
test_data = np.random.randint(0, 
                              100, 
                              size=(50, 10))
# initialize Pool
train_pool = Pool(train_data, 
                  train_label, 
                  cat_features=[0,2,5])
test_pool = Pool(test_data, 
                 cat_features=[0,2,5]) 

# specify the training parameters 
model = CatBoostRegressor(iterations=2, 
                          depth=2, 
                          learning_rate=1, 
                          loss_function='RMSE')
#train the model
model.fit(train_pool)
# make the prediction using the resulting model
preds = model.predict(test_pool)

print("CatboostRegressor:\n")
print(preds)
