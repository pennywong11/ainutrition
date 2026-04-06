# app/notifications.py

from fastapi import APIRouter, Form, HTTPException
from fastapi.responses import HTMLResponse
import firebase_admin
from firebase_admin import credentials, messaging
from pydantic import BaseModel

router = APIRouter()

class NotificationRequest(BaseModel):
    title: str
    body: str


@router.post("/send")
async def send_notification(data: NotificationRequest):
    message = messaging.Message(
        data={
            "title": data.title,
            "body": data.body,
        },
        topic="all",
        # token="frEu2SI3lwFOFlRh7xOOAP:APA91bEYSuocjcBWe9D3qOzZ9C9x4RTy_IXcu6I11XOCy6UDCz7z0_lhm1zz25ewB_qddFLy74s0gVbPU3OTb4RKPssHAqs5pkGjEBKZw2h6uLTO4yuEehA"
    )

    response = messaging.send(message)

    return {"status": "success", "message_id": response}