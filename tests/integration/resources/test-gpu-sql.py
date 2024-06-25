from pyspark.sql import SparkSession
from pyspark.conf import SparkConf
from time import time
import os

def runMicroBenchmark(spark, appName, query, retryTimes) -> float:
    count = 0
    total_time = 0
    # You can print the physical plan of each query
    # spark.sql(query).explain()
    while count < retryTimes:
        start = time()
        spark.sql(query).show(5)
        end = time()
        total_time += round(end - start, 2)
        count = count + 1
        print("Retry times : {}, ".format(count) + appName + " microbenchmark takes {} seconds".format(round(end - start, 2)))
    print(appName + " microbenchmark takes average {} seconds after {} retries".format(round(total_time/retryTimes),retryTimes))
    return round(total_time/retryTimes)

spark = SparkSession.builder.appName("GPUBenchmark").getOrCreate()

dataRoot = "s3a://data"
spark.read.parquet(dataRoot + "/tpcds/customer").createOrReplaceTempView("customer")
spark.read.parquet(dataRoot + "/tpcds/store_sales").createOrReplaceTempView("store_sales")
spark.read.parquet(dataRoot + "/tpcds/catalog_sales").createOrReplaceTempView("catalog_sales")
spark.read.parquet(dataRoot + "/tpcds/web_sales").createOrReplaceTempView("web_sales")
spark.read.parquet(dataRoot + "/tpcds/item").createOrReplaceTempView("item")
spark.read.parquet(dataRoot + "/tpcds/date_dim").createOrReplaceTempView("date_dim")
print("-"*50)

query = '''
select c_current_hdemo_sk,
count(DISTINCT if(c_salutation=="Ms.",c_salutation,null)) as c1,
count(DISTINCT if(c_salutation=="Mr.",c_salutation,null)) as c12,
count(DISTINCT if(c_salutation=="Dr.",c_salutation,null)) as c13,
count(DISTINCT if(c_salutation=="Ms.",c_first_name,null)) as c2,
count(DISTINCT if(c_salutation=="Mr.",c_first_name,null)) as c22,
count(DISTINCT if(c_salutation=="Dr.",c_first_name,null)) as c23,
count(DISTINCT if(c_salutation=="Ms.",c_last_name,null)) as c3,
count(DISTINCT if(c_salutation=="Mr.",c_last_name,null)) as c32,
count(DISTINCT if(c_salutation=="Dr.",c_last_name,null)) as c33,
count(DISTINCT if(c_salutation=="Ms.",c_birth_country,null)) as c4,
count(DISTINCT if(c_salutation=="Mr.",c_birth_country,null)) as c42,
count(DISTINCT if(c_salutation=="Dr.",c_birth_country,null)) as c43,
count(DISTINCT if(c_salutation=="Ms.",c_email_address,null)) as c5,
count(DISTINCT if(c_salutation=="Mr.",c_email_address,null)) as c52,
count(DISTINCT if(c_salutation=="Dr.",c_email_address,null)) as c53,
count(DISTINCT if(c_salutation=="Ms.",c_login,null)) as c6,
count(DISTINCT if(c_salutation=="Mr.",c_login,null)) as c62,
count(DISTINCT if(c_salutation=="Dr.",c_login,null)) as c63,
count(DISTINCT if(c_salutation=="Ms.",c_preferred_cust_flag,null)) as c7,
count(DISTINCT if(c_salutation=="Mr.",c_preferred_cust_flag,null)) as c72,
count(DISTINCT if(c_salutation=="Dr.",c_preferred_cust_flag,null)) as c73,
count(DISTINCT if(c_salutation=="Ms.",c_birth_month,null)) as c8,
count(DISTINCT if(c_salutation=="Mr.",c_birth_month,null)) as c82,
count(DISTINCT if(c_salutation=="Dr.",c_birth_month,null)) as c83,
avg(if(c_salutation=="Ms.",c_birth_year,null)) as avg1,
avg(if(c_salutation=="Mr.",c_birth_year,null)) as avg2,
avg(if(c_salutation=="Dr.",c_birth_year,null)) as avg3,
avg(if(c_salutation=="Miss.",c_birth_year,null)) as avg4,
avg(if(c_salutation=="Mrs.",c_birth_year,null)) as avg5,
avg(if(c_salutation=="Sir.",c_birth_year,null)) as avg6,
avg(if(c_salutation=="Professor.",c_birth_year,null)) as avg7,
avg(if(c_salutation=="Teacher.",c_birth_year,null)) as avg8,
avg(if(c_salutation=="Agent.",c_birth_year,null)) as avg9,
avg(if(c_salutation=="Director.",c_birth_year,null)) as avg10
from customer group by c_current_hdemo_sk
'''

# Run microbenchmark with n retry time
runMicroBenchmark(spark,"Expand&HashAggregate",query,2)


query = '''
select ss_customer_sk,avg(avg_price) as avg_price
from
(
SELECT ss_customer_sk ,avg(ss_sales_price) OVER (PARTITION BY ss_customer_sk order by ss_sold_date_sk ROWS BETWEEN 50 PRECEDING AND 50 FOLLOWING ) as avg_price
FROM store_sales
where ss_customer_sk is not null
) group by ss_customer_sk order by 2 desc 
'''
print("-"*50)

# Run microbenchmark with n retry time
runMicroBenchmark(spark,"Windowing without skew",query,2)

query = '''
select ss_customer_sk,avg(avg_price) as avg_price
from
(
SELECT ss_customer_sk ,avg(ss_sales_price) OVER (PARTITION BY ss_customer_sk order by ss_sold_date_sk ROWS BETWEEN 50 PRECEDING AND 50 FOLLOWING ) as avg_price
FROM store_sales
) group by ss_customer_sk order by 2 desc 
'''
print("-"*50)

# Run microbenchmark with n retry time
runMicroBenchmark(spark,"Windowing with skew",query,2)


query = '''
select i_item_sk ss_item_sk
 from item,
    (select iss.i_brand_id brand_id, iss.i_class_id class_id, iss.i_category_id category_id
     from store_sales, item iss, date_dim d1
     where ss_item_sk = iss.i_item_sk
                    and ss_sold_date_sk = d1.d_date_sk
       and d1.d_year between 1999 AND 1999 + 2
   intersect
     select ics.i_brand_id, ics.i_class_id, ics.i_category_id
     from catalog_sales, item ics, date_dim d2
     where cs_item_sk = ics.i_item_sk
       and cs_sold_date_sk = d2.d_date_sk
       and d2.d_year between 1999 AND 1999 + 2
   intersect
     select iws.i_brand_id, iws.i_class_id, iws.i_category_id
     from web_sales, item iws, date_dim d3
     where ws_item_sk = iws.i_item_sk
       and ws_sold_date_sk = d3.d_date_sk
       and d3.d_year between 1999 AND 1999 + 2) x
 where i_brand_id = brand_id
   and i_class_id = class_id
   and i_category_id = category_id
'''

# Run microbenchmark with n retry time
runMicroBenchmark(spark,"NDS Q14a subquery",query,2)


start = time() 
spark.read.parquet(dataRoot + "/tpcds/customer").limit(1000000).write.format("parquet").mode("overwrite").save(dataRoot + "/tmp/customer1m")
end = time()
# Parquet file scanning and writing will be about 3 times faster running on GPU
print("scanning and writing parquet cost : {} seconds".format(round(end - start, 2)))
spark.read.parquet(dataRoot + "/tmp/customer1m").repartition(200).createOrReplaceTempView("costomer_df_1_million")
query = '''
select count(*) from costomer_df_1_million c1 inner join costomer_df_1_million c2 on c1.c_customer_sk>c2.c_customer_sk
'''
print("-"*50)

# Run microbenchmark with n retry time
runMicroBenchmark(spark,"Crossjoin",query,2)