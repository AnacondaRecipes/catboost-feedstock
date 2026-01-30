import subprocess
import pkgutil
import platform
import os

# CUDA environment diagnostics
print("=== CUDA Environment Check ===")
try:
    subprocess.run(["nvidia-smi"], check=False)
except FileNotFoundError:
    print("nvidia-smi not found - no CUDA drivers installed")
try:
    subprocess.run(["sh", "-c", "ls -la /usr/lib/x86_64-linux-gnu/libcuda* 2>/dev/null || echo 'libcuda not found'"], check=False)
except Exception as e:
    print(f"libcuda check failed: {e}")
try:
    subprocess.run(["sh", "-c", "ldconfig -p | grep -i cuda || echo 'No CUDA in ldconfig'"], check=False)
except Exception as e:
    print(f"ldconfig check failed: {e}")
print(f"LD_LIBRARY_PATH={os.environ.get('LD_LIBRARY_PATH', 'not set')}")
print("=== End CUDA Check ===")

import catboost
import numpy as np

from catboost import Pool, CatBoostRegressor
from catboost.datasets import adult
from catboost.text_processing import Tokenizer


py_impl = platform.python_implementation().lower()
machine = platform.machine().lower()

print("Python implementation:", py_impl)
print("              Machine:", machine)

subprocess.run(["pip", "check"])


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
