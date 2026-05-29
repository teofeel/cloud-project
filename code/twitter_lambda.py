import os

os.environ["KAGGLE_CONFIG_DIR"] = "/tmp"

import boto3
from kaggle.api.kaggle_api_extended import KaggleApi
from boto3.s3.transfer import TransferConfig
import sys
import threading

download_path = "./tmp/"

class ProgressPercentage(object):
    def __init__(self, filename):
        self._filename = filename
        self._size = float(os.path.getsize(filename))
        self._seen_so_far = 0
        self._lock = threading.Lock()

    def __call__(self, bytes_amount):
        with self._lock:
            self._seen_so_far += bytes_amount
            percentage = (self._seen_so_far / self._size) * 100
            sys.stdout.write(
                f"\nSending {os.path.basename(self._filename)}: "
                f"{self._seen_so_far / (1024*1024):.2f} MB / {self._size / (1024*1024):.2f} MB "
                f"({percentage:.2f}%)"
            )
            sys.stdout.flush()

def lambda_handler(event, context):
    bucket_name = os.environ['S3_BUCKET_NAME']
    
    api = KaggleApi()
    api.authenticate()
    
    dataset = "kaushiksuresh147/bitcoin-tweets"
    download_path = "/tmp/"
    
    print("Download...")
    api.dataset_download_files(dataset, path=download_path, unzip=True)
    
    s3 = boto3.client('s3')
    
    config = TransferConfig(
        multipart_threshold=1024 * 1024 * 15,  
        multipart_chunksize=1024 * 1024 * 15,  
        max_concurrency=20,                   
        use_threads=True
    )
    
    print("\nStarting S3 upload...")
    for file in os.listdir(download_path):
        if file.endswith(".csv") or file.endswith(".json"):
            s3_key = f"bronze/x_twitter/{file}"
            local_path = os.path.join(download_path, file)
            
            progress = ProgressPercentage(local_path)
            s3.upload_file(
                local_path, 
                bucket_name, 
                s3_key, 
                Config=config, 
                Callback=progress
            )
            print(f"\n[OK] Successfully sent: {file}")
            
    return {"status": "success"}

# if __name__ == "__main__":
#     lambda_handler(None, None)