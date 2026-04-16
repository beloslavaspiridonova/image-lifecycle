"""Image Lifecycle Management - FastAPI application."""
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

import config
from database import init_db, seed_owner

# import all routers
from routes import auth, candidates, builds, validations, publish, distribution, audit, system, settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("image-lifecycle")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    seed_owner()
    logger.info("Image Lifecycle API started")
    yield
    logger.info("Image Lifecycle API shutting down")


app = FastAPI(title="Image Lifecycle Management API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(candidates.router)
app.include_router(builds.router)
app.include_router(validations.router)
app.include_router(publish.router)
app.include_router(distribution.router)
app.include_router(audit.router)
app.include_router(system.router)
app.include_router(settings.router)

# Serve built frontend if it exists
frontend_dist = os.path.join(os.path.dirname(__file__), "..", "frontend", "dist")
if os.path.exists(frontend_dist):
    app.mount("/", StaticFiles(directory=frontend_dist, html=True), name="frontend")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
