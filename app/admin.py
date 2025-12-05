from fastapi import FastAPI, APIRouter, Header, HTTPException, Depends
from firebase_admin import auth, credentials
from pydantic import BaseModel

class CreateUserRequest(BaseModel):
    email: str
    password: str


router = APIRouter()

# 設定 Custom Claim：role = admin
def set_admin(uid):
    auth.set_custom_user_claims(uid, {'admin': True})
    print(f"✅ 已設定 {uid} 為管理員")
    user = auth.get_user(uid)
    print("目前使用者自訂權限：", user.custom_claims)

# set_admin('ID3KnaS0WTfrabSCwWuOPCOHMKX2')

async def get_current_user(authorization: str = Header(...)):
    """
    - 驗證 Firebase ID Token
    - 回傳 uid、是否 admin、claims
    """
    id_token = _extract_token(authorization)
    try:
        decoded_token = auth.verify_id_token(id_token)
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {e}")

    is_admin = decoded_token.get("admin") is True
    return {"uid": decoded_token.get("uid"), "is_admin": is_admin, "claims": decoded_token}

async def admin_required(user=Depends(get_current_user)):
    """
    - 依賴注入
    - 只有 admin 才能通過
    """
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="Admin only")
    return user

@router.get("/verify_admin")
async def admin_route(user=Depends(admin_required)):
    """
    - 只允許 admin 訪問
    - 回傳 admin 身份資訊
    """
    return {
        "status": "verified",
        "uid": user["uid"],
        "admin": user["is_admin"],
        "msg": "Welcome Admin!"
    }

#@router.get("/admin")
async def admin_route(authorization: str = Header(...)):
    print("Authorization header:", authorization)
    try:
        token = _extract_token(authorization)
        decoded = auth.verify_id_token(token)

        if not decoded.get("admin", False):
            raise HTTPException(status_code=403, detail="Not admin")

        return {"msg": "Welcome Admin!"}
        '''
        return {
            "status": "verified",
            "uid": uid,
            "admin": is_admin,
            "msg": "Welcome Admin!"
        }
        '''

    except:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")
    
def _extract_token(authorization: str) -> str:
    try:
        scheme, token = authorization.split()
        if scheme.lower() != "bearer":
            raise ValueError("Invalid auth scheme")
        return token
    except:
        raise HTTPException(status_code=401, detail="Invalid Authorization header")

@router.get("/get_users")
async def list_all_users(user=Depends(admin_required)):
    """
    - 只有 admin 可以列出所有 Firebase 使用者
    """
    try:
        # 列出最多 1000 位使用者
        page = auth.list_users().iterate_all()
        users = []
        for u in page:
            users.append({
                "uid": u.uid,
                "email": u.email,
                "admin": u.custom_claims.get("admin") if u.custom_claims else False
            })
        return {"users": users}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to list users: {e}")
    
@router.get("/get_user/{uid}")
async def get_user_detail(uid: str, user=Depends(admin_required)):
    """
    只有 admin 可以取得單一使用者詳細資料
    """
    try:
        u = auth.get_user(uid)

        return {
            "uid": u.uid,
            "email": u.email,
            #"phone": u.phone_number,
            #"disabled": u.disabled,
            "email_verified": u.email_verified,
            #"provider": [p.provider_id for p in u.provider_data],
            "admin": u.custom_claims.get("admin") if u.custom_claims else False,
            "metadata": {
                "creation_time": u.user_metadata.creation_timestamp,
                "last_sign_in_time": u.user_metadata.last_sign_in_timestamp,
            }
        }

    except Exception as e:
        raise HTTPException(status_code=404, detail=f"User not found: {e}")

@router.get("/get_user_by_email/")
async def get_user_by_email(email: str, user=Depends(admin_required)):
    """
    只有 admin 可以透過 email 取得使用者詳細資料
    """
    try:
        u = auth.get_user_by_email(email)

        return {
            "uid": u.uid,
            "email": u.email,
            #"phone": u.phone_number,
            #"disabled": u.disabled,
            "email_verified": u.email_verified,
            #"provider": [p.provider_id for p in u.provider_data],
            "admin": u.custom_claims.get("admin") if u.custom_claims else False,
            "metadata": {
                "creation_time": u.user_metadata.creation_timestamp,
                "last_sign_in_time": u.user_metadata.last_sign_in_timestamp,
            }
        }

    except Exception as e:
        raise HTTPException(status_code=404, detail=f"User not found: {e}")

@router.get("/search")
async def search_users(q: str, user=Depends(admin_required)
):
    """
    - 支援模糊搜尋 email / uid
    - q="abc" → 搜尋包含 abc 的 email 或 uid
    """
    q_lower = q.lower()
    results = []

    try:
        for u in auth.list_users().iterate_all():
            email = u.email.lower() if u.email else ""
            uid = u.uid.lower()

            if q_lower in email or q_lower in uid:
                results.append({
                    "uid": u.uid,
                    "email": u.email,
                    "admin": u.custom_claims.get("admin") if u.custom_claims else False
                })

        return {"results": results}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Search failed: {e}")

@router.post("/create_user")
async def create_user(data: CreateUserRequest, user=Depends(admin_required)):
    try:
        user_record = auth.create_user(
            email=data.email,
            password=data.password
        )
        return {
            "uid": user_record.uid,
            "email": user_record.email,
        }
    except auth.EmailAlreadyExistsError:
        raise HTTPException(status_code=400, detail="Email already exists")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create users: {e}")
    
@router.delete("/delete_user/{uid}")
async def delete_user(uid: str, user=Depends(admin_required)):
    try:
        auth.delete_user(uid)
        return {"msg": f"User {uid} deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete user: {e}")
    
