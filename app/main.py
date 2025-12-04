# main.py

#import os
#from dotenv import load_dotenv
from fastapi import FastAPI, Depends, Header, HTTPException
import firebase_admin
from firebase_admin import auth, credentials
from firebase_admin import firestore_async

from app.admin import router as admin_router
#from app.routes.settings import router as settings_router

#API_BASE_URL = os.getenv("API_BASE_URL")

# 初始化 Firebase Admin SDK
if not firebase_admin._apps:
    cred = credentials.Certificate("config/serviceAccountKey.json")
    default_app = firebase_admin.initialize_app(cred)
    db = firestore_async.client()

app = FastAPI()

// ↓↓↓部署前要改↓↓↓
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
// ↑↑↑部署前要改↑↑↑

app.include_router(admin_router, prefix="/admin")  # include the user router under /users path
app.include_router(settings_router, prefix="/settings")  # include the settings router under /settings path

