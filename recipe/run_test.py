import subprocess
import platform

import catboost
import numpy as np

from catboost import Pool, CatBoostRegressor
from catboost.text_processing import Tokenizer
from catboost.utils import get_gpu_device_count


py_impl = platform.python_implementation().lower()
machine = platform.machine().lower()

print("Python implementation:", py_impl)
print("              Machine:", machine)

subprocess.run(["pip", "check"])


# Tokenizer
text = "Still, I would love to see you at 12, if you don't mind"

tokenized = Tokenizer(lowercasing=True,
                      separator_type='BySense',
                      token_types=['Word', 'Number']).tokenize(text)
print("Tokenized text:\n")
print(tokenized)

# initialize data
train_data = np.random.randint(0, 100, size=(100, 10))
train_label = np.random.randint(0, 1000, size=(100))
test_data = np.random.randint(0, 100, size=(50, 10))

train_pool = Pool(train_data, train_label, cat_features=[0, 2, 5])
test_pool = Pool(test_data, cat_features=[0, 2, 5])

# CPU test
print("\n--- CPU test ---")
model_cpu = CatBoostRegressor(iterations=2, depth=2, learning_rate=1,
                              loss_function='RMSE', task_type='CPU')
model_cpu.fit(train_pool, verbose=False)
preds_cpu = model_cpu.predict(test_pool)
print("CPU predictions:", preds_cpu[:5], "...")

# GPU test (CUDA variant on nodes with GPUs)
gpu_count = get_gpu_device_count()
print(f"\nGPU devices detected: {gpu_count}")

if gpu_count > 0:
    print("\n--- GPU test ---")
    model_gpu = CatBoostRegressor(iterations=2, depth=2, learning_rate=1,
                                  loss_function='RMSE', task_type='GPU')
    model_gpu.fit(train_pool, verbose=False)
    preds_gpu = model_gpu.predict(test_pool)
    print("GPU predictions:", preds_gpu[:5], "...")
    print("GPU test PASSED")
else:
    print("No GPU available, skipping GPU test")
