#import pyrebase
from fastapi import FastAPI, Header, HTTPException
import firebase_admin
from firebase_admin import auth, credentials

# 初始化 Firebase Admin SDK
if not firebase_admin._apps:
    cred = credentials.Certificate("config/serviceAccountKey.json")
    default_app = firebase_admin.initialize_app(cred)

# 設定 Custom Claim：role = admin
def set_admin(uid):
    auth.set_custom_user_claims(uid, {'admin': True})
    print(f"✅ 已設定 {uid} 為管理員")
    user = auth.get_user(uid)
    print("目前使用者自訂權限：", user.custom_claims)

set_admin('fzw5CF45sKgzfLFfJBmu6agA3hV2')