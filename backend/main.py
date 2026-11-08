import os
import secrets
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from livekit import api

load_dotenv(Path(__file__).with_name(".env"))

LIVEKIT_URL = os.getenv("LIVEKIT_URL")
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")

app = FastAPI(title="SWAT Backend")


class AnswerRequest(BaseModel):
    room: str


async def find_active_sip_rooms(livekit):
    response = await livekit.room.list_rooms(api.ListRoomsRequest())
    incoming = []

    for room in response.rooms:
        if not room.name.startswith("swat-call-"):
            continue

        try:
            participants = await livekit.room.list_participants(
                api.ListParticipantsRequest(room=room.name)
            )
        except Exception as error:
            # A call may end between listing the room
            # and checking its participants.
            if "not_found" in str(error) or "404" in str(error):
                print(f"Skipping ended room: {room.name}")
                continue
            raise

        sip_callers = [
            participant
            for participant in participants.participants
            if participant.kind == api.ParticipantInfo.Kind.SIP
        ]

        if sip_callers:
            incoming.append(room.name)

    return incoming


@app.get("/")
async def home():
    return {
        "app": "SWAT",
        "status": "Backend is running",
    }


@app.get("/incoming")
async def incoming_calls():
    if not all([LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET]):
        raise HTTPException(
            status_code=500,
            detail="LiveKit credentials are missing",
        )

    try:
        async with api.LiveKitAPI(
            url=LIVEKIT_URL,
            api_key=LIVEKIT_API_KEY,
            api_secret=LIVEKIT_API_SECRET,
        ) as livekit:
            rooms = await find_active_sip_rooms(livekit)

        return {
            "calls": [
                {
                    "room": room,
                    "caller": "Incoming phone call",
                }
                for room in rooms
            ]
        }

    except Exception as error:
        print(f"LiveKit error: {error}")
        raise HTTPException(
            status_code=502,
            detail="Could not check LiveKit calls",
        )


@app.post("/answer")
async def answer_call(request: AnswerRequest):
    if not all([LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET]):
        raise HTTPException(
            status_code=500,
            detail="LiveKit credentials are missing",
        )

    try:
        async with api.LiveKitAPI(
            url=LIVEKIT_URL,
            api_key=LIVEKIT_API_KEY,
            api_secret=LIVEKIT_API_SECRET,
        ) as livekit:
            active_rooms = await find_active_sip_rooms(livekit)

        if request.room not in active_rooms:
            raise HTTPException(
                status_code=404,
                detail="This phone call is no longer active",
            )

        identity = f"swat-emulator-{secrets.token_hex(4)}"

        token = (
            api.AccessToken(
                LIVEKIT_API_KEY,
                LIVEKIT_API_SECRET,
            )
            .with_identity(identity)
            .with_name("SWAT Phone")
            .with_grants(
                api.VideoGrants(
                    room_join=True,
                    room=request.room,
                    can_publish=True,
                    can_subscribe=True,
                )
            )
            .with_ttl(timedelta(minutes=5))
            .to_jwt()
        )

        return {
            "url": LIVEKIT_URL,
            "token": token,
            "room": request.room,
        }

    except HTTPException:
        raise

    except Exception as error:
        print(f"LiveKit answer error: {error}")
        raise HTTPException(
            status_code=502,
            detail="Could not create call connection",
        )