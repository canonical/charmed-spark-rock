import argparse
import random

from pyspark.sql import SparkSession
from pyspark.sql.types import LongType, StructType, StructField

parser = argparse.ArgumentParser("TestIceberg")
parser.add_argument("--num_rows", "-n", type=int)
args = parser.parse_args()
num_rows = args.num_rows

spark = SparkSession\
    .builder\
    .appName("IcebergExample")\
    .getOrCreate()


schema = StructType([
  StructField("row_id", LongType(), True),
  StructField("row_val", LongType(), True)
])

# df = spark.createDataFrame([], schema)
# df.writeTo("demo.foo.bar").create()

# schema = spark.table("demo.nyc.taxis").schema
data = []
for idx in range(num_rows):
    row = (idx + 1, random.randint(1, 100))
    data.append(row)

df = spark.createDataFrame(data, schema)
# df.writeTo("demo.nyc.taxis").append()
df.writeTo("demo.foo.bar").create()


df = spark.table("demo.foo.bar")
count = df.count()
print(f"Number of rows inserted: {count}")